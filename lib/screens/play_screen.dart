import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/coach_profile.dart';
import '../models/game_record.dart';
import '../models/move_analysis.dart';
import '../models/opening_entry.dart';
import '../services/app_services.dart';
import '../services/coach/coach_engine.dart';

enum OpponentMode {
  stockfishBot('Stockfish Bot'),
  aiCoachModel('AI Coach Model'),
  passAndPlay('2-Player Offline');

  const OpponentMode(this.label);
  final String label;
}

class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.services,
    this.initialFen,
  });

  final AppServices services;
  final String? initialFen;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final Uuid _uuid = const Uuid();

  late ChessboardController _boardController;
  late Position _position;
  final List<Position> _positionHistory = [];
  final List<Position> _redoStack = [];
  final List<String> _sanHistory = [];
  final List<Move?> _moveHistory = [];
  final Map<int, MoveAnalysis> _analysesByPly = {};

  Move? _lastMove;
  Side _orientation = Side.white;
  Side _playerSide = Side.white;
  OpponentMode _opponentMode = OpponentMode.stockfishBot;
  int _stockfishSkill = 6;

  List<CoachProfile> _coaches = const [];
  CoachProfile? _activeCoach;
  CoachProfile? _opponentCoach;

  StockfishEval _currentEval = const StockfishEval(
    centipawns: 0,
    bestMoveUci: '',
    pvUci: [],
    depth: 0,
  );
  OpeningEntry? _detectedOpening;

  bool _opponentThinking = false;
  bool _coachingLoading = false;
  String _liveCoachText = '';
  CoachResponse? _lastCoachResponse;
  String? _statusBanner;

  @override
  void initState() {
    super.initState();
    _initPosition(widget.initialFen);
    _boardController = ChessboardController(game: _buildGameData());
    _loadCoachesAndSettings();
  }

  void _initPosition(String? fen) {
    if (fen != null && fen.trim().isNotEmpty) {
      try {
        _position = Chess.fromSetup(Setup.parseFen(fen.trim()));
      } catch (_) {
        _position = Chess.initial;
      }
    } else {
      _position = Chess.initial;
    }
    _positionHistory
      ..clear()
      ..add(_position);
    _redoStack.clear();
    _sanHistory.clear();
    _moveHistory.clear();
    _analysesByPly.clear();
    _lastMove = null;
    _detectedOpening = null;
    _liveCoachText = '';
    _lastCoachResponse = null;
    _statusBanner = null;
  }

  Future<void> _loadCoachesAndSettings() async {
    final coaches = await widget.services.storageService.getCoachProfiles();
    final activeId = await widget.services.storageService.getActiveCoachId();
    final skill = await widget.services.storageService.getStockfishSkillLevel();
    final active = coaches.firstWhere(
      (c) => c.id == activeId,
      orElse: () => coaches.first,
    );
    final aiOpponent = coaches.firstWhere(
      (c) => c.providerType != CoachProviderType.ruleBased,
      orElse: () => active,
    );

    if (!mounted) return;
    setState(() {
      _coaches = coaches;
      _activeCoach = active;
      _opponentCoach = aiOpponent;
      _stockfishSkill = skill;
    });
    _refreshPositionEval();
  }

  GameData _buildGameData() {
    final PlayerSide interactable = _opponentThinking || _position.isGameOver
        ? PlayerSide.none
        : _opponentMode == OpponentMode.passAndPlay
            ? PlayerSide.both
            : (_playerSide == Side.white
                ? PlayerSide.white
                : PlayerSide.black);

    return GameData(
      fen: _position.fen,
      lastMove: _lastMove,
      playerSide: interactable,
      sideToMove: _position.turn,
      kingSquareInCheck:
          _position.isCheck ? _position.board.kingOf(_position.turn) : null,
      validMoves: makeLegalMoves(_position),
    );
  }

  void _syncBoard({bool animate = true}) {
    final allowAnim =
        animate && widget.services.capabilityService.capability.enableHeavyAnimations;
    _boardController.updatePosition(
      _buildGameData(),
      animate: allowAnim,
      resetPremove: !animate,
    );
  }

  Future<void> _refreshPositionEval() async {
    final eval = await widget.services.stockfishService.evaluatePosition(
      _position.fen,
    );
    if (!mounted) return;
    setState(() {
      _currentEval = eval;
    });
  }

  Future<void> _onUserMove(Move move, {bool? viaDragAndDrop}) async {
    if (!_position.isLegal(move) || _opponentThinking) return;

    final fenBefore = _position.fen;
    final evalBefore = _currentEval;
    final isWhiteMove = _position.turn == Side.white;
    final (nextPos, san) = _position.makeSan(move);

    setState(() {
      _position = nextPos;
      _lastMove = move;
      _positionHistory.add(nextPos);
      _redoStack.clear();
      _sanHistory.add(san);
      _moveHistory.add(move);
      _detectedOpening =
          widget.services.openingPuzzleService.detectOpening(_sanHistory);
      _statusBanner = null;
    });
    _syncBoard(animate: true);

    final plyIndex = _sanHistory.length;
    // Run anti-hallucination Stockfish move analysis in background
    unawaited(
      _analyzeMoveAsync(
        plyIndex: plyIndex,
        fenBefore: fenBefore,
        fenAfter: nextPos.fen,
        playedMoveSan: san,
        playedMoveUci: move.uci,
        isWhiteMove: isWhiteMove,
        cachedEvalBefore: evalBefore.depth > 0 ? evalBefore : null,
      ),
    );

    if (_position.isGameOver) {
      _showGameOverDialog();
      return;
    }

    if (_opponentMode != OpponentMode.passAndPlay &&
        _position.turn != _playerSide) {
      await _playOpponentTurn();
    }
  }

  Future<void> _analyzeMoveAsync({
    required int plyIndex,
    required String fenBefore,
    required String fenAfter,
    required String playedMoveSan,
    required String playedMoveUci,
    required bool isWhiteMove,
    StockfishEval? cachedEvalBefore,
  }) async {
    final analysis = await widget.services.stockfishService.analyzePlayedMove(
      plyIndex: plyIndex,
      fenBefore: fenBefore,
      fenAfter: fenAfter,
      playedMoveSan: playedMoveSan,
      playedMoveUci: playedMoveUci,
      isWhiteMove: isWhiteMove,
      cachedEvalBefore: cachedEvalBefore,
    );
    if (!mounted) return;
    setState(() {
      _analysesByPly[plyIndex] = analysis;
      _currentEval = analysis.evalAfter;
    });
  }

  Future<void> _playOpponentTurn() async {
    if (_position.isGameOver) return;
    setState(() => _opponentThinking = true);
    _syncBoard(animate: false);

    try {
      Move? chosenMove;
      String? chosenSan;
      String? note;

      if (_opponentMode == OpponentMode.stockfishBot) {
        final uci = await widget.services.stockfishService.getBotMove(
          _position.fen,
          skillLevel: _stockfishSkill,
        );
        if (uci != null) {
          final parsed = Move.parse(uci);
          if (parsed != null && _position.isLegal(parsed)) {
            chosenMove = parsed;
            chosenSan = _position.makeSan(parsed).$2;
          }
        }
      } else if (_opponentMode == OpponentMode.aiCoachModel &&
          _opponentCoach != null) {
        final aiResult = await widget.services.aiOpponentService.chooseMove(
          position: _position,
          pgn: _buildPgnText(),
          opponentCoach: _opponentCoach!,
        );
        if (aiResult != null) {
          chosenMove = aiResult.move;
          chosenSan = aiResult.san;
          note = aiResult.statusNote;
        }
      }

      if (!mounted) return;
      if (chosenMove != null && chosenSan != null) {
        final fenBefore = _position.fen;
        final isWhiteMove = _position.turn == Side.white;
        final nextPos = _position.playUnchecked(chosenMove);

        setState(() {
          _position = nextPos;
          _lastMove = chosenMove;
          _positionHistory.add(nextPos);
          _sanHistory.add(chosenSan!);
          _moveHistory.add(chosenMove);
          _detectedOpening =
              widget.services.openingPuzzleService.detectOpening(_sanHistory);
          _statusBanner = note;
        });

        unawaited(
          _analyzeMoveAsync(
            plyIndex: _sanHistory.length,
            fenBefore: fenBefore,
            fenAfter: nextPos.fen,
            playedMoveSan: chosenSan,
            playedMoveUci: chosenMove.uci,
            isWhiteMove: isWhiteMove,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opponentThinking = false);
        _syncBoard(animate: true);
        if (_position.isGameOver) {
          _showGameOverDialog();
        }
      }
    }
  }

  void _undoMove() {
    if (_positionHistory.length <= 1 || _opponentThinking) return;
    setState(() {
      final popped = _positionHistory.removeLast();
      _redoStack.add(popped);
      if (_sanHistory.isNotEmpty) _sanHistory.removeLast();
      if (_moveHistory.isNotEmpty) _moveHistory.removeLast();
      _position = _positionHistory.last;
      _lastMove = _moveHistory.isNotEmpty ? _moveHistory.last : null;
      _detectedOpening =
          widget.services.openingPuzzleService.detectOpening(_sanHistory);
    });
    _syncBoard(animate: false);
    _refreshPositionEval();
  }

  void _redoMove() {
    if (_redoStack.isEmpty || _opponentThinking) return;
    setState(() {
      final restored = _redoStack.removeLast();
      _positionHistory.add(restored);
      _position = restored;
    });
    _syncBoard(animate: false);
    _refreshPositionEval();
  }

  void _startNewGame() {
    setState(() {
      _initPosition(null);
    });
    _syncBoard(animate: false);
    _refreshPositionEval();
    if (_opponentMode != OpponentMode.passAndPlay &&
        _position.turn != _playerSide) {
      _playOpponentTurn();
    }
  }

  String _buildPgnText() {
    final buffer = StringBuffer();
    for (int i = 0; i < _sanHistory.length; i++) {
      if (i.isEven) {
        buffer.write('${(i ~/ 2) + 1}. ');
      }
      buffer.write('${_sanHistory[i]} ');
    }
    return buffer.toString().trim();
  }

  Future<void> _saveCurrentGame() async {
    final resultStr = _position.isGameOver
        ? (_position.outcome?.winner == Side.white
            ? '1-0'
            : _position.outcome?.winner == Side.black
                ? '0-1'
                : '1/2-1/2')
        : '*';

    final opponentLabel = switch (_opponentMode) {
      OpponentMode.stockfishBot => 'Stockfish (Lvl $_stockfishSkill)',
      OpponentMode.aiCoachModel => _opponentCoach?.name ?? 'AI Coach',
      OpponentMode.passAndPlay => 'Local 2-Player',
    };

    final record = GameRecord(
      id: _uuid.v4(),
      title: _detectedOpening?.name ?? 'Boardwell Match',
      pgn: _buildPgnText(),
      finalFen: _position.fen,
      result: resultStr,
      opponentType: _opponentMode.name,
      opponentLabel: opponentLabel,
      playerSide: _playerSide == Side.white ? 'white' : 'black',
      moveCount: _sanHistory.length,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      openingName: _detectedOpening?.name ?? '',
    );

    await widget.services.storageService.saveGame(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Game saved to local SQLite history.')),
    );
  }

  Future<void> _askActiveCoach({int? plyIndex}) async {
    final targetPly = plyIndex ?? _sanHistory.length;
    if (targetPly <= 0 || _activeCoach == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Play at least one move to ask your coach.')),
      );
      return;
    }

    MoveAnalysis? analysis = _analysesByPly[targetPly];
    if (analysis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analyzing position with Stockfish first...')),
      );
      final fenBefore = _positionHistory[targetPly - 1].fen;
      final fenAfter = _positionHistory[targetPly].fen;
      final san = _sanHistory[targetPly - 1];
      final uci = _moveHistory[targetPly - 1]?.uci ?? '';
      analysis = await widget.services.stockfishService.analyzePlayedMove(
        plyIndex: targetPly,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        playedMoveSan: san,
        playedMoveUci: uci,
        isWhiteMove: targetPly.isOdd,
      );
      if (mounted) {
        setState(() => _analysesByPly[targetPly] = analysis!);
      }
    }

    setState(() {
      _coachingLoading = true;
      _liveCoachText = '';
    });

    final response = await widget.services.coachRouter.getCoaching(
      primaryCoach: _activeCoach!,
      analysis: analysis,
      pgn: _buildPgnText(),
      openingName: _detectedOpening?.name ?? '',
      onToken: (partial) {
        if (!mounted) return;
        setState(() => _liveCoachText = partial);
      },
    );

    if (!mounted) return;
    setState(() {
      _coachingLoading = false;
      _lastCoachResponse = response;
      _liveCoachText = response.text;
    });
  }

  Future<void> _openCompareCoachesSheet({int? plyIndex}) async {
    final targetPly = plyIndex ?? _sanHistory.length;
    if (targetPly <= 0 || _coaches.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Play a move and have at least 2 coaches to compare.'),
        ),
      );
      return;
    }

    final analysis = _analysesByPly[targetPly];
    if (analysis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait a moment for Stockfish analysis to finish.')),
      );
      return;
    }

    CoachProfile coachA = _activeCoach ?? _coaches.first;
    CoachProfile coachB = _coaches.firstWhere(
      (c) => c.id != coachA.id,
      orElse: () => _coaches.last,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        bool running = false;
        CoachResponse? respA;
        CoachResponse? respB;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Compare Coaches on ${analysis.playedMoveSan} (${analysis.quality.label})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: coachA.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Coach A',
                            border: OutlineInputBorder(),
                          ),
                          items: _coaches
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setModalState(() {
                              coachA = _coaches.firstWhere((c) => c.id == val);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: coachB.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Coach B',
                            border: OutlineInputBorder(),
                          ),
                          items: _coaches
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setModalState(() {
                              coachB = _coaches.firstWhere((c) => c.id == val);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: running
                        ? null
                        : () async {
                            setModalState(() {
                              running = true;
                              respA = null;
                              respB = null;
                            });
                            final pair = await widget.services.coachRouter
                                .compareCoaches(
                              firstCoach: coachA,
                              secondCoach: coachB,
                              analysis: analysis,
                              pgn: _buildPgnText(),
                              openingName: _detectedOpening?.name ?? '',
                            );
                            if (!context.mounted) return;
                            setModalState(() {
                              running = false;
                              respA = pair.first;
                              respB = pair.second;
                            });
                          },
                    icon: running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compare_arrows),
                    label: Text(running ? 'Comparing...' : 'Run Side-by-Side Comparison'),
                  ),
                  if (respA != null && respB != null) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.42,
                      ),
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _CompareCard(response: respA!)),
                            const SizedBox(width: 8),
                            Expanded(child: _CompareCard(response: respB!)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showGameOverDialog() {
    final outcome = _position.outcome;
    final summary = outcome == null
        ? 'Game Over'
        : outcome.winner == Side.white
            ? 'White wins (${outcome.termination.name})'
            : outcome.winner == Side.black
                ? 'Black wins (${outcome.termination.name})'
                : 'Draw (${outcome.termination.name})';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Game Finished'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _saveCurrentGame();
            },
            child: const Text('Save Game'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _startNewGame();
            },
            child: const Text('New Game'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _boardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = (screenWidth - 24).clamp(240.0, 480.0);
    final cap = widget.services.capabilityService.capability;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _sanHistory.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _sanHistory.isNotEmpty) {
          _saveCurrentGame();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Play & Coach'),
          actions: [
            IconButton(
              tooltip: 'Save Game',
              icon: const Icon(Icons.save_outlined),
              onPressed: _saveCurrentGame,
            ),
            IconButton(
              tooltip: 'Flip Board',
              icon: const Icon(Icons.swap_vert),
              onPressed: () {
                setState(() {
                  _orientation =
                      _orientation == Side.white ? Side.black : Side.white;
                });
              },
            ),
            IconButton(
              tooltip: 'New Game',
              icon: const Icon(Icons.refresh),
              onPressed: _startNewGame,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Opponent Mode & Skill Controls
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<OpponentMode>(
                    segments: OpponentMode.values
                        .map(
                          (m) => ButtonSegment<OpponentMode>(
                            value: m,
                            label: Text(
                              m == OpponentMode.stockfishBot
                                  ? 'Stockfish'
                                  : m == OpponentMode.aiCoachModel
                                      ? 'AI Model'
                                      : '2P',
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_opponentMode},
                    onSelectionChanged: (sel) {
                      setState(() => _opponentMode = sel.first);
                      _syncBoard(animate: false);
                    },
                  ),
                  if (_opponentMode == OpponentMode.stockfishBot)
                    ActionChip(
                      avatar: const Icon(Icons.tune, size: 16),
                      label: Text('Skill $_stockfishSkill/20'),
                      onPressed: _showSkillPicker,
                    ),
                  if (_opponentMode == OpponentMode.aiCoachModel &&
                      _coaches.isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.smart_toy, size: 16),
                      label: Text(_opponentCoach?.name ?? 'Select AI'),
                      onPressed: _showOpponentCoachPicker,
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Live Evaluation Bar + Opening Badge
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 16,
                        child: Row(
                          children: [
                            Expanded(
                              flex: (_currentEval.whiteAdvantageRatio * 100)
                                  .round()
                                  .clamp(5, 95),
                              child: Container(color: Colors.grey.shade200),
                            ),
                            Expanded(
                              flex: ((1.0 - _currentEval.whiteAdvantageRatio) * 100)
                                  .round()
                                  .clamp(5, 95),
                              child: Container(color: Colors.grey.shade900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _currentEval.formattedScore,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (_detectedOpening != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_detectedOpening!.eco} • ${_detectedOpening!.name}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: colorScheme.primary),
                ),
              ],
              if (_statusBanner != null) ...[
                const SizedBox(height: 4),
                Text(
                  _statusBanner!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.tertiary),
                ),
              ],
              const SizedBox(height: 8),

              // Interactive Chessground Board
              Center(
                child: Chessboard(
                  controller: _boardController,
                  size: boardSize,
                  orientation: _orientation,
                  settings: ChessboardSettings(
                    animationDuration: cap.enableHeavyAnimations
                        ? const Duration(milliseconds: 220)
                        : Duration.zero,
                    showValidMoves: true,
                    showLastMove: true,
                    enableCoordinates: true,
                  ),
                  onMove: _onUserMove,
                ),
              ),
              const SizedBox(height: 10),

              // Undo / Redo / Ask Coach / Compare Coaches Controls
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Undo',
                    onPressed: _positionHistory.length > 1 ? _undoMove : null,
                    icon: const Icon(Icons.undo),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    tooltip: 'Redo',
                    onPressed: _redoStack.isNotEmpty ? _redoMove : null,
                    icon: const Icon(Icons.redo),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _coachingLoading ? null : () => _askActiveCoach(),
                      icon: const Icon(Icons.psychology),
                      label: Text(
                        _coachingLoading ? 'Thinking...' : 'Ask Coach',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openCompareCoachesSheet(),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Compare'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Move Strip with Stockfish Quality Badges
              if (_sanHistory.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sanHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final ply = index + 1;
                      final analysis = _analysesByPly[ply];
                      final moveNum = (index ~/ 2) + 1;
                      final label = index.isEven
                          ? '$moveNum.${_sanHistory[index]}'
                          : _sanHistory[index];

                      return ActionChip(
                        avatar: analysis != null
                            ? CircleAvatar(
                                radius: 6,
                                backgroundColor: Color(analysis.quality.colorHex),
                              )
                            : null,
                        label: Text(
                          analysis != null
                              ? '$label (${analysis.quality.label})'
                              : label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _askActiveCoach(plyIndex: ply),
                      );
                    },
                  ),
                ),

              // Coach Feedback Panel
              if (_liveCoachText.isNotEmpty || _coachingLoading) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.school, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _lastCoachResponse?.coachName ??
                                    _activeCoach?.name ??
                                    'Coach',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_lastCoachResponse?.usedFallback == true)
                              Chip(
                                label: const Text(
                                  'Offline Fallback',
                                  style: TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        if (_lastCoachResponse?.fallbackReason != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _lastCoachResponse!.fallbackReason!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.tertiary,
                                ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SelectableText(
                          _liveCoachText.isEmpty
                              ? 'Generating Stockfish-grounded feedback...'
                              : _liveCoachText,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSkillPicker() async {
    int tempSkill = _stockfishSkill;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Stockfish Skill Level'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Level $tempSkill (0 = Beginner, 20 = Maximum)'),
              Slider(
                value: tempSkill.toDouble(),
                min: 0,
                max: 20,
                divisions: 20,
                label: '$tempSkill',
                onChanged: (v) => setDlgState(() => tempSkill = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                setState(() => _stockfishSkill = tempSkill);
                await widget.services.storageService
                    .setStockfishSkillLevel(tempSkill);
                await widget.services.stockfishService.setSkillLevel(tempSkill);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOpponentCoachPicker() async {
    final selectable = _coaches
        .where((c) => c.providerType != CoachProviderType.ruleBased)
        .toList();
    if (selectable.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Select Direct AI Opponent',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...selectable.map(
            (coach) => ListTile(
              title: Text(coach.name),
              subtitle: Text(
                '${coach.providerType.displayName} • ${coach.modelId.isEmpty ? "Local model" : coach.modelId}',
              ),
              trailing: _opponentCoach?.id == coach.id
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () {
                setState(() => _opponentCoach = coach);
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.response});

  final CoachResponse response;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              response.coachName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              response.providerUsed.displayName,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (response.usedFallback && response.fallbackReason != null) ...[
              const SizedBox(height: 4),
              Text(
                response.fallbackReason!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              response.text,
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
