import 'package:boardwell/models/coach_profile.dart';
import 'package:boardwell/models/move_analysis.dart';
import 'package:boardwell/services/coach/coach_engine.dart';
import 'package:boardwell/services/coach/rule_based_coach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoveQuality classification', () {
    test('classifies centipawn loss accurately', () {
      expect(MoveQuality.fromCentipawnLoss(0), MoveQuality.best);
      expect(MoveQuality.fromCentipawnLoss(45), MoveQuality.good);
      expect(MoveQuality.fromCentipawnLoss(100), MoveQuality.inaccuracy);
      expect(MoveQuality.fromCentipawnLoss(200), MoveQuality.mistake);
      expect(MoveQuality.fromCentipawnLoss(350), MoveQuality.blunder);
    });
  });

  group('CoachProfile backup safety', () {
    test('backup JSON preserves key reference without raw secrets', () {
      const coach = CoachProfile(
        id: 'c1',
        name: 'Cloud Coach',
        personaPrompt: 'Be concise.',
        providerType: CoachProviderType.cloudApi,
        modelId: 'gemini-2.5-flash',
        apiBaseUrl: 'https://openrouter.ai/api/v1',
        secureKeyId: 'coach_key_c1',
      );
      final json = coach.toBackupJson();
      expect(json['secureKeyId'], 'coach_key_c1');
      expect(json.containsKey('apiKey'), isFalse);
    });
  });

  group('RuleBasedCoach grounded output', () {
    test('mentions played move, quality, and Stockfish best move', () {
      const coach = RuleBasedCoach();
      const analysis = MoveAnalysis(
        plyIndex: 1,
        playedMoveSan: 'f3',
        playedMoveUci: 'f2f3',
        fenBefore: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenAfter: 'rnbqkbnr/pppppppp/8/8/8/5P2/PPPPP1PP/RNBQKBNR b KQkq - 0 1',
        evalBefore: StockfishEval(
          centipawns: 25,
          bestMoveUci: 'e2e4',
          pvUci: ['e2e4', 'e7e5', 'g1f3'],
          depth: 12,
        ),
        evalAfter: StockfishEval(
          centipawns: -90,
          bestMoveUci: 'e7e5',
          pvUci: ['e7e5'],
          depth: 12,
        ),
        centipawnLoss: 115,
        quality: MoveQuality.inaccuracy,
        isWhiteMove: true,
        bestMoveSan: 'e4',
        pvSan: ['e4', 'e5', 'Nf3'],
      );

      final text = coach.buildExplanation(
        CoachRequest(
          profile: CoachProfile.defaultBuiltInCoaches().first,
          analysis: analysis,
        ),
      );

      expect(text, contains('f3'));
      expect(text, contains('Inaccuracy'));
      expect(text, contains('e4'));
    });
  });
}
