package com.shaz.plugin.fist.flutter_internet_speed_test

import android.app.Activity
import android.content.Context
import android.util.Log
import fr.bmartel.speedtest.SpeedTestReport
import fr.bmartel.speedtest.SpeedTestSocket
import fr.bmartel.speedtest.inter.IRepeatListener
import fr.bmartel.speedtest.inter.ISpeedTestListener
import fr.bmartel.speedtest.model.SpeedTestError
import fr.bmartel.speedtest.model.SpeedTestMode
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** FlutterInternetSpeedTestPlugin */
class FlutterInternetSpeedTestPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private val defaultFileSizeInBytes: Int = 10 * 1024 * 1024 //10 MB
    private val defaultTestTimeoutInMillis: Int = TimeUnit.SECONDS.toMillis(20).toInt()
    private val defaultResponseDelayInMillis: Int = TimeUnit.MILLISECONDS.toMillis(500).toInt()

    private lateinit var methodChannel: MethodChannel
    private var activity: Activity? = null
    private var applicationContext: Context? = null

    private val logger = Logger()

    // Executor service to manage threads
    private val executorService = Executors.newCachedThreadPool()

    private val activeListeners = mutableMapOf<Int, Any>()
    private val activeSockets = mutableMapOf<Int, SpeedTestSocket>()
    private val cancellationFlags = mutableMapOf<Int, AtomicBoolean>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "com.shaz.plugin.fist/method")
        methodChannel.setMethodCallHandler(this)

        // Enable logger if needed:
        logger.enabled = false
        logger.print("Plugin attached to engine.")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        logger.print("onMethodCall: ${call.method}, arguments: ${call.arguments}")
        when (call.method) {
            "startListening" -> mapToCall(result, call.arguments)
            "cancelListening" -> cancelListening(call.arguments, result)
            "toggleLog" -> toggleLog(call.arguments)
            "cancelTest" -> cancelTasks(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activity = null
        applicationContext = null
        methodChannel.setMethodCallHandler(null)
        logger.print("Plugin detached from engine.")
    }

    override fun onDetachedFromActivity() {
        activity = null
        logger.print("Detached from activity.")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        logger.print("Reattached to activity for config changes.")
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        logger.print("Attached to activity.")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        logger.print("Detached from activity for config changes.")
    }

    private fun mapToCall(result: MethodChannel.Result, arguments: Any?) {
        logger.print("mapToCall with arguments: $arguments")
        val argsMap = arguments as Map<*, *>

        val fileSize =
            if (argsMap.containsKey("fileSize")) argsMap["fileSize"] as Int else defaultFileSizeInBytes
        logger.print("fileSize: $fileSize Bytes")

        val testServer = argsMap["testServer"] as? String
        logger.print("testServer: $testServer")

        val listenerId = argsMap["id"] as Int
        logger.print("ListenerId: $listenerId")

        when (listenerId) {
            CallbacksEnum.START_DOWNLOAD_TESTING.ordinal -> {
                logger.print("Method name is startDownloadTesting")
                startListening(listenerId, result, "startDownloadTesting", testServer ?: "", fileSize)
            }
            CallbacksEnum.START_UPLOAD_TESTING.ordinal -> {
                logger.print("Method name is startUploadTesting")
                startListening(listenerId, result, "startUploadTesting", testServer ?: "", fileSize)
            }
            CallbacksEnum.START_LATENCY_TESTING.ordinal -> {
                logger.print("Method name is startLatencyTesting")
                startListening(listenerId, result, "startLatencyTesting", testServer ?: "", fileSize)
            }
        }
    }

    private fun toggleLog(arguments: Any?) {
        val argsMap = arguments as Map<*, *>

        if (argsMap.containsKey("value")) {
            val logValue = argsMap["value"] as Boolean
            logger.enabled = logValue
            logger.print("Logging toggled to: $logValue")
        }
    }

    private fun startListening(
        args: Int,
        result: MethodChannel.Result,
        methodName: String,
        testServer: String,
        fileSize: Int,
    ) {
        logger.print("startListening: methodName=$methodName, testServer=$testServer, fileSize=$fileSize")
        val currentListenerId = args
        val argsMap: MutableMap<String, Any> = mutableMapOf()
        argsMap["id"] = currentListenerId

        activeListeners.remove(currentListenerId)
        val existingCancellationFlag = cancellationFlags[currentListenerId]
        if (existingCancellationFlag != null) {
            existingCancellationFlag.set(true)
            cancellationFlags.remove(currentListenerId)
        }

        logger.print("Test listener Id: $currentListenerId")

        when (methodName) {
            "startDownloadTesting" -> {
                val speedTestSocket = SpeedTestSocket()
                activeSockets[currentListenerId] = speedTestSocket
                logger.print("Starting download test with SpeedTestSocket, server: $testServer")

                val listener = object : TestListener {
                    override fun onComplete(transferRate: Double) {
                        logger.print("Download complete with rate: $transferRate bit/s")
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onError(speedTestError: String, errorMessage: String) {
                        logger.print("Download error: $speedTestError, $errorMessage")
                        val finalErrorMessage = if (errorMessage.isEmpty()) "Unknown error" else errorMessage
                        val finalSpeedTestError = if (speedTestError.isEmpty()) "Unknown error" else speedTestError
                        argsMap["speedTestError"] = finalSpeedTestError
                        argsMap["errorMessage"] = finalErrorMessage
                        argsMap["type"] = ListenerEnum.ERROR.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onProgress(percent: Double, transferRate: Double) {
                        logger.print("Download progress: $percent%, $transferRate bit/s")
                        argsMap["percent"] = percent
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }

                    override fun onCancel() {
                        logger.print("Download test cancelled.")
                        argsMap["type"] = ListenerEnum.CANCEL.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }
                }
                activeListeners[currentListenerId] = listener
                executorService.execute {
                    testDownloadSpeed(speedTestSocket, listener, testServer, fileSize)
                }
            }
            "startUploadTesting" -> {
                val speedTestSocket = SpeedTestSocket()
                activeSockets[currentListenerId] = speedTestSocket
                logger.print("Starting upload test with SpeedTestSocket, server: $testServer")

                val listener = object : TestListener {
                    override fun onComplete(transferRate: Double) {
                        logger.print("Upload complete with rate: $transferRate bit/s")
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onError(speedTestError: String, errorMessage: String) {
                        logger.print("Upload error: $speedTestError, $errorMessage")
                        val finalErrorMessage = if (errorMessage.isEmpty()) "Unknown error" else errorMessage
                        val finalSpeedTestError = if (speedTestError.isEmpty()) "Unknown error" else speedTestError
                        argsMap["speedTestError"] = finalSpeedTestError
                        argsMap["errorMessage"] = finalErrorMessage
                        argsMap["type"] = ListenerEnum.ERROR.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onProgress(percent: Double, transferRate: Double) {
                        logger.print("Upload progress: $percent%, $transferRate bit/s")
                        argsMap["percent"] = percent
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }

                    override fun onCancel() {
                        logger.print("Upload test cancelled.")
                        argsMap["type"] = ListenerEnum.CANCEL.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }
                }
                activeListeners[currentListenerId] = listener
                executorService.execute {
                    testUploadSpeed(speedTestSocket, listener, testServer, fileSize)
                }
            }
            "startLatencyTesting" -> {
                val cancellationFlag = AtomicBoolean(false)
                cancellationFlags[currentListenerId] = cancellationFlag
                logger.print("Starting latency test with server: $testServer")

                val listener = object : LatencyTestListener  {
                    override fun onLatencyMeasured(percent: Double, latency: Double, jitter: Double) {
                        logger.print("Latency progress: $percent%, latency: $latency ms, jitter: $jitter ms")
                        argsMap["percent"] = percent
                        argsMap["latency"] = latency
                        argsMap["jitter"] = jitter
                        argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }

                    override fun onComplete(averageLatency: Double, jitter: Double) {
                        logger.print("Latency test complete: average latency: $averageLatency ms, jitter: $jitter ms")
                        argsMap["latency"] = averageLatency
                        argsMap["jitter"] = jitter
                        argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        cancellationFlags.remove(currentListenerId)
                    }

                    override fun onError(errorMessage: String) {
                        logger.print("Latency test error: $errorMessage")
                        val finalErrorMessage = if (errorMessage.isEmpty()) "Unknown error" else errorMessage
                        argsMap["errorMessage"] = finalErrorMessage
                        argsMap["type"] = ListenerEnum.ERROR.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        cancellationFlags.remove(currentListenerId)
                    }

                    override fun onCancel() {
                        logger.print("Latency test cancelled.")
                        argsMap["type"] = ListenerEnum.CANCEL.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        activeListeners.remove(currentListenerId)
                        cancellationFlags.remove(currentListenerId)
                    }
                }
                activeListeners[currentListenerId] = listener
                executorService.execute {
                    testLatency(testServer, listener, cancellationFlag)
                }
            }
        }
        result.success(null)
    }

    private fun testLatency(testServer: String, testListener: LatencyTestListener, cancellationFlag: AtomicBoolean) {
        logger.print("testLatency: testServer=$testServer")
        val latencyMeasurements = mutableListOf<Long>()
        val serverUrl = URL(testServer)
        val serverHost = serverUrl.host
        val serverPort = if (serverUrl.port != -1) serverUrl.port else serverUrl.defaultPort

        logger.print("Latency test connecting to host=$serverHost, port=$serverPort")

        val totalPings = 100
        var currentPing = 0

        while (!cancellationFlag.get() && currentPing < totalPings) {
            try {
                val startTime = System.currentTimeMillis()
                val socket = Socket()
                val socketAddress = InetSocketAddress(serverHost, serverPort)
                logger.print("Connecting to $serverHost:$serverPort")
                socket.connect(socketAddress, 5000) // 5s timeout
                val endTime = System.currentTimeMillis()
                val latency = endTime - startTime
                logger.print("Ping $currentPing: latency=$latency ms")
                latencyMeasurements.add(latency)
                socket.close()

                currentPing++
                val percent = (currentPing.toDouble() / totalPings) * 100.0
                val jitter = calculateJitterFromLatencies(latencyMeasurements)

                testListener.onLatencyMeasured(percent, latency.toDouble(), jitter)

                Thread.sleep(100)
            } catch (e: Exception) {
                e.printStackTrace()
                logger.print("Latency test error: ${e.message}")
                testListener.onError(e.message ?: "Unknown error")
                break
            }
        }

        if (latencyMeasurements.isNotEmpty() && !cancellationFlag.get()) {
            val averageLatency = latencyMeasurements.average()
            val jitter = calculateJitterFromLatencies(latencyMeasurements)
            testListener.onComplete(averageLatency, jitter)
        }
    }

    private fun calculateJitterFromLatencies(latencyMeasurements: List<Long>): Double {
        if (latencyMeasurements.size < 2) {
            return 0.0
        }
        val jitters = latencyMeasurements.zipWithNext { a, b -> kotlin.math.abs(b - a) }
        return jitters.average()
    }

    private fun testUploadSpeed(
        speedTestSocket: SpeedTestSocket,
        testListener: TestListener,
        testServer: String,
        fileSize: Int
    ) {
        logger.print("testUploadSpeed: testServer=$testServer, fileSize=$fileSize")
        speedTestSocket.addSpeedTestListener(object : ISpeedTestListener {
            override fun onCompletion(report: SpeedTestReport) {
                // Do nothing here
            }

            override fun onError(speedTestError: SpeedTestError, errorMessage: String) {
                logger.print("Upload OnError: ${speedTestError.name}, $errorMessage")
                testListener.onError(errorMessage, speedTestError.name)
            }

            override fun onProgress(percent: Float, report: SpeedTestReport) {
                // Do nothing here
            }
        })

        logger.print("Starting upload repeat test with timeout=$defaultTestTimeoutInMillis and responseDelay=$defaultResponseDelayInMillis")
        speedTestSocket.startUploadRepeat(
            testServer,
            defaultTestTimeoutInMillis,
            defaultResponseDelayInMillis,
            fileSize,
            object : IRepeatListener {
                override fun onCompletion(report: SpeedTestReport) {
                    logger.print("[UPLOAD COMPLETED] rate in bit/s: ${report.transferRateBit}")
                    testListener.onComplete(report.transferRateBit.toDouble())
                }

                override fun onReport(report: SpeedTestReport) {
                    logger.print("[UPLOAD PROGRESS] progress: ${report.progressPercent}%, rate in bit/s: ${report.transferRateBit}")
                    testListener.onProgress(report.progressPercent.toDouble(), report.transferRateBit.toDouble())
                }
            }
        )
        logger.print("After Testing Upload")
    }

    private fun testDownloadSpeed(
        speedTestSocket: SpeedTestSocket,
        testListener: TestListener,
        testServer: String,
        fileSize: Int
    ) {
        logger.print("testDownloadSpeed: testServer=$testServer, fileSize=$fileSize")
        speedTestSocket.addSpeedTestListener(object : ISpeedTestListener {
            override fun onCompletion(report: SpeedTestReport) {
                // Do nothing here
            }

            override fun onError(speedTestError: SpeedTestError, errorMessage: String) {
                logger.print("Download OnError: ${speedTestError.name}, $errorMessage")
                testListener.onError(errorMessage, speedTestError.name)
            }

            override fun onProgress(percent: Float, report: SpeedTestReport) {
                // Do nothing here
            }
        })

        logger.print("Starting download repeat test with timeout=$defaultTestTimeoutInMillis and responseDelay=$defaultResponseDelayInMillis")
        speedTestSocket.startDownloadRepeat(
            testServer,
            defaultTestTimeoutInMillis,
            defaultResponseDelayInMillis,
            object : IRepeatListener {
                override fun onCompletion(report: SpeedTestReport) {
                    logger.print("[DOWNLOAD COMPLETED] rate in bit/s: ${report.transferRateBit}")
                    testListener.onComplete(report.transferRateBit.toDouble())
                }

                override fun onReport(report: SpeedTestReport) {
                    logger.print("[DOWNLOAD PROGRESS] progress: ${report.progressPercent}%, rate in bit/s: ${report.transferRateBit}")
                    testListener.onProgress(report.progressPercent.toDouble(), report.transferRateBit.toDouble())
                }
            }
        )
        logger.print("After Testing Download")
    }

    private fun cancelListening(args: Any, result: MethodChannel.Result) {
        val currentListenerId = args as Int
        logger.print("cancelListening for listenerId=$currentListenerId")
        activeListeners.remove(currentListenerId)
        val cancellationFlag = cancellationFlags[currentListenerId]
        if (cancellationFlag != null) {
            logger.print("Setting cancellation flag for listenerId=$currentListenerId")
            cancellationFlag.set(true)
            cancellationFlags.remove(currentListenerId)
        }
        result.success(null)
    }

    private fun cancelTasks(arguments: Any?, result: MethodChannel.Result) {
        logger.print("cancelTasks called with arguments: $arguments")
        Thread {
            arguments?.let { args ->
                val idsToCancel = args as List<Int>
                try {
                    for (id in idsToCancel) {
                        logger.print("Cancelling test for id=$id")
                        val socket = activeSockets[id]
                        if (socket != null && socket.speedTestMode != SpeedTestMode.NONE) {
                            socket.forceStopTask()
                            activeSockets.remove(id)
                            logger.print("Socket forced stopped for id=$id")
                        }
                        val cancellationFlag = cancellationFlags[id]
                        if (cancellationFlag != null) {
                            logger.print("Setting cancellation flag for id=$id")
                            cancellationFlag.set(true)
                            cancellationFlags.remove(id)
                        }
                        val listener = activeListeners[id]
                        if (listener != null) {
                            when (listener) {
                                is TestListener -> listener.onCancel()
                                is LatencyTestListener -> listener.onCancel()
                            }
                            activeListeners.remove(id)
                            logger.print("Listener removed for id=$id")
                        }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    e.localizedMessage?.let { logger.print("Error in cancelTasks: $it") }
                    result.success(false)
                }
            } ?: run {
                logger.print("No arguments provided to cancelTasks.")
                result.success(false)
            }
        }.start()
    }
}
