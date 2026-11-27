import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/opening_entry.dart';
import '../models/puzzle_item.dart';

class OpeningPuzzleService {
  List<OpeningEntry> _openings = const [];
  List<PuzzleItem> _puzzles = const [];

  List<OpeningEntry> get openings => _openings;
  List<PuzzleItem> get puzzles => _puzzles;

  Future<void> loadAssets() async {
    final openingsRaw =
        await rootBundle.loadString('assets/data/openings_eco.json');
    final openingsJson = jsonDecode(openingsRaw) as List<dynamic>;
    _openings = openingsJson
        .map((e) => OpeningEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final puzzlesRaw =
        await rootBundle.loadString('assets/data/puzzles_offline.json');
    final puzzlesJson = jsonDecode(puzzlesRaw) as List<dynamic>;
    _puzzles = puzzlesJson
        .map((e) => PuzzleItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Detects the deepest matching ECO opening from the game's SAN move list.
  OpeningEntry? detectOpening(List<String> sanMoves) {
    if (sanMoves.isEmpty || _openings.isEmpty) return null;
    OpeningEntry? bestMatch;
    int longestPrefix = 0;

    for (final opening in _openings) {
      if (opening.moves.length > sanMoves.length) continue;
      bool matches = true;
      for (int i = 0; i < opening.moves.length; i++) {
        if (sanMoves[i] != opening.moves[i]) {
          matches = false;
          break;
        }
      }
      if (matches && opening.moves.length > longestPrefix) {
        longestPrefix = opening.moves.length;
        bestMatch = opening;
      }
    }
    return bestMatch;
  }
}
