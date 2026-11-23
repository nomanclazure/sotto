import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    enum DictationState {
        case idle, recording, transcribing
    }

    private var statusItem: NSStatusItem!
    private let hotkeyMonitor = HotkeyMonitor()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let models = ModelManager.shared
    private let settings = Settings.shared

    private var state: DictationState = .idle {
        didSet { updateStatusIcon() }
    }
    private var recordStart = Date()
    private var maxDurationTimer: Timer?
    private var tapRetryTimer: Timer?

    private static let maxRecordingSeconds: TimeInterval = 300
    private static let minRecordingSeconds: TimeInterval = 0.5

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = []
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()

        hotkeyMonitor.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkeyMonitor.onRelease = { [weak self] in self?.hotkeyReleased() }

        models.onProgress = { [weak self] _, _ in self?.updateStatusIcon() }
        models.onFinished = { [weak self] model, ok in
            guard let self else { return }
            self.updateStatusIcon()
            if ok, model == self.settings.model {
                self.transcriber.preload(modelPath: self.models.path(for: model).path)
            } else if !ok {
                self.showAlert(title: "Model download failed",
                               message: "Sotto couldn't download the \(model.rawValue) model. Check your internet connection, then pick the model again from the Sotto menu to retry.")
            }
        }

        if !settings.onboarded {
            runOnboarding()
        } else {
            startHotkeyMonitorOrRetry()
        }

        ensureModelAvailable(promptIfMissing: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
        transcriber.unloadSync()
    }

    // MARK: Onboarding / permissions

    private func runOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Welcome to Sotto"
        alert.informativeText = """
        Sotto is push-to-talk dictation that runs 100% on this Mac.

        Hold the Right Option (⌥) key, speak, release — your words are typed into whatever app you're using.

        Sotto needs three permissions, and macOS will ask for them one at a time:

        1. Microphone — to hear you
        2. Input Monitoring — to notice the hotkey in any app
        3. Accessibility — to type the text for you

        For Input Monitoring and Accessibility, System Settings will open: turn ON the switch next to Sotto, then come back.
        """
        alert.addButton(withTitle: "Set Up Permissions")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        settings.onboarded = true
        guard response == .alertFirstButtonReturn else {
            startHotkeyMonitorOrRetry()
            return
        }

        Permissions.requestMic { [weak self] _ in
            Permissions.requestInputMonitoring()
            Permissions.promptAccessibility()
            self?.startHotkeyMonitorOrRetry()
        }
    }

    /// Try to start the global hotkey listener; if Input Monitoring hasn't
    /// been granted yet, keep retrying quietly until it has been.
    private func startHotkeyMonitorOrRetry() {
        tapRetryTimer?.invalidate()
        tapRetryTimer = nil
        if hotkeyMonitor.start() {
            updateStatusIcon()
            return
        }
        updateStatusIcon()
        tapRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.hotkeyMonitor.start() {
                self.tapRetryTimer?.invalidate()
                self.tapRetryTimer = nil
                self.updateStatusIcon()
            }
        }
    }

    // MARK: Dictation flow

    private func hotkeyPressed() {
        guard settings.enabled, state == .idle else { return }

        guard Permissions.micGranted else {
            handleMissingMicPermission()
            return
        }
        guard ensureModelAvailable(promptIfMissing: true) else { return }

        do {
            try recorder.start(deviceUID: settings.micDeviceUID)
        } catch {
            Sounds.error()
            showAlert(title: "Couldn't start recording",
                      message: (error as? RecorderError)?.errorDescription ?? error.localizedDescription)
            return
        }

        recordStart = Date()
        state = .recording
        Sounds.recordStart()

        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingSeconds, repeats: false) { [weak self] _ in
            self?.hotkeyReleased()
        }
    }

    private func hotkeyReleased() {
        guard state == .recording else { return }
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        let duration = -recordStart.timeIntervalSinceNow
        let samples = recorder.stop()
        Sounds.recordStop()

        // Accidental tap → discard
        if duration < Self.minRecordingSeconds || samples.count < Int(0.3 * Recorder.targetSampleRate) {
            state = .idle
            return
        }

        state = .transcribing
        let modelPath = models.path(for: settings.model).path
        transcriber.transcribe(samples: samples, modelPath: modelPath) { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = .idle
                guard let text else {
                    Sounds.error()
                    self.showAlert(title: "Transcription failed",
                                   message: "The speech model could not process this recording. If this keeps happening, pick the model again in the Sotto menu to re-download it.")
                    return
                }
                guard !text.isEmpty else { return }
                TextInserter.insert(text)
            }
        }
    }

    private func handleMissingMicPermission() {
        Sounds.error()
        if Permissions.micStatus == .notDetermined {
            Permissions.requestMic { [weak self] granted in
                if !granted { self?.showMicDeniedAlert() }
            }
        } else {
            showMicDeniedAlert()
        }
    }

    private func showMicDeniedAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Sotto can't hear you yet"
        alert.informativeText = """
        Microphone access is turned off for Sotto.

        To fix it:
        1. Click "Open Settings" below (or open System Settings → Privacy & Security → Microphone)
        2. Turn ON the switch next to Sotto
        3. Try dictating again
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openMicSettings()
        }
    }

    /// Returns true if the selected model is on disk. If not, kicks off the
    /// download (auto-download on first run) and optionally tells the user.
    @discardableResult
    private func ensureModelAvailable(promptIfMissing: Bool) -> Bool {
        let model = settings.model
        if models.isDownloaded(model) {
            transcriber.preload(modelPath: models.path(for: model).path)
            return true
        }
        let alreadyDownloading = models.isDownloading(model)
        if !alreadyDownloading {
            models.download(model)
        }
        if promptIfMissing {
            Sounds.error()
            showAlert(title: "Speech model is downloading",
                      message: "Sotto is downloading the \(model.rawValue) speech model (one-time). The menu bar icon shows a down-arrow while it downloads — try again once it finishes.")
        }
        return false
    }

    // MARK: Status icon

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        var symbol: String
        var tint: NSColor? = nil
        var help: String

        if !settings.enabled {
            symbol = "mic.slash"
            help = "Sotto — dictation is disabled"
        } else if !models.downloading.isEmpty {
            symbol = "arrow.down.circle"
            let pct = Int((models.downloading.values.first ?? 0) * 100)
            help = "Sotto — downloading model (\(pct)%)"
        } else if !hotkeyMonitor.isRunning {
            symbol = "exclamationmark.triangle"
            tint = .systemYellow
            help = "Sotto — needs the Input Monitoring permission"
        } else {
            switch state {
            case .idle:
                symbol = "mic"
                help = "Sotto — hold \(settings.hotkey.label) and speak"
            case .recording:
                symbol = "mic.fill"
                tint = .systemRed
                help = "Sotto — recording…"
            case .transcribing:
                symbol = "waveform.circle.fill"
                tint = .systemOrange
                help = "Sotto — transcribing…"
            }
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
        button.toolTip = help
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status line
        let statusTitle: String
        if !settings.enabled {
            statusTitle = "Dictation is off"
        } else if !hotkeyMonitor.isRunning {
            statusTitle = "⚠ Needs Input Monitoring permission"
        } else {
            switch state {
            case .idle: statusTitle = "Hold \(settings.hotkey.label) and speak"
            case .recording: statusTitle = "Recording…"
            case .transcribing: statusTitle = "Transcribing…"
            }
        }
        let statusLine = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        // Enable / disable
        let enableItem = NSMenuItem(title: "Enable Dictation", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = settings.enabled ? .on : .off
        menu.addItem(enableItem)

        // Hotkey submenu
        let hotkeyMenu = NSMenu()
        for option in HotkeyOption.allCases {
            let item = NSMenuItem(title: option.label, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = settings.hotkey == option ? .on : .off
            hotkeyMenu.addItem(item)
        }
        let hotkeyRoot = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotkeyRoot.submenu = hotkeyMenu
        menu.addItem(hotkeyRoot)

        // Microphone submenu
        let micMenu = NSMenu()
        let defaultItem = NSMenuItem(title: "System Default", action: #selector(selectMic(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = nil as String?
        defaultItem.state = settings.micDeviceUID == nil ? .on : .off
        micMenu.addItem(defaultItem)
        let devices = AudioDevices.inputDevices()
        if !devices.isEmpty { micMenu.addItem(.separator()) }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = settings.micDeviceUID == device.uid ? .on : .off
            micMenu.addItem(item)
        }
        let micRoot = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micRoot.submenu = micMenu
        menu.addItem(micRoot)

        // Model submenu
        let modelMenu = NSMenu()
        for option in ModelOption.allCases {
            var title = option.displayName
            if let progress = models.downloading[option] {
                title += " — downloading \(Int(progress * 100))%"
            } else if !models.isDownloaded(option) {
                title += " — not downloaded"
            }
            let item = NSMenuItem(title: title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = settings.model == option ? .on : .off
            modelMenu.addItem(item)
        }
        let modelRoot = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelRoot.submenu = modelMenu
        menu.addItem(modelRoot)

        // Sounds
        let soundsItem = NSMenuItem(title: "Play Sounds", action: #selector(toggleSounds), keyEquivalent: "")
        soundsItem.target = self
        soundsItem.state = settings.soundsEnabled ? .on : .off
        menu.addItem(soundsItem)

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Check Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Sotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: Menu actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled, state == .recording {
            _ = recorder.stop()
            state = .idle
        }
        updateStatusIcon()
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = HotkeyOption(rawValue: raw) else { return }
        settings.hotkey = option
        updateStatusIcon()
    }

    @objc private func selectMic(_ sender: NSMenuItem) {
        settings.micDeviceUID = sender.representedObject as? String
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = ModelOption(rawValue: raw) else { return }
        settings.model = option
        if models.isDownloaded(option) {
            transcriber.preload(modelPath: models.path(for: option).path)
        } else {
            models.download(option)
            updateStatusIcon()
        }
    }

    @objc private func toggleSounds() {
        settings.soundsEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Couldn't change Launch at Login",
                      message: "macOS reported: \(error.localizedDescription)\n\nMake sure Sotto is in the Applications folder.")
        }
    }

    @objc private func showPermissions() {
        NSApp.activate(ignoringOtherApps: true)
        let mic = Permissions.micGranted ? "✅" : "❌"
        let input = Permissions.inputMonitoringGranted ? "✅" : "❌"
        let ax = Permissions.accessibilityGranted ? "✅" : "❌"

        let alert = NSAlert()
        alert.messageText = "Sotto permissions"
        alert.informativeText = """
        \(mic) Microphone — lets Sotto hear you
        \(input) Input Monitoring — lets Sotto notice the hotkey in any app
        \(ax) Accessibility — lets Sotto type the text for you

        All three must show ✅ for dictation to work.

        To grant one, click its button below — System Settings opens on the right page. Turn ON the switch next to Sotto (you may need to click + and pick Sotto from Applications). If a permission was just granted but dictation still doesn't work, quit Sotto and open it again.
        """
        alert.addButton(withTitle: "Microphone…")
        alert.addButton(withTitle: "Input Monitoring…")
        alert.addButton(withTitle: "Accessibility…")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if Permissions.micStatus == .notDetermined {
                Permissions.requestMic { _ in }
            } else {
                Permissions.openMicSettings()
            }
        case .alertSecondButtonReturn:
            Permissions.requestInputMonitoring()
            Permissions.openInputMonitoringSettings()
        case .alertThirdButtonReturn:
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
        default:
            break
        }
    }

    // MARK: Helpers

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
