package com.shaz.plugin.fist.flutter_internet_speed_test

interface TestListener {

    fun onComplete(transferRate: Double)
    fun onError(speedTestError: String, errorMessage: String)
    fun onProgress(percent: Double, transferRate: Double)
    fun onCancel()

} 

interface LatencyTestListener {
    fun onLatencyMeasured(percent: Double, latency: Long, jitter: Double)
    fun onComplete(averageLatency: Double, jitter: Double)
    fun onError(errorMessage: String)
    fun onCancel()
}

