import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/coach_profile.dart';
import '../models/game_record.dart';
import '../models/local_model_info.dart';

class StorageService {
  static const String _dbName = 'boardwell_local.db';
  static const int _dbVersion = 1;
  static const String _activeCoachKey = 'active_coach_id';
  static const String _stockfishSkillKey = 'stockfish_skill_level';
  static const String _boardThemeKey = 'board_theme_name';

  Database? _db;

  // flutter_secure_storage v10 uses RSA OAEP + AES-GCM by default on Android API 23+
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<void> initialize() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _dbName);

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE coach_profiles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            personaPrompt TEXT NOT NULL,
            providerType TEXT NOT NULL,
            modelId TEXT NOT NULL,
            localModelPath TEXT NOT NULL,
            apiBaseUrl TEXT NOT NULL,
            secureKeyId TEXT NOT NULL,
            fallbackCoachId TEXT NOT NULL,
            isBuiltIn INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE games (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            pgn TEXT NOT NULL,
            finalFen TEXT NOT NULL,
            result TEXT NOT NULL,
            opponentType TEXT NOT NULL,
            opponentLabel TEXT NOT NULL,
            playerSide TEXT NOT NULL,
            moveCount INTEGER NOT NULL,
            createdAtMs INTEGER NOT NULL,
            openingName TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE puzzle_progress (
            puzzleId TEXT PRIMARY KEY,
            solved INTEGER NOT NULL DEFAULT 0,
            attempts INTEGER NOT NULL DEFAULT 0,
            solvedAtMs INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE local_models (
            id TEXT PRIMARY KEY,
            displayName TEXT NOT NULL,
            filePath TEXT NOT NULL,
            sourceUrl TEXT NOT NULL,
            sizeBytes INTEGER NOT NULL,
            installedAtMs INTEGER NOT NULL,
            isActive INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    await _seedDefaultCoachesIfEmpty();
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('StorageService has not been initialized.');
    }
    return db;
  }

  Future<void> _seedDefaultCoachesIfEmpty() async {
    final existing = await getCoachProfiles();
    if (existing.isEmpty) {
      for (final coach in CoachProfile.defaultBuiltInCoaches()) {
        await upsertCoachProfile(coach);
      }
    }
  }

  // -------------------- Coach Profiles --------------------

  Future<List<CoachProfile>> getCoachProfiles() async {
    final rows = await _database.query('coach_profiles', orderBy: 'isBuiltIn DESC, name ASC');
    return rows.map(CoachProfile.fromMap).toList();
  }

  Future<CoachProfile?> getCoachById(String id) async {
    final rows = await _database.query(
      'coach_profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CoachProfile.fromMap(rows.first);
  }

  Future<void> upsertCoachProfile(CoachProfile profile) async {
    await _database.insert(
      'coach_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCoachProfile(String id) async {
    final target = await getCoachById(id);
    if (target != null && target.isBuiltIn) {
      return; // Never delete the built-in instant rule coach
    }
    if (target != null && target.secureKeyId.isNotEmpty) {
      await deleteApiKey(target.secureKeyId);
    }
    await _database.delete('coach_profiles', where: 'id = ?', whereArgs: [id]);

    final activeId = await getActiveCoachId();
    if (activeId == id) {
      await setActiveCoachId('builtin_rule_coach');
    }
  }

  // -------------------- Secure API Keys --------------------

  Future<void> saveApiKey(String secureKeyId, String apiKey) async {
    if (secureKeyId.isEmpty) return;
    await _secureStorage.write(key: secureKeyId, value: apiKey.trim());
  }

  Future<String?> readApiKey(String secureKeyId) async {
    if (secureKeyId.isEmpty) return null;
    return _secureStorage.read(key: secureKeyId);
  }

  Future<void> deleteApiKey(String secureKeyId) async {
    if (secureKeyId.isEmpty) return;
    await _secureStorage.delete(key: secureKeyId);
  }

  Future<bool> hasApiKey(String secureKeyId) async {
    final key = await readApiKey(secureKeyId);
    return key != null && key.trim().isNotEmpty;
  }

  // -------------------- Games --------------------

  Future<List<GameRecord>> getSavedGames({int limit = 100}) async {
    final rows = await _database.query(
      'games',
      orderBy: 'createdAtMs DESC',
      limit: limit,
    );
    return rows.map(GameRecord.fromMap).toList();
  }

  Future<void> saveGame(GameRecord game) async {
    await _database.insert(
      'games',
      game.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteGame(String id) async {
    await _database.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------- Puzzles --------------------

  Future<Set<String>> getSolvedPuzzleIds() async {
    final rows = await _database.query(
      'puzzle_progress',
      where: 'solved = 1',
    );
    return rows.map((r) => r['puzzleId'] as String).toSet();
  }

  Future<void> recordPuzzleAttempt({
    required String puzzleId,
    required bool solved,
  }) async {
    final existing = await _database.query(
      'puzzle_progress',
      where: 'puzzleId = ?',
      whereArgs: [puzzleId],
      limit: 1,
    );
    final prevAttempts =
        existing.isEmpty ? 0 : (existing.first['attempts'] as num?)?.toInt() ?? 0;
    final prevSolved = existing.isNotEmpty && existing.first['solved'] == 1;

    await _database.insert(
      'puzzle_progress',
      {
        'puzzleId': puzzleId,
        'solved': (solved || prevSolved) ? 1 : 0,
        'attempts': prevAttempts + 1,
        'solvedAtMs': solved ? DateTime.now().millisecondsSinceEpoch : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // -------------------- Local On-Device Models --------------------

  Future<List<LocalModelInfo>> getLocalModels() async {
    final rows = await _database.query(
      'local_models',
      orderBy: 'isActive DESC, installedAtMs DESC',
    );
    return rows.map(LocalModelInfo.fromMap).toList();
  }

  Future<void> upsertLocalModel(LocalModelInfo model) async {
    if (model.isActive) {
      await _database.update('local_models', {'isActive': 0});
    }
    await _database.insert(
      'local_models',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setActiveLocalModel(String id) async {
    await _database.update('local_models', {'isActive': 0});
    await _database.update(
      'local_models',
      {'isActive': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLocalModelRecord(String id) async {
    await _database.delete('local_models', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------- Preferences --------------------

  Future<String> getActiveCoachId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeCoachKey) ?? 'builtin_rule_coach';
  }

  Future<void> setActiveCoachId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeCoachKey, id);
  }

  Future<int> getStockfishSkillLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stockfishSkillKey) ?? 6;
  }

  Future<void> setStockfishSkillLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stockfishSkillKey, level.clamp(0, 20));
  }

  Future<String> getBoardThemeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_boardThemeKey) ?? 'green';
  }

  Future<void> setBoardThemeName(String themeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_boardThemeKey, themeName);
  }

  // -------------------- JSON Backup Export / Import (Zero Raw API Keys) --------------------

  Future<String> exportBackupJson() async {
    final coaches = await getCoachProfiles();
    final games = await getSavedGames(limit: 1000);
    final puzzleRows = await _database.query('puzzle_progress');
    final activeCoachId = await getActiveCoachId();
    final skillLevel = await getStockfishSkillLevel();
    final boardTheme = await getBoardThemeName();

    final payload = {
      'app': 'Boardwell',
      'schemaVersion': 1,
      'exportedAtIso': DateTime.now().toUtc().toIso8601String(),
      'securityNotice': 'API keys are stored only in Android Keystore and are never exported.',
      'preferences': {
        'activeCoachId': activeCoachId,
        'stockfishSkillLevel': skillLevel,
        'boardTheme': boardTheme,
      },
      'coaches': coaches.map((c) => c.toBackupJson()).toList(),
      'games': games.map((g) => g.toMap()).toList(),
      'puzzleProgress': puzzleRows,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<({int coachesImported, int gamesImported, int puzzlesImported})>
      importBackupJson(String jsonString) async {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    int coachesImported = 0;
    int gamesImported = 0;
    int puzzlesImported = 0;

    final coachesList = decoded['coaches'] as List<dynamic>? ?? const [];
    for (final item in coachesList) {
      if (item is Map<String, dynamic>) {
        final profile = CoachProfile.fromMap(item);
        await upsertCoachProfile(profile);
        coachesImported++;
      }
    }

    final gamesList = decoded['games'] as List<dynamic>? ?? const [];
    for (final item in gamesList) {
      if (item is Map<String, dynamic>) {
        final game = GameRecord.fromMap(item);
        await saveGame(game);
        gamesImported++;
      }
    }

    final puzzlesList = decoded['puzzleProgress'] as List<dynamic>? ?? const [];
    for (final item in puzzlesList) {
      if (item is Map<String, dynamic> && item['puzzleId'] is String) {
        await _database.insert(
          'puzzle_progress',
          {
            'puzzleId': item['puzzleId'],
            'solved': (item['solved'] == 1 || item['solved'] == true) ? 1 : 0,
            'attempts': (item['attempts'] as num?)?.toInt() ?? 1,
            'solvedAtMs': (item['solvedAtMs'] as num?)?.toInt() ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        puzzlesImported++;
      }
    }

    final prefs = decoded['preferences'] as Map<String, dynamic>?;
    if (prefs != null) {
      if (prefs['activeCoachId'] is String) {
        await setActiveCoachId(prefs['activeCoachId'] as String);
      }
      if (prefs['stockfishSkillLevel'] is num) {
        await setStockfishSkillLevel((prefs['stockfishSkillLevel'] as num).toInt());
      }
      if (prefs['boardTheme'] is String) {
        await setBoardThemeName(prefs['boardTheme'] as String);
      }
    }

    return (
      coachesImported: coachesImported,
      gamesImported: gamesImported,
      puzzlesImported: puzzlesImported,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
