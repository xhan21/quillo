import AppKit
import Foundation

// Only the loopback address and a verified on-disk model are allowed. No cloud fallback,
// model downloads, saved prompts, proxy, cookies, or HTTP redirects.
private final class LocalModelSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class LocalOllamaClient {
    static let model = "qwen3.5:9b"
    private let selectedModel: String
    private let session: URLSession
    init(model: String = LocalOllamaClient.model, resourceTimeout: Double = 100) {
        selectedModel = model
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 90; configuration.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: configuration, delegate: LocalModelSessionDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func post(_ path: String, body: [String: Any], timeout: Double = 90) async throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/" + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SlideSummaryError.failed }
        if response.statusCode == 404 { throw SlideSummaryError.modelMissing }
        guard response.statusCode == 200 else { throw SlideSummaryError.failed }
        return data
    }
    static func validateLocalModel(_ data: Data) throws {
        guard let details = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SlideSummaryError.failed }
        if (details["remote_host"] as? String)?.isEmpty == false || (details["remote_model"] as? String)?.isEmpty == false { throw SlideSummaryError.remoteModel }
        guard let model = details["details"] as? [String: Any],
              let format = model["format"] as? String,
              format == "gguf" || (format == "safetensors" && model["runner"] as? String == "mlx")
        else { throw SlideSummaryError.remoteModel }
    }
    func prepare() async throws {
        do { try Self.validateLocalModel(await post("show", body: ["model": selectedModel], timeout: 3)); return }
        catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost, .timedOut].contains(error.code) {
            // Launch the already installed application without bringing its window forward.
            let launched = await MainActor.run { () -> Bool in
                let paths = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
                guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return false }
                let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, _ in }
                return true
            }
            guard launched else { throw SlideSummaryError.unavailable }
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(500))
                do { try Self.validateLocalModel(await post("show", body: ["model": selectedModel], timeout: 2)); return }
                catch is URLError { continue }
            }
            throw SlideSummaryError.unavailable
        }
    }
}
