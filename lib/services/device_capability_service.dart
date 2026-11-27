import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_capability.dart';

class DeviceCapabilityService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.boardwell.app/device_capabilities');
  static const String _overrideLocalLlmKey = 'override_low_ram_local_llm';

  DeviceCapability _capability = DeviceCapability.fallbackSafe();
  bool _allowLowRamLocalLlmOverride = false;
  bool _initialized = false;

  DeviceCapability get capability => _capability;
  bool get allowLowRamLocalLlmOverride => _allowLowRamLocalLlmOverride;
  bool get isInitialized => _initialized;

  bool get canUseLocalLlm =>
      _capability.localLlmRecommended || _allowLowRamLocalLlmOverride;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _allowLowRamLocalLlmOverride = prefs.getBool(_overrideLocalLlmKey) ?? false;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final raw = await _channel
            .invokeMapMethod<String, dynamic>('getDeviceCapabilities');
        if (raw != null) {
          _capability = _parseCapability(raw);
        }
      } catch (e) {
        debugPrint('[DeviceCapabilityService] Channel fallback: $e');
        _capability = DeviceCapability.fallbackSafe();
      }
    } else {
      _capability = const DeviceCapability(
        totalRamBytes: 8 * 1024 * 1024 * 1024,
        availableRamBytes: 4 * 1024 * 1024 * 1024,
        isAndroidLowRamFlag: false,
        supportedAbis: ['arm64-v8a'],
        primaryAbi: 'arm64-v8a',
        is64Bit: true,
        sdkInt: 36,
        androidRelease: '16',
        deviceModel: 'Desktop / Non-Android Host',
        cpuCores: 4,
        tier: PerformanceTier.standardHigh,
        stockfishThreads: 2,
        stockfishHashMb: 32,
        stockfishMaxDepth: 14,
        enableHeavyAnimations: true,
        localLlmRecommended: true,
      );
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setLowRamLocalLlmOverride(bool enabled) async {
    _allowLowRamLocalLlmOverride = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_overrideLocalLlmKey, enabled);
    notifyListeners();
  }

  DeviceCapability _parseCapability(Map<String, dynamic> raw) {
    final totalRamBytes = (raw['totalRamBytes'] as num?)?.toInt() ?? 0;
    final availableRamBytes = (raw['availableRamBytes'] as num?)?.toInt() ?? 0;
    final isAndroidLowRamFlag = raw['isLowRamDevice'] as bool? ?? false;
    final supportedAbis = (raw['supportedAbis'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    final primaryAbi = raw['primaryAbi'] as String? ?? 'armeabi-v7a';
    final is64Bit = raw['is64Bit'] as bool? ?? false;
    final sdkInt = (raw['sdkInt'] as num?)?.toInt() ?? 24;
    final androidRelease = raw['androidRelease'] as String? ?? '7.0';
    final deviceModel = raw['deviceModel'] as String? ?? 'Android Device';
    final cpuCores = (raw['cpuCores'] as num?)?.toInt() ?? 2;

    final totalRamGb = totalRamBytes / (1024 * 1024 * 1024);

    // Low-Memory Profile: < 3.5 GB RAM OR 32-bit ABI OR Android low-RAM flag
    final isLowMemory = totalRamGb < 3.5 || !is64Bit || isAndroidLowRamFlag;

    return DeviceCapability(
      totalRamBytes: totalRamBytes,
      availableRamBytes: availableRamBytes,
      isAndroidLowRamFlag: isAndroidLowRamFlag,
      supportedAbis: supportedAbis,
      primaryAbi: primaryAbi,
      is64Bit: is64Bit,
      sdkInt: sdkInt,
      androidRelease: androidRelease,
      deviceModel: deviceModel,
      cpuCores: cpuCores,
      tier: isLowMemory
          ? PerformanceTier.lowMemory
          : PerformanceTier.standardHigh,
      stockfishThreads: isLowMemory ? 1 : 2,
      stockfishHashMb: isLowMemory ? 16 : 32,
      stockfishMaxDepth: isLowMemory ? 10 : 14,
      enableHeavyAnimations: !isLowMemory,
      localLlmRecommended: !isLowMemory && totalRamGb >= 4.0,
    );
  }
}
