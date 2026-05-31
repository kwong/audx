import Foundation
import IOBluetooth

guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { exit(1) }

for device in paired {
    if device.isConnected() {
        print("\(device.nameOrAddress ?? "") - raw battery level?")
        // device.batteryLevel is unavailable? Let's check ObjC runtime selectors
        let sel = NSSelectorFromString("batteryLevel")
        if device.responds(to: sel) {
            let val = device.perform(sel)?.takeUnretainedValue() as? Int
            print("batteryLevel: \(String(describing: val))")
        }
    }
}
