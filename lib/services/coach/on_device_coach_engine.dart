import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_mediapipe/flutter_edge_ai_mediapipe.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/coach_profile.dart';
import '../../models/local_model_info.dart';
import '../storage_service.dart';
import 'coach_engine.dart';

/// On-device LLM coach backed by flutter_edge_ai + flutter_edge_ai_mediapipe.
/// Enforces a strict single-model-in-RAM lifecycle and releases memory when paused.
class OnDeviceCoachEngine implements CoachEngine {
  OnDeviceCoachEngine({required StorageService storageService})
      : _storageService = storageService;

  final StorageService _storageService;
  final Uuid _uuid = const Uuid();

  bool _engineRegistered = false;
  InferenceModel? _loadedModel;
  String? _loadedModelSourceKey;
  bool _isBusy = false;

  bool get isModelLoaded => _loadedModel != null;
  String? get loadedModelSourceKey => _loadedModelSourceKey;

  Future<void> initializeRuntime() async {
    if (_engineRegistered) return;
    try {
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [MediaPipeEngine()],
      );
      _engineRegistered = true;
    } catch (e) {
      debugPrint('[OnDeviceCoachEngine] Runtime init warning: $e');
    }
  }

  /// Downloads a MediaPipe .task/.bin model with live progress (0.0 to 1.0).
  Future<LocalModelInfo> downloadModelFromUrl({
    required String displayName,
    required String downloadUrl,
    required void Function(double progress) onProgress,
  }) async {
    await initializeRuntime();
    await releaseMemory();

    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
    )
        .fromNetwork(downloadUrl.trim())
        .withProgress((int percent) {
          onProgress((percent.clamp(0, 100)) / 100.0);
        })
        .install();

    final record = LocalModelInfo(
      id: _uuid.v4(),
      displayName: displayName.trim().isEmpty ? 'Downloaded MediaPipe Model' : displayName.trim(),
      filePath: downloadUrl.trim(),
      sourceUrl: downloadUrl.trim(),
      sizeBytes: 0,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      isActive: true,
    );
    await _storageService.upsertLocalModel(record);
    return record;
  }

  /// Imports a user-selected local .task or .bin model via Storage Access Framework.
  Future<LocalModelInfo> importLocalModelFile({
    required String sourceFilePath,
    String? customName,
  }) async {
    await initializeRuntime();
    await releaseMemory();

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Selected model file does not exist', sourceFilePath);
    }

    // Copy into app-internal storage so it remains accessible without external storage permissions
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'on_device_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final fileName = p.basename(sourceFilePath);
    final destPath = p.join(modelsDir.path, fileName);
    if (sourceFilePath != destPath) {
      await sourceFile.copy(destPath);
    }

    final fileSize = await File(destPath).length();

    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
    ).fromFile(destPath).install();

    final record = LocalModelInfo(
      id: _uuid.v4(),
      displayName: (customName != null && customName.trim().isNotEmpty)
          ? customName.trim()
          : p.basenameWithoutExtension(fileName),
      filePath: destPath,
      sourceUrl: '',
      sizeBytes: fileSize,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      isActive: true,
    );
    await _storageService.upsertLocalModel(record);
    return record;
  }

  /// Activates a previously installed local model, strictly unloading any previous model first.
  Future<void> activateInstalledModel(LocalModelInfo model) async {
    await initializeRuntime();
    await releaseMemory();

    if (model.filePath.isNotEmpty && await File(model.filePath).exists()) {
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(model.filePath).install();
    } else if (model.sourceUrl.isNotEmpty) {
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromNetwork(model.sourceUrl).install();
    }

    await _storageService.setActiveLocalModel(model.id);
    _loadedModelSourceKey = model.id;
  }

  /// Deletes a local model from app storage and SQLite registry after releasing RAM.
  Future<void> deleteLocalModel(LocalModelInfo model) async {
    await releaseMemory();
    if (model.filePath.isNotEmpty && !model.filePath.startsWith('http')) {
      final file = File(model.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _storageService.deleteLocalModelRecord(model.id);
  }

  /// Strictly enforces single-model-in-RAM: closes any old model before loading a new one.
  Future<InferenceModel> _ensureModelLoaded({
    required String? requestedLocalPath,
    int maxTokens = 1024,
  }) async {
    await initializeRuntime();

    final targetKey = (requestedLocalPath != null && requestedLocalPath.isNotEmpty)
        ? requestedLocalPath
        : 'active_default';

    if (_loadedModel != null && _loadedModelSourceKey == targetKey) {
      return _loadedModel!;
    }

    // Strict unload before loading another model
    await releaseMemory();

    if (requestedLocalPath != null &&
        requestedLocalPath.isNotEmpty &&
        !requestedLocalPath.startsWith('http') &&
        await File(requestedLocalPath).exists()) {
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(requestedLocalPath).install();
    }

    final model = await FlutterEdgeAi.getActiveModel(maxTokens: maxTokens);
    _loadedModel = model;
    _loadedModelSourceKey = targetKey;
    return model;
  }

  /// Releases loaded on-device LLM memory immediately (called on AppLifecycleState.paused & model switch).
  Future<void> releaseMemory() async {
    final model = _loadedModel;
    _loadedModel = null;
    _loadedModelSourceKey = null;
    if (model != null) {
      try {
        await model.close();
      } catch (e) {
        debugPrint('[OnDeviceCoachEngine] Error closing model: $e');
      }
    }
  }

  @override
  Stream<String> streamCoaching(CoachRequest request) async* {
    if (_isBusy) {
      throw StateError('On-device model is currently busy with another request.');
    }
    _isBusy = true;
    try {
      final model = await _ensureModelLoaded(
        requestedLocalPath: request.profile.localModelPath,
        maxTokens: 1024,
      );
      final chat = await model.openChat();
      try {
        final fullPrompt =
            'System Persona: ${request.profile.personaPrompt}\n\n'
            '${buildGroundedCoachingPrompt(request)}';
        await chat.addQueryChunk(Message.text(text: fullPrompt, isUser: true));

        await for (final chunk in chat.generateChatResponseAsync()) {
          if (chunk is TextResponse && chunk.token.isNotEmpty) {
            yield chunk.token;
          }
        }
      } finally {
        await chat.close();
      }
    } finally {
      _isBusy = false;
    }
  }

  @override
  Future<String> generateRawPrompt({
    required CoachProfile profile,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 256,
  }) async {
    if (_isBusy) {
      throw StateError('On-device model is currently busy.');
    }
    _isBusy = true;
    try {
      final model = await _ensureModelLoaded(
        requestedLocalPath: profile.localModelPath,
        maxTokens: maxTokens.clamp(512, 2048),
      );
      final chat = await model.openChat();
      try {
        final combined = '$systemPrompt\n\n$userPrompt';
        await chat.addQueryChunk(Message.text(text: combined, isUser: true));
        final buffer = StringBuffer();
        await for (final chunk in chat.generateChatResponseAsync()) {
          if (chunk is TextResponse) {
            buffer.write(chunk.token);
          }
        }
        return buffer.toString().trim();
      } finally {
        await chat.close();
      }
    } finally {
      _isBusy = false;
    }
  }
}
