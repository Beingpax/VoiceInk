import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import os

// MARK: - Core Audio Recorder (AUHAL-based, does not change system default device)
final class CoreAudioRecorder: @unchecked Sendable {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CoreAudioRecorder")

    private var audioUnit: AudioUnit?
    private var audioFile: ExtAudioFileRef?

    private var isRecording = false
    private var isAudioUnitInitialized = false
    private var currentDeviceID: AudioDeviceID = 0
    private var recordingURL: URL?

    // Device format (what the hardware provides)
    private var deviceFormat = AudioStreamBasicDescription()
    // Output format (16kHz mono PCM Int16 for transcription)
    private var outputFormat = AudioStreamBasicDescription()

    // Conversion buffer
    private var conversionBuffer: UnsafeMutablePointer<Int16>?
    private var conversionBufferSize: UInt32 = 0

    // Audio metering (thread-safe)
    private let meterLock = NSLock()
    private var _averagePower: Float = -160.0
    private var _peakPower: Float = -160.0

    var averagePower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _averagePower
    }

    var peakPower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _peakPower
    }

    // Pre-allocated render buffer (to avoid malloc in real-time callback)
    private var renderBuffer: UnsafeMutablePointer<Float32>?
    private var renderBufferSize: UInt32 = 0

    /// Called on the audio thread with raw PCM data (16-bit, 16kHz, mono) for streaming.
    private let audioChunkLock = NSLock()
    private var _onAudioChunk: ((_ data: Data) -> Void)?
    var onAudioChunk: ((_ data: Data) -> Void)? {
        get {
            audioChunkLock.lock()
            defer { audioChunkLock.unlock() }
            return _onAudioChunk
        }
        set {
            audioChunkLock.lock()
            _onAudioChunk = newValue
            audioChunkLock.unlock()
        }
    }

    // MARK: - Initialization

    init() {}

    deinit {
        teardown()
    }

    // MARK: - Public Interface

    /// Prepares AUHAL for the selected device without starting capture.
    func prepare(deviceID: AudioDeviceID) throws {
        if isRecording {
            return
        }

        try validateDevice(deviceID)

        if isPrepared(for: deviceID) {
            return
        }

        teardownPreparedAudioUnit()
        currentDeviceID = deviceID

        logDeviceDetails(deviceID: deviceID)

        do {
            try createAudioUnit()

            try setInputDevice(deviceID)

            try configureFormats()

            try setupInputCallback()

            try initializeAudioUnit()
        } catch {
            teardownPreparedAudioUnit()
            throw error
        }
    }

    /// Starts recording from the specified device to the given URL (WAV format)
    func startRecording(toOutputFile url: URL, deviceID: AudioDeviceID) throws {
        // Stop any existing recording
        stopRecording()

        try prepare(deviceID: deviceID)

        do {
            recordingURL = url

            // The output file is per recording; the AUHAL setup above is reused.
            try createOutputFile(at: url)

            try startAudioUnit()
        } catch {
            isRecording = false
            closeOutputFile()
            recordingURL = nil
            teardownPreparedAudioUnit()
            throw error
        }
    }

    /// Stops the current recording
    func stopRecording() {
        guard isRecording || audioFile != nil else {
            return
        }

        let wasRecording = isRecording
        isRecording = false

        if wasRecording, let unit = audioUnit {
            let stopStatus = AudioOutputUnitStop(unit)
            if stopStatus != noErr {
                logger.warning("🎙️ AudioOutputUnitStop returned \(stopStatus, privacy: .public)")
            }

            let resetStatus = AudioUnitReset(unit, kAudioUnitScope_Global, 0)
            if resetStatus != noErr {
                logger.warning("🎙️ AudioUnitReset returned \(resetStatus, privacy: .public)")
            }
        }

        closeOutputFile()
        recordingURL = nil

        resetMeters()
    }

    /// Releases the prepared AUHAL and buffers. Use for app shutdown or hard recovery.
    func teardown() {
        stopRecording()
        teardownPreparedAudioUnit()
        recordingURL = nil
        currentDeviceID = 0
        resetMeters()
    }

    var isCurrentlyRecording: Bool { isRecording }
    var currentRecordingURL: URL? { recordingURL }
    var currentDevice: AudioDeviceID { currentDeviceID }

    /// Switches to a new input device mid-recording without stopping the file write
    func switchDevice(to newDeviceID: AudioDeviceID) throws {
        guard isRecording, let unit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Don't switch if it's the same device
        guard newDeviceID != currentDeviceID else { return }

        let oldDeviceID = currentDeviceID
        logger.notice("🎙️ Switching recording device from \(oldDeviceID, privacy: .public) to \(newDeviceID, privacy: .public)")

        // Step 1: Stop the AudioUnit (but keep file open)
        var status = AudioOutputUnitStop(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioOutputUnitStop returned \(status, privacy: .public)")
        }

        // Step 2: Uninitialize to allow reconfiguration
        status = AudioUnitUninitialize(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioUnitUninitialize returned \(status, privacy: .public)")
        }
        isAudioUnitInitialized = false

        // Step 3: Set the new device
        var device = newDeviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            // Try to recover by restarting with old device
            logger.error("Failed to set new device: \(status, privacy: .public). Attempting recovery...")
            var recoveryDevice = oldDeviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &recoveryDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
            let initializeStatus = AudioUnitInitialize(unit)
            isAudioUnitInitialized = initializeStatus == noErr
            if initializeStatus == noErr {
                AudioOutputUnitStart(unit)
            }
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }

        // Step 4: Get new device format
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var newDeviceFormat = AudioStreamBasicDescription()
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &newDeviceFormat,
            &formatSize
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Step 5: Configure callback format for new device
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: newDeviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: newDeviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Step 6: Reallocate buffers if needed
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * newDeviceFormat.mChannelsPerFrame
        if bufferSamples > renderBufferSize {
            renderBuffer?.deallocate()
            renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
            renderBufferSize = bufferSamples
        }

        // Reallocate conversion buffer if new sample rate requires more space
        let maxOutputFrames = UInt32(Double(maxFrames) * (outputFormat.mSampleRate / newDeviceFormat.mSampleRate)) + 1
        if maxOutputFrames > conversionBufferSize {
            conversionBuffer?.deallocate()
            conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(maxOutputFrames))
            conversionBufferSize = maxOutputFrames
        }

        // Update stored format
        deviceFormat = newDeviceFormat
        currentDeviceID = newDeviceID

        // Step 7: Reinitialize and restart
        status = AudioUnitInitialize(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }
        isAudioUnitInitialized = true

        status = AudioOutputUnitStart(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToStart(status: status)
        }

        logger.notice("🎙️ Successfully switched to device \(newDeviceID, privacy: .public)")
    }

    // MARK: - AudioUnit Setup

    private func createAudioUnit() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            logger.error("AudioUnit not found - HAL Output component unavailable")
            throw CoreAudioRecorderError.audioUnitNotFound
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            logger.error("Failed to create AudioUnit instance: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateAudioUnit(status: status)
        }

        self.audioUnit = audioUnit

        // Enable input on element 1 (input scope)
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Element 1 = input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to enable audio input: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToEnableInput(status: status)
        }

        // Disable output on element 0 (output scope)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // Element 0 = output
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to disable audio output: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToDisableOutput(status: status)
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.error("Failed to set input device \(deviceID, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }
    }

    private func configureFormats() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Get the device's native format (input scope, element 1)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &deviceFormat,
            &formatSize
        )

        if status != noErr {
            logger.error("Failed to get device format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Configure output format: 16kHz, mono, PCM Int16
        outputFormat = AudioStreamBasicDescription(
            mSampleRate: 16000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        // Set callback format (Float32 for processing, then convert to Int16 for file)
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: deviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: deviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            logger.error("Failed to set audio format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Log format details
        let devSampleRate = deviceFormat.mSampleRate
        let devChannels = deviceFormat.mChannelsPerFrame
        let devBits = deviceFormat.mBitsPerChannel
        let outSampleRate = outputFormat.mSampleRate
        let outChannels = outputFormat.mChannelsPerFrame
        let outBits = outputFormat.mBitsPerChannel
        logger.notice("🎙️ Device format: sampleRate=\(devSampleRate, privacy: .public), channels=\(devChannels, privacy: .public), bitsPerChannel=\(devBits, privacy: .public)")
        logger.notice("🎙️ Output format: sampleRate=\(outSampleRate, privacy: .public), channels=\(outChannels, privacy: .public), bitsPerChannel=\(outBits, privacy: .public)")
        if devSampleRate != outSampleRate {
            logger.notice("🎙️ Converting: \(Int(devSampleRate), privacy: .public)Hz → \(Int(outSampleRate), privacy: .public)Hz")
        }

        freeBuffers()

        // Pre-allocate buffers for real-time callback (avoid malloc in callback)
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * deviceFormat.mChannelsPerFrame
        renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
        renderBufferSize = bufferSamples

        // Pre-allocate conversion buffer (output is always smaller due to downsampling)
        let maxOutputFrames = UInt32(Double(maxFrames) * (outputFormat.mSampleRate / deviceFormat.mSampleRate)) + 1
        conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(maxOutputFrames))
        conversionBufferSize = maxOutputFrames
    }

    private func setupInputCallback() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to set input callback: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetCallback(status: status)
        }
    }

    private func createOutputFile(at url: URL) throws {
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create ExtAudioFile for writing
        var fileRef: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &fileRef
        )

        if status != noErr {
            logger.error("Failed to create audio file at \(url.path, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateFile(status: status)
        }

        audioFile = fileRef

        // Set client format (what we'll write)
        status = ExtAudioFileSetProperty(
            fileRef!,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &outputFormat
        )

        if status != noErr {
            logger.error("Failed to set file format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetFileFormat(status: status)
        }
    }

    private func initializeAudioUnit() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        guard !isAudioUnitInitialized else { return }

        let status = AudioUnitInitialize(audioUnit)
        if status != noErr {
            logger.error("Failed to initialize AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }
        isAudioUnitInitialized = true
    }

    private func startAudioUnit() throws {
        guard let audioUnit = audioUnit, isAudioUnitInitialized else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        isRecording = true
        let status = AudioOutputUnitStart(audioUnit)
        if status != noErr {
            isRecording = false
            logger.error("Failed to start AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToStart(status: status)
        }
    }

    private func isPrepared(for deviceID: AudioDeviceID) -> Bool {
        audioUnit != nil && isAudioUnitInitialized && currentDeviceID == deviceID && isDeviceAvailable(deviceID)
    }

    private func validateDevice(_ deviceID: AudioDeviceID) throws {
        if deviceID == 0 {
            logger.error("Cannot start recording - no valid audio device (deviceID is 0)")
            throw CoreAudioRecorderError.failedToSetDevice(status: 0)
        }

        guard isDeviceAvailable(deviceID) else {
            logger.error("Cannot start recording - device \(deviceID, privacy: .public) is no longer available")
            throw CoreAudioRecorderError.deviceNotAvailable
        }
    }

    private func closeOutputFile() {
        if let file = audioFile {
            ExtAudioFileDispose(file)
            audioFile = nil
        }
    }

    private func teardownPreparedAudioUnit() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            if isAudioUnitInitialized {
                AudioUnitUninitialize(unit)
            }
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        isAudioUnitInitialized = false
        freeBuffers()
    }

    private func freeBuffers() {
        if let buffer = conversionBuffer {
            buffer.deallocate()
            conversionBuffer = nil
            conversionBufferSize = 0
        }

        if let buffer = renderBuffer {
            buffer.deallocate()
            renderBuffer = nil
            renderBufferSize = 0
        }
    }

    private func resetMeters() {
        meterLock.lock()
        _averagePower = -160.0
        _peakPower = -160.0
        meterLock.unlock()
    }

    // MARK: - Input Callback

    private let inputCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in

        let recorder = Unmanaged<CoreAudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.handleInputBuffer(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inBusNumber: inBusNumber,
            inNumberFrames: inNumberFrames
        )
    }

    private func handleInputBuffer(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) -> OSStatus {

        guard let audioUnit = audioUnit, isRecording, let renderBuf = renderBuffer else {
            return noErr
        }

        // Use pre-allocated buffer for input data
        let channelCount = deviceFormat.mChannelsPerFrame
        let requiredSamples = inNumberFrames * channelCount

        // Safety check - shouldn't happen with 4096 max frames
        guard requiredSamples <= renderBufferSize else {
            return noErr
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * channelCount
        let bufferSize = inNumberFrames * bytesPerFrame

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: channelCount,
                mDataByteSize: bufferSize,
                mData: renderBuf
            )
        )

        // Render audio from the input
        let status = AudioUnitRender(
            audioUnit,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            &bufferList
        )

        if status != noErr {
            return status
        }

        // Calculate audio meters from input buffer
        calculateMeters(from: &bufferList, frameCount: inNumberFrames)

        // Convert and write to file
        convertAndWriteToFile(inputBuffer: &bufferList, frameCount: inNumberFrames)

        return noErr
    }

    private func calculateMeters(from bufferList: inout AudioBufferList, frameCount: UInt32) {
        guard let data = bufferList.mBuffers.mData else { return }
        guard frameCount > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float32.self)
        let channelCount = Int(deviceFormat.mChannelsPerFrame)
        let totalSamples = Int(frameCount) * channelCount

        guard totalSamples > 0 else { return }

        var sum: Float = 0.0
        var peak: Float = 0.0

        for i in 0..<totalSamples {
            let sample = abs(samples[i])
            sum += sample * sample
            if sample > peak {
                peak = sample
            }
        }

        let rms = sqrt(sum / Float(totalSamples))
        let avgDb = 20.0 * log10(max(rms, 0.000001))
        let peakDb = 20.0 * log10(max(peak, 0.000001))

        meterLock.lock()
        _averagePower = avgDb
        _peakPower = peakDb
        meterLock.unlock()
    }

    private func convertAndWriteToFile(inputBuffer: inout AudioBufferList, frameCount: UInt32) {
        guard let file = audioFile else { return }

        let inputChannels = deviceFormat.mChannelsPerFrame
        let inputSampleRate = deviceFormat.mSampleRate
        let outputSampleRate = outputFormat.mSampleRate

        // Get input samples
        guard let inputData = inputBuffer.mBuffers.mData else { return }
        let inputSamples = inputData.assumingMemoryBound(to: Float32.self)

        // Calculate output frame count after sample rate conversion
        let ratio = outputSampleRate / inputSampleRate
        let outputFrameCount = UInt32(Double(frameCount) * ratio)

        guard outputFrameCount > 0,
              let outputBuffer = conversionBuffer,
              outputFrameCount <= conversionBufferSize else { return }

        // Convert Float32 multi-channel → Int16 mono (with sample rate conversion if needed)
        if inputSampleRate == outputSampleRate {
            // Direct conversion, just format change and channel mixing
            for i in 0..<Int(frameCount) {
                var sample: Float32 = 0
                // Mix all channels to mono
                for ch in 0..<Int(inputChannels) {
                    sample += inputSamples[i * Int(inputChannels) + ch]
                }
                sample /= Float32(inputChannels)

                // Convert to Int16 with clipping
                let scaled = sample * 32767.0
                let clipped = max(-32768.0, min(32767.0, scaled))
                outputBuffer[i] = Int16(clipped)
            }
        } else {
            // Sample rate conversion needed - use linear interpolation
            for i in 0..<Int(outputFrameCount) {
                let inputIndex = Double(i) / ratio
                let inputIndexInt = Int(inputIndex)
                let frac = Float32(inputIndex - Double(inputIndexInt))

                var sample: Float32 = 0
                let idx1 = min(inputIndexInt, Int(frameCount) - 1)
                let idx2 = min(inputIndexInt + 1, Int(frameCount) - 1)

                // Mix channels and interpolate
                for ch in 0..<Int(inputChannels) {
                    let s1 = inputSamples[idx1 * Int(inputChannels) + ch]
                    let s2 = inputSamples[idx2 * Int(inputChannels) + ch]
                    sample += s1 + frac * (s2 - s1)
                }
                sample /= Float32(inputChannels)

                // Convert to Int16
                let scaled = sample * 32767.0
                let clipped = max(-32768.0, min(32767.0, scaled))
                outputBuffer[i] = Int16(clipped)
            }
        }

        // Write to file
        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: outputFrameCount * 2,
                mData: outputBuffer
            )
        )

        let writeStatus = ExtAudioFileWrite(file, outputFrameCount, &outputBufferList)
        if writeStatus != noErr {
            logger.error("🎙️ ExtAudioFileWrite failed with status: \(writeStatus, privacy: .public)")
        }

        // Send the same PCM data to the streaming callback if set.
        if let audioChunk = onAudioChunk {
            let byteCount = Int(outputFrameCount) * MemoryLayout<Int16>.size
            let data = Data(bytes: outputBuffer, count: byteCount)
            audioChunk(data)
        }
    }

    // MARK: - Device Info Logging

    private func logDeviceDetails(deviceID: AudioDeviceID) {
        // Get device name
        let deviceName = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Unknown"

        // Get device UID
        let deviceUID = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "Unknown"

        // Get transport type
        let transportType = getTransportType(deviceID: deviceID)

        // Get manufacturer
        let manufacturer = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString) ?? "Unknown"

        logger.notice("🎙️ Device info: name=\(deviceName, privacy: .public), uid=\(deviceUID, privacy: .public)")
        logger.notice("🎙️ Device details: transport=\(transportType, privacy: .public), manufacturer=\(manufacturer, privacy: .public)")

        // Get buffer frame size
        if let bufferSize = getBufferFrameSize(deviceID: deviceID) {
            let latencyMs = (Double(bufferSize) / 48000.0) * 1000.0 // Approximate latency assuming 48kHz
            logger.notice("🎙️ Buffer size: \(bufferSize, privacy: .public) frames, ~latency: \(String(format: "%.1f", latencyMs), privacy: .public)ms")
        }
    }

    private func getDeviceStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var property: CFString?

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )

        if status == noErr, let cfString = property {
            return cfString as String
        }
        return nil
    }

    private func getTransportType(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        if status != noErr {
            return "Unknown"
        }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeAggregate:
            return "Aggregate"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        case kAudioDeviceTransportTypePCI:
            return "PCI"
        case kAudioDeviceTransportTypeFireWire:
            return "FireWire"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeAVB:
            return "AVB"
        case kAudioDeviceTransportTypeThunderbolt:
            return "Thunderbolt"
        default:
            return "Other (\(transportType))"
        }
    }

    private func getBufferFrameSize(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bufferSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &bufferSize
        )

        return status == noErr ? bufferSize : nil
    }

    /// Checks if a device is currently available using Apple's kAudioDevicePropertyDeviceIsAlive
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isAlive
        )

        return status == noErr && isAlive == 1
    }
}

