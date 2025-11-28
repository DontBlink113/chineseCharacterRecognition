import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case serverError(String)
}

class NetworkManager {
    // Update this with your actual server URL after deployment
    #if DEBUG
    private let baseURL = "http://localhost:5000/api"
    #else
    private let baseURL = "YOUR_DEPLOYED_SERVER_URL/api"
    #endif
    
    static let shared = NetworkManager()
    private init() {}
    
    // MARK: - Server Health Check
    
    func checkServerHealth(completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        let endpoint = "\(baseURL)/health"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(.serverError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.serverError("Invalid response")))
                return
            }
            
            completion(.success(httpResponse.statusCode == 200))
        }
        
        task.resume()
    }
    
    // MARK: - Character Analysis
    
    func analyzeCharacters(_ characters: [String], completion: @escaping (Result<[CharacterAnalysis], NetworkError>) -> Void) {
        // Implementation will be added later
        // This is a placeholder for the actual implementation
        completion(.success([]))
    }
}

// MARK: - Response Models

struct CharacterAnalysis: Codable, Identifiable {
    var id: String { character }
    let character: String
    let strokeCount: Int
    let pinyin: String
    let complexityScore: Double
    let similarCharacters: [String]
    
    enum CodingKeys: String, CodingKey {
        case character
        case strokeCount = "stroke_count"
        case pinyin
        case complexityScore = "complexity_score"
        case similarCharacters = "similar_characters"
    }
}
