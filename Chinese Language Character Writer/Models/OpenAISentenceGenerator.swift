import Foundation

struct GeneratedSentence: Codable {
    let chinese: String
    let english: String
}

enum SentenceGenError: Error {
    case missingAPIKey
    case emptyAllowedSet
    case invalidResponse
    case validationFailed
}

final class OpenAISentenceGenerator {
    private let apiKey: String
    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o-mini"
    private let session: URLSession

    init(apiKey: String? = nil) throws {
        if let k = apiKey, !k.isEmpty {
            self.apiKey = k
        } else if let k = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !k.isEmpty {
            self.apiKey = k
        } else {
            throw SentenceGenError.missingAPIKey
        }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func generate(allowed: [String], retries: Int = 1, networkRetries: Int = 3) async throws -> GeneratedSentence {
        let unique = Array(Set(allowed)).joined()
        if unique.isEmpty { throw SentenceGenError.emptyAllowedSet }
        var last: GeneratedSentence? = nil
        for attempt in 0...retries {
            let result = try await requestWithRetry(allowed: unique, correction: attempt == 0 ? nil : last, networkRetries: networkRetries)
            if disallowedChinese(in: result.chinese, allowed: Set(unique.map { String($0) })).isEmpty {
                return result
            }
            last = result
        }
        throw SentenceGenError.validationFailed
    }

    private func requestWithRetry(allowed: String, correction: GeneratedSentence?, networkRetries: Int) async throws -> GeneratedSentence {
        var lastError: Error? = nil
        for attempt in 0...max(0, networkRetries) {
            do {
                return try await request(allowed: allowed, correction: correction)
            } catch {
                lastError = error
                if let urlErr = error as? URLError {
                    let retriable: Set<URLError.Code> = [
                        .timedOut,
                        .networkConnectionLost,
                        .cannotFindHost,
                        .cannotConnectToHost,
                        .notConnectedToInternet,
                        .dataNotAllowed,
                        .internationalRoamingOff
                    ]
                    if retriable.contains(urlErr.code) && attempt < networkRetries {
                        let delay = pow(2.0, Double(attempt)) * 0.5 // 0.5s, 1s, 2s, ...
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }
                // Non-retriable or out of attempts
                throw error
            }
        }
        throw lastError ?? SentenceGenError.invalidResponse
    }

    private func request(allowed: String, correction: GeneratedSentence?) async throws -> GeneratedSentence {
        var sys = "You are a Chinese language teacher. Generate exactly one short Chinese sentence using ONLY the characters from the allowed set. Do not use any other Chinese characters. Punctuation should be omitted unless it is within the allowed set. Respond ONLY as compact JSON: {\"chinese\": \"...\", \"english\": \"...\"}."
        if correction != nil {
            sys += " Important: Your previous output used disallowed characters. Regenerate strictly using only the allowed set."
        }
        let user = "Allowed characters: \(allowed)\nRules:\n- Only use the allowed characters (may repeat)\n- Length: 6–20 characters\n- Output JSON with keys: chinese, english"
        let messages: [[String: String]] = [
            ["role": "system", "content": sys],
            ["role": "user", "content": user]
        ]
        let payload: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0.6,
            "max_tokens": 120,
            "messages": messages
        ]
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Try to decode OpenAI error body for better diagnostics
            struct OpenAIErrorBody: Decodable { struct Err: Decodable { let message: String? }; let error: Err? }
            if let err = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data), let msg = err.error?.message {
                print("OpenAI API error (\(http.statusCode)): \(msg)")
            } else if let raw = String(data: data, encoding: .utf8) {
                print("OpenAI API error (\(http.statusCode)): \(raw)")
            }
            throw SentenceGenError.invalidResponse
        }
        struct ChatResponse: Decodable { struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }; let choices: [Choice] }
        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let rawContent = chat.choices.first?.message.content else { throw SentenceGenError.invalidResponse }
        // Some models may wrap JSON in code fences; extract the JSON object defensively
        let jsonString: String = {
            if let start = rawContent.firstIndex(of: "{"), let end = rawContent.lastIndex(of: "}") , start <= end {
                return String(rawContent[start...end])
            }
            return rawContent
        }()
        guard let contentData = jsonString.data(using: .utf8) else { throw SentenceGenError.invalidResponse }
        return try JSONDecoder().decode(GeneratedSentence.self, from: contentData)
    }
}

private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
}

private func disallowedChinese(in text: String, allowed: Set<String>) -> [String] {
    var bad: [String] = []
    var seen = Set<String>()
    for s in text.unicodeScalars where isCJK(s) {
        let c = String(s)
        if !allowed.contains(c), !seen.contains(c) {
            bad.append(c)
            seen.insert(c)
        }
    }
    return bad
}
