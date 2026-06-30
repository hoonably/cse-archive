import Foundation
import os

/// Launches an external command (e.g. llama.cpp's `llama-cli`) as the LLM backend.
/// Emits signposts around the process lifecycle and assembles standard llama.cpp
/// arguments from separate app fields for the model path, prompt, and extra args.
final class ExternalProcessLLMEngine: LLMEngine, @unchecked Sendable {
    private let deterministicSeed = 1234
    private let command: String
    private let modelPath: String
    private let extraArguments: String
    private let logger: CSVLogger?
    private let outputHandler: @Sendable (String) -> Void
    private var process: Process?

    init(
        command: String,
        modelPath: String,
        extraArguments: String,
        logger: CSVLogger?,
        outputHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.command = command
        self.modelPath = modelPath
        self.extraArguments = extraArguments
        self.logger = logger
        self.outputHandler = outputHandler
    }

    func inference(prompt: String) async throws {
        let state = Signposts.beginInference()
        logger?.log(event: "llm_inference_start", params: "cmd=\(command)")

        let proc = Process()
        let resolvedCommand = resolvedCommandLaunch()
        proc.executableURL = URL(fileURLWithPath: resolvedCommand.executablePath)

        var args = resolvedCommand.arguments
        args.append(contentsOf: ["-m", modelPath])
        let extraArgs = extraArguments.shellSplit()
        args.append(contentsOf: extraArgs)
        if !extraArgs.containsSeedArgument {
            args.append(contentsOf: ["--seed", String(deterministicSeed)])
        }
        if !extraArgs.containsSamplingArgument {
            args.append(contentsOf: ["--temp", "0", "--top-k", "1"])
        }
        args.append(contentsOf: ["-p", prompt])
        proc.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        let stdoutHandle = stdout.fileHandleForReading
        stdoutHandle.readabilityHandler = { [outputHandler] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                outputHandler(chunk)
            }
        }

        self.process = proc

        do {
            try proc.run()
        } catch {
            logger?.log(event: "llm_error", params: "launch_failed: \(error.localizedDescription)")
            Signposts.endInference(state)
            throw error
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            proc.terminationHandler = { _ in
                stdoutHandle.readabilityHandler = nil
                cont.resume()
            }
        }

        let exitCode = proc.terminationStatus
        logger?.log(event: "llm_inference_end", params: "exit=\(exitCode)")
        Signposts.endInference(state)
    }

    func cancel() {
        process?.terminate()
        process = nil
    }

    private func resolvedCommandLaunch() -> (executablePath: String, arguments: [String]) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return ("/usr/bin/env", ["llama-cli"])
        }

        if trimmedCommand.contains("/") {
            return ((trimmedCommand as NSString).expandingTildeInPath, [])
        }

        return ("/usr/bin/env", [trimmedCommand])
    }
}

private extension String {
    func shellSplit() -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in self {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
                continue
            }

            if character.isWhitespace && quote == nil {
                if !current.isEmpty {
                    result.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}

private extension Array where Element == String {
    var containsSeedArgument: Bool {
        contains("--seed") || contains("-s")
    }

    var containsSamplingArgument: Bool {
        contains("--temp")
            || contains("--top-k")
            || contains("--top-p")
            || contains("--min-p")
            || contains("--typical")
            || contains("--mirostat")
    }
}
