import Foundation

/// ComputationMethod as per Java code
public enum ComputationMethod {
    case medianAllTime
    case medianInterval
}

/// SpeedTestMode as per Java code
public enum SpeedTestMode {
    case none
    case download
    case upload
}

public enum SpeedTestError: Error {
    case networkError
    case hostNotFound
}

public final class SpeedTest {
    private let hostService: HostsProviderService
    private let pingService: HostPingService
    private let downloadService = CustomHostDownloadService()
    private let uploadService = CustomHostUploadService()

    // Add computation method, setup times and expose them so that we mimic Java code exactly
    private var computationMethod: ComputationMethod = .medianAllTime
    private var downloadSetupTime: TimeInterval = 0
    private var uploadSetupTime: TimeInterval = 0

    public func setComputationMethod(_ method: ComputationMethod) {
        self.computationMethod = method
    }

    public func getComputationMethod() -> ComputationMethod {
        return self.computationMethod
    }

    public func setDownloadSetupTime(_ time: TimeInterval) {
        self.downloadSetupTime = time
    }

    public func setUploadSetupTime(_ time: TimeInterval) {
        self.uploadSetupTime = time
    }

    public required init(hosts: HostsProviderService, ping: HostPingService) {
        self.hostService = hosts
        self.pingService = ping
    }

    public convenience init() {
        self.init(hosts: SpeedTestService(), ping: DefaultHostPingService())
    }

    public func findHosts(
        timeout: TimeInterval, closure: @escaping (Result<[SpeedTestHost], SpeedTestError>) -> Void
    ) {
        hostService.getHosts(timeout: timeout) { result in
            switch result {
            case .value(let hosts):
                DispatchQueue.main.async {
                    closure(.value(hosts))
                }
            case .error(_):
                DispatchQueue.main.async {
                    closure(.error(.networkError))
                }
            }
        }
    }

    public func findBestHost(
        from max: Int, timeout: TimeInterval,
        closure: @escaping (Result<(URL, Int), SpeedTestError>) -> Void
    ) {
        hostService.getHosts(max: max, timeout: timeout) { [weak self] result in
            guard let strongSelf = self else { return }
            switch result {
            case .error(_):
                DispatchQueue.main.async {
                    closure(.error(.networkError))
                }
            case .value(let hosts):
                strongSelf.pingAllHosts(hosts: hosts.map { $0.url }, timeout: timeout) { pings in
                    DispatchQueue.main.async {
                        closure(strongSelf.findBestPings(from: pings))
                    }
                }
            }
        }
    }

    public func ping(
        host: SpeedTestHost, timeout: TimeInterval,
        closure: @escaping (Result<Int, SpeedTestError>) -> Void
    ) {
        pingService.ping(url: host.url, timeout: timeout) { result in
            DispatchQueue.main.async {
                switch result {
                case .value(let ping):
                    closure(.value(ping))
                case .error(_):
                    closure(.error(.networkError))
                }
            }
        }
    }

    public func runDownloadTest(
        for host: URL, size: Int, timeout: TimeInterval,
        current: @escaping (Speed) -> Void,
        final: @escaping (Result<Speed, NetworkError>) -> Void
    ) {

        downloadService.setupTestParams(
            mode: .download, computationMethod: computationMethod, setupTime: downloadSetupTime)

        self.downloadService.test(
            host, fileSize: size, timeout: timeout,
            current: { speed in
                DispatchQueue.main.async {
                    current(speed)
                }
            },
            final: { resultSpeed in
                DispatchQueue.main.async {
                    final(resultSpeed)
                }
            })

    }

    public func runUploadTest(
        for host: URL, size: Int, timeout: TimeInterval,
        current: @escaping (Speed) -> Void,
        final: @escaping (Result<Speed, NetworkError>) -> Void
    ) {

        uploadService.setupTestParams(
            mode: .upload, computationMethod: computationMethod, setupTime: uploadSetupTime)

        self.uploadService.test(
            host, fileSize: size, timeout: timeout,
            current: { speed in
                DispatchQueue.main.async {
                    current(speed)
                }
            },
            final: { resultSpeed in
                DispatchQueue.main.async {
                    final(resultSpeed)
                }
            })

    }

    public func cancelTasks() {
        downloadService.cancelTask()
        uploadService.cancelTask()
    }

    private func pingAllHosts(
        hosts: [URL], timeout: TimeInterval, closure: @escaping ([(host: URL, ping: Int)]) -> Void
    ) {
        let group = DispatchGroup()
        var pings = [(URL, Int)]()
        hosts.forEach { url in
            group.enter()
            pingService.ping(
                url: url, timeout: timeout,
                closure: { result in
                    print("Url is \(url)")
                    switch result {
                    case .error(_): break
                    case .value(let ping):
                        print("ping is \(ping)")
                        pings.append((url, ping))
                    }
                    group.leave()
                })
        }
        group.notify(queue: DispatchQueue.global(qos: .default)) {
            closure(pings)
        }
    }

    private func findBestPings(from pings: [(host: URL, ping: Int)]) -> Result<
        (URL, Int), SpeedTestError
    > {
        let best = pings.min(by: { (left, right) in
            left.ping < right.ping
        })
        if let best = best {
            return .value(best)
        } else {
            return .error(.hostNotFound)
        }
    }
}
