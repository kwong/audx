import Foundation
import IOBluetooth

struct BluetoothAudioDevice: Identifiable, Equatable {
    let id: String // MAC Address
    let name: String
    let device: IOBluetoothDevice
    var batteryLevel: String?
    
    static func == (lhs: BluetoothAudioDevice, rhs: BluetoothAudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

class BluetoothManager: ObservableObject {
    @Published var connectedAudioDevices: [BluetoothAudioDevice] = []
    
    init() {
        refreshDevices()
    }
    
    func refreshDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        
        var connected: [BluetoothAudioDevice] = []
        
        for device in paired {
            if device.isConnected() {
                // Major class 1 is Computer, 2 is Phone, 4 is Audio/Video
                // Sometimes audio devices present as other classes depending on profile,
                // but usually, if it's an audio sink, it has major device class 4 or related service classes.
                // We'll trust major device class 4 OR (service class includes Audio/Render).
                let deviceClass = device.deviceClassMajor
                
                // 0x04 is Audio/Video
                let isAudio = deviceClass == kBluetoothDeviceClassMajorAudio
                
                if isAudio {
                    let name = device.nameOrAddress ?? "Unknown"
                    let address = device.addressString ?? "Unknown"
                    connected.append(BluetoothAudioDevice(id: address, name: name, device: device))
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.fetchBatteryLevels(for: &connected)
            DispatchQueue.main.async {
                self.connectedAudioDevices = connected
            }
        }
    }
    
    private func fetchBatteryLevels(for devices: inout [BluetoothAudioDevice]) {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let btData = json["SPBluetoothDataType"] as? [[String: Any]],
               let firstBlock = btData.first,
               let connectedBlock = firstBlock["device_connected"] as? [[String: Any]] {
                
                var batteryMap: [String: String] = [:]
                
                for devDict in connectedBlock {
                    for (_, details) in devDict {
                        if let dict = details as? [String: Any],
                           let address = dict["device_address"] as? String {
                            // Can be device_batteryLevelMain or just device_batteryLevel
                            if let level = dict["device_batteryLevelMain"] as? String {
                                batteryMap[address] = level
                            } else if let level = dict["device_batteryLevel"] as? String {
                                batteryMap[address] = level
                            } else if let level = dict["device_batteryLevelLeft"] as? String {
                                let right = dict["device_batteryLevelRight"] as? String ?? ""
                                batteryMap[address] = "L: \(level) R: \(right)"
                            }
                        }
                    }
                }
                
                for i in 0..<devices.count {
                    if let level = batteryMap[devices[i].id] {
                        devices[i].batteryLevel = level
                    }
                }
            }
        } catch {
            print("Failed to fetch Bluetooth battery levels: \(error)")
        }
    }
    
    func disconnect(device: IOBluetoothDevice) {
        device.closeConnection()
        refreshDevices()
    }
}
