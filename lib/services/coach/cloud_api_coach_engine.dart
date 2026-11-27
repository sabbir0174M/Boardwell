import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/coach_profile.dart';
import '../storage_service.dart';
import 'coach_engine.dart';

/// Universal OpenAI-compatible streaming /chat/completions client (BYOK).
/// Works with OpenRouter, Google AI Studio, OpenAI, Groq, and any custom endpoint.
class CloudApiCoachEngine implements CoachEngine {
  CloudApiCoachEngine({
    required StorageService storageService,
    http.Client? httpClient,
  })  : _storageService = storageService,
        _client = httpClient ?? http.Client();

  final StorageService _storageService;
  final http.Client _client;

  Uri _buildCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse('$trimmed/chat/completions');
  }

  Future<Map<String, String>> _buildHeaders(CoachProfile profile) async {
    final apiKey = await _storageService.readApiKey(profile.secureKeyId);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError(
        'Missing API key for "${profile.name}". Add your key in Coach Editor.',
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiKey.trim()}',
      'HTTP-Referer': 'https://github.com/sabbir404M',
      'X-Title': 'Boardwell Chess Coach',
    };
  }

  @override
  Stream<String> streamCoaching(CoachRequest request) async* {
    final profile = request.profile;
    if (profile.apiBaseUrl.trim().isEmpty || profile.modelId.trim().isEmpty) {
      throw StateError(
        'Cloud coach "${profile.name}" requires both an API Base URL and a Model ID.',
      );
    }

    final uri = _buildCompletionsUri(profile.apiBaseUrl);
    final headers = await _buildHeaders(profile);

    final body = jsonEncode({
      'model': profile.modelId.trim(),
      'stream': true,
      'temperature': 0.35,
      'max_tokens': 320,
      'messages': [
        {
          'role': 'system',
          'content': profile.personaPrompt.trim().isEmpty
              ? 'You are a helpful chess coach grounded strictly in Stockfish data.'
              : profile.personaPrompt.trim(),
        },
        {
          'role': 'user',
          'content': buildGroundedCoachingPrompt(request),
        },
      ],
    });

    final req = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = body;

    final streamed = await _client.send(req).timeout(const Duration(seconds: 25));

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errorBody = await streamed.stream.bytesToString();
      throw HttpException(
        'Cloud API HTTP ${streamed.statusCode}: ${_truncate(errorBody, 180)}',
      );
    }

    final contentType = streamed.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      // Handle providers that ignore stream:true and return a standard JSON response
      final raw = await streamed.stream.bytesToString();
      final extracted = _extractNonStreamingText(raw);
      if (extracted.isNotEmpty) {
        yield extracted;
      }
      return;
    }

    final lineStream = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') break;

      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        final choices = decoded['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // Ignore non-JSON heartbeat lines
      }
    }
  }

  @override
  Future<String> generateRawPrompt({
    required CoachProfile profile,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 120,
  }) async {
    if (profile.apiBaseUrl.trim().isEmpty || profile.modelId.trim().isEmpty) {
      throw StateError('Missing API Base URL or Model ID for ${profile.name}.');
    }

    final uri = _buildCompletionsUri(profile.apiBaseUrl);
    final headers = await _buildHeaders(profile);

    final response = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'model': profile.modelId.trim(),
            'stream': false,
            'temperature': 0.2,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Cloud API HTTP ${response.statusCode}: ${_truncate(response.body, 180)}',
      );
    }

    return _extractNonStreamingText(response.body);
  }

  String _extractNonStreamingText(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) return '';
    final first = choices.first as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>?;
    return (message?['content'] as String? ?? '').trim();
  }

  String _truncate(String input, int maxLen) {
    if (input.length <= maxLen) return input;
    return '${input.substring(0, maxLen)}...';
  }

  void dispose() {
    _client.close();
  }
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
