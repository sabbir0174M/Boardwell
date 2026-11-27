import 'coach/ai_opponent_service.dart';
import 'coach/cloud_api_coach_engine.dart';
import 'coach/coach_router.dart';
import 'coach/on_device_coach_engine.dart';
import 'coach/rule_based_coach.dart';
import 'device_capability_service.dart';
import 'opening_puzzle_service.dart';
import 'stockfish_service.dart';
import 'storage_service.dart';

/// Dependency container initialized once at startup and passed cleanly through the app.
class AppServices {
  AppServices._({
    required this.capabilityService,
    required this.storageService,
    required this.stockfishService,
    required this.openingPuzzleService,
    required this.ruleBasedCoach,
    required this.onDeviceCoachEngine,
    required this.cloudApiCoachEngine,
    required this.coachRouter,
    required this.aiOpponentService,
  });

  final DeviceCapabilityService capabilityService;
  final StorageService storageService;
  final StockfishService stockfishService;
  final OpeningPuzzleService openingPuzzleService;
  final RuleBasedCoach ruleBasedCoach;
  final OnDeviceCoachEngine onDeviceCoachEngine;
  final CloudApiCoachEngine cloudApiCoachEngine;
  final CoachRouter coachRouter;
  final AiOpponentService aiOpponentService;

  static Future<AppServices> bootstrap() async {
    final capabilityService = DeviceCapabilityService();
    await capabilityService.initialize();

    final storageService = StorageService();
    await storageService.initialize();

    final openingPuzzleService = OpeningPuzzleService();
    await openingPuzzleService.loadAssets();

    final stockfishService = StockfishService();
    final savedSkill = await storageService.getStockfishSkillLevel();
    await stockfishService.initialize(
      capabilityService.capability,
      initialSkillLevel: savedSkill,
    );

    const ruleBasedCoach = RuleBasedCoach();
    final onDeviceCoachEngine = OnDeviceCoachEngine(
      storageService: storageService,
    );
    await onDeviceCoachEngine.initializeRuntime();

    final cloudApiCoachEngine = CloudApiCoachEngine(
      storageService: storageService,
    );

    final coachRouter = CoachRouter(
      storageService: storageService,
      capabilityService: capabilityService,
      ruleBasedCoach: ruleBasedCoach,
      onDeviceCoachEngine: onDeviceCoachEngine,
      cloudApiCoachEngine: cloudApiCoachEngine,
    );

    final aiOpponentService = AiOpponentService(
      stockfishService: stockfishService,
      onDeviceCoachEngine: onDeviceCoachEngine,
      cloudApiCoachEngine: cloudApiCoachEngine,
      coachRouter: coachRouter,
      capabilityService: capabilityService,
    );

    return AppServices._(
      capabilityService: capabilityService,
      storageService: storageService,
      stockfishService: stockfishService,
      openingPuzzleService: openingPuzzleService,
      ruleBasedCoach: ruleBasedCoach,
      onDeviceCoachEngine: onDeviceCoachEngine,
      cloudApiCoachEngine: cloudApiCoachEngine,
      coachRouter: coachRouter,
      aiOpponentService: aiOpponentService,
    );
  }

  Future<void> dispose() async {
    await onDeviceCoachEngine.releaseMemory();
    stockfishService.dispose();
    cloudApiCoachEngine.dispose();
    await storageService.close();
  }
}
