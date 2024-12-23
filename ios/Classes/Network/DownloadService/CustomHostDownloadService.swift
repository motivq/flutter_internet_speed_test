import Foundation

class CustomHostDownloadService: NSObject, SpeedService {
    // Logging enabled
    private let loggerEnabled = true

    private func log(_ message: String) {
        if loggerEnabled {
            print("[DownloadService] \(message)")
        }
    }

    private var computationMethod: ComputationMethod = .medianAllTime
    private var speedTestMode: SpeedTestMode = .none
    private var setupTime: TimeInterval = 0

    private var mTimeStart: CFTimeInterval = 0
    private var mTimeComputeStart: CFTimeInterval = 0
    private var mDlComputationTempPacketSize: Int64 = 0
    private var totalBytesReceived: Int64 = 0
    private var didCallFinal = false
    private var startTime: Date?
    private var tasks: [URLSessionDataTask] = []
    private var task: URLSessionDataTask?
    private var current: ((Speed) -> Void)!
    private var final: ((Result<Speed, NetworkError>) -> Void)!
    private var reportTimer: DispatchSourceTimer?
    private var testTimeout: TimeInterval = 20.0
    private let defaultReportInterval: TimeInterval = 0.5

    private let parallelCount = 4

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
        self.log(
            "Starting download test with URL: \(url), requested file size: \(fileSize), timeout: \(timeout)s"
        )

        self.current = current
        self.final = final
        self.totalBytesReceived = 0
        self.mDlComputationTempPacketSize = 0
        self.didCallFinal = false
        self.testTimeout = timeout
        self.startTime = Date()
        mTimeStart = CFAbsoluteTimeGetCurrent()
        mTimeComputeStart = mTimeStart

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.log("Download test timed out at \(timeout)s, finalizing test...")
            self?.finalizeTest()
        }

        setupReportTimer()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        log("Directly starting \(parallelCount) parallel downloads from provided URL: \(url)")
        for _ in 0..<parallelCount {
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: testTimeout
            )
            let task = session.dataTask(with: request)
            tasks.append(task)
        }
        tasks.forEach { $0.resume() }
    }
    /*
    private func fetchContentLength(
        session: URLSession, url: URL, completion: @escaping (Bool, Int64) -> Void
    ) {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let task = session.dataTask(with: req) { data, response, error in
            if let err = error as NSError? {
                self.log("HEAD request error: \(err.localizedDescription)")
                completion(false, 0)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.log("HEAD request no HTTP response")
                completion(false, 0)
                return
            }
            if http.statusCode == 200 {
                let length = http.expectedContentLength
                self.log("HEAD response 200 OK, contentLength: \(length)")
                completion(true, length)
            } else {
                self.log("HEAD response code: \(http.statusCode)")
                completion(false, 0)
            }
        }
        task.resume()
    }


    private func startDownload(url: URL, session: URLSession) {
        self.log("Starting actual data download from \(url)")
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: testTimeout
        )

        task = session.dataTask(with: request)
        task?.resume()
    }
    */

    func cancelTask() {
        log("Download tasks cancelled by user.")
        tasks.forEach { $0.cancel() }
        cancelReportTimer()
        if !didCallFinal {
            didCallFinal = true
            final(.error(.requestFailed))
        }
    }

    private func finalizeTest() {
        guard !didCallFinal else { return }
        didCallFinal = true

        log("Finalizing test. Total bytes: \(totalBytesReceived)")
        tasks.forEach { $0.cancel() }
        cancelReportTimer()

        let finalSpeed = computeCurrentSpeed(allTime: true)
        log("Final speed: \(finalSpeed)")
        DispatchQueue.main.async {
            self.final(.value(finalSpeed))
        }
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
                bytesForRate = totalBytesReceived
                let fullElapsed = currentTime - mTimeStart
                if fullElapsed <= 0 { return Speed(value: 0, units: .Kbps) }
                return Speed(bytes: bytesForRate, seconds: fullElapsed).pretty
            } else {
                bytesForRate = totalBytesReceived
            }
        case .medianInterval:
            bytesForRate = mDlComputationTempPacketSize
        }

        if shallCalculateTransferRate() {
            let speed = Speed(bytes: bytesForRate, seconds: elapsedCompute).pretty
            if computationMethod == .medianInterval {
                mDlComputationTempPacketSize = 0
                mTimeComputeStart = currentTime
            }
            return speed
        } else {
            return Speed(value: 0, units: .Kbps)
        }
    }

    private func setupReportTimer() {
        self.log("Setting up report timer with interval: \(defaultReportInterval)s")
        let queue = DispatchQueue(label: "com.speedtest.download.report", qos: .background)
        reportTimer = DispatchSource.makeTimerSource(queue: queue)
        reportTimer?.schedule(
            deadline: .now() + defaultReportInterval, repeating: defaultReportInterval)
        reportTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let speed = self.computeCurrentSpeed()
            if speed.value > 0 {
                self.log("Reporting progress speed: \(speed)")
                DispatchQueue.main.async {
                    self.current(speed)
                }
            } else {
                self.log("Progress speed not reported yet, waiting for setup time...")
            }
        }
        reportTimer?.resume()
    }

    private func cancelReportTimer() {
        if reportTimer != nil {
            self.log("Cancelling report timer.")
            reportTimer?.cancel()
            reportTimer = nil
        }
    }

    // We'll track how many tasks completed
    private var completedTasksCount = 0

    private func taskCompleted() {
        completedTasksCount += 1
        // Once all tasks complete, finalize
        if completedTasksCount == tasks.count && !didCallFinal {
            log("All parallel download tasks completed successfully.")
            finalizeTest()
        }
    }
}

extension CustomHostDownloadService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let count = Int64(data.count)
        totalBytesReceived += count
        mDlComputationTempPacketSize += count
        log("Received \(data.count) bytes (task: \(dataTask)), total: \(totalBytesReceived)")
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError taskError: Error?
    ) {
        if let err = taskError {
            log("A download task completed with error: \(err.localizedDescription)")
            // If one task fails, we fail the whole test
            if !didCallFinal {
                didCallFinal = true
                cancelReportTimer()
                DispatchQueue.main.async {
                    self.final(.error(.requestFailed))
                }
            }
        } else {
            log("A download task completed successfully.")
            // If a task completed fine, check if all are done
            taskCompleted()
        }
    }
}
