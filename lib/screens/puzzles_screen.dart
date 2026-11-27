import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../models/puzzle_item.dart';
import '../services/app_services.dart';

class PuzzlesScreen extends StatefulWidget {
  const PuzzlesScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<PuzzlesScreen> createState() => _PuzzlesScreenState();
}

class _PuzzlesScreenState extends State<PuzzlesScreen> {
  late ChessboardController _boardController;
  late Position _position;

  int _currentIndex = 0;
  int _solutionStep = 0;
  Move? _lastMove;
  bool _showHint = false;
  bool _solvedCurrent = false;
  String _feedback = 'Find the best move!';
  Set<String> _solvedIds = {};

  List<PuzzleItem> get _puzzles => widget.services.openingPuzzleService.puzzles;
  PuzzleItem get _currentPuzzle => _puzzles[_currentIndex];

  @override
  void initState() {
    super.initState();
    _loadPuzzle(0, createController: true);
    _loadSolvedProgress();
  }

  Future<void> _loadSolvedProgress() async {
    final solved = await widget.services.storageService.getSolvedPuzzleIds();
    if (!mounted) return;
    setState(() => _solvedIds = solved);
  }

  void _loadPuzzle(int index, {bool createController = false}) {
    _currentIndex = index.clamp(0, _puzzles.length - 1);
    final puzzle = _currentPuzzle;
    _position = Chess.fromSetup(Setup.parseFen(puzzle.fen));
    _solutionStep = 0;
    _lastMove = null;
    _showHint = false;
    _solvedCurrent = false;
    _feedback =
        '${_position.turn == Side.white ? "White" : "Black"} to move — find the tactic!';

    final data = _buildGameData();
    if (createController) {
      _boardController = ChessboardController(game: data);
    } else {
      _boardController.updatePosition(data, animate: false, resetPremove: true);
    }
  }

  GameData _buildGameData() {
    final playerSide = _solvedCurrent
        ? PlayerSide.none
        : (_position.turn == Side.white ? PlayerSide.white : PlayerSide.black);
    return GameData(
      fen: _position.fen,
      lastMove: _lastMove,
      playerSide: playerSide,
      sideToMove: _position.turn,
      kingSquareInCheck:
          _position.isCheck ? _position.board.kingOf(_position.turn) : null,
      validMoves: makeLegalMoves(_position),
    );
  }

  Future<void> _onMove(Move move, {bool? viaDragAndDrop}) async {
    if (_solvedCurrent || !_position.isLegal(move)) return;

    final expectedUci = _currentPuzzle.solutionUci[_solutionStep];
    if (move.uci == expectedUci) {
      final nextPos = _position.playUnchecked(move);
      setState(() {
        _position = nextPos;
        _lastMove = move;
        _solutionStep++;
      });
      _boardController.updatePosition(_buildGameData(), animate: true);

      if (_solutionStep >= _currentPuzzle.solutionUci.length) {
        setState(() {
          _solvedCurrent = true;
          _feedback = 'Solved! Well done.';
          _solvedIds = {..._solvedIds, _currentPuzzle.id};
        });
        await widget.services.storageService.recordPuzzleAttempt(
          puzzleId: _currentPuzzle.id,
          solved: true,
        );
        return;
      }

      // Play the forced opponent reply automatically if puzzle has multiple plies
      final replyUci = _currentPuzzle.solutionUci[_solutionStep];
      final replyMove = Move.parse(replyUci);
      if (replyMove != null && _position.isLegal(replyMove)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        setState(() {
          _position = _position.playUnchecked(replyMove);
          _lastMove = replyMove;
          _solutionStep++;
          _feedback = 'Keep going — find the follow-up!';
        });
        _boardController.updatePosition(_buildGameData(), animate: true);
      }
    } else {
      await widget.services.storageService.recordPuzzleAttempt(
        puzzleId: _currentPuzzle.id,
        solved: false,
      );
      setState(() {
        _feedback = 'Not quite (${move.uci}). Try another move or tap Hint.';
      });
    }
  }

  @override
  void dispose() {
    _boardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_puzzles.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No offline puzzles loaded.')),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = (screenWidth - 24).clamp(240.0, 460.0);
    final puzzle = _currentPuzzle;
    final isSolved = _solvedIds.contains(puzzle.id);

    return Scaffold(
      appBar: AppBar(
        title: Text('Offline Puzzles (${_solvedIds.length}/${_puzzles.length})'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                title: Text(
                  '${_currentIndex + 1}. ${puzzle.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Rating ${puzzle.rating} • ${puzzle.themes.join(", ")}',
                ),
                trailing: isSolved
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Chessboard(
                controller: _boardController,
                size: boardSize,
                orientation: _position.turn == Side.white && _solutionStep == 0
                    ? Side.white
                    : (puzzle.fen.contains(' b ') ? Side.black : Side.white),
                settings: ChessboardSettings(
                  animationDuration: widget.services.capabilityService.capability
                          .enableHeavyAnimations
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
                  showValidMoves: true,
                  showLastMove: true,
                ),
                onMove: _onMove,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _feedback,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_showHint) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Hint: ${puzzle.hint}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _loadPuzzle(_currentIndex - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showHint = true),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Hint'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _loadPuzzle(_currentIndex)),
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _currentIndex < _puzzles.length - 1
                      ? () => setState(() => _loadPuzzle(_currentIndex + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
