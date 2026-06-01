import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let isPlaying: Bool
    let isInput: Bool
    let isOutput: Bool
}

class AudioManager: ObservableObject {
    @Published var outputDevices: [AudioDevice] = []
    @Published var inputDevices: [AudioDevice] = []
    @Published var defaultOutputDeviceID: AudioDeviceID?
    @Published var defaultInputDeviceID: AudioDeviceID?
    
    private var refreshTimer: Timer?
    
    init() {
        refreshDevices()
        startMonitoring()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    private func startMonitoring() {
        // Periodic refresh to keep isPlaying state current
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        
        // Listen for default device changes via CoreAudio
        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
        
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
    }
    
    func refreshDevices() {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else { return }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs)
        guard status == noErr else { return }
        
        var outputs: [AudioDevice] = []
        var inputs: [AudioDevice] = []
        
        for id in deviceIDs {
            let isOut = hasChannels(id: id, scope: kAudioDevicePropertyScopeOutput)
            let isIn = hasChannels(id: id, scope: kAudioDevicePropertyScopeInput)
            
            if isOut || isIn {
                let name = getDeviceName(id: id)
                let playing = isDevicePlaying(id: id)
                
                let dev = AudioDevice(id: id, name: name, isPlaying: playing, isInput: isIn, isOutput: isOut)
                
                if isOut { outputs.append(dev) }
                if isIn { inputs.append(dev) }
            }
        }
        
        outputDevices = outputs
        inputDevices = inputs
        defaultOutputDeviceID = getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        defaultInputDeviceID = getDefaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
    }
    
    func setDefaultOutputDevice(id: AudioDeviceID) {
        setDevice(id: id, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }
    
    func setDefaultInputDevice(id: AudioDeviceID) {
        setDevice(id: id, selector: kAudioHardwarePropertyDefaultInputDevice)
    }
    
    // MARK: - Private Helpers
    
    private func setDevice(id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, size, &deviceID)
        
        refreshDevices()
    }
    
    private func hasChannels(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else { return false }
        
        let bufferListPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(propertySize))
        defer { bufferListPointer.deallocate() }
        
        let status2 = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &propertySize, bufferListPointer)
        guard status2 == noErr else { return false }
        
        let bufferList = bufferListPointer.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0.pointee }
        return bufferList.mNumberBuffers > 0
    }
    
    private func getDeviceName(id: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceName: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        
        let status = withUnsafeMutablePointer(to: &deviceName) { ptr in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &propertySize, ptr)
        }
        guard status == noErr else { return "Unknown Device" }
        return deviceName as String
    }
    
    private func isDevicePlaying(id: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isRunning: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &propertySize, &isRunning)
        if status != noErr {
            propertyAddress.mSelector = kAudioDevicePropertyDeviceIsRunning
            let status2 = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &propertySize, &isRunning)
            if status2 != noErr { return false }
        }
        
        return isRunning > 0
    }
    
    private func getDefaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        return status == noErr ? deviceID : nil
    }
}
