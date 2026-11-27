package com.boardwell.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CAPABILITY_CHANNEL = "com.boardwell.app/device_capabilities"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Mandatory Edge-to-Edge support for Android 15/16/17+
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAPABILITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceCapabilities" -> {
                    try {
                        val activityManager =
                            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memoryInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memoryInfo)

                        val supportedAbis = Build.SUPPORTED_ABIS.toList()
                        val primaryAbi = supportedAbis.firstOrNull() ?: "unknown"
                        val is64Bit = Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
                        val cpuCores = Runtime.getRuntime().availableProcessors()

                        val payload = mapOf(
                            "totalRamBytes" to memoryInfo.totalMem,
                            "availableRamBytes" to memoryInfo.availMem,
                            "isLowRamDevice" to activityManager.isLowRamDevice,
                            "supportedAbis" to supportedAbis,
                            "primaryAbi" to primaryAbi,
                            "is64Bit" to is64Bit,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "androidRelease" to Build.VERSION.RELEASE,
                            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                            "cpuCores" to cpuCores
                        )
                        result.success(payload)
                    } catch (e: Exception) {
                        result.error(
                            "CAPABILITY_ERROR",
                            "Failed to read Android hardware capabilities: ${e.message}",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
