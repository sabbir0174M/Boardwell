enum CoachProviderType {
  ruleBased('rule_based', 'Rule-Based (Offline, 0 MB RAM)'),
  onDevice('on_device', 'On-Device LLM (Offline)'),
  cloudApi('cloud_api', 'Cloud AI API (BYOK)');

  const CoachProviderType(this.value, this.displayName);

  final String value;
  final String displayName;

  static CoachProviderType fromValue(String raw) {
    return CoachProviderType.values.firstWhere(
      (e) => e.value == raw,
      orElse: () => CoachProviderType.ruleBased,
    );
  }
}

class CoachProfile {
  const CoachProfile({
    required this.id,
    required this.name,
    required this.personaPrompt,
    required this.providerType,
    this.modelId = '',
    this.localModelPath = '',
    this.apiBaseUrl = '',
    this.secureKeyId = '',
    this.fallbackCoachId = 'builtin_rule_coach',
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String personaPrompt;
  final CoachProviderType providerType;
  final String modelId;
  final String localModelPath;
  final String apiBaseUrl;
  final String secureKeyId;
  final String fallbackCoachId;
  final bool isBuiltIn;

  CoachProfile copyWith({
    String? id,
    String? name,
    String? personaPrompt,
    CoachProviderType? providerType,
    String? modelId,
    String? localModelPath,
    String? apiBaseUrl,
    String? secureKeyId,
    String? fallbackCoachId,
    bool? isBuiltIn,
  }) {
    return CoachProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      personaPrompt: personaPrompt ?? this.personaPrompt,
      providerType: providerType ?? this.providerType,
      modelId: modelId ?? this.modelId,
      localModelPath: localModelPath ?? this.localModelPath,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      secureKeyId: secureKeyId ?? this.secureKeyId,
      fallbackCoachId: fallbackCoachId ?? this.fallbackCoachId,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'personaPrompt': personaPrompt,
      'providerType': providerType.value,
      'modelId': modelId,
      'localModelPath': localModelPath,
      'apiBaseUrl': apiBaseUrl,
      'secureKeyId': secureKeyId,
      'fallbackCoachId': fallbackCoachId,
      'isBuiltIn': isBuiltIn ? 1 : 0,
    };
  }

  /// Export-safe JSON map (never includes raw API keys; keeps only key reference id).
  Map<String, dynamic> toBackupJson() {
    return {
      'id': id,
      'name': name,
      'personaPrompt': personaPrompt,
      'providerType': providerType.value,
      'modelId': modelId,
      'localModelPath': localModelPath,
      'apiBaseUrl': apiBaseUrl,
      'secureKeyId': secureKeyId,
      'fallbackCoachId': fallbackCoachId,
      'isBuiltIn': isBuiltIn,
    };
  }

  factory CoachProfile.fromMap(Map<String, dynamic> map) {
    return CoachProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      personaPrompt: map['personaPrompt'] as String? ?? '',
      providerType: CoachProviderType.fromValue(
        map['providerType'] as String? ?? 'rule_based',
      ),
      modelId: map['modelId'] as String? ?? '',
      localModelPath: map['localModelPath'] as String? ?? '',
      apiBaseUrl: map['apiBaseUrl'] as String? ?? '',
      secureKeyId: map['secureKeyId'] as String? ?? '',
      fallbackCoachId: map['fallbackCoachId'] as String? ?? 'builtin_rule_coach',
      isBuiltIn: (map['isBuiltIn'] == 1 || map['isBuiltIn'] == true),
    );
  }

  static List<CoachProfile> defaultBuiltInCoaches() {
    return const [
      CoachProfile(
        id: 'builtin_rule_coach',
        name: 'Boardwell Tactician (Instant)',
        personaPrompt:
            'Give crisp, encouraging, practical chess feedback grounded strictly in the Stockfish evaluation and principal variation.',
        providerType: CoachProviderType.ruleBased,
        fallbackCoachId: 'builtin_rule_coach',
        isBuiltIn: true,
      ),
      CoachProfile(
        id: 'builtin_on_device_coach',
        name: 'Pocket GM (On-Device)',
        personaPrompt:
            'You are a patient, practical chess coach. Explain why the played move succeeded or faltered using the exact Stockfish evaluation and best line. Keep advice under 120 words and end with one concrete takeaway.',
        providerType: CoachProviderType.onDevice,
        modelId: 'gemma-local-task',
        fallbackCoachId: 'builtin_rule_coach',
        isBuiltIn: false,
      ),
      CoachProfile(
        id: 'builtin_cloud_coach',
        name: 'Cloud Grandmaster (BYOK)',
        personaPrompt:
            'You are a warm, insightful Grandmaster coach. Analyze the exact Stockfish-verified position, highlight tactical motifs and strategic plans from the PV line, and never invent moves outside the given data.',
        providerType: CoachProviderType.cloudApi,
        modelId: 'google/gemini-2.5-flash',
        apiBaseUrl: 'https://openrouter.ai/api/v1',
        secureKeyId: 'coach_key_builtin_cloud_coach',
        fallbackCoachId: 'builtin_rule_coach',
        isBuiltIn: false,
      ),
    ];
  }
}

class CloudProviderPreset {
  const CloudProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.suggestedModelId,
    required this.notes,
  });

  final String name;
  final String baseUrl;
  final String suggestedModelId;
  final String notes;

  static const List<CloudProviderPreset> presets = [
    CloudProviderPreset(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      suggestedModelId: 'google/gemini-2.5-flash',
      notes: 'Access hundreds of free & paid models with one OpenAI-compatible key.',
    ),
    CloudProviderPreset(
      name: 'Google AI Studio',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      suggestedModelId: 'gemini-2.5-flash',
      notes: 'Direct Gemini OpenAI-compatible endpoint.',
    ),
    CloudProviderPreset(
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      suggestedModelId: 'gpt-4o-mini',
      notes: 'Official OpenAI Chat Completions endpoint.',
    ),
    CloudProviderPreset(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      suggestedModelId: 'llama-3.3-70b-versatile',
      notes: 'Ultra-low-latency inference for open-weight models.',
    ),
    CloudProviderPreset(
      name: 'Custom OpenAI-Compatible',
      baseUrl: '',
      suggestedModelId: '',
      notes: 'Point to any self-hosted or future OpenAI-compatible server URL.',
    ),
  ];
}
