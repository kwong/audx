import Foundation
import SwiftUI
import UserNotifications

class IdleManager: ObservableObject {
    private var timer: Timer?
    private var idleStartTimes: [String: Date] = [:] // MAC Address to Date
    private var notifiedDevices: Set<String> = [] // MAC Address Set
    
    @AppStorage("idleTimeoutMinutes") private var idleTimeoutMinutes: Double = 15.0
    @AppStorage("showIdleWarnings") private var showIdleWarnings: Bool = true
    
    // Dependencies
    weak var audioManager: AudioManager?
    weak var bluetoothManager: BluetoothManager?
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error.localizedDescription)")
            }
        }
    }
    
    func start() {
        // Poll every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdleStatus()
        }
        checkIdleStatus()
    }
    
    private func checkIdleStatus() {
        if idleTimeoutMinutes <= 0.0 {
            idleStartTimes.removeAll()
            notifiedDevices.removeAll()
            return // "Never" timeout selected
        }
        
        guard let btm = bluetoothManager, let am = audioManager else { return }
        
        btm.refreshDevices()
        am.refreshDevices()
        
        let connectedBTDevices = btm.connectedAudioDevices
        
        var currentBTIds: Set<String> = []
        
        for btDevice in connectedBTDevices {
            currentBTIds.insert(btDevice.id)
            
            // Match via exact name in either output or input
            let isPlayingOut = am.outputDevices.contains { $0.name == btDevice.name && $0.isPlaying }
            let isPlayingIn = am.inputDevices.contains { $0.name == btDevice.name && $0.isPlaying }
            let isPlaying = isPlayingOut || isPlayingIn
            
            if isPlaying {
                idleStartTimes.removeValue(forKey: btDevice.id)
                notifiedDevices.remove(btDevice.id)
            } else {
                if idleStartTimes[btDevice.id] == nil {
                    idleStartTimes[btDevice.id] = Date()
                } else if let startTime = idleStartTimes[btDevice.id] {
                    let idleDuration = Date().timeIntervalSince(startTime)
                    let timeoutSeconds = idleTimeoutMinutes * 60
                    
                    let warningThreshold = max(0, timeoutSeconds - 60) // 1 minute before disconnect
                    
                    if showIdleWarnings && idleDuration >= warningThreshold && !notifiedDevices.contains(btDevice.id) && timeoutSeconds > 60 {
                        sendIdleNotification(for: btDevice.name, id: btDevice.id)
                        notifiedDevices.insert(btDevice.id)
                    }
                    
                    if idleDuration >= timeoutSeconds {
                        print("Device \(btDevice.name) has been idle. Disconnecting...")
                        btm.disconnect(device: btDevice.device)
                        idleStartTimes.removeValue(forKey: btDevice.id)
                        notifiedDevices.remove(btDevice.id)
                    }
                }
            }
        }
        
        // Cleanup tracking for devices that disconnected naturally
        for trackedId in idleStartTimes.keys {
            if !currentBTIds.contains(trackedId) {
                idleStartTimes.removeValue(forKey: trackedId)
                notifiedDevices.remove(trackedId)
            }
        }
    }
    
    private func sendIdleNotification(for deviceName: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = "Device Idle"
        content.body = "\(deviceName) will be disconnected in 1 minute due to inactivity."
        content.sound = .default
        
        // Remove stale notifications for this device to prevent clutter
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["idle-\(id)"])
        
        let request = UNNotificationRequest(identifier: "idle-\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error.localizedDescription)")
            }
        }
    }
}
