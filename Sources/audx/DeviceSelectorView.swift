import SwiftUI
import CoreAudio

struct DeviceListView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @AppStorage("devicesMenuExpanded") private var isExpanded = false
    @State private var isHovered = false
    
    var body: some View {
        Menu {
            if !audioManager.outputDevices.isEmpty {
                Text("Output")
                ForEach(audioManager.outputDevices) { device in
                    let btLevel = bluetoothManager.connectedAudioDevices.first(where: { $0.name == device.name })?.batteryLevel
                    
                    Button(action: {
                        audioManager.setDefaultOutputDevice(id: device.id)
                    }) {
                        let check = device.id == audioManager.defaultOutputDeviceID ? " ✓" : ""
                        let batt = btLevel != nil ? " (\(btLevel!) 🔋)" : ""
                        let icon = device.id == audioManager.defaultOutputDeviceID ? "speaker.wave.2.fill" : "speaker"
                        Label("\(device.name)\(check)\(batt)", systemImage: icon)
                    }
                }
            }
            
            if !audioManager.inputDevices.isEmpty {
                Divider()
                Text("Input")
                ForEach(audioManager.inputDevices) { device in
                    let btLevel = bluetoothManager.connectedAudioDevices.first(where: { $0.name == device.name })?.batteryLevel
                    
                    Button(action: {
                        audioManager.setDefaultInputDevice(id: device.id)
                    }) {
                        let check = device.id == audioManager.defaultInputDeviceID ? " ✓" : ""
                        let batt = btLevel != nil ? " (\(btLevel!) 🔋)" : ""
                        let icon = device.id == audioManager.defaultInputDeviceID ? "mic.fill" : "mic"
                        Label("\(device.name)\(check)\(batt)", systemImage: icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 30, height: 30)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Select Audio Device")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.gray.opacity(0.4) : Color.gray.opacity(0.25))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            audioManager.refreshDevices()
        }
    }
}

class SelectionState: ObservableObject {
    @Published var index: Int = 0
}

struct ExpandedDeviceListView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @StateObject private var selection = SelectionState()
    @State private var localMonitor: Any?
    @Namespace private var highlightNamespace
    
    // Refresh automatically evaluated when items change
    private var allDevices: [AudioDevice] {
        audioManager.outputDevices + audioManager.inputDevices
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !audioManager.outputDevices.isEmpty {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                
                ForEach(Array(audioManager.outputDevices.enumerated()), id: \.element.id) { index, device in
                    let btLevel = bluetoothManager.connectedAudioDevices.first(where: { $0.name == device.name })?.batteryLevel
                    DeviceRowMenu(device: device,
                                  isDefault: device.id == audioManager.defaultOutputDeviceID,
                                  isSelected: index == selection.index,
                                  namespace: highlightNamespace,
                                  iconName: "speaker.wave.2.fill",
                                  inactiveIconName: "speaker",
                                  batteryLevel: btLevel) {
                        audioManager.setDefaultOutputDevice(id: device.id)
                    }
                }
            }
            
            if !audioManager.inputDevices.isEmpty {
                Divider()
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                
                Text("Input")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                
                ForEach(Array(audioManager.inputDevices.enumerated()), id: \.element.id) { index, device in
                    let mappedIndex = index + audioManager.outputDevices.count
                    let btLevel = bluetoothManager.connectedAudioDevices.first(where: { $0.name == device.name })?.batteryLevel
                    DeviceRowMenu(device: device,
                                  isDefault: device.id == audioManager.defaultInputDeviceID,
                                  isSelected: mappedIndex == selection.index,
                                  namespace: highlightNamespace,
                                  iconName: "mic.fill",
                                  inactiveIconName: "mic",
                                  batteryLevel: btLevel) {
                        audioManager.setDefaultInputDevice(id: device.id)
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .onAppear {
            audioManager.refreshDevices()
            
            if let defIdx = allDevices.firstIndex(where: { $0.id == audioManager.defaultOutputDeviceID }) {
                selection.index = defIdx
            }
            
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard NSApp.keyWindow != nil else { return event }
                let devices = allDevices
                guard !devices.isEmpty else { return event }
                
                switch event.keyCode {
                case 125: // Down
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection.index = (selection.index + 1) % devices.count
                    }
                    return nil
                case 126: // Up
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection.index = (selection.index - 1 + devices.count) % devices.count
                    }
                    return nil
                case 36, 49: // Return or Space
                    let dev = devices[selection.index]
                    if audioManager.outputDevices.contains(where: { $0.id == dev.id }) {
                        audioManager.setDefaultOutputDevice(id: dev.id)
                    } else {
                        audioManager.setDefaultInputDevice(id: dev.id)
                    }
                    return nil
                case 53: // Escape
                    NotificationCenter.default.post(name: .dismissPopover, object: nil)
                    return nil
                default:
                    break
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct BreathingWaveform: View {
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: "waveform")
            .scaleEffect(isAnimating ? 1.2 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct DeviceRowMenu: View {
    let device: AudioDevice
    let isDefault: Bool
    let isSelected: Bool
    let namespace: Namespace.ID
    let iconName: String
    let inactiveIconName: String
    let batteryLevel: String?
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isDefault ? iconName : inactiveIconName)
                    .foregroundColor(isSelected ? .white : (isDefault ? .blue : .primary))
                    .frame(width: 20)
                
                Text(device.name)
                    .font(.body)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                if let level = batteryLevel {
                    Text("(\(level) 🔋)")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                if device.isPlaying {
                    if isSelected {
                        Image(systemName: "waveform")
                            .foregroundColor(.white)
                    } else {
                        BreathingWaveform()
                            .foregroundColor(.green)
                    }
                }
                
                if isDefault {
                    Image(systemName: "checkmark")
                        .foregroundColor(isSelected ? .white : .blue)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "highlight", in: namespace)
                    }
                    
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}


