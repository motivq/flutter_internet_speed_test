import Foundation

class CustomHostUploadService: NSObject, SpeedService {
    private var responseDate: Date?
    private var latestDate: Date?
    private var current: ((Speed) -> ())!
    private var final: ((Result<Speed, NetworkError>) -> ())!
    
    private var task: URLSessionTask?
    private var uploadData: Data?
    private var didCallFinal = false
    private let logger = SwiftInternetSpeedTestPlugin.Logger()
    
    private var lastBytesSentForCalc: Int64 = 0
    private var calcStartDate: Date?
    
    func test(_ url: URL, fileSize: Int, timeout: TimeInterval,
              current: @escaping (Speed) -> (),
              final: @escaping (Result<Speed, NetworkError>) -> ()) {
        self.current = current
        self.final = final
        
        logger.printLog(message: "Starting upload test with URL: \(url), fileSize: \(fileSize)")
        self.uploadData = Data(count: fileSize)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        let config = sessionConfiguration(timeout: timeout)
        
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        
        responseDate = Date()
        latestDate = responseDate
        calcStartDate = responseDate
        lastBytesSentForCalc = 0
        
        task = session.uploadTask(withStreamedRequest: request)
        task?.resume()
    }
    
    func cancelTask() {
        task?.cancel()
    }
    
    private func sessionConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return config
    }
    
    private func calculate(bytes: Int64, seconds: TimeInterval) -> Speed {
        return Speed(bytes: bytes, seconds: seconds).pretty
    }
}

extension CustomHostUploadService: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                   dataTask: URLSessionDataTask,
                   didReceive response: URLResponse,
                   completionHandler: @escaping (URLSession.ResponseDisposition) -> Swift.Void) {
        let totalBytesSent = dataTask.countOfBytesSent
        let result = calculate(bytes: totalBytesSent, seconds: Date().timeIntervalSince(self.responseDate ?? Date()))
        logger.printLog(message: "Upload didReceiveResponse, total sent: \(totalBytesSent), final speed: \(result)")
        if !didCallFinal {
            didCallFinal = true
            self.final(.value(result))
        }
        responseDate = nil
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        logger.printLog(message: "needNewBodyStream called - providing InputStream")
        if let data = uploadData {
            completionHandler(InputStream(data: data))
        } else {
            completionHandler(nil)
        }
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        logger.printLog(message: "didSendBodyData: justSent=\(bytesSent), totalSent=\(totalBytesSent), expected=\(totalBytesExpectedToSend)")
        guard let startDate = responseDate, let calcStart = calcStartDate else {
            if responseDate == nil {
                responseDate = Date()
            }
            if calcStartDate == nil {
                calcStartDate = Date()
            }
            return
        }
        
        let currentTime = Date()
        let elapsed = currentTime.timeIntervalSince(calcStart)
        let bytesThisChunk = totalBytesSent - lastBytesSentForCalc
        if elapsed > 0 {
            let currentSpeed = calculate(bytes: bytesThisChunk, seconds: elapsed)
            let average = calculate(bytes: totalBytesSent, seconds: -startDate.timeIntervalSinceNow)
            
            DispatchQueue.global(qos: .background).async {
                self.current(currentSpeed)
            }
            
            calcStartDate = currentTime
            lastBytesSentForCalc = totalBytesSent
        }
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let err = error, !didCallFinal {
            didCallFinal = true
            logger.printLog(message: "Upload completed with error: \(err.localizedDescription)")
            self.final(.error(NetworkError.requestFailed))
            responseDate = nil
        } else if !didCallFinal {
            didCallFinal = true
            guard let start = self.responseDate else {
                logger.printLog(message: "No responseDate at completion")
                self.final(.error(NetworkError.requestFailed))
                return
            }
            let sent = task.countOfBytesSent
            let elapsed = Date().timeIntervalSince(start)
            let result = calculate(bytes: sent, seconds: elapsed)
            logger.printLog(message: "Upload finished, total bytes: \(sent), elapsed: \(elapsed), speed: \(result)")
            self.final(.value(result))
        }
    }
}
