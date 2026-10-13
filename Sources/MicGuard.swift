import Foundation
import CoreAudio
import AppKit

let system = AudioObjectID(kAudioObjectSystemObject)
let queue = DispatchQueue(label: "local.micguard.audio")

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func scalar(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var property = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

func devices() -> [AudioDeviceID] {
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return [] }
    guard size > 0 else { return [] }
    var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let status = result.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? result : []
}

func hasInput(_ device: AudioDeviceID) -> Bool {
    var property = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
}

func builtInMicrophone() -> AudioDeviceID? {
    devices().first {
        scalar($0, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn
        && scalar($0, kAudioDevicePropertyDeviceIsAlive) == 1 && hasInput($0)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date()): \(message)\n".utf8))
}

@discardableResult
func enforce() -> Bool {
    guard var target = builtInMicrophone() else { return false }
    if scalar(system, kAudioHardwarePropertyDefaultInputDevice) == target { return true }
    var property = address(kAudioHardwarePropertyDefaultInputDevice)
    let status = AudioObjectSetPropertyData(system, &property, 0, nil,
                                           UInt32(MemoryLayout<AudioDeviceID>.size), &target)
    if status == noErr {
        log("Restored built-in microphone (device \(target)).")
    } else {
        log("Could not restore microphone: OSStatus \(status).")
    }
    return status == noErr
}

// Bounded retries cover devices becoming ready after reconnect or wake.
var pendingRetry: DispatchWorkItem?
func reconcile(_ retries: Int = 5) {
    pendingRetry?.cancel()
    if !enforce(), retries > 0 {
        let retry = DispatchWorkItem { reconcile(retries - 1) }
        pendingRetry = retry
        queue.asyncAfter(deadline: .now() + 1, execute: retry)
    }
}

if CommandLine.arguments.contains("--status") {
    print("Default input: \(scalar(system, kAudioHardwarePropertyDefaultInputDevice) ?? 0)")
    print("Built-in microphone: \(builtInMicrophone() ?? 0)")
    print("Default output: \(scalar(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0)")
    exit(0)
}

for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
    var property = address(selector)
    let status = AudioObjectAddPropertyListenerBlock(system, &property, queue) { _, _ in reconcile() }
    guard status == noErr else {
        log("Could not register listener: OSStatus \(status).")
        exit(1)
    }
}

let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
) { _ in queue.async { reconcile() } }

queue.async { reconcile() }
log("MicGuard started.")
RunLoop.main.run()
