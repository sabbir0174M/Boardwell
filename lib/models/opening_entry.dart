class OpeningEntry {
  const OpeningEntry({
    required this.eco,
    required this.name,
    required this.moves,
    required this.fen,
    required this.summary,
  });

  final String eco;
  final String name;
  final List<String> moves;
  final String fen;
  final String summary;

  String get formattedLine {
    final buffer = StringBuffer();
    for (int i = 0; i < moves.length; i++) {
      if (i.isEven) {
        buffer.write('${(i ~/ 2) + 1}. ');
      }
      buffer.write('${moves[i]} ');
    }
    return buffer.toString().trim();
  }

  factory OpeningEntry.fromJson(Map<String, dynamic> json) {
    return OpeningEntry(
      eco: json['eco'] as String? ?? 'A00',
      name: json['name'] as String? ?? 'Unknown Opening',
      moves: (json['moves'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      fen: json['fen'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
    );
  }
}
