import Foundation
import IOKit

var batteryLevels: [String: String] = [:]

guard let matchingDict = IOServiceMatching("AppleDeviceManagementHIDEventService") else {
    print("No matching dict")
    exit(1)
}

var iterator: io_iterator_t = 0
let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

if result == KERN_SUCCESS {
    var service = IOIteratorNext(iterator)
    while service != 0 {
        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
            if let dict = properties?.takeRetainedValue() as? [String: Any] {
                if let address = dict["DeviceAddress"] as? String,
                   let battery = dict["BatteryPercent"] as? Int {
                    let mac = address.replacingOccurrences(of: "-", with: ":").uppercased()
                    batteryLevels[mac] = "\(battery)%"
                }
            }
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    IOObjectRelease(iterator)
}

print(batteryLevels)
