enum MoveQuality {
  best('Best', 0xFF2E7D32),
  good('Good', 0xFF558B2F),
  inaccuracy('Inaccuracy', 0xFFF9A825),
  mistake('Mistake', 0xFFEF6C00),
  blunder('Blunder', 0xFFC62828);

  const MoveQuality(this.label, this.colorHex);

  final String label;
  final int colorHex;

  static MoveQuality fromCentipawnLoss(int cpLoss) {
    if (cpLoss <= 20) return MoveQuality.best;
    if (cpLoss <= 60) return MoveQuality.good;
    if (cpLoss <= 130) return MoveQuality.inaccuracy;
    if (cpLoss <= 260) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }
}

class StockfishEval {
  const StockfishEval({
    required this.centipawns,
    this.mateIn,
    required this.bestMoveUci,
    required this.pvUci,
    required this.depth,
  });

  /// Score from White's perspective in centipawns (+100 = +1.00 for White).
  final int centipawns;

  /// Mate in N moves from White's perspective (+N = White mates, -N = Black mates).
  final int? mateIn;

  final String bestMoveUci;
  final List<String> pvUci;
  final int depth;

  String get formattedScore {
    if (mateIn != null) {
      return mateIn! > 0 ? '+M${mateIn!.abs()}' : '-M${mateIn!.abs()}';
    }
    final pawns = centipawns / 100.0;
    final sign = pawns >= 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(2)}';
  }

  /// Normalized 0.0 (Black winning) to 1.0 (White winning) for live eval bar.
  double get whiteAdvantageRatio {
    if (mateIn != null) {
      return mateIn! > 0 ? 1.0 : 0.0;
    }
    final clamped = centipawns.clamp(-1000, 1000);
    return 0.5 + (clamped / 2000.0);
  }
}

class MoveAnalysis {
  const MoveAnalysis({
    required this.plyIndex,
    required this.playedMoveSan,
    required this.playedMoveUci,
    required this.fenBefore,
    required this.fenAfter,
    required this.evalBefore,
    required this.evalAfter,
    required this.centipawnLoss,
    required this.quality,
    required this.isWhiteMove,
    this.bestMoveSan = '',
    this.pvSan = const [],
  });

  final int plyIndex;
  final String playedMoveSan;
  final String playedMoveUci;
  final String fenBefore;
  final String fenAfter;
  final StockfishEval evalBefore;
  final StockfishEval evalAfter;
  final int centipawnLoss;
  final MoveQuality quality;
  final bool isWhiteMove;
  final String bestMoveSan;
  final List<String> pvSan;

  String get topPvSummary {
    if (pvSan.isNotEmpty) {
      return pvSan.take(3).join(' ');
    }
    return evalBefore.pvUci.take(3).join(' ');
  }
}
