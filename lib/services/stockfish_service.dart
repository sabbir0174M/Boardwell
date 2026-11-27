import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:stockfish_flutter_plus/stockfish_flutter_plus.dart';

import '../models/device_capability.dart';
import '../models/move_analysis.dart';

class StockfishService {
  Stockfish? _engine;
  StreamSubscription<String>? _stdoutSub;
  final List<void Function(String line)> _lineListeners = [];

  DeviceCapability _capability = DeviceCapability.fallbackSafe();
  int _skillLevel = 6;
  bool _isReady = false;
  Future<void> _serialQueue = Future<void>.value();

  bool get isReady => _isReady;
  int get skillLevel => _skillLevel;
  DeviceCapability get capability => _capability;

  Future<void> initialize(
    DeviceCapability capability, {
    int initialSkillLevel = 6,
  }) async {
    _capability = capability;
    _skillLevel = initialSkillLevel.clamp(0, 20);

    if (_engine != null && _isReady) {
      await applyAutoTunedOptions();
      return;
    }

    try {
      final instance = Stockfish();
      _engine = instance;

      final readyCompleter = Completer<void>();
      void stateListener() {
        if (instance.state.value == StockfishState.ready &&
            !readyCompleter.isCompleted) {
          readyCompleter.complete();
        } else if (instance.state.value == StockfishState.error &&
            !readyCompleter.isCompleted) {
          readyCompleter.completeError(
            StateError('Stockfish engine failed to start.'),
          );
        }
      }

      if (instance.state.value == StockfishState.ready) {
        readyCompleter.complete();
      } else {
        instance.state.addListener(stateListener);
      }

      await readyCompleter.future.timeout(const Duration(seconds: 12));
      instance.state.removeListener(stateListener);

      _stdoutSub = instance.stdout.listen((line) {
        for (final listener in List<void Function(String)>.from(_lineListeners)) {
          listener(line);
        }
      });

      _isReady = true;
      await applyAutoTunedOptions();
    } catch (e) {
      debugPrint('[StockfishService] Startup warning: $e');
      _isReady = false;
    }
  }

  Future<void> applyAutoTunedOptions() async {
    if (!_isReady || _engine == null) return;
    await _enqueue(() async {
      _send('uci');
      await _waitForToken('uciok', timeout: const Duration(seconds: 4));
      _send('setoption name Threads value ${_capability.stockfishThreads}');
      _send('setoption name Hash value ${_capability.stockfishHashMb}');
      _send('setoption name Skill Level value $_skillLevel');
      _send('isready');
      await _waitForToken('readyok', timeout: const Duration(seconds: 4));
    });
  }

  Future<void> setSkillLevel(int level) async {
    _skillLevel = level.clamp(0, 20);
    if (!_isReady || _engine == null) return;
    await _enqueue(() async {
      _send('setoption name Skill Level value $_skillLevel');
      _send('isready');
      await _waitForToken('readyok', timeout: const Duration(seconds: 3));
    });
  }

