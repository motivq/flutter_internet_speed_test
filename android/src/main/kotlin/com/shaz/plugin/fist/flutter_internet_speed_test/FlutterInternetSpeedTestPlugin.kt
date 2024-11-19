package com.shaz.plugin.fist.flutter_internet_speed_test

import android.app.Activity
import android.content.Context
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
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/** FlutterInternetSpeedTestPlugin */
class FlutterInternetSpeedTestPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
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
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        print("FlutterInternetSpeedTestPlugin: onMethodCall: ${call.method}")
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
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    private fun mapToCall(result: Result, arguments: Any?) {
        val argsMap = arguments as Map<*, *>

        val fileSize =
            if (argsMap.containsKey("fileSize")) argsMap["fileSize"] as Int else defaultFileSizeInBytes
        when (val args = argsMap["id"] as Int) {
            CallbacksEnum.START_DOWNLOAD_TESTING.ordinal -> startListening(args,
                result,
                "startDownloadTesting",
                argsMap["testServer"] as String,
                fileSize)
            CallbacksEnum.START_UPLOAD_TESTING.ordinal -> startListening(args,
                result,
                "startUploadTesting",
                argsMap["testServer"] as String,
                fileSize)
            CallbacksEnum.START_LATENCY_TESTING.ordinal -> startListening(args,
                result,
                "startLatencyTesting",
                argsMap["testServer"] as String,
                fileSize)
        }
    }

    private fun toggleLog(arguments: Any?) {
        val argsMap = arguments as Map<*, *>

        if (argsMap.containsKey("value")) {
            val logValue = argsMap["value"] as Boolean
            logger.enabled = logValue
        }
    }

    private fun startListening(
        args: Any,
        result: Result,
        methodName: String,
        testServer: String,
        fileSize: Int,
    ) {
        // Get callback id
        logger.print("Test starting")
        val currentListenerId = args as Int
        val argsMap: MutableMap<String, Any> = mutableMapOf()
        argsMap["id"] = currentListenerId

        // Remove any existing listener and cancellation flag
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

                val listener = object : TestListener {
                    override fun onComplete(transferRate: Double) {
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        // Remove listener and socket when done
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onError(speedTestError: String, errorMessage: String) {
                        argsMap["speedTestError"] = speedTestError
                        argsMap["errorMessage"] = errorMessage
                        argsMap["type"] = ListenerEnum.ERROR.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        // Remove listener and socket when done
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onProgress(percent: Double, transferRate: Double) {
                        logger.print("onProgress $percent, $transferRate")
                        argsMap["percent"] = percent
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }

                    override fun onCancel() {
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
                val listener = object : TestListener {
                    override fun onComplete(transferRate: Double) {
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        // Remove listener and socket when done
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onError(speedTestError: String, errorMessage: String) {
                        argsMap["speedTestError"] = speedTestError
                        argsMap["errorMessage"] = errorMessage
                        argsMap["type"] = ListenerEnum.ERROR.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        // Remove listener and socket when done
                        activeListeners.remove(currentListenerId)
                        activeSockets.remove(currentListenerId)
                    }

                    override fun onProgress(percent: Double, transferRate: Double) {
                        logger.print("onProgress $percent, $transferRate")
                        argsMap["percent"] = percent
                        argsMap["transferRate"] = transferRate
                        argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                    }

                    override fun onCancel() {
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

                val listener = object : LatencyTestListener  {
                     override fun onLatencyMeasured(percent: Double, latency: Double, jitter: Double) {
                            argsMap["percent"] = percent
                            argsMap["latency"] = latency
                            argsMap["jitter"] = jitter
                            argsMap["type"] = ListenerEnum.PROGRESS.ordinal
                            activity?.runOnUiThread {
                                methodChannel.invokeMethod("callListener", argsMap)
                            }
                        }

                         override fun onComplete(averageLatency: Double, jitter: Double) {
                            argsMap["latency"] = averageLatency
                            argsMap["jitter"] = jitter
                            argsMap["type"] = ListenerEnum.COMPLETE.ordinal
                            activity?.runOnUiThread {
                                methodChannel.invokeMethod("callListener", argsMap)
                            }
                            // Remove listener and cancellation flag when done
                            activeListeners.remove(currentListenerId)
                            cancellationFlags.remove(currentListenerId)
                        }
                        override fun onError(errorMessage: String) {
                            argsMap["errorMessage"] = errorMessage
                            argsMap["type"] = ListenerEnum.ERROR.ordinal
                            activity?.runOnUiThread {
                                methodChannel.invokeMethod("callListener", argsMap)
                            }
                            // Remove listener and cancellation flag when done
                            activeListeners.remove(currentListenerId)
                            cancellationFlags.remove(currentListenerId)
                        }

                    override fun onCancel() {
                        argsMap["type"] = ListenerEnum.CANCEL.ordinal
                        activity?.runOnUiThread {
                            methodChannel.invokeMethod("callListener", argsMap)
                        }
                        // Remove listener and cancellation flag when cancelled
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
            val latencyMeasurements = mutableListOf<Long>()
            val serverUrl = URL(testServer)
            val serverHost = serverUrl.host
            val serverPort = if (serverUrl.port != -1) serverUrl.port else serverUrl.defaultPort

            val totalPings = 100 // Total number of pings
            var currentPing = 0

            while (!cancellationFlag.get() && currentPing < totalPings) {
            try {
                val startTime = System.currentTimeMillis()
                val socket = Socket()
                val socketAddress = InetSocketAddress(serverHost, serverPort)
                socket.connect(socketAddress, 5000) // 5 seconds timeout
                val endTime = System.currentTimeMillis()
                val latency = endTime - startTime
                latencyMeasurements.add(latency)
                socket.close()

                currentPing++
                val percent = (currentPing.toDouble() / totalPings) * 100.0
                val jitter = calculateJitterFromLatencies(latencyMeasurements)
                
                testListener.onLatencyMeasured(percent, latency.toDouble(), jitter)
                
                Thread.sleep(100) // Sleep 100ms between pings
            } catch (e: Exception) {
                e.printStackTrace()
                testListener.onError(e.message ?: "Unknown error")
                break
                }
            }   
            if (latencyMeasurements.isNotEmpty()) {
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

    private fun testUploadSpeed(speedTestSocket: SpeedTestSocket, testListener: TestListener, testServer: String, fileSize: Int) {
        speedTestSocket.addSpeedTestListener(object : ISpeedTestListener {
            override fun onCompletion(report: SpeedTestReport) {
                // Do nothing here
            }

            override fun onError(speedTestError: SpeedTestError, errorMessage: String) {
                logger.print("OnError: ${speedTestError.name}, $errorMessage")
                testListener.onError(errorMessage, speedTestError.name)
            }

            override fun onProgress(percent: Float, report: SpeedTestReport) {
                // Do nothing here
            }
        })
        speedTestSocket.startUploadRepeat(
            testServer,
            defaultTestTimeoutInMillis,
            defaultResponseDelayInMillis,
            fileSize,
            object : IRepeatListener {
                override fun onCompletion(report: SpeedTestReport) {
                    logger.print("[COMPLETED] rate in bit/s   : " + report.transferRateBit)
                    testListener.onComplete(report.transferRateBit.toDouble())
                }

                override fun onReport(report: SpeedTestReport) {
                    logger.print("[PROGRESS] progress : ${report.progressPercent}%")
                    logger.print("[PROGRESS] rate in bit/s   : " + report.transferRateBit)
                    testListener.onProgress(report.progressPercent.toDouble(), report.transferRateBit.toDouble())
                }
            })
        logger.print("After Testing")
    }

    private fun testDownloadSpeed( speedTestSocket: SpeedTestSocket, testListener: TestListener, testServer: String, fileSize: Int) {

        speedTestSocket.addSpeedTestListener(object : ISpeedTestListener {
            override fun onCompletion(report: SpeedTestReport) {
                // Do nothing here
            }

            override fun onError(speedTestError: SpeedTestError, errorMessage: String) {
                logger.print("OnError: ${speedTestError.name}, $errorMessage")
                testListener.onError(errorMessage, speedTestError.name)
            }

            override fun onProgress(percent: Float, report: SpeedTestReport) {
                // Do nothing here
            }
        })
        speedTestSocket.startDownloadRepeat(
            testServer,
            defaultTestTimeoutInMillis,
            defaultResponseDelayInMillis,
            object : IRepeatListener {
                override fun onCompletion(report: SpeedTestReport) {
                    logger.print("[COMPLETED] rate in bit/s   : " + report.transferRateBit)
                    testListener.onComplete(report.transferRateBit.toDouble())
                }

                override fun onReport(report: SpeedTestReport) {
                    logger.print("[PROGRESS] progress : ${report.progressPercent}%")
                    logger.print("[PROGRESS] rate in bit/s   : " + report.transferRateBit)
                    testListener.onProgress(report.progressPercent.toDouble(), report.transferRateBit.toDouble())
                }
            })
        logger.print("After Testing")
    }

    private fun cancelListening(args: Any, result: Result) {
        val currentListenerId = args as Int
        activeListeners.remove(currentListenerId)
        val cancellationFlag = cancellationFlags[currentListenerId]
        if (cancellationFlag != null) {
            cancellationFlag.set(true)
            cancellationFlags.remove(currentListenerId)
        }
        result.success(null)
    }

    private fun cancelTasks(arguments: Any?, result: Result) {
        Thread(Runnable {
            arguments?.let { args ->
                val idsToCancel = args as List<Int>
                try {
                    idsToCancel.forEach { id ->
                        val socket = activeSockets[id]
                        if (socket != null && socket.speedTestMode != SpeedTestMode.NONE) {
                            socket.forceStopTask()
                            activeSockets.remove(id)
                        }
                        val cancellationFlag = cancellationFlags[id]
                        if (cancellationFlag != null) {
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
                        }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    e.localizedMessage?.let { logger.print(it) }
                    result.success(false)
                }
            } ?: run {
                result.success(false)
            }
        }).start()
    }
}


