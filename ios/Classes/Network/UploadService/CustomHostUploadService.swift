import Foundation

class CustomHostUploadService: NSObject, SpeedService {
    // Logging enabled
    private let loggerEnabled = true
    private func log(_ message: String) {
        if loggerEnabled {
            print("[UploadService] \(message)")
        }
    }

    private var computationMethod: ComputationMethod = .medianAllTime
    private var speedTestMode: SpeedTestMode = .none
    private var setupTime: TimeInterval = 0
    private var mTimeStart: CFTimeInterval = 0
    private var mTimeComputeStart: CFTimeInterval = 0
    private var mUlComputationTempFileSize: Int64 = 0
    private var totalBytesSent: Int64 = 0
    private var didCallFinal = false
    private var startTime: Date?
    private var task: URLSessionTask?
    private var current: ((Speed) -> Void)!
    private var final: ((Result<Speed, NetworkError>) -> Void)!
    private var uploadData: Data?
    private var reportTimer: DispatchSourceTimer?
    private var testTimeout: TimeInterval = 20.0
    private let defaultReportInterval: TimeInterval = 0.5

    func setupTestParams(
        mode: SpeedTestMode, computationMethod: ComputationMethod, setupTime: TimeInterval
    ) {
        self.speedTestMode = mode
        self.computationMethod = computationMethod
        self.setupTime = setupTime
    }

    func test(
        _ url: URL,
        fileSize: Int,
        timeout: TimeInterval,
        current: @escaping (Speed) -> Void,
        final: @escaping (Result<Speed, NetworkError>) -> Void
    ) {
        log("Starting upload test to URL: \(url), fileSize: \(fileSize), timeout: \(timeout)s")

        self.didCallFinal = false
        self.current = current
        self.final = final
        self.totalBytesSent = 0
        self.mUlComputationTempFileSize = 0
        self.testTimeout = timeout
        self.uploadData = Data(count: fileSize)
        self.startTime = Date()
        mTimeStart = CFAbsoluteTimeGetCurrent()
        mTimeComputeStart = mTimeStart

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, !self.didCallFinal else { return }
            self.log("Upload test timed out at \(timeout)s, finalizing test...")
            self.task?.cancel()
            self.finalizeTest()
        }

        setupReportTimer()

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
        log("Starting uploadTask with streamed request...")
        task = session.uploadTask(withStreamedRequest: request)
        task?.resume()
    }

    func cancelTask() {
        log("Upload task cancelled by user.")
        task?.cancel()
        finalizeTest()
    }

    private func shallCalculateTransferRate() -> Bool {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsed = currentTime - mTimeStart
        return elapsed > setupTime
    }

    private func computeCurrentSpeed(allTime: Bool = false) -> Speed {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsedCompute = currentTime - mTimeComputeStart
        if elapsedCompute <= 0 { return Speed(value: 0, units: .Kbps) }

        var bytesForRate: Int64 = 0
        switch computationMethod {
        case .medianAllTime:
            if allTime {
                bytesForRate = totalBytesSent
                let fullElapsed = currentTime - mTimeStart
                if fullElapsed <= 0 { return Speed(value: 0, units: .Kbps) }
                return Speed(bytes: bytesForRate, seconds: fullElapsed).pretty
            } else {
                bytesForRate = totalBytesSent
            }
        case .medianInterval:
            bytesForRate = mUlComputationTempFileSize
        }

        if shallCalculateTransferRate() {
            let speed = Speed(bytes: bytesForRate, seconds: elapsedCompute).pretty
            if computationMethod == .medianInterval {
                mUlComputationTempFileSize = 0
                mTimeComputeStart = currentTime
            }
            return speed
        } else {
            return Speed(value: 0, units: .Kbps)
        }
    }

    private func setupReportTimer() {
        log("Setting up report timer with interval: \(defaultReportInterval)s")
        let queue = DispatchQueue(label: "com.speedtest.upload.report", qos: .background)
        reportTimer = DispatchSource.makeTimerSource(queue: queue)
        reportTimer?.schedule(
            deadline: .now() + defaultReportInterval, repeating: defaultReportInterval)
        reportTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let speed = self.computeCurrentSpeed()
            if speed.value > 0 {
                self.log("Reporting upload progress speed: \(speed)")
                DispatchQueue.main.async {
                    self.current(speed)
                }
            } else {
                self.log("Upload progress speed not reported yet, waiting for setup time...")
            }
        }
        reportTimer?.resume()
    }

    private func cancelReportTimer() {
        if reportTimer != nil {
            log("Cancelling report timer.")
            reportTimer?.cancel()
            reportTimer = nil
        }
    }

    private func finalizeTest() {
        guard !didCallFinal else { return }
        didCallFinal = true
        cancelReportTimer()

        let finalSpeed = computeCurrentSpeed(allTime: true)
        log("Final upload speed: \(finalSpeed), total bytes sent: \(totalBytesSent)")
        DispatchQueue.main.async {
            self.final(.value(finalSpeed))
        }
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
        self.totalBytesSent = totalBytesSent
        mUlComputationTempFileSize += bytesSent
        log("Sent \(bytesSent) bytes this chunk, total sent: \(totalBytesSent)")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
    ) {
        log(
            "needNewBodyStream called. Providing input stream of size \(uploadData?.count ?? 0) bytes."
        )
        if let data = uploadData {
            completionHandler(InputStream(data: data))
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError taskError: Error?
    ) {
        if let err = taskError, !didCallFinal {
            log("Upload completed with error: \(err.localizedDescription)")
            didCallFinal = true
            cancelReportTimer()
            DispatchQueue.main.async {
                self.final(.error(.requestFailed))
            }
        } else {
            log("Upload completed successfully.")
            finalizeTest()
        }
    }
}
