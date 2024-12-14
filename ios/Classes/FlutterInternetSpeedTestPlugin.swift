import Flutter
import UIKit

public class SwiftInternetSpeedTestPlugin: NSObject, FlutterPlugin {
    let DEFAULT_FILE_SIZE = 10485760
    let DEFAULT_TEST_TIMEOUT = 20000

    var callbackById: [Int: () -> Void] = [:]

    private var cancellationFlags = [Int: Bool]()
    private var speedTests = [Int: SpeedTest]()
    private var lastUpdateTimeById: [Int: Date] = [:] // For throttling

    static var channel: FlutterMethodChannel!

    private let logger = Logger()

    // Throttling properties
    private let updateThrottleInterval: TimeInterval = 0.1 // 100 ms

    public static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "com.shaz.plugin.fist/method", binaryMessenger: registrar.messenger())
        let instance = SwiftInternetSpeedTestPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "startListening" {
            mapToCall(result: result, arguments: call.arguments)
        } else if call.method == "cancelListening" {
            cancelListening(arguments: call.arguments, result: result)
        } else if call.method == "toggleLog" {
            toggleLog(result: result, arguments: call.arguments)
        } else if call.method == "cancelTest" {
            cancelTasks(result: result, arguments: call.arguments)
        }
    }

    private func mapToCall(result: FlutterResult, arguments: Any?) {
        guard let argsMap = arguments as? [String: Any],
              let testId = argsMap["id"] as? Int else {
            logger.printLog(message: "Invalid arguments for startListening")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'id' in arguments", details: nil))
            return
        }

        var fileSize = DEFAULT_FILE_SIZE
        if let fileSizeArgument = argsMap["fileSize"] as? Int {
            fileSize = fileSizeArgument
        }
        logger.printLog(message: "file is of size \(fileSize) Bytes")

        guard let testServer = argsMap["testServer"] as? String else {
            logger.printLog(message: "Missing testServer argument.")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'testServer' in arguments", details: nil))
            return
        }

        switch testId {
        case 0:
            startListening(
                args: testId, flutterResult: result, methodName: "startDownloadTesting",
                testServer: testServer, fileSize: fileSize)
        case 1:
            startListening(
                args: testId, flutterResult: result, methodName: "startUploadTesting",
                testServer: testServer, fileSize: fileSize)
        case 2:
            startListening(
                args: testId, flutterResult: result, methodName: "startLatencyTesting",
                testServer: testServer, fileSize: fileSize)
        default:
            logger.printLog(message: "Invalid test id: \(testId)")
            result(FlutterError(code: "INVALID_ID", message: "Invalid test id provided", details: nil))
        }
    }

    private func toggleLog(result: FlutterResult, arguments: Any?) {
        let argsMap = arguments as! [String: Any]
        if let logValue = argsMap["value"] as? Bool {
            logger.enabled = logValue
        }
        result(nil)
    }

    private func cancelTasks(result: FlutterResult, arguments: Any?) {
        for (_, st) in speedTests {
            st.cancelTasks()
        }
        speedTests.removeAll()
        for (id, _) in cancellationFlags {
            cancellationFlags[id] = true
            callbackById.removeValue(forKey: id)
            lastUpdateTimeById.removeValue(forKey: id)
        }
        logger.printLog(message: "All tests cancelled.")
        result(true)
    }

    private func cancelListening(arguments: Any?, result: FlutterResult) {
        guard let currentListenerId = arguments as? Int else {
            result(nil)
            return
        }

        if cancellationFlags.keys.contains(currentListenerId) {
            cancellationFlags[currentListenerId] = true
        }

        callbackById.removeValue(forKey: currentListenerId)
        lastUpdateTimeById.removeValue(forKey: currentListenerId)

        if let st = speedTests[currentListenerId] {
            st.cancelTasks()
            speedTests.removeValue(forKey: currentListenerId)
        }

        logger.printLog(message: "Listener \(currentListenerId) cancelled.")
        result(nil)
    }

    func startListening(
        args: Any, flutterResult: FlutterResult, methodName: String, testServer: String,
        fileSize: Int)
    {
        let currentListenerId = args as! Int
        logger.printLog(message: "Method name is \(methodName)")
        logger.printLog(message: "id is \(currentListenerId)")

        cancellationFlags[currentListenerId] = false

        let st = SpeedTest()
        speedTests[currentListenerId] = st

        let fun = {
            if self.callbackById.keys.contains(currentListenerId) {
                switch methodName {
                case "startDownloadTesting":
                    // *** CHANGE START ***
                    st.runDownloadTest(
                        for: URL(string: testServer)!, size: fileSize,
                        timeout: TimeInterval(self.DEFAULT_TEST_TIMEOUT),
                        current: { currentSpeed in
                            self.sendSpeedUpdateToFlutter(
                                listenerId: currentListenerId,
                                speed: currentSpeed,
                                type: 2
                            )
                        },
                        final: { resultSpeed in
                            switch resultSpeed {
                            case .value(let finalSpeed):
                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["transferRate"] = self.getSpeedInBytes(speed: finalSpeed)
                                argsMap["percent"] = 100
                                argsMap["type"] = 0
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            case .error(let error):
                                self.logger.printLog(message: "Error is \(error.localizedDescription)")
                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["speedTestError"] = error.localizedDescription
                                argsMap["type"] = 1
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            }
                        }
                    )
                    // *** CHANGE END ***
                case "startUploadTesting":
                    st.runUploadTest(
                        for: URL(string: testServer)!, size: fileSize,
                        timeout: TimeInterval(self.DEFAULT_TEST_TIMEOUT),
                        current: { [weak self] currentSpeed in
                            guard let self = self else { return }
                            self.sendSpeedUpdateToFlutter(
                                listenerId: currentListenerId,
                                speed: currentSpeed,
                                type: 2
                            )
                        },
                        final: { resultSpeed in
                            switch resultSpeed {
                            case .value(let finalSpeed):
                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["transferRate"] = self.getSpeedInBytes(speed: finalSpeed)
                                argsMap["percent"] = 100
                                argsMap["type"] = 0
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            case .error(let error):
                                self.logger.printLog(message: "Error is \(error.localizedDescription)")
                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["speedTestError"] = error.localizedDescription
                                argsMap["type"] = 1
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            }
                        }
                    )
                    
                case "startLatencyTesting":
                    DispatchQueue.global(qos: .background).async {
                        self.runLatencyTest(
                            testServer: testServer,
                            listenerId: currentListenerId)
                    }
                    
                default:
                    self.logger.printLog(message: "Unknown methodName: \(methodName)")
                    DispatchQueue.main.async {
                        var argsMap: [String: Any] = [:]
                        argsMap["id"] = currentListenerId
                        argsMap["speedTestError"] = "Unknown test method"
                        argsMap["type"] = 1
                        SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                        self.cleanupListener(id: currentListenerId)
                    }
                }
            }
        }

        callbackById[currentListenerId] = fun
        fun()
        flutterResult(true)
    }

    private func sendSpeedUpdateToFlutter(listenerId: Int, speed: Speed, type: Int) {
        let now = Date()
        let lastUpdate = lastUpdateTimeById[listenerId] ?? Date.distantPast
        if now.timeIntervalSince(lastUpdate) >= updateThrottleInterval {
            lastUpdateTimeById[listenerId] = now
            
            var argsMap: [String: Any] = [:]
            argsMap["id"] = listenerId
            argsMap["transferRate"] = self.getSpeedInBytes(speed: speed)
            argsMap["percent"] = 50
            argsMap["type"] = type
            DispatchQueue.main.async {
                SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
            }
        }
    }

    func getSpeedInBytes(speed: Speed) -> Double {
        var rate = speed.value
        if speed.units == .Kbps {
            rate = rate * 1000
        } else if speed.units == .Mbps {
            rate = rate * 1000 * 1000
        } else {
            rate = rate * 1000 * 1000 * 1000
        }
        return rate
    }

    private func runLatencyTest(testServer: String, listenerId: Int) {
        guard let url = URL(string: testServer) else {
            DispatchQueue.main.async {
                var argsMap: [String: Any] = [:]
                argsMap["id"] = listenerId
                argsMap["speedTestError"] = "Invalid URL"
                argsMap["type"] = 1
                SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                self.cleanupListener(id: listenerId)
            }
            return
        }

        let host = url.host ?? ""
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let totalPings = 100
        var latencyMeasurements = [Double]()

        for currentPing in 1 ... totalPings {
            if cancellationFlags[listenerId] == true {
                DispatchQueue.main.async {
                    var argsMap: [String: Any] = [:]
                    argsMap["id"] = listenerId
                    argsMap["type"] = 3
                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                    self.cleanupListener(id: listenerId)
                }
                return
            }

            let startTime = Date().timeIntervalSince1970
            let success = self.connectToServer(host: host, port: port, timeout: 5.0)
            let endTime = Date().timeIntervalSince1970

            if !success {
                DispatchQueue.main.async {
                    var argsMap: [String: Any] = [:]
                    argsMap["id"] = listenerId
                    argsMap["speedTestError"] = "Connection failed"
                    argsMap["type"] = 1
                    SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
                    self.cleanupListener(id: listenerId)
                }
                return
            }

            let latency = (endTime - startTime) * 1000
            latencyMeasurements.append(latency)

            let percent = (Double(currentPing) / Double(totalPings)) * 100.0
            let jitter = self.calculateJitter(latencies: latencyMeasurements)

            DispatchQueue.main.async {
                var argsMap: [String: Any] = [:]
                argsMap["id"] = listenerId
                argsMap["percent"] = percent
                argsMap["latency"] = latency
                argsMap["jitter"] = jitter
                argsMap["type"] = 2
                SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        let averageLatency = latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)
        let jitter = self.calculateJitter(latencies: latencyMeasurements)

        DispatchQueue.main.async {
            var argsMap: [String: Any] = [:]
            argsMap["id"] = listenerId
            argsMap["latency"] = averageLatency
            argsMap["jitter"] = jitter
            argsMap["type"] = 0
            SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
            self.cleanupListener(id: listenerId)
        }
    }

    private func connectToServer(host: String, port: Int, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.global().async {
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?

            CFStreamCreatePairWithSocketToHost(
                nil, host as CFString, UInt32(port), &readStream, &writeStream)

            if let inputStream = readStream?.takeRetainedValue(),
               let outputStream = writeStream?.takeRetainedValue() {
                CFReadStreamSetProperty(
                    inputStream,
                    CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket),
                    kCFBooleanTrue)
                CFWriteStreamSetProperty(
                    outputStream,
                    CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket),
                    kCFBooleanTrue)

                if CFReadStreamOpen(inputStream) && CFWriteStreamOpen(outputStream) {
                    success = true
                }

                CFReadStreamClose(inputStream)
                CFWriteStreamClose(outputStream)
            }

            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            return false
        }
        return success
    }

    private func calculateJitter(latencies: [Double]) -> Double {
        guard latencies.count > 1 else {
            return 0.0
        }
        var differences = [Double]()
        for i in 1 ..< latencies.count {
            differences.append(abs(latencies[i] - latencies[i - 1]))
        }
        return differences.reduce(0, +) / Double(differences.count)
    }

    private func cleanupListener(id: Int) {
        logger.printLog(message: "Cleaning up listener \(id)")
        callbackById.removeValue(forKey: id)
        cancellationFlags.removeValue(forKey: id)
        speedTests.removeValue(forKey: id)
        lastUpdateTimeById.removeValue(forKey: id)
    }

    class Logger {
        var enabled = false

        func printLog(message: String) {
            if enabled {
                print(message)
            }
        }
    }
}
