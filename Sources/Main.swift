import AppKit
import SwiftUI
import Speech
import AVFoundation
import Carbon

@main
enum KotobaMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            print("Quillo \(version) / \(ProcessInfo.processInfo.operatingSystemVersionString)")
            for language in CaptionLanguage.speechInputLanguages {
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechLocale))
                print("\(language.rawValue): on-device=\(recognizer?.supportsOnDeviceRecognition ?? false), available=\(recognizer?.isAvailable ?? false)")
            }
            print("Speech authorization: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
            print("Microphone authorization: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = AppModel()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.overlay = OverlayController(model: model)
        model.showControlWindow = { [weak self] in self?.showWindow() }
        configureMenus()
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: min(880, visibleHeight - 80)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Quillo — 設定"
        window.minSize = NSSize(width: 690, height: 650)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ControlView(model: model))
        window.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "Quillo")
        statusItem.button?.toolTip = "Quillo — 字幕の表示・固定・設定"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        registerHotkeys()
        showWindow()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleOverlay() { model.toggleOverlay() }
    @objc func toggleLock() { model.toggleLock() }
    @objc func stopSlideTranslation() { model.slides.stop() }
    @objc func showSlideTranslationPanel() { model.slides.showTranslationPanel() }
    @objc func toggleSummaryPanel() { model.slides.togglePanel() }
    @objc func toggleSummaryLock() { model.slides.positionLocked.toggle() }
    @objc func stopMic() { model.stopMic() }
    @objc func toggleMic() { model.toggleMic() }
    @objc func showHelp() { showWindow(); model.helpVisible = true }
    @objc func quit() { NSApp.terminate(nil) }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    private func configureMenus() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(); let applicationMenu = NSMenu(title: "Quillo")
        applicationMenu.addItem(menuItem("設定を開く", #selector(showWindow), key: ","))
        applicationMenu.addItem(menuItem("Quillo の使い方", #selector(showHelp)))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem("Quillo を終了", #selector(quit), key: "q"))
        applicationItem.submenu = applicationMenu; mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "編集")
        for (title, action, key) in [("取り消す", "undo:", "z"), ("切り取る", "cut:", "x"), ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"), ("すべてを選択", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        let displayItem = NSMenuItem(); let displayMenu = NSMenu(title: "字幕")
        displayMenu.addItem(menuItem("話して字幕を出す／停止", #selector(toggleMic)))
        displayMenu.addItem(menuItem("字幕の表示を切り替え", #selector(toggleOverlay)))
        displayMenu.addItem(menuItem("位置の固定を切り替え", #selector(toggleLock)))
        displayMenu.addItem(menuItem("マイクを停止", #selector(stopMic)))
        displayMenu.addItem(menuItem("資料の要約を停止", #selector(stopSlideTranslation)))
        displayMenu.addItem(menuItem("資料の要約パネルを表示", #selector(showSlideTranslationPanel)))
        displayItem.submenu = displayMenu; mainMenu.addItem(displayItem)
        NSApp.mainMenu = mainMenu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(menuItem("設定を開く", #selector(showWindow)))
        menu.addItem(menuItem(model.slides.panelVisible ? "要約を隠す" : "要約を表示", #selector(toggleSummaryPanel)))
        menu.addItem(menuItem(model.slides.positionLocked ? "要約位置の固定を解除" : "要約位置を固定", #selector(toggleSummaryLock)))
        menu.addItem(.separator())
        menu.addItem(menuItem(model.microphoneActionTitle, #selector(toggleMic)))
        if model.overlayVisible { menu.addItem(menuItem("字幕を隠す", #selector(toggleOverlay))) }
        else if model.isListening || model.isStartingMic { menu.addItem(menuItem("字幕を再表示", #selector(toggleOverlay))) }
        menu.addItem(menuItem(model.positionLocked ? "字幕位置の固定を解除" : "字幕位置を固定", #selector(toggleLock)))
        if model.slides.isRunning { menu.addItem(menuItem("資料の要約を停止", #selector(stopSlideTranslation))) }
        menu.addItem(.separator())
        menu.addItem(menuItem("使い方", #selector(showHelp)))
        menu.addItem(menuItem("Quillo を終了", #selector(quit)))
    }
    private func registerHotkeys() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let number = identifier.id
            Task { @MainActor in if number == 1 { delegate.toggleOverlay() } else { delegate.toggleLock() } }
            return noErr
        }, 1, &type, pointer, &handler)
        for (code, id) in [(kVK_ANSI_K, UInt32(1)), (kVK_ANSI_L, UInt32(2))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x4b544241, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotkeys.append(reference) }
        }
    }
}
