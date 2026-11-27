import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../models/coach_profile.dart';
import '../../models/move_analysis.dart';
import '../device_capability_service.dart';
import '../storage_service.dart';
import 'cloud_api_coach_engine.dart';
import 'coach_engine.dart';
import 'on_device_coach_engine.dart';
import 'rule_based_coach.dart';

class CoachRouter {
  CoachRouter({
    required StorageService storageService,
    required DeviceCapabilityService capabilityService,
    required RuleBasedCoach ruleBasedCoach,
    required OnDeviceCoachEngine onDeviceCoachEngine,
    required CloudApiCoachEngine cloudApiCoachEngine,
  })  : _storageService = storageService,
        _capabilityService = capabilityService,
        _ruleBasedCoach = ruleBasedCoach,
        _onDeviceCoachEngine = onDeviceCoachEngine,
        _cloudApiCoachEngine = cloudApiCoachEngine;

  final StorageService _storageService;
  final DeviceCapabilityService _capabilityService;
  final RuleBasedCoach _ruleBasedCoach;
  final OnDeviceCoachEngine _onDeviceCoachEngine;
  final CloudApiCoachEngine _cloudApiCoachEngine;

  Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Queries a coach with automatic hybrid fallback when offline or if an engine fails.
  Future<CoachResponse> getCoaching({
    required CoachProfile primaryCoach,
    required MoveAnalysis analysis,
    String pgn = '',
    String openingName = '',
    String? userQuestion,
    void Function(String partialText)? onToken,
  }) async {
    final request = CoachRequest(
      profile: primaryCoach,
      analysis: analysis,
      pgn: pgn,
      openingName: openingName,
      userQuestion: userQuestion,
    );

    // 1. Offline guard for Cloud API coaches
    if (primaryCoach.providerType == CoachProviderType.cloudApi) {
      final online = await isOnline();
      if (!online) {
        return _executeFallback(
          primaryCoach: primaryCoach,
          analysis: analysis,
          pgn: pgn,
          openingName: openingName,
          userQuestion: userQuestion,
          reason: 'Offline detected — switched automatically to fallback coach.',
          onToken: onToken,
        );
      }
    }

    // 2. Low-RAM guard for On-Device coaches (unless advanced user override is enabled)
    if (primaryCoach.providerType == CoachProviderType.onDevice &&
        !_capabilityService.canUseLocalLlm) {
      return _executeFallback(
        primaryCoach: primaryCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
        userQuestion: userQuestion,
        reason:
            'Low-memory device (<4 GB RAM / 32-bit) — using instant offline fallback.',
        onToken: onToken,
      );
    }

    // 3. Attempt primary coach
    try {
      final text = await _runEngineStreaming(
        providerType: primaryCoach.providerType,
        request: request,
        onToken: onToken,
      );
      if (text.trim().isNotEmpty) {
        return CoachResponse(
          coachId: primaryCoach.id,
          coachName: primaryCoach.name,
          providerUsed: primaryCoach.providerType,
          text: text.trim(),
        );
      }
      throw StateError('Coach returned an empty response.');
    } catch (e) {
      return _executeFallback(
        primaryCoach: primaryCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
        userQuestion: userQuestion,
        reason: '${primaryCoach.name} unavailable ($e) — used fallback coach.',
        onToken: onToken,
      );
    }
  }

  /// Side-by-side "Compare Coaches" mode on the exact same Stockfish-verified position.
  Future<({CoachResponse first, CoachResponse second})> compareCoaches({
    required CoachProfile firstCoach,
    required CoachProfile secondCoach,
    required MoveAnalysis analysis,
    String pgn = '',
    String openingName = '',
  }) async {
    // Run sequentially if both are on-device to respect strict single-model-in-RAM lifecycle
    final bothOnDevice = firstCoach.providerType == CoachProviderType.onDevice &&
        secondCoach.providerType == CoachProviderType.onDevice;

    if (bothOnDevice) {
      final first = await getCoaching(
        primaryCoach: firstCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
      );
      final second = await getCoaching(
        primaryCoach: secondCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
      );
      return (first: first, second: second);
    }

    final results = await Future.wait([
      getCoaching(
        primaryCoach: firstCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
      ),
      getCoaching(
        primaryCoach: secondCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
      ),
    ]);
    return (first: results[0], second: results[1]);
  }

  Future<CoachResponse> _executeFallback({
    required CoachProfile primaryCoach,
    required MoveAnalysis analysis,
    required String pgn,
    required String openingName,
    required String? userQuestion,
    required String reason,
    void Function(String partialText)? onToken,
  }) async {
    CoachProfile? fallback;
    if (primaryCoach.fallbackCoachId.isNotEmpty &&
        primaryCoach.fallbackCoachId != primaryCoach.id) {
      fallback = await _storageService.getCoachById(primaryCoach.fallbackCoachId);
    }

    // Try configured on-device fallback if device supports it
    if (fallback != null &&
        fallback.providerType == CoachProviderType.onDevice &&
        _capabilityService.canUseLocalLlm) {
      try {
        final text = await _runEngineStreaming(
          providerType: CoachProviderType.onDevice,
          request: CoachRequest(
            profile: fallback,
            analysis: analysis,
            pgn: pgn,
            openingName: openingName,
            userQuestion: userQuestion,
          ),
          onToken: onToken,
        );
        if (text.trim().isNotEmpty) {
          return CoachResponse(
            coachId: fallback.id,
            coachName: fallback.name,
            providerUsed: CoachProviderType.onDevice,
            text: text.trim(),
            usedFallback: true,
            fallbackReason: reason,
          );
        }
      } catch (_) {
        // Fall through to guaranteed instant RuleBasedCoach
      }
    }

    final ruleCoach = (await _storageService.getCoachById('builtin_rule_coach')) ??
        CoachProfile.defaultBuiltInCoaches().first;
    final text = _ruleBasedCoach.buildExplanation(
      CoachRequest(
        profile: ruleCoach,
        analysis: analysis,
        pgn: pgn,
        openingName: openingName,
        userQuestion: userQuestion,
      ),
    );
    onToken?.call(text);

    return CoachResponse(
      coachId: ruleCoach.id,
      coachName: ruleCoach.name,
      providerUsed: CoachProviderType.ruleBased,
      text: text,
      usedFallback: primaryCoach.providerType != CoachProviderType.ruleBased,
      fallbackReason:
          primaryCoach.providerType != CoachProviderType.ruleBased ? reason : null,
    );
  }

  Future<String> _runEngineStreaming({
    required CoachProviderType providerType,
    required CoachRequest request,
    void Function(String partialText)? onToken,
  }) async {
    final CoachEngine engine = switch (providerType) {
      CoachProviderType.ruleBased => _ruleBasedCoach,
      CoachProviderType.onDevice => _onDeviceCoachEngine,
      CoachProviderType.cloudApi => _cloudApiCoachEngine,
    };

    final buffer = StringBuffer();
    await for (final chunk in engine.streamCoaching(request)) {
      buffer.write(chunk);
      onToken?.call(buffer.toString());
    }
    return buffer.toString();
  }
}
