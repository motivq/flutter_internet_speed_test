// CustomHostDownloadService.swift
import Foundation

class CustomHostDownloadService: NSObject, SpeedService {
    private let defaultTestTimeoutInMillis: TimeInterval = 20.0
    private let defaultReportInterval: TimeInterval = 0.1
    private var task: URLSessionDataTask?
    private var current: ((Speed) -> ())!
    private var final: ((Result<Speed, NetworkError>) -> ())!
    private var totalBytesReceived: Int64 = 0
    private var startTime: Date?
    private var didCallFinal = false
    private var lastReportTime: Date?
    private var lastReportBytes: Int64 = 0
    
    func test(
        _ url: URL,
        fileSize: Int,
        timeout: TimeInterval,
        current: @escaping (Speed) -> (),
        final: @escaping (Result<Speed, NetworkError>) -> ()
    ) {
        // Reset state
        self.current = current
        self.final = final
        self.totalBytesReceived = 0
        self.lastReportBytes = 0
        self.startTime = Date()
        self.lastReportTime = Date()
        self.didCallFinal = false
        
        // Setup force completion timer
        DispatchQueue.main.asyncAfter(deadline: .now() + defaultTestTimeoutInMillis) { [weak self] in
            self?.finalizeTest()
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        startDownload(url: url, session: session, fileSize: fileSize)
    }
    
    private func startDownload(url: URL, session: URLSession, fileSize: Int) {
        // Use HostURLFormatter to request a large file.
        let hostFormatter = HostURLFormatter(speedTestURL: url)
        let finalURL = hostFormatter.downloadURL(size: fileSize)
        
        let request = URLRequest(
            url: finalURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: defaultTestTimeoutInMillis
        )

        task = session.dataTask(with: request)
        task?.resume()
    }
    
    func cancelTask() {
        task?.cancel()
        if !didCallFinal {
            didCallFinal = true
            final(.error(.requestFailed))
        }
    }
    
    private func finalizeTest() {
        guard !didCallFinal else { return }
        didCallFinal = true
        
        task?.cancel()
        
        let finalSpeed = calculateSpeed(bytes: totalBytesReceived, start: startTime ?? Date(), end: Date())
        DispatchQueue.main.async {
            self.final(.value(finalSpeed))
        }
    }
    
    private func calculateSpeed(bytes: Int64, start: Date, end: Date) -> Speed {
        let elapsed = end.timeIntervalSince(start)
        guard elapsed > 0 else { return Speed(value: 0, units: .Kbps) }
        return Speed(bytes: bytes, seconds: elapsed).pretty
    }
    
    private func reportProgress() {
        guard let lastReport = lastReportTime else { return }
        let now = Date()
        let bytesSinceLastReport = totalBytesReceived - lastReportBytes
        let speed = calculateSpeed(bytes: bytesSinceLastReport, start: lastReport, end: now)
        
        lastReportTime = now
        lastReportBytes = totalBytesReceived
        
        DispatchQueue.main.async {
            self.current(speed)
        }
    }
}

extension CustomHostDownloadService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        totalBytesReceived += Int64(data.count)
        
        // Only report progress every defaultReportInterval
        if let lastReport = lastReportTime,
           Date().timeIntervalSince(lastReport) >= defaultReportInterval {
            reportProgress()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let _ = error, !didCallFinal {
            didCallFinal = true
            DispatchQueue.main.async {
                self.final(.error(.requestFailed))
            }
        }
    }
}
