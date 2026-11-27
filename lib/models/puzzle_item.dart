class PuzzleItem {
  const PuzzleItem({
    required this.id,
    required this.title,
    required this.rating,
    required this.themes,
    required this.fen,
    required this.solutionUci,
    required this.hint,
  });

  final String id;
  final String title;
  final int rating;
  final List<String> themes;
  final String fen;
  final List<String> solutionUci;
  final String hint;

  factory PuzzleItem.fromJson(Map<String, dynamic> json) {
    return PuzzleItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Tactical Puzzle',
      rating: (json['rating'] as num?)?.toInt() ?? 1000,
      themes: (json['themes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      fen: json['fen'] as String,
      solutionUci: (json['solutionUci'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hint: json['hint'] as String? ?? 'Look for forcing checks, captures, and threats.',
    );
  }
}
