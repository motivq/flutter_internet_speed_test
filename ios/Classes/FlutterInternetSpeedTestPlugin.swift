import Flutter
import UIKit

public class SwiftInternetSpeedTestPlugin: NSObject, FlutterPlugin {
    let DEFAULT_FILE_SIZE = 10485760
    let DEFAULT_TEST_TIMEOUT = 20000

    var callbackById: [Int: () -> Void] = [:]

    private var cancellationFlags = [Int: Bool]()
    private var speedTests = [Int: SpeedTest]()

    static var channel: FlutterMethodChannel!

    private let logger = Logger()

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
        let argsMap = arguments as! [String: Any]
        let args = argsMap["id"] as! Int
        var fileSize = DEFAULT_FILE_SIZE
        if let fileSizeArgument = argsMap["fileSize"] as? Int {
            fileSize = fileSizeArgument
        }
        logger.printLog(message: "file is of size \(fileSize) Bytes")
        switch args {
        case 0:
            startListening(
                args: args, flutterResult: result, methodName: "startDownloadTesting",
                testServer: argsMap["testServer"] as! String, fileSize: fileSize)
        case 1:
            startListening(
                args: args, flutterResult: result, methodName: "startUploadTesting",
                testServer: argsMap["testServer"] as! String, fileSize: fileSize)
        case 2:
            startListening(
                args: args, flutterResult: result, methodName: "startLatencyTesting",
                testServer: argsMap["testServer"] as! String, fileSize: fileSize)
        default:
            break
        }
    }

    private func toggleLog(result: FlutterResult, arguments: Any?) {
        let argsMap = arguments as! [String: Any]
        if argsMap["value"] != nil {
            let logValue = argsMap["value"] as! Bool
            logger.enabled = logValue
        }
    }

    private func cancelTasks(result: FlutterResult, arguments: Any?) {
        for (_, st) in speedTests {
            st.cancelTasks()
        }
        speedTests.removeAll()
        // Reset all cancellation flags
        for (id, _) in cancellationFlags {
            cancellationFlags[id] = true
            callbackById.removeValue(forKey: id)
        }
        result(true)
    }

    private func cancelListening(arguments: Any?, result: FlutterResult) {
        guard let currentListenerId = arguments as? Int else {
            result(nil)
            return
        }

        // Set cancellation flag for latency if exists
        if cancellationFlags.keys.contains(currentListenerId) {
            cancellationFlags[currentListenerId] = true
        }

        // Remove callback
        callbackById.removeValue(forKey: currentListenerId)

        if let st = speedTests[currentListenerId] {
            st.cancelTasks()
            speedTests.removeValue(forKey: currentListenerId)
        }

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
                    st.runDownloadTest(
                        for: URL(string: testServer)!, size: fileSize,
                        timeout: TimeInterval(self.DEFAULT_TEST_TIMEOUT),
                        current: { currentSpeed in
                            var argsMap: [String: Any] = [:]
                            argsMap["id"] = currentListenerId
                            argsMap["transferRate"] = self.getSpeedInBytes(speed: currentSpeed)
                            // In Kotlin, progress is dynamic. Here, we had 50% as a placeholder.
                            // Let's keep consistent with intermediate updates. We can assume
                            // multiple updates - but since not directly provided in Swift's
                            // SpeedTest, we keep percent as 50 for intermediate step for now.
                            argsMap["percent"] = 50
                            argsMap["type"] = 2
                            DispatchQueue.main.async {
                                SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                    "callListener", arguments: argsMap)
                            }
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
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                        "callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            case .error(let error):
                                self.logger.printLog(
                                    message: "Error is \(error.localizedDescription)")
                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["speedTestError"] = error.localizedDescription
                                argsMap["type"] = 1
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                        "callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            }
                        })

                case "startUploadTesting":
                    st.runUploadTest(
                        for: URL(string: testServer)!, size: fileSize,
                        timeout: TimeInterval(self.DEFAULT_TEST_TIMEOUT),
                        current: { currentSpeed in
                            var argsMap: [String: Any] = [:]
                            argsMap["id"] = currentListenerId
                            argsMap["transferRate"] = self.getSpeedInBytes(speed: currentSpeed)
                            // similarly keep percent as 50 for intermediate updates
                            argsMap["percent"] = 50
                            argsMap["type"] = 2
                            DispatchQueue.main.async {
                                SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                    "callListener", arguments: argsMap)
                            }
                        },
                        final: { resultSpeed in
                            switch resultSpeed {
                            case .value(let finalSpeed):

                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["transferRate"] = self.getSpeedInBytes(speed: finalSpeed)
                                // Adjust percent to 100 at completion
                                argsMap["percent"] = 100
                                argsMap["type"] = 0 // complete

                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                        "callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            case .error(let error):

                                self.logger.printLog(
                                    message: "Error is \(error.localizedDescription)")

                                var argsMap: [String: Any] = [:]
                                argsMap["id"] = currentListenerId
                                argsMap["speedTestError"] = error.localizedDescription
                                argsMap["type"] = 1
                                DispatchQueue.main.async {
                                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                                        "callListener", arguments: argsMap)
                                    self.cleanupListener(id: currentListenerId)
                                }
                            }
                        })
                case "startLatencyTesting":
                    // We'll run a series of latency checks similar to Kotlin's approach.
                    // Perform test in a background thread.
                    DispatchQueue.global(qos: .background).async {
                        self.runLatencyTest(
                            testServer: testServer,
                            listenerId: currentListenerId)
                    }
                default:
                    break
                }
            }
        }
        callbackById[currentListenerId] = fun
        fun()
        flutterResult(nil)
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

    // We'll perform 100 pings to the server and measure latency and jitter.
    private func runLatencyTest(testServer: String, listenerId: Int) {
        guard let url = URL(string: testServer) else {
            DispatchQueue.main.async {
                var argsMap: [String: Any] = [:]
                argsMap["id"] = listenerId
                argsMap["errorMessage"] = "Invalid URL"
                argsMap["type"] = 1 // error
                SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                    "callListener", arguments: argsMap)
                self.cleanupListener(id: listenerId) // Cleanup after error
            }
            return
        }

        let host = url.host ?? ""
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let totalPings = 100
        var latencyMeasurements = [Double]()

        for currentPing in 1 ... totalPings {
            // Check if cancelled
            if cancellationFlags[listenerId] == true {
                // If cancelled, notify
                DispatchQueue.main.async {
                    var argsMap: [String: Any] = [:]
                    argsMap["id"] = listenerId
                    argsMap["type"] = 3 // let's assume 3 = CANCEL (consistent with Kotlin where CANCEL = ListenerEnum.CANCEL.ordinal)
                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                        "callListener", arguments: argsMap)
                    self.cleanupListener(id: listenerId) // Cleanup after cancel
                }
                return
            }

            let startTime = Date().timeIntervalSince1970
            let success = connectToServer(host: host, port: port, timeout: 5.0)
            let endTime = Date().timeIntervalSince1970

            if !success {
                // On error
                DispatchQueue.main.async {
                    var argsMap: [String: Any] = [:]
                    argsMap["id"] = listenerId
                    argsMap["errorMessage"] = "Connection failed"
                    argsMap["type"] = 1 // error
                    SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                        "callListener", arguments: argsMap)
                    self.cleanupListener(id: listenerId) // Cleanup after cancel
                }
                return
            }

            let latency = (endTime - startTime) * 1000 // in ms
            latencyMeasurements.append(latency)

            let percent = (Double(currentPing) / Double(totalPings)) * 100.0
            let jitter = calculateJitter(latencies: latencyMeasurements)

            // Progress update
            DispatchQueue.main.async {
                var argsMap: [String: Any] = [:]
                argsMap["id"] = listenerId
                argsMap["percent"] = percent
                argsMap["latency"] = latency
                argsMap["jitter"] = jitter
                argsMap["type"] = 2 // progress
                SwiftInternetSpeedTestPlugin.channel.invokeMethod(
                    "callListener", arguments: argsMap)
            }

            // Sleep 100ms between pings
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Test complete
        let averageLatency = latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)
        let jitter = calculateJitter(latencies: latencyMeasurements)

        DispatchQueue.main.async {
            var argsMap: [String: Any] = [:]
            argsMap["id"] = listenerId
            argsMap["latency"] = averageLatency
            argsMap["jitter"] = jitter
            argsMap["type"] = 0 // complete
            SwiftInternetSpeedTestPlugin.channel.invokeMethod("callListener", arguments: argsMap)
            self.cleanupListener(id: listenerId) // Cleanup after cancel
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
               let outputStream = writeStream?.takeRetainedValue()
            {
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

                // Close streams after checking
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
