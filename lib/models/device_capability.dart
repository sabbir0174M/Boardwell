enum PerformanceTier {
  lowMemory,
  standardHigh,
}

class DeviceCapability {
  const DeviceCapability({
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.isAndroidLowRamFlag,
    required this.supportedAbis,
    required this.primaryAbi,
    required this.is64Bit,
    required this.sdkInt,
    required this.androidRelease,
    required this.deviceModel,
    required this.cpuCores,
    required this.tier,
    required this.stockfishThreads,
    required this.stockfishHashMb,
    required this.stockfishMaxDepth,
    required this.enableHeavyAnimations,
    required this.localLlmRecommended,
  });

  final int totalRamBytes;
  final int availableRamBytes;
  final bool isAndroidLowRamFlag;
  final List<String> supportedAbis;
  final String primaryAbi;
  final bool is64Bit;
  final int sdkInt;
  final String androidRelease;
  final String deviceModel;
  final int cpuCores;
  final PerformanceTier tier;

  // Auto-tuned engine & UI parameters
  final int stockfishThreads;
  final int stockfishHashMb;
  final int stockfishMaxDepth;
  final bool enableHeavyAnimations;
  final bool localLlmRecommended;

  double get totalRamGb => totalRamBytes / (1024 * 1024 * 1024);
  double get availableRamGb => availableRamBytes / (1024 * 1024 * 1024);

  bool get isLowMemoryProfile => tier == PerformanceTier.lowMemory;

  String get tierLabel =>
      isLowMemoryProfile ? 'Low-Memory Profile' : 'Standard / High Profile';

  String get architectureLabel =>
      is64Bit ? '64-bit ($primaryAbi)' : '32-bit ($primaryAbi)';

  factory DeviceCapability.fallbackSafe() {
    return const DeviceCapability(
      totalRamBytes: 2 * 1024 * 1024 * 1024,
      availableRamBytes: 1024 * 1024 * 1024,
      isAndroidLowRamFlag: true,
      supportedAbis: ['armeabi-v7a'],
      primaryAbi: 'armeabi-v7a',
      is64Bit: false,
      sdkInt: 24,
      androidRelease: '7.0',
      deviceModel: 'Generic Android Device',
      cpuCores: 4,
      tier: PerformanceTier.lowMemory,
      stockfishThreads: 1,
      stockfishHashMb: 16,
      stockfishMaxDepth: 10,
      enableHeavyAnimations: false,
      localLlmRecommended: false,
    );
  }
}
