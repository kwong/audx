import SwiftUI

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct audxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // No SwiftUI scenes — everything is managed manually via NSStatusItem + NSPopover
        // Settings window is shown on demand via AppState.showSettingsWindow()
        Settings { EmptyView() }
    }
}

struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    
    @AppStorage("idleTimeoutMinutes") private var idleTimeoutMinutes: Double = 15.0
    @AppStorage("shortcutName") private var shortcutName: String = "⌘ \\"
    
    let timeoutOptions: [Double] = [0, 5, 10, 15, 30] // 0 = Never
    
    private var sliderIndex: Binding<Double> {
        Binding<Double>(
            get: { Double(timeoutOptions.firstIndex(of: idleTimeoutMinutes) ?? 3) },
            set: { idleTimeoutMinutes = timeoutOptions[Int(round($0))] }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Device List with Liquid styling
            ExpandedDeviceListView(
                audioManager: appState.audioManager,
                bluetoothManager: appState.bluetoothManager
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider().padding(.horizontal, 12)
            
            // BT Device Idle Timeout
            VStack(alignment: .leading, spacing: 8) {
                Text("BT Device Idle Timeout: \(idleTimeoutMinutes == 0 ? "Never" : "\(Int(idleTimeoutMinutes)) mins")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                CustomSlider(value: sliderIndex)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider().padding(.horizontal, 12)
            
            // Bottom actions
            HStack {
                // Shortcut hint
                Text(shortcutName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                    )
                
                Spacer()
                
                Button("Settings...") {
                    NotificationCenter.default.post(name: .dismissPopover, object: nil)
                    appState.showSettingsWindow()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                
                Text("·").foregroundColor(.secondary)
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
    }
}

class NoFocusRingHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLayout() {
        super.viewDidLayout()
        stripFocusRings(from: view)
    }
    
    private func stripFocusRings(from view: NSView) {
        view.focusRingType = .none
        for subview in view.subviews {
            stripFocusRings(from: subview)
        }
    }
}


class AppState: NSObject, ObservableObject {
    let audioManager = AudioManager()
    let bluetoothManager = BluetoothManager()
    let idleManager = IdleManager()
    
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    override init() {
        super.init()
        
        idleManager.audioManager = audioManager
        idleManager.bluetoothManager = bluetoothManager
        idleManager.start()
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateMenuBarIcon()
        observeAppearanceChanges()
        
        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NoFocusRingHostingController(rootView: PopoverContentView(appState: self))
        popover.contentViewController = hostingController
        
        // Wire the global hotkey
        HotKeyManager.shared.onHotKeyPressed = { [weak self] in
            self?.togglePopover(nil)
        }
        
        let savedKeyCode = UserDefaults.standard.integer(forKey: "shortcutKeyCode")
        let savedMods = UserDefaults.standard.integer(forKey: "shortcutModifiers")
        
        let initialCode = savedKeyCode == 0 && UserDefaults.standard.object(forKey: "shortcutKeyCode") == nil ? UInt16(42) : UInt16(savedKeyCode)
        let initialMods = savedMods == 0 && UserDefaults.standard.object(forKey: "shortcutModifiers") == nil ? NSEvent.ModifierFlags.command : NSEvent.ModifierFlags(rawValue: UInt(savedMods))
        
        HotKeyManager.shared.register(keyCode: initialCode, modifiers: initialMods)
        
        // Listen for dismiss notifications from keyboard events
        NotificationCenter.default.addObserver(forName: .dismissPopover, object: nil, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Suppress the default blue focus ring on the hosting view
            if let view = popover.contentViewController?.view {
                view.focusRingType = .none
                view.window?.makeKey()
            }
        }
    }
    
    private var appearanceObserver: NSKeyValueObservation?
    
    private func observeAppearanceChanges() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }
    }
    
    func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        button.image = makeMenuBarIcon(dark: false)
        button.image?.isTemplate = true
    }
    
    private func makeMenuBarIcon(dark: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY

            let strokeColor: NSColor = .black
            strokeColor.setStroke()
            strokeColor.setFill()

            let lineW: CGFloat = 1.8

            // Headband - semicircle arc across the top
            let bandRadius: CGFloat = 6.0
            let bandCenter = NSPoint(x: cx, y: cy - 0.5)
            let headband = NSBezierPath()
            headband.appendArc(withCenter: bandCenter,
                               radius: bandRadius,
                               startAngle: 0, endAngle: 180, clockwise: false)
            headband.lineWidth = lineW
            headband.lineCapStyle = .round
            headband.stroke()

            // Left ear cup - rounded rect hanging from left end of band
            let earW: CGFloat = 3.5
            let earH: CGFloat = 5.5
            let leftX = bandCenter.x - bandRadius
            let leftEar = NSBezierPath(roundedRect: NSRect(x: leftX - earW/2, y: bandCenter.y - earH, width: earW, height: earH),
                                        xRadius: 1.4, yRadius: 1.4)
            leftEar.lineWidth = lineW
            leftEar.stroke()

            // Right ear cup - rounded rect hanging from right end of band
            let rightX = bandCenter.x + bandRadius
            let rightEar = NSBezierPath(roundedRect: NSRect(x: rightX - earW/2, y: bandCenter.y - earH, width: earW, height: earH),
                                         xRadius: 1.4, yRadius: 1.4)
            rightEar.lineWidth = lineW
            rightEar.stroke()

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }
    
    private var settingsWindow: NSWindow?
    
    func showSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let controller = NSHostingController(rootView: SettingsView(appState: self))
        let window = NSWindow(contentViewController: controller)
        window.title = "audx Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    @AppStorage("idleTimeoutMinutes") private var idleTimeoutMinutes: Double = 15.0
    @AppStorage("showIdleWarnings") private var showIdleWarnings: Bool = true
    @AppStorage("shortcutKeyCode") private var shortcutKeyCode: Int = 42
    @AppStorage("shortcutModifiers") private var shortcutModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    @AppStorage("shortcutName") private var shortcutName: String = "⌘ \\"
    
    let timeoutOptions: [Double] = [0, 5, 10, 15, 30]
    
    private var sliderIndex: Binding<Double> {
        Binding<Double>(
            get: { Double(timeoutOptions.firstIndex(of: idleTimeoutMinutes) ?? 3) },
            set: { idleTimeoutMinutes = timeoutOptions[Int(round($0))] }
        )
    }
    
    var body: some View {
        ZStack {
            // Liquid glass background — adapts to system theme
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    
                    // Header
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 36, height: 36)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.7))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("audx")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Settings")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    
                    // — Card 1: BT Idle Timeout —
                    SettingsCard {
                        SettingsCardHeader(
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: Color(red: 0.2, green: 0.6, blue: 1.0),
                            title: "BT Device Idle Timeout"
                        )
                        
                        Divider()
                            .padding(.horizontal, -16)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Timeout")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(idleTimeoutMinutes == 0 ? "Never" : "\(Int(idleTimeoutMinutes)) min")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.primary.opacity(0.1))
                                    )
                            }
                            CustomSlider(value: sliderIndex)
                                .padding(.top, 2)
                        }
                        
                        Divider()
                            .padding(.horizontal, -16)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Disconnect warning")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.85))
                                Text("Show a notification before disconnecting")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $showIdleWarnings)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                    
                    // — Card 2: Global Shortcut —
                    SettingsCard {
                        SettingsCardHeader(
                            icon: "command.square.fill",
                            iconColor: Color(red: 0.6, green: 0.4, blue: 1.0),
                            title: "Global Shortcut"
                        )
                        
                        Divider()
                            .padding(.horizontal, -16)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open device menu")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.85))
                                Text("Must include ⌘, ⌥, or ⌃")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            ShortcutRecorderView(
                                recordedKeyCode: Binding(
                                    get: { UInt16(shortcutKeyCode) },
                                    set: { shortcutKeyCode = Int($0) }
                                ),
                                recordedModifiers: Binding(
                                    get: { NSEvent.ModifierFlags(rawValue: UInt(shortcutModifiers)) },
                                    set: { shortcutModifiers = Int($0.rawValue) }
                                ),
                                recordedName: $shortcutName,
                                onShortcutRecorded: { keyCode, modifiers in
                                    HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers)
                                }
                            )
                        }
                    }
                    
                    Spacer(minLength: 16)
                }
            }
        }
        .frame(width: 420, height: 420)
    }
}