  /// Evaluates a FEN position at full strength (Skill Level 20) for coaching & eval bar.
  Future<StockfishEval> evaluatePosition(
    String fen, {
    int? depth,
  }) async {
    final targetDepth = (depth ?? _capability.stockfishMaxDepth).clamp(4, 18);
    if (!_isReady || _engine == null) {
      return _heuristicFallbackEval(fen);
    }

    return _enqueue<StockfishEval>(() async {
      final sideToMoveIsWhite = _isWhiteToMove(fen);
      int latestCp = 0;
      int? latestMate;
      int latestDepth = 1;
      List<String> latestPv = const [];
      String bestMoveUci = '';

      final completer = Completer<StockfishEval>();

      void onLine(String line) {
        if (line.startsWith('info ')) {
          final parsed = _parseInfoLine(line, sideToMoveIsWhite);
          if (parsed != null) {
            latestDepth = parsed.depth;
            latestCp = parsed.cp;
            latestMate = parsed.mate;
            if (parsed.pv.isNotEmpty) {
              latestPv = parsed.pv;
            }
          }
        } else if (line.startsWith('bestmove ')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2 && parts[1] != '(none)') {
            bestMoveUci = parts[1];
          }
          if (!completer.isCompleted) {
            completer.complete(
              StockfishEval(
                centipawns: latestCp,
                mateIn: latestMate,
                bestMoveUci:
                    bestMoveUci.isNotEmpty ? bestMoveUci : (latestPv.isNotEmpty ? latestPv.first : ''),
                pvUci: latestPv,
                depth: latestDepth,
              ),
            );
          }
        }
      }

      _lineListeners.add(onLine);
      try {
        // Temporarily ensure full strength for accurate evaluation
        _send('setoption name Skill Level value 20');
        _send('position fen $fen');
        _send('go depth $targetDepth');
        final result = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _send('stop');
            return StockfishEval(
              centipawns: latestCp,
              mateIn: latestMate,
              bestMoveUci: latestPv.isNotEmpty ? latestPv.first : '',
              pvUci: latestPv,
              depth: latestDepth,
            );
          },
        );
        _send('setoption name Skill Level value $_skillLevel');
        return result;
      } finally {
        _lineListeners.remove(onLine);
      }
    });
  }

  /// Requests a bot move at the user's configured Skill Level (0-20).
  Future<String?> getBotMove(
    String fen, {
    int? skillLevel,
    int? depth,
  }) async {
    final effectiveSkill = (skillLevel ?? _skillLevel).clamp(0, 20);
    final effectiveDepth = (depth ?? (_capability.isLowMemoryProfile ? 8 : 12)).clamp(2, 16);

    if (!_isReady || _engine == null) {
      return _fallbackLegalMoveUci(fen);
    }

    return _enqueue<String?>(() async {
      final completer = Completer<String?>();
      void onLine(String line) {
        if (line.startsWith('bestmove ')) {
          final parts = line.split(RegExp(r'\s+'));
          final move = (parts.length >= 2 && parts[1] != '(none)') ? parts[1] : null;
          if (!completer.isCompleted) {
            completer.complete(move);
          }
        }
      }

      _lineListeners.add(onLine);
      try {
        _send('setoption name Skill Level value $effectiveSkill');
        _send('position fen $fen');
        _send('go depth $effectiveDepth movetime ${_capability.isLowMemoryProfile ? 750 : 1200}');
        return await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _send('stop');
            return _fallbackLegalMoveUci(fen);
          },
        );
      } finally {
        _lineListeners.remove(onLine);
      }
    });
  }

  /// Runs Stockfish before/after comparison and converts best move + top 3 PV moves into SAN.
  Future<MoveAnalysis> analyzePlayedMove({
    required int plyIndex,
    required String fenBefore,
    required String fenAfter,
    required String playedMoveSan,
    required String playedMoveUci,
    required bool isWhiteMove,
    StockfishEval? cachedEvalBefore,
  }) async {
    final evalBefore = cachedEvalBefore ?? await evaluatePosition(fenBefore);
    final evalAfter = await evaluatePosition(fenAfter);

    final int scoreBeforePerspective = _perspectiveScore(evalBefore, isWhiteMove);
    final int scoreAfterPerspective = _perspectiveScore(evalAfter, isWhiteMove);
    final int cpLoss = (scoreBeforePerspective - scoreAfterPerspective).clamp(0, 2000);

    final MoveQuality quality = playedMoveUci == evalBefore.bestMoveUci
        ? MoveQuality.best
        : MoveQuality.fromCentipawnLoss(cpLoss);

    final pvSan = _uciLineToSan(fenBefore, evalBefore.pvUci.take(3).toList());
    final bestMoveSan = pvSan.isNotEmpty
        ? pvSan.first
        : _singleUciToSan(fenBefore, evalBefore.bestMoveUci);

    return MoveAnalysis(
      plyIndex: plyIndex,
      playedMoveSan: playedMoveSan,
      playedMoveUci: playedMoveUci,
      fenBefore: fenBefore,
      fenAfter: fenAfter,
      evalBefore: evalBefore,
      evalAfter: evalAfter,
      centipawnLoss: cpLoss,
      quality: quality,
      isWhiteMove: isWhiteMove,
      bestMoveSan: bestMoveSan,
      pvSan: pvSan,
    );
  }

  int _perspectiveScore(StockfishEval eval, bool isWhite) {
    int whiteCp = eval.centipawns;
    if (eval.mateIn != null) {
      whiteCp = eval.mateIn! > 0 ? 1500 : -1500;
    }
    return isWhite ? whiteCp : -whiteCp;
  }

  String _singleUciToSan(String fen, String uci) {
    if (uci.isEmpty) return '';
    try {
      final pos = Chess.fromSetup(Setup.parseFen(fen));
      final move = Move.parse(uci);
      if (move == null || !pos.isLegal(move)) return uci;
      final (_, san) = pos.makeSan(move);
      return san;
    } catch (_) {
      return uci;
    }
  }

  List<String> _uciLineToSan(String fen, List<String> uciMoves) {
    final result = <String>[];
    try {
      Position pos = Chess.fromSetup(Setup.parseFen(fen));
      for (final uci in uciMoves) {
        final move = Move.parse(uci);
        if (move == null || !pos.isLegal(move)) break;
        final (nextPos, san) = pos.makeSan(move);
        result.add(san);
        pos = nextPos;
      }
    } catch (_) {
      // Return whatever prefix converted cleanly
    }
    return result;
  }

  ({int depth, int cp, int? mate, List<String> pv})? _parseInfoLine(
    String line,
    bool sideToMoveIsWhite,
  ) {
    final tokens = line.split(RegExp(r'\s+'));
    int depth = 0;
    int? cp;
    int? mate;
    List<String> pv = const [];

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == 'depth' && i + 1 < tokens.length) {
        depth = int.tryParse(tokens[i + 1]) ?? depth;
      } else if (token == 'score' && i + 2 < tokens.length) {
        final scoreType = tokens[i + 1];
        final scoreVal = int.tryParse(tokens[i + 2]);
        if (scoreVal != null) {
          final normalized = sideToMoveIsWhite ? scoreVal : -scoreVal;
          if (scoreType == 'cp') {
            cp = normalized;
            mate = null;
          } else if (scoreType == 'mate') {
            mate = normalized;
            cp = normalized > 0 ? 1500 : -1500;
          }
        }
      } else if (token == 'pv' && i + 1 < tokens.length) {
        pv = tokens.sublist(i + 1);
        break;
      }
    }

    if (cp == null && mate == null) return null;
    return (depth: depth, cp: cp ?? 0, mate: mate, pv: pv);
  }

  bool _isWhiteToMove(String fen) {
    final parts = fen.split(' ');
    return parts.length < 2 || parts[1] == 'w';
  }

  StockfishEval _heuristicFallbackEval(String fen) {
    try {
      final pos = Chess.fromSetup(Setup.parseFen(fen));
      final legal = _fallbackLegalMoveUci(fen) ?? '';
      int material = 0;
      for (final sq in Square.values) {
        final piece = pos.board.pieceAt(sq);
        if (piece == null) continue;
        final val = switch (piece.role) {
          Role.pawn => 100,
          Role.knight => 320,
          Role.bishop => 330,
          Role.rook => 500,
          Role.queen => 900,
          Role.king => 0,
        };
        material += piece.color == Side.white ? val : -val;
      }
      return StockfishEval(
        centipawns: material,
        bestMoveUci: legal,
        pvUci: legal.isNotEmpty ? [legal] : const [],
        depth: 1,
      );
    } catch (_) {
      return const StockfishEval(
        centipawns: 0,
        bestMoveUci: '',
        pvUci: [],
        depth: 0,
      );
    }
  }

  String? _fallbackLegalMoveUci(String fen) {
    try {
      final pos = Chess.fromSetup(Setup.parseFen(fen));
      final moves = makeLegalMoves(pos);
      for (final entry in moves.entries) {
        if (entry.value.isNotEmpty) {
          final to = entry.value.squares.first;
          return NormalMove(from: entry.key, to: to).uci;
        }
      }
    } catch (_) {}
    return null;
  }

  void _send(String command) {
    if (_engine != null) {
      _engine!.stdin = command;
    }
  }

  Future<void> _waitForToken(String token, {required Duration timeout}) async {
    final completer = Completer<void>();
    void onLine(String line) {
      if (line.trim() == token && !completer.isCompleted) {
        completer.complete();
      }
    }

    _lineListeners.add(onLine);
    try {
      await completer.future.timeout(timeout, onTimeout: () {});
    } finally {
      _lineListeners.remove(onLine);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serialQueue = _serialQueue.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void dispose() {
    _stdoutSub?.cancel();
    _lineListeners.clear();
    if (_engine != null) {
      try {
        _engine!.stdin = 'quit';
        _engine!.dispose();
      } catch (_) {}
      _engine = null;
    }
    _isReady = false;
  }
}
