import Foundation

/// Abstraction for background LLM workload generation.
/// Implement this protocol to plug in any local inference engine
/// (e.g. llama.cpp, MLX, CoreML, or a custom Metal compute pipeline).
protocol LLMEngine: Sendable {
    /// Simulate or execute an end-to-end inference request.
    func inference(prompt: String) async throws

    /// Request cancellation of any in-progress work.
    func cancel()
}
