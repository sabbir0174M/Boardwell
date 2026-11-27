import 'package:dartchess/dartchess.dart';

import '../../models/coach_profile.dart';
import '../device_capability_service.dart';
import '../stockfish_service.dart';
import 'cloud_api_coach_engine.dart';
import 'coach_router.dart';
import 'on_device_coach_engine.dart';

class AiOpponentMoveResult {
  const AiOpponentMoveResult({
    required this.move,
    required this.san,
    required this.usedStockfishFallback,
    required this.attemptsUsed,
    this.statusNote,
  });

  final Move move;
  final String san;
  final bool usedStockfishFallback;
  final int attemptsUsed;
  final String? statusNote;
}

/// Direct AI Model Opponent Mode:
/// Sends PGN + legal SAN moves to any configured on-device or cloud Coach model,
/// validates with dartchess, retries up to 3 times on illegal moves, and falls back to Stockfish.
class AiOpponentService {
  AiOpponentService({
    required StockfishService stockfishService,
    required OnDeviceCoachEngine onDeviceCoachEngine,
    required CloudApiCoachEngine cloudApiCoachEngine,
    required CoachRouter coachRouter,
    required DeviceCapabilityService capabilityService,
  })  : _stockfishService = stockfishService,
        _onDeviceCoachEngine = onDeviceCoachEngine,
        _cloudApiCoachEngine = cloudApiCoachEngine,
        _coachRouter = coachRouter,
        _capabilityService = capabilityService;

  final StockfishService _stockfishService;
  final OnDeviceCoachEngine _onDeviceCoachEngine;
  final CloudApiCoachEngine _cloudApiCoachEngine;
  final CoachRouter _coachRouter;
  final DeviceCapabilityService _capabilityService;

  Future<AiOpponentMoveResult?> chooseMove({
    required Position position,
    required String pgn,
    required CoachProfile opponentCoach,
  }) async {
    final legalMap = _buildLegalSanMap(position);
    if (legalMap.isEmpty) return null;

    final legalSanList = legalMap.keys.toList();

    // Check if opponent coach can actually run an LLM
    final bool canRunCloud =
        opponentCoach.providerType == CoachProviderType.cloudApi &&
            await _coachRouter.isOnline();
    final bool canRunLocal =
        opponentCoach.providerType == CoachProviderType.onDevice &&
            _capabilityService.canUseLocalLlm;

    if (!canRunCloud && !canRunLocal) {
      return _stockfishFallback(
        position: position,
        reason:
            '${opponentCoach.name} is offline or unavailable — played Stockfish fallback move.',
      );
    }

    const int maxRetries = 3;
    String? lastIllegalAttempt;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final sideName = position.turn == Side.white ? 'White' : 'Black';
      final systemPrompt =
          '${opponentCoach.personaPrompt}\n'
          'You are playing chess as $sideName. Reply with ONLY one legal chess move in Standard Algebraic Notation (SAN) chosen verbatim from the provided legal moves list. No commentary.';

      final userPrompt = StringBuffer()
        ..writeln('Current FEN: ${position.fen}')
        ..writeln('Game PGN: ${pgn.isEmpty ? "(Opening move)" : pgn}')
        ..writeln('Legal SAN moves: ${legalSanList.join(", ")}');

      if (lastIllegalAttempt != null) {
        userPrompt.writeln(
          'Your previous reply "$lastIllegalAttempt" was illegal. '
          'Pick ONE exact move from the Legal SAN moves list above.',
        );
      }

      try {
        final rawReply = opponentCoach.providerType == CoachProviderType.cloudApi
            ? await _cloudApiCoachEngine.generateRawPrompt(
                profile: opponentCoach,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt.toString(),
                maxTokens: 24,
              )
            : await _onDeviceCoachEngine.generateRawPrompt(
                profile: opponentCoach,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt.toString(),
                maxTokens: 512,
              );

        final matched = _extractLegalMove(rawReply, legalMap, position);
        if (matched != null) {
          return AiOpponentMoveResult(
            move: matched.move,
            san: matched.san,
            usedStockfishFallback: false,
            attemptsUsed: attempt,
          );
        }
        lastIllegalAttempt = rawReply.trim();
      } catch (_) {
        lastIllegalAttempt = 'engine_error';
      }
    }

    return _stockfishFallback(
      position: position,
      reason:
          '${opponentCoach.name} did not return a legal move after 3 tries — Stockfish played instead.',
    );
  }

  Map<String, Move> _buildLegalSanMap(Position position) {
    final result = <String, Move>{};
    final legalMoves = makeLegalMoves(position);
    for (final entry in legalMoves.entries) {
      final from = entry.key;
      for (final to in entry.value.squares) {
        final isPromotion = position.board.pieceAt(from)?.role == Role.pawn &&
            (to.rank == Rank.eighth || to.rank == Rank.first);
        if (isPromotion) {
          for (final role in [Role.queen, Role.rook, Role.bishop, Role.knight]) {
            final move = NormalMove(from: from, to: to, promotion: role);
            if (position.isLegal(move)) {
              final (_, san) = position.makeSan(move);
              result[san] = move;
            }
          }
        } else {
          final move = NormalMove(from: from, to: to);
          if (position.isLegal(move)) {
            final (_, san) = position.makeSan(move);
            result[san] = move;
          }
        }
      }
    }
    return result;
  }

  ({Move move, String san})? _extractLegalMove(
    String rawReply,
    Map<String, Move> legalMap,
    Position position,
  ) {
    final cleaned = rawReply
        .replaceAll(RegExp(r'[*`"\n\r]'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;

    // 1. Exact token match against legal SANs
    final tokens = cleaned.split(RegExp(r'\s+'));
    for (final rawToken in tokens) {
      final token = rawToken.replaceAll(RegExp(r'^[0-9]+\.+'), '').replaceAll(RegExp(r'[.,;:!?]+$'), '');
      if (legalMap.containsKey(token)) {
        return (move: legalMap[token]!, san: token);
      }
      // Try dartchess parseSan directly
      final parsedSan = position.parseSan(token);
      if (parsedSan != null && position.isLegal(parsedSan)) {
        final (_, san) = position.makeSan(parsedSan);
        return (move: parsedSan, san: san);
      }
      // Try UCI fallback if model replied e2e4
      final parsedUci = Move.parse(token.toLowerCase());
      if (parsedUci != null && position.isLegal(parsedUci)) {
        final (_, san) = position.makeSan(parsedUci);
        return (move: parsedUci, san: san);
      }
    }

    return null;
  }

  Future<AiOpponentMoveResult?> _stockfishFallback({
    required Position position,
    required String reason,
  }) async {
    final uci = await _stockfishService.getBotMove(position.fen);
    if (uci == null) return null;
    final move = Move.parse(uci);
    if (move == null || !position.isLegal(move)) return null;
    final (_, san) = position.makeSan(move);
    return AiOpponentMoveResult(
      move: move,
      san: san,
      usedStockfishFallback: true,
      attemptsUsed: 3,
      statusNote: reason,
    );
  }
}
