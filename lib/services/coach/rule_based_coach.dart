import '../../models/coach_profile.dart';
import '../../models/move_analysis.dart';
import 'coach_engine.dart';

/// Instant, zero-RAM offline coach grounded strictly in Stockfish's evaluation & PV.
class RuleBasedCoach implements CoachEngine {
  const RuleBasedCoach();

  @override
  Stream<String> streamCoaching(CoachRequest request) async* {
    yield buildExplanation(request);
  }

  String buildExplanation(CoachRequest request) {
    final a = request.analysis;
    final side = a.isWhiteMove ? 'White' : 'Black';
    final bestMove = a.bestMoveSan.isNotEmpty ? a.bestMoveSan : a.evalBefore.bestMoveUci;
    final pvText = a.pvSan.isNotEmpty
        ? a.pvSan.take(3).join(' ')
        : a.evalBefore.pvUci.take(3).join(' ');

    final buffer = StringBuffer();

    switch (a.quality) {
      case MoveQuality.best:
        buffer.write(
          '$side played ${a.playedMoveSan} — **Best Move** (${a.evalAfter.formattedScore}). '
          'This matches Stockfish\'s top choice and maintains maximum precision.',
        );
      case MoveQuality.good:
        buffer.write(
          '$side played ${a.playedMoveSan} — **Good Move** (eval ${a.evalBefore.formattedScore} → ${a.evalAfter.formattedScore}, -${a.centipawnLoss} cp). ',
        );
        if (bestMove.isNotEmpty && bestMove != a.playedMoveSan) {
          buffer.write('Stockfish slightly preferred $bestMove.');
        }
      case MoveQuality.inaccuracy:
        buffer.write(
          '$side played ${a.playedMoveSan} — **Inaccuracy** (${a.evalBefore.formattedScore} → ${a.evalAfter.formattedScore}, -${a.centipawnLoss} cp). ',
        );
        if (bestMove.isNotEmpty) {
          buffer.write(
            '$bestMove kept tighter control of the position.',
          );
        }
      case MoveQuality.mistake:
        buffer.write(
          '$side played ${a.playedMoveSan} — **Mistake** (${a.evalBefore.formattedScore} → ${a.evalAfter.formattedScore}, -${a.centipawnLoss} cp). ',
        );
        if (bestMove.isNotEmpty) {
          buffer.write(
            'Prefer $bestMove instead to avoid conceding tactical or positional initiative.',
          );
        }
      case MoveQuality.blunder:
        buffer.write(
          '$side played ${a.playedMoveSan} — **Blunder** (${a.evalBefore.formattedScore} → ${a.evalAfter.formattedScore}, -${a.centipawnLoss} cp). ',
        );
        if (bestMove.isNotEmpty) {
          buffer.write(
            'Always check forcing replies before moving — $bestMove was critical here.',
          );
        }
    }

    if (pvText.isNotEmpty) {
      buffer.write('\n\nEngine principal line: `$pvText`');
    }

    if (request.openingName.isNotEmpty) {
      buffer.write('\nOpening context: ${request.openingName}.');
    }

    return buffer.toString();
  }

  @override
  Future<String> generateRawPrompt({
    required CoachProfile profile,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 256,
  }) async {
    return 'Rule-Based Coach operates offline using Stockfish analysis and does not generate free-form LLM text.';
  }
}
