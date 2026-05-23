import Foundation
import Speech
import AVFoundation

class SpeechRecognizerManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var soundLevel: Float = 0.0
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var isMicrophoneAuthorized: Bool = false

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let speechQueue = DispatchQueue(label: "com.antigravity.MacSynergy.SpeechQueue", qos: .userInitiated)

    init() {
        // Default to system locale or Korean
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) ?? SFSpeechRecognizer()
        checkExistingPermissions()
    }
    
    private func checkExistingPermissions() {
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        self.isMicrophoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Requests all required permissions asynchronously. Returns true if both are granted.
    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        await MainActor.run {
            self.authorizationStatus = speechStatus
        }
        
        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        await MainActor.run {
            self.isMicrophoneAuthorized = micGranted
        }
        
        return (speechStatus == .authorized) && micGranted
    }

    /// Starts recording and transcribing audio.
    func startRecording(onTranscriptUpdate: @escaping (String) -> Void) {
        speechQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check permissions first
            guard SFSpeechRecognizer.authorizationStatus() == .authorized,
                  AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                DispatchQueue.main.async {
                    self.transcript = "Permission Denied. Please enable Microphone & Speech Recognition in Settings."
                    onTranscriptUpdate(self.transcript)
                }
                return
            }

            self.stopRecordingInternal()

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            
            // Native on-device translation is faster if supported
            if #available(macOS 10.15, *), let recognizer = self.speechRecognizer, recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            self.audioEngine = engine
            self.recognitionRequest = request

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                self?.calculateSoundLevel(from: buffer)
            }

            engine.prepare()
            do {
                try engine.start()
            } catch {
                print("SpeechRecognizerManager: Failed to start audio engine: \(error)")
                self.stopRecordingInternal()
                return
            }

            guard let recognizer = self.speechRecognizer else {
                print("SpeechRecognizerManager: Speech recognizer not available.")
                self.stopRecordingInternal()
                return
            }

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.transcript = text
                        onTranscriptUpdate(text)
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecordingInternal()
                }
            }

            DispatchQueue.main.async {
                self.isRecording = true
                self.transcript = ""
            }
        }
    }

    /// Stops recording and cleans up resources.
    func stopRecording() {
        speechQueue.async { [weak self] in
            self?.stopRecordingInternal()
        }
    }

    private func stopRecordingInternal() {
        if let task = recognitionTask {
            task.cancel()
            recognitionTask = nil
        }
        
        if let request = recognitionRequest {
            request.endAudio()
            recognitionRequest = nil
        }
        
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }

        DispatchQueue.main.async {
            self.isRecording = false
            self.soundLevel = 0.0
        }
    }

    /// Calculates RMS power of audio buffer and updates soundLevel between 0.0 and 1.0.
    private func calculateSoundLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataLength = Int(buffer.frameLength)
        
        var sum: Float = 0.0
        for i in 0..<channelDataLength {
            sum += channelData[i] * channelData[i]
        }
        
        let rms = sqrt(sum / Float(channelDataLength))
        // Map RMS (usually 0.0 to ~0.3) to 0.0 - 1.0
        let level = min(max(rms * 4.0, 0.0), 1.0)
        
        DispatchQueue.main.async {
            self.soundLevel = level
        }
    }
}
