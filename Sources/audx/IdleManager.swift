import Foundation
import SwiftUI
import AppKit
import UserNotifications

enum NotificationAuthorizationState: Equatable {
    case notDetermined
    case denied
    case authorized

    init(status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral:
            self = .authorized
        case .denied:
            self = .denied
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }
}

class IdleManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var notificationsAllowed: Bool = false
    @Published var notificationAuthorizationState: NotificationAuthorizationState = .notDetermined
    @Published var isUpdatingNotificationPermission: Bool = false
    private var timer: Timer?
    private var idleStartTimes: [String: Date] = [:] // MAC Address to Date
    private var notifiedDevices: Set<String> = [] // MAC Address Set
    private var lastTestNotificationIdentifier: String?
    
    @AppStorage("idleTimeoutMinutes") private var idleTimeoutMinutes: Double = 15.0
    @AppStorage("showIdleWarnings") private var showIdleWarnings: Bool = true
    
    // Dependencies
    weak var audioManager: AudioManager?
    weak var bluetoothManager: BluetoothManager?
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshNotificationAuthorizationStatus()
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

    func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.applyNotificationSettings(settings)
            }
        }
    }

    func setDisconnectWarningsEnabled(_ enabled: Bool) {
        guard enabled else {
            showIdleWarnings = false
            refreshNotificationAuthorizationStatus()
            return
        }

        isUpdatingNotificationPermission = true
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }

            DispatchQueue.main.async {
                self.applyNotificationSettings(settings)
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    self.showIdleWarnings = true
                    self.isUpdatingNotificationPermission = false
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("[IdleManager] Notification auth error: \(error.localizedDescription)")
                    }

                    self.refreshNotificationAuthorizationStatus()

                    DispatchQueue.main.async {
                        self.showIdleWarnings = granted
                        self.isUpdatingNotificationPermission = false
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    self.showIdleWarnings = false
                    self.isUpdatingNotificationPermission = false
                }
            @unknown default:
                DispatchQueue.main.async {
                    self.showIdleWarnings = false
                    self.isUpdatingNotificationPermission = false
                }
            }
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func sendTestIdleNotification() {
        let deviceName = bluetoothManager?.connectedAudioDevices.first?.name ?? "Bluetooth Device"
        let identifier = "test-\(UUID().uuidString)"
        removeNotificationIfNeeded(identifier: lastTestNotificationIdentifier)
        lastTestNotificationIdentifier = identifier
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        sendNotification(
            for: deviceName,
            id: identifier,
            disableWarningsOnFailure: false,
            trigger: trigger
        )
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
        sendNotification(for: deviceName, id: id, disableWarningsOnFailure: true, trigger: nil)
    }

    private func sendNotification(
        for deviceName: String,
        id: String,
        disableWarningsOnFailure: Bool,
        trigger: UNNotificationTrigger?
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            print("[IdleManager] Notification authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue)")
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("[IdleManager] Notifications not authorized")
                DispatchQueue.main.async {
                    self?.applyNotificationSettings(settings)
                    if disableWarningsOnFailure {
                        self?.showIdleWarnings = false
                    }
                }
                return
            }

            let content = self?.makeIdleNotificationContent(for: deviceName) ?? UNMutableNotificationContent()

            // Remove stale notifications for this device to prevent clutter
            self?.removeNotification(identifier: id)

            let request = UNNotificationRequest(identifier: "idle-\(id)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[IdleManager] Error showing notification: \(error.localizedDescription)")
                }
            }
        }
    }

    private func makeIdleNotificationContent(for deviceName: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Device Idle"
        content.body = "\(deviceName) will be disconnected in 1 minute due to inactivity."
        content.sound = .default
        return content
    }

    private func removeNotificationIfNeeded(identifier: String?) {
        guard let identifier else { return }
        removeNotification(identifier: identifier)
    }

    private func removeNotification(identifier: String) {
        let notificationIdentifier = "idle-\(identifier)"
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private func applyNotificationSettings(_ settings: UNNotificationSettings) {
        let state = NotificationAuthorizationState(status: settings.authorizationStatus)
        notificationAuthorizationState = state
        notificationsAllowed = state == .authorized

        if state == .denied && showIdleWarnings {
            showIdleWarnings = false
        }
    }
}