// MARK: - Error Types

enum CoreAudioRecorderError: LocalizedError {
    case audioUnitNotFound
    case audioUnitNotInitialized
    case deviceNotAvailable
    case failedToCreateAudioUnit(status: OSStatus)
    case failedToEnableInput(status: OSStatus)
    case failedToDisableOutput(status: OSStatus)
    case failedToSetDevice(status: OSStatus)
    case failedToGetDeviceFormat(status: OSStatus)
    case failedToSetFormat(status: OSStatus)
    case failedToSetCallback(status: OSStatus)
    case failedToCreateFile(status: OSStatus)
    case failedToSetFileFormat(status: OSStatus)
    case failedToInitialize(status: OSStatus)
    case failedToStart(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .audioUnitNotFound:
            return "HAL Output AudioUnit not found"
        case .audioUnitNotInitialized:
            return "AudioUnit not initialized"
        case .deviceNotAvailable:
            return "Audio device is no longer available"
        case .failedToCreateAudioUnit(let status):
            return "Failed to create AudioUnit: \(status)"
        case .failedToEnableInput(let status):
            return "Failed to enable input: \(status)"
        case .failedToDisableOutput(let status):
            return "Failed to disable output: \(status)"
        case .failedToSetDevice(let status):
            return "Failed to set input device: \(status)"
        case .failedToGetDeviceFormat(let status):
            return "Failed to get device format: \(status)"
        case .failedToSetFormat(let status):
            return "Failed to set audio format: \(status)"
        case .failedToSetCallback(let status):
            return "Failed to set input callback: \(status)"
        case .failedToCreateFile(let status):
            return "Failed to create audio file: \(status)"
        case .failedToSetFileFormat(let status):
            return "Failed to set file format: \(status)"
        case .failedToInitialize(let status):
            return "Failed to initialize AudioUnit: \(status)"
        case .failedToStart(let status):
            return "Failed to start AudioUnit: \(status)"
        }
    }
}
