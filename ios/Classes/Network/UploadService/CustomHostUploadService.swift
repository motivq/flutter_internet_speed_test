// CustomHostUploadService.swift
import Foundation

class CustomHostUploadService: NSObject, SpeedService {
    // *** CHANGES START ***
    private let defaultTestTimeoutInMillis: TimeInterval = 20.0
    private let defaultReportInterval: TimeInterval = 0.5
    private var lastReportTime: Date?
    private var didCallFinal = false
    private var startTime: Date?
    // *** CHANGES END ***
    
    private var task: URLSessionTask?
    private var current: ((Speed) -> ())!
    private var final: ((Result<Speed, NetworkError>) -> ())!
    private var uploadData: Data?
    private var totalBytesSent: Int64 = 0
    
    func test(
        _ url: URL,
        fileSize: Int,
        timeout: TimeInterval,
        current: @escaping (Speed) -> (),
        final: @escaping (Result<Speed, NetworkError>) -> ()
    ) {
        // *** CHANGES START ***
        self.didCallFinal = false
        self.current = current
        self.final = final
        self.totalBytesSent = 0
        self.startTime = Date()
        self.lastReportTime = nil
        self.uploadData = Data(count: fileSize)
        
        // Force close after timeout like Android
        DispatchQueue.main.asyncAfter(deadline: .now() + defaultTestTimeoutInMillis) { [weak self] in
            guard let self = self else { return }
            if !self.didCallFinal {
                self.task?.cancel()
                self.finalizeTest()
            }
        }
        // *** CHANGES END ***
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.uploadTask(withStreamedRequest: request)
        task?.resume()
    }
    
    func cancelTask() {
        task?.cancel()
        finalizeTest()
    }
    
    // *** CHANGES START ***
    private func shouldReport() -> Bool {
        guard let lastReport = lastReportTime else { return true }
        return Date().timeIntervalSince(lastReport) >= defaultReportInterval
    }
    
    private func finalizeTest() {
        guard !didCallFinal else { return }
        didCallFinal = true
        let speed = cumulativeSpeed()
        DispatchQueue.main.async {
            self.final(.value(speed))
        }
    }
    // *** CHANGES END ***
    
    private func cumulativeSpeed() -> Speed {
        guard let start = startTime, start != Date() else {
            return Speed(value: 0, units: .Kbps)
        }
        let elapsed = Date().timeIntervalSince(start)
        return Speed(bytes: totalBytesSent, seconds: elapsed).pretty
    }
}

extension CustomHostUploadService: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        // *** CHANGES START ***
        if startTime == nil {
            startTime = Date()
        }
        
        self.totalBytesSent = totalBytesSent
        
        if shouldReport() {
            lastReportTime = Date()
            let speed = cumulativeSpeed()
            DispatchQueue.main.async {
                self.current(speed)
            }
        }
        // *** CHANGES END ***
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
    ) {
        if let data = uploadData {
            completionHandler(InputStream(data: data))
        } else {
            completionHandler(nil)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let _ = error {
            didCallFinal = true
            DispatchQueue.main.async {
                self.final(.error(.requestFailed))
            }
        } else {
            finalizeTest()
        }
    }
}
