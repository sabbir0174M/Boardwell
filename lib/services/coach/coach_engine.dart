import '../../models/coach_profile.dart';
import '../../models/move_analysis.dart';

class CoachRequest {
  const CoachRequest({
    required this.profile,
    required this.analysis,
    this.pgn = '',
    this.openingName = '',
    this.userQuestion,
  });

  final CoachProfile profile;
  final MoveAnalysis analysis;
  final String pgn;
  final String openingName;
  final String? userQuestion;
}

class CoachResponse {
  const CoachResponse({
    required this.coachId,
    required this.coachName,
    required this.providerUsed,
    required this.text,
    this.usedFallback = false,
    this.fallbackReason,
  });

  final String coachId;
  final String coachName;
  final CoachProviderType providerUsed;
  final String text;
  final bool usedFallback;
  final String? fallbackReason;
}

abstract class CoachEngine {
  Stream<String> streamCoaching(CoachRequest request);

  Future<String> generateRawPrompt({
    required CoachProfile profile,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 256,
  });
}

/// Anti-hallucination prompt builder: injects Stockfish-verified facts + Coach persona.
String buildGroundedCoachingPrompt(CoachRequest request) {
  final a = request.analysis;
  final sideLabel = a.isWhiteMove ? 'White' : 'Black';
  final bestLine = a.pvSan.isNotEmpty
      ? a.pvSan.take(3).join(' -> ')
      : a.evalBefore.pvUci.take(3).join(' ');

  final buffer = StringBuffer()
    ..writeln('### VERIFIED STOCKFISH ENGINE DATA (DO NOT CONTRADICT OR INVENT MOVES)')
    ..writeln('- FEN before move: ${a.fenBefore}')
    ..writeln('- FEN after move: ${a.fenAfter}')
    ..writeln('- Side that moved: $sideLabel')
    ..writeln('- Played move: ${a.playedMoveSan} (UCI: ${a.playedMoveUci})')
    ..writeln('- Move classification: ${a.quality.label} (Centipawn loss: ${a.centipawnLoss})')
    ..writeln('- Eval before move (White POV): ${a.evalBefore.formattedScore}')
    ..writeln('- Eval after move (White POV): ${a.evalAfter.formattedScore}')
    ..writeln('- Engine best move: ${a.bestMoveSan.isNotEmpty ? a.bestMoveSan : a.evalBefore.bestMoveUci}')
    ..writeln('- Top 3-move PV line: ${bestLine.isNotEmpty ? bestLine : "N/A"}');

  if (request.openingName.isNotEmpty) {
    buffer.writeln('- Detected Opening: ${request.openingName}');
  }
  if (request.pgn.isNotEmpty) {
    buffer.writeln('- Recent PGN: ${request.pgn}');
  }
  if (request.userQuestion != null && request.userQuestion!.trim().isNotEmpty) {
    buffer.writeln('- Student question: ${request.userQuestion!.trim()}');
  }

  buffer
    ..writeln()
    ..writeln('### COACHING INSTRUCTIONS')
    ..writeln('1. Base your explanation strictly on the verified Stockfish data above.')
    ..writeln('2. Explain why ${a.playedMoveSan} was rated "${a.quality.label}" and compare it with ${a.bestMoveSan.isNotEmpty ? a.bestMoveSan : a.evalBefore.bestMoveUci}.')
    ..writeln('3. Keep the response concise (3-5 sentences), actionable, and tailored to your persona.');

  return buffer.toString();
}
