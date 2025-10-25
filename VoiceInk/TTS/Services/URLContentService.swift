import Foundation

@MainActor
protocol URLContentLoading {
    func fetchPlainText(from url: URL) async throws -> String
}

@MainActor
struct URLContentService: URLContentLoading {
    private let session: URLSession
    private static let redditUserAgent = "VoiceInkTTS/1.0 (+https://github.com/Beingpax/VoiceInk)"

    init(session: URLSession = SecureURLSession.makeEphemeral()) {
        self.session = session
    }

    func fetchPlainText(from url: URL) async throws -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw URLError(.unsupportedURL)
        }

        if let redditURL = redditJSONURL(for: url) {
            do {
                let redditText = try await fetchRedditThread(from: redditURL)
                if !redditText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return redditText
                }
            } catch is RedditContentParser.ParserError {
                // Fall back to generic HTML parsing when the Reddit payload is unusable.
            } catch {
                throw error
            }
        }

        let (data, response) = try await loadData(from: url)
        return try plainText(from: data, response: response)
    }

    private func fetchRedditThread(from url: URL) async throws -> String {
        let (data, _) = try await loadData(from: url, headers: ["User-Agent": Self.redditUserAgent])
        return try RedditContentParser.buildThreadText(from: data)
    }

    private func loadData(from url: URL, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        return (data, response)
    }

    private func plainText(from data: Data, response: URLResponse) throws -> String {
        let encodingName = (response as? HTTPURLResponse)?.textEncodingName
        let encoding = encodingName
            .flatMap { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
            .flatMap { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) }

        let rawHTML = String(data: data, encoding: encoding ?? .utf8) ?? String(decoding: data, as: UTF8.self)

        if let articleText = ArticleHTMLExtractor.extractPrimaryText(from: rawHTML) {
            return articleText
        }

        if let attributed = try? NSAttributedString(
            data: Data(rawHTML.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        } else {
            return rawHTML
        }
    }

    private func redditJSONURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }

        if host.hasSuffix("reddit.com") {
            return redditComJSONURL(for: url)
        }

        if host.hasSuffix("redd.it") {
            return reddItJSONURL(for: url)
        }

        return nil
    }

    private func redditComJSONURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !components.path.isEmpty else {
            return nil
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }

        guard !path.isEmpty else { return nil }

        if !path.hasSuffix(".json") {
            path += ".json"
        }

        components.path = path

        var filteredQueryItems = (components.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return name != "limit" && name != "raw_json"
        }
        filteredQueryItems.append(URLQueryItem(name: "limit", value: "100"))
        filteredQueryItems.append(URLQueryItem(name: "raw_json", value: "1"))
        components.queryItems = filteredQueryItems

        return components.url
    }

    private func reddItJSONURL(for url: URL) -> URL? {
        let identifiers = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let postID = identifiers.first else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.reddit.com"
        components.path = "/comments/\(postID).json"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "raw_json", value: "1")
        ]

        return components.url
    }
}