// — Reusable card container —
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
    }
}

// — Card header with icon badge —
struct SettingsCardHeader: View {
    let icon: String
    let iconColor: Color
    let title: String
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
        }
    }
}

// — Dark pill button style —
struct DarkPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0.12))
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ShortcutRecorderView: View {
    @Binding var recordedKeyCode: UInt16
    @Binding var recordedModifiers: NSEvent.ModifierFlags
    @Binding var recordedName: String
    let onShortcutRecorded: (UInt16, NSEvent.ModifierFlags) -> Void
    
    @State private var isRecording = false
    @State private var localMonitor: Any?
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
            if isRecording { startRecording() }
            else { stopRecording() }
        }) {
            Text(isRecording ? "Type Shortcut..." : recordedName)
                .frame(width: 150)
        }
        .onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        // Temporarily disable global hotkey so it doesn't fire during recording
        HotKeyManager.shared.unregister()
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                recordedKeyCode = event.keyCode
                recordedModifiers = mods
                
                var name = ""
                if mods.contains(.control) { name += "⌃ " }
                if mods.contains(.option) { name += "⌥ " }
                if mods.contains(.shift) { name += "⇧ " }
                if mods.contains(.command) { name += "⌘ " }
                
                if let chars = event.charactersIgnoringModifiers {
                    name += chars.uppercased()
                } else {
                    name += "?"
                }
                
                recordedName = name
                onShortcutRecorded(event.keyCode, mods)
                isRecording = false
                stopRecording()
                return nil
            }
            return event
        }
    }
    
    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Restore the current configured shortcut when recording is cancelled.
        onShortcutRecorded(recordedKeyCode, recordedModifiers)
    }
}

struct CustomSlider: View {
    @Binding var value: Double // Expected range 0...4
    
    var body: some View {
        GeometryReader { geometry in
            let trackHeight: CGFloat = 5
            let thumbWidth: CGFloat = 18
            let thumbHeight: CGFloat = 14
            
            let width = geometry.size.width
            let padding = thumbWidth / 2
            let trackWidth = width - thumbWidth
            
            let percent = CGFloat(value / 4.0)
            let thumbOffset = percent * trackWidth
            
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: trackHeight)
                
                // Active Track
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: thumbOffset + padding, height: trackHeight)
                
                // Thumb
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.3), radius: 1.5, x: 0, y: 1)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .offset(x: thumbOffset)
            }
            .frame(height: thumbHeight)
            .position(x: width / 2, y: geometry.size.height / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let tapX = gesture.location.x - padding
                        let newPercent = max(0, min(1, tapX / trackWidth))
                        let newValue = round(Double(newPercent) * 4.0)
                        if value != newValue {
                            value = newValue
                        }
                    }
            )
        }
        .frame(height: 24)
    }
}
