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
                let majorClass = device.deviceClassMajor
                let serviceClass = device.serviceClassMajor
                let name = device.nameOrAddress ?? "Unknown"
                let address = device.addressString ?? "Unknown"
                print("[BluetoothManager] connected: \(name) majorClass=0x\(String(majorClass, radix: 16)) serviceClass=0x\(String(serviceClass, radix: 16))")

                // Major class 4 = Audio/Video.
                // Service class bit 0x100 = Audio (some headsets only set service class, not major class).
                let isAudio = majorClass == kBluetoothDeviceClassMajorAudio
                    || (serviceClass & 0x100) != 0

                if isAudio {
                    connected.append(BluetoothAudioDevice(id: address, name: name, device: device))
                }
            }
        }
        
        // Update device list immediately so idle manager sees current state
        connectedAudioDevices = connected

        // Fetch battery levels in background and update in-place when done
        var snapshot = connected
        DispatchQueue.global(qos: .userInitiated).async {
            self.fetchBatteryLevels(for: &snapshot)
            DispatchQueue.main.async {
                // Merge battery data into current list (devices may have changed while fetching)
                for updated in snapshot {
                    if let idx = self.connectedAudioDevices.firstIndex(where: { $0.id == updated.id }) {
                        self.connectedAudioDevices[idx].batteryLevel = updated.batteryLevel
                    }
                }
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
