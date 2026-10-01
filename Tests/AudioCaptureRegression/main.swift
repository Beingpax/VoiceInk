import AVFoundation
import CoreAudio
import Foundation

// Hardware regression test: run only with explicit opt-in. It temporarily changes
// the built-in microphone rate, restores it, and never uploads the recordings.
guard CommandLine.arguments.contains("--allow-sample-rate-changes") else {
    fatalError("Pass --allow-sample-rate-changes to test the built-in microphone")
}
func check(_ status: OSStatus) throws {
    if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}
func run() throws {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices))
    var selected: AudioDeviceID?
    for device in devices {
        var uid: CFString = "" as CFString
        address.mSelector = kAudioDevicePropertyDeviceUID
        size = UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid))
        if uid as String == "BuiltInMicrophoneDevice" { selected = device }
    }
    guard let device = selected else { throw NSError(domain: "Missing built-in microphone", code: 1) }
    address.mSelector = kAudioDevicePropertyNominalSampleRate
    size = UInt32(MemoryLayout<Double>.size)
    var originalRate: Double = 0
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &originalRate))
    let recorder = CoreAudioRecorder()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        recorder.teardown()
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &originalRate)
        if status != noErr { print("ERROR restoring microphone rate: \(status)") }
        try? FileManager.default.removeItem(at: directory)
    }
    func record(_ name: String) throws {
        let url = directory.appendingPathComponent(name + ".wav")
        try recorder.startRecording(toOutputFile: url, deviceID: device)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        recorder.stopRecording()
        let file = try AVAudioFile(forReading: url)
        guard file.length > 16000,
              file.fileFormat.sampleRate == 16000,
              file.fileFormat.channelCount == 1 else {
            throw NSError(domain: "Empty or invalid recording: \(name), frames=\(file.length)", code: 1)
        }
        print("PASS \(name): \(file.length) frames, 16 kHz mono")
    }
    try record("initial")
    try record("unchanged-reuse")
    // A DAW can change the rate without changing the device ID. Before the fix,
    // this next recording starts successfully but contains zero audio frames.
    var otherRate: Double = originalRate == 48000 ? 44100 : 48000
    try check(AudioObjectSetPropertyData(device, &address, 0, nil, size, &otherRate))
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    try record("changed-rate-reuse")
    try check(AudioObjectSetPropertyData(device, &address, 0, nil, size, &originalRate))
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    try record("restored-rate-reuse")
}
do { try run() } catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
