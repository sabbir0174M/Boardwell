class GameRecord {
  const GameRecord({
    required this.id,
    required this.title,
    required this.pgn,
    required this.finalFen,
    required this.result,
    required this.opponentType,
    required this.opponentLabel,
    required this.playerSide,
    required this.moveCount,
    required this.createdAtMs,
    this.openingName = '',
  });

  final String id;
  final String title;
  final String pgn;
  final String finalFen;
  final String result;
  final String opponentType; // 'stockfish' | 'ai_coach' | 'local_two_player'
  final String opponentLabel;
  final String playerSide; // 'white' | 'black'
  final int moveCount;
  final int createdAtMs;
  final String openingName;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'pgn': pgn,
      'finalFen': finalFen,
      'result': result,
      'opponentType': opponentType,
      'opponentLabel': opponentLabel,
      'playerSide': playerSide,
      'moveCount': moveCount,
      'createdAtMs': createdAtMs,
      'openingName': openingName,
    };
  }

  factory GameRecord.fromMap(Map<String, dynamic> map) {
    return GameRecord(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Boardwell Game',
      pgn: map['pgn'] as String? ?? '',
      finalFen: map['finalFen'] as String? ?? '',
      result: map['result'] as String? ?? '*',
      opponentType: map['opponentType'] as String? ?? 'stockfish',
      opponentLabel: map['opponentLabel'] as String? ?? 'Stockfish',
      playerSide: map['playerSide'] as String? ?? 'white',
      moveCount: (map['moveCount'] as num?)?.toInt() ?? 0,
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
      openingName: map['openingName'] as String? ?? '',
    );
  }
}
