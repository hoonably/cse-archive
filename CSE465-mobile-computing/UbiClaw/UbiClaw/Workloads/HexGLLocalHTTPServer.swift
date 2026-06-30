import Foundation
import Network

enum HexGLLocalHTTPServerError: LocalizedError {
    case missingPort
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingPort:
            return "Local HTTP server did not receive a listening port."
        case .cancelled:
            return "Local HTTP server was cancelled before it became ready."
        }
    }
}

final class HexGLLocalHTTPServer {
    private let rootDirectory: URL
    private let queue = DispatchQueue(label: "UbiClaw.HexGLLocalHTTPServer")

    private var listener: NWListener?
    private var baseURL: URL?
    private var startCompletion: ((Result<URL, Error>) -> Void)?

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            if let baseURL = self.baseURL {
                DispatchQueue.main.async {
                    completion(.success(baseURL))
                }
                return
            }

            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }

                    switch state {
                    case .ready:
                        guard let port = listener?.port else {
                            self.completeStart(.failure(HexGLLocalHTTPServerError.missingPort))
                            return
                        }
                        guard let baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
                            self.completeStart(.failure(HexGLLocalHTTPServerError.missingPort))
                            return
                        }
                        self.baseURL = baseURL
                        self.completeStart(.success(baseURL))
                    case .failed(let error):
                        self.completeStart(.failure(error))
                        self.stop()
                    case .cancelled:
                        self.completeStart(.failure(HexGLLocalHTTPServerError.cancelled))
                    default:
                        break
                    }
                }

                self.listener = listener
                self.startCompletion = completion
                listener.start(queue: self.queue)
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.baseURL = nil
            self.startCompletion = nil
        }
    }

    private func completeStart(_ result: Result<URL, Error>) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var requestData = buffer
            if let content {
                requestData.append(content)
            }

            let requestTerminator = Data("\r\n\r\n".utf8)
            if requestData.range(of: requestTerminator) != nil || isComplete || requestData.count > 128 * 1024 {
                self.respond(to: requestData, on: connection)
            } else {
                self.receiveRequest(on: connection, buffer: requestData)
            }
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard
            let request = String(data: requestData.prefix(4096), encoding: .utf8),
            let firstLine = request.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        else {
            send(status: 400, reason: "Bad Request", body: "Bad Request", contentType: "text/plain", method: "GET", on: connection)
            return
        }

        let parts = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count >= 2 else {
            send(status: 400, reason: "Bad Request", body: "Bad Request", contentType: "text/plain", method: "GET", on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        if method == "OPTIONS" {
            send(status: 204, reason: "No Content", body: Data(), contentType: "text/plain", method: method, on: connection)
            return
        }

        guard method == "GET" || method == "HEAD" else {
            send(status: 405, reason: "Method Not Allowed", body: "Method Not Allowed", contentType: "text/plain", method: method, on: connection)
            return
        }

        let fileURL = resolvedFileURL(for: String(parts[1]))
        guard let fileURL else {
            send(status: 403, reason: "Forbidden", body: "Forbidden", contentType: "text/plain", method: method, on: connection)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            send(status: 404, reason: "Not Found", body: "Not Found", contentType: "text/plain", method: method, on: connection)
            return
        }

        do {
            let body = try Data(contentsOf: fileURL)
            send(status: 200, reason: "OK", body: body, contentType: Self.contentType(for: fileURL), method: method, on: connection)
        } catch {
            send(status: 500, reason: "Internal Server Error", body: "Internal Server Error", contentType: "text/plain", method: method, on: connection)
        }
    }

    private func resolvedFileURL(for rawPath: String) -> URL? {
        let pathWithoutQuery = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawPath
        let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        let relativePath: String

        if decodedPath == "/" || decodedPath.isEmpty {
            relativePath = "index.html"
        } else {
            relativePath = String(decodedPath.drop { $0 == "/" })
        }

        guard
            !relativePath.isEmpty,
            !relativePath.contains(".."),
            !relativePath.contains("\0"),
            !relativePath.hasPrefix("/")
        else {
            return nil
        }

        let fileURL = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootDirectory.path
        guard fileURL.path == rootPath || fileURL.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return fileURL
    }

    private func send(status: Int, reason: String, body: String, contentType: String, method: String, on connection: NWConnection) {
        send(status: status, reason: reason, body: Data(body.utf8), contentType: contentType, method: method, on: connection)
    }

    private func send(status: Int, reason: String, body: Data, contentType: String, method: String, on connection: NWConnection) {
        var response = Data()
        response.append(Data("""
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """.utf8))

        if method != "HEAD" {
            response.append(body)
        }

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "js":
            return "application/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json", "webapp":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ogg":
            return "audio/ogg"
        case "mp3":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }
}
