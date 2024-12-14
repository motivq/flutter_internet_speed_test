import Foundation

class HostURLFormatter {
    private let initialUrl: URL
    
    private var downloadURL: URL {
        return initialUrl
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("download")
    }
    
    var uploadURL: URL {
        return initialUrl
    }
    
    init(speedTestURL: URL) {
        initialUrl = speedTestURL
    }
    
    func downloadURL(size: Int) -> URL {
        // *** CHANGE START ***
        return initialUrl
        // *** CHANGE END ***
    }
}
