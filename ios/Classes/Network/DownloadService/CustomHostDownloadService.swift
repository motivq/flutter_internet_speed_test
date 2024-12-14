// *** FILE: CustomHostDownloadService.swift ***
// *** CHANGE START ***
// Replaced .failure with .error and .success with .value 
// to match the custom Result enum cases.
// Also explicitly prefixed NetworkError cases.
import Foundation

class CustomHostDownloadService: NSObject, SpeedService {
    private var task: URLSessionDataTask?
    private var current: ((Speed) -> ())!
    private var final: ((Result<Speed, NetworkError>) -> ())!
    private var totalBytesReceived: Int64 = 0
    private var lastBytesReceivedForCalc: Int64 = 0
    private var responseDate: Date?
    private var calcStartDate: Date?

    func test(
        _ url: URL,
        fileSize: Int,
        timeout: TimeInterval,
        current: @escaping (Speed) -> (),
        final: @escaping (Result<Speed, NetworkError>) -> ()
    ) {
        self.current = current
        self.final = final

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        task = session.dataTask(with: request)

        responseDate = Date()
        calcStartDate = responseDate
        totalBytesReceived = 0
        lastBytesReceivedForCalc = 0

        task?.resume()
    }

    func cancelTask() {
        task?.cancel()
    }

    private func calculateSpeed(bytes: Int64, seconds: TimeInterval) -> Speed {
        return Speed(bytes: bytes, seconds: seconds).pretty
    }
}

extension CustomHostDownloadService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        totalBytesReceived += Int64(data.count)
        let now = Date()

        guard let calcStart = calcStartDate else { return }
        let elapsed = now.timeIntervalSince(calcStart)
        let bytesThisChunk = totalBytesReceived - lastBytesReceivedForCalc

        if elapsed > 0 {
            let currentSpeed = calculateSpeed(bytes: bytesThisChunk, seconds: elapsed)
            DispatchQueue.global(qos: .background).async {
                self.current(currentSpeed)
            }

            lastBytesReceivedForCalc = totalBytesReceived
            calcStartDate = now
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let _ = error {
            // *** CHANGE START ***
            // Using .error instead of .failure
            // Using .error(.requestFailed) instead of .failure(.requestFailed)
            final(.error(NetworkError.requestFailed))
            // *** CHANGE END ***
        } else {
            guard let start = responseDate else {
                // *** CHANGE START ***
                // Using .error instead of .failure
                final(.error(NetworkError.requestFailed))
                // *** CHANGE END ***
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            let finalSpeed = calculateSpeed(bytes: totalBytesReceived, seconds: elapsed)
            // *** CHANGE START ***
            // Using .value instead of .success
            final(.value(finalSpeed))
            // *** CHANGE END ***
        }
    }
}
// *** CHANGE END ***
