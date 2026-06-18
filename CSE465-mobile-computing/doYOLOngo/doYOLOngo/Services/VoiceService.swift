import Foundation
import Speech
import AVFoundation

final class VoiceService {
    // English recognition (en-US)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    /// Request speech recognition and microphone permissions
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async { completion(granted) }
                    }
                default:
                    completion(false)
                }
            }
        }
    }
    
    /// Start microphone recording and speech recognition
    func startListening(onText: @escaping (String) -> Void, onError: @escaping () -> Void) {
        stopListening()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Duck other audio and enter recording mode (duckOthers)
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Voice] Audio Session Error: \(error)")
            onError()
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest, 
              let speechRecognizer = speechRecognizer, 
              speechRecognizer.isAvailable else {
            onError()
            return
        }
        
        // Allow partial results (continuous feedback while speaking)
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                onText(text)
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self?.stopListening()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("[Voice] Audio Engine Error: \(error)")
            onError()
        }
    }
    
    /// Force stop speech recognition
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        // Release microphone access
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
