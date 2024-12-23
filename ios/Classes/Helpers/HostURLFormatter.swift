import Foundation

class HostURLFormatter {
    private let initialUrl: URL
    
    var uploadURL: URL {
        return initialUrl
    }
    
    init(speedTestURL: URL) {
        initialUrl = speedTestURL
    }
    
    func downloadURL(size: Int) -> URL {
        // Attempt to request a large file by passing size as a query parameter
        var components = URLComponents(url: initialUrl, resolvingAgainstBaseURL: false)
        // Append a size parameter if the server supports it, e.g. http://example.com?size=10485760
        components?.queryItems = [URLQueryItem(name: "size", value: "\(size)")]
        
        return components?.url ?? initialUrl
    }
}
