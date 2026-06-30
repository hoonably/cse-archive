import Foundation
import os

/// In-process LLM engine using llama.cpp via LlamaBridge (Obj-C++).
/// Replaces ExternalProcessLLMEngine by running inference directly
/// inside the app process with runtime thread control.
final class InProcessLLMEngine: LLMEngine, @unchecked Sendable {
    private let bridge: LlamaBridge
    private let modelPath: String
    private let nThreads: Int
    private let nCtx: Int
    private let maxTokens: Int
    private var logger: CSVLogger?
    private let loggerLock = NSLock()
    private let outputHandler: @Sendable (String) -> Void
    private let modelLoadLock = NSLock()
    private var modelLoaded = false

    init(
        modelPath: String,
        nThreads: Int = 4,
        nCtx: Int = 2048,
        maxTokens: Int = 512,
        logger: CSVLogger?,
        outputHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.bridge = LlamaBridge()
        self.modelPath = modelPath
        self.nThreads = nThreads
        self.nCtx = nCtx
        self.maxTokens = maxTokens
        self.logger = logger
        self.outputHandler = outputHandler
    }

    func setLogger(_ logger: CSVLogger?) {
        loggerLock.lock()
        defer { loggerLock.unlock() }
        self.logger = logger
    }

    func inference(prompt: String) async throws {
        let state = Signposts.beginInference()
        log(event: "llm_inference_start", params: "in_process")

        try ensureModelLoaded()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bridge.startGeneration(
                withPrompt: prompt,
                tokenCallback: { [outputHandler] token in
                    outputHandler(token)
                },
                completion: {
                    cont.resume()
                }
            )
        }

        log(event: "llm_inference_end", params: "in_process")
        Signposts.endInference(state)
    }

    /// Preload the model before the measured scenario timer starts.
    @discardableResult
    func preloadModel() -> Bool {
        do {
            try ensureModelLoaded(preload: true)
            return true
        } catch {
            log(event: "llm_error", params: "preload_failed")
            return false
        }
    }

    func preloadModelAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                let loaded = preloadModel()
                continuation.resume(returning: loaded)
            }
        }
    }

    func cancel() {
        bridge.stopGeneration()
    }

    // MARK: - Decode delay

    /// Set the delay in milliseconds between token decode steps.
    func setDecodeDelayMs(_ ms: Int) {
        bridge.setDecodeDelayMicroseconds(Int32(ms * 1000))
    }

    func setQoSMode(_ mode: LLMQoSMode) {
        bridge.setGenerationQoSMode(mode.bridgeMode)
    }

    func setGenerationPaused(_ paused: Bool) {
        bridge.setGenerationPaused(paused)
    }

    private func log(event: String, params: String = "") {
        loggerLock.lock()
        let logger = logger
        loggerLock.unlock()
        logger?.log(event: event, params: params)
    }

    private func ensureModelLoaded(preload: Bool = false) throws {
        modelLoadLock.lock()
        defer { modelLoadLock.unlock() }

        guard !modelLoaded else { return }

        let ok = bridge.loadModel(atPath: modelPath, nThreads: Int32(nThreads), nCtx: Int32(nCtx))
        guard ok else {
            log(event: "llm_error", params: preload ? "preload_failed" : "model_load_failed")
            throw NSError(
                domain: "LlamaBridge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load model at \(modelPath)"]
            )
        }

        modelLoaded = true
        if preload {
            log(event: "llm_model_preloaded", params: "path=\(modelPath)")
        }
    }
}
