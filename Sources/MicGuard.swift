import Foundation
import CoreAudio
import AppKit

// Core Audio does not identify the caller. Only infer takeovers during a
// short connection window; consume the window before attempting a correction.
struct ConnectionPolicy {
    private var known: Set<UInt32>?
    private var current: UInt32?
    private var candidates: Set<UInt32> = []
    private var previous: UInt32?
    private var deadline: TimeInterval = 0

    mutating func observe(inputs: Set<UInt32>, selected: UInt32,
                          now: TimeInterval) -> UInt32? {
        guard inputs.contains(selected) else { return nil }
        guard let known else {
            self.known = inputs
            current = selected
            return nil
        }
        let added = inputs.subtracting(known)
        self.known = inputs
        if now >= deadline || previous.map({ !inputs.contains($0) }) == true {
            candidates.removeAll()
            previous = nil
        }
        candidates.formIntersection(inputs)
        if !added.isEmpty {
            candidates.formUnion(added)
            previous = current
            deadline = now + 2
        }
        guard selected != current else { return nil }
        let target = previous
        let shouldRestore = candidates.contains(selected)
            && now < deadline && target.map(inputs.contains) == true
            && target != selected
        // Any choice consumes the pending connection, including our own write.
        candidates.removeAll()
        previous = nil
        current = selected
        return shouldRestore ? target : nil
    }
}

#if !POLICY_TESTS
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

func devices() -> [AudioDeviceID]? {
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return nil }
    guard size > 0 else { return [] }
    var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let status = result.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? result : nil
}

func hasInput(_ device: AudioDeviceID) -> Bool {
    var property = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
}

func builtInMicrophone() -> AudioDeviceID? {
    devices()?.first {
        scalar($0, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn
        && scalar($0, kAudioDevicePropertyDeviceIsAlive) == 1 && hasInput($0)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date()): \(message)\n".utf8))
}

var policy = ConnectionPolicy()

func reconcile() {
    guard let allDevices = devices(),
          let selected = scalar(system, kAudioHardwarePropertyDefaultInputDevice) else { return }
    let inputs = Set(allDevices.filter(hasInput))
    guard var target = policy.observe(inputs: inputs, selected: selected,
                                     now: ProcessInfo.processInfo.systemUptime) else { return }
    // Do not overwrite a newer selection made while the snapshot was read.
    guard scalar(system, kAudioHardwarePropertyDefaultInputDevice) == selected,
          scalar(target, kAudioDevicePropertyDeviceIsAlive) == 1 else { return }
    var property = address(kAudioHardwarePropertyDefaultInputDevice)
    let status = AudioObjectSetPropertyData(system, &property, 0, nil,
                                           UInt32(MemoryLayout<AudioDeviceID>.size), &target)
    if status == noErr {
        log("Restored previous microphone once (device \(target)).")
    } else {
        log("Could not restore microphone: OSStatus \(status).")
    }
}

@main
struct MicGuard {
    static func main() {
        if CommandLine.arguments.contains("--status") {
            print("Default input: \(scalar(system, kAudioHardwarePropertyDefaultInputDevice) ?? 0)")
            print("Built-in microphone: \(builtInMicrophone() ?? 0)")
            print("Default output: \(scalar(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0)")
            exit(0)
        }

        // Initialize and register on the same queue that processes notifications.
        queue.sync {
            reconcile()
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
                var property = address(selector)
                let status = AudioObjectAddPropertyListenerBlock(system, &property, queue) { _, _ in reconcile() }
                guard status == noErr else {
                    log("Could not register listener: OSStatus \(status).")
                    exit(1)
                }
            }
        }

        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { _ in queue.async { reconcile() } }

        log("MicGuard started.")
        withExtendedLifetime(wakeObserver) { RunLoop.main.run() }
    }
}
#endif
