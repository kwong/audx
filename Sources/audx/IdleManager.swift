import Foundation
import SwiftUI
import AppKit
import UserNotifications

class IdleManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var notificationsAllowed: Bool = true
    private var timer: Timer?
    private var idleStartTimes: [String: Date] = [:] // MAC Address to Date
    private var notifiedDevices: Set<String> = [] // MAC Address Set
    
    @AppStorage("idleTimeoutMinutes") private var idleTimeoutMinutes: Double = 15.0
    @AppStorage("showIdleWarnings") private var showIdleWarnings: Bool = true
    
    // Dependencies
    weak var audioManager: AudioManager?
    weak var bluetoothManager: BluetoothManager?
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationsAllowed = granted
            }
            if let error = error {
                print("[IdleManager] Notification auth error: \(error.localizedDescription)")
            }
            print("[IdleManager] Notification permission granted=\(granted)")
            if !granted {
                print("[IdleManager] Notifications denied. Enable audx notifications in System Settings → Notifications.")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    func start() {
        // Poll every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdleStatus()
        }
        checkIdleStatus()
    }
    
    private func checkIdleStatus() {
        print("[IdleManager] checkIdleStatus — timeout=\(idleTimeoutMinutes)m showWarnings=\(showIdleWarnings)")
        if idleTimeoutMinutes <= 0.0 {
            idleStartTimes.removeAll()
            notifiedDevices.removeAll()
            return // "Never" timeout selected
        }
        
        guard let btm = bluetoothManager, let am = audioManager else {
            print("[IdleManager] managers not ready")
            return
        }
        
        btm.refreshDevices()
        am.refreshDevices()
        
        let connectedBTDevices = btm.connectedAudioDevices
        print("[IdleManager] BT audio devices: \(connectedBTDevices.map(\.name))")
        print("[IdleManager] CoreAudio outputs: \(am.outputDevices.map { "\($0.name) playing=\($0.isPlaying)" })")
        
        var currentBTIds: Set<String> = []
        
        for btDevice in connectedBTDevices {
            currentBTIds.insert(btDevice.id)
            
            // Match via exact name in either output or input
            let isPlayingOut = am.outputDevices.contains { $0.name == btDevice.name && $0.isPlaying }
            let isPlayingIn = am.inputDevices.contains { $0.name == btDevice.name && $0.isPlaying }
            let isPlaying = isPlayingOut || isPlayingIn
            print("[IdleManager] \(btDevice.name) — isPlaying=\(isPlaying) idleSince=\(idleStartTimes[btDevice.id].map { String(format: "%.0fs ago", Date().timeIntervalSince($0)) } ?? "nil")")
            
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
                    print("[IdleManager] \(btDevice.name) — idleDuration=\(String(format: "%.0f", idleDuration))s threshold=\(String(format: "%.0f", warningThreshold))s timeout=\(String(format: "%.0f", timeoutSeconds))s warned=\(notifiedDevices.contains(btDevice.id))")
                    
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
        print("[IdleManager] Sending idle notification for \(deviceName)")
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            print("[IdleManager] Notification authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue)")
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("[IdleManager] Notifications not authorized — opening System Settings")
                DispatchQueue.main.async {
                    self?.notificationsAllowed = false
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Device Idle"
            content.body = "\(deviceName) will be disconnected in 1 minute due to inactivity."
            content.sound = .default

            // Remove stale notifications for this device to prevent clutter
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["idle-\(id)"])

            let request = UNNotificationRequest(identifier: "idle-\(id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[IdleManager] Error showing notification: \(error.localizedDescription)")
                }
            }
        }
    }
}
