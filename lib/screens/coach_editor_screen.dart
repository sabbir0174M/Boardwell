import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/coach_profile.dart';
import '../models/local_model_info.dart';
import '../services/app_services.dart';

class CoachEditorScreen extends StatefulWidget {
  const CoachEditorScreen({
    super.key,
    required this.services,
    required this.allCoaches,
    this.existingCoach,
  });

  final AppServices services;
  final List<CoachProfile> allCoaches;
  final CoachProfile? existingCoach;

  @override
  State<CoachEditorScreen> createState() => _CoachEditorScreenState();
}

class _CoachEditorScreenState extends State<CoachEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  late TextEditingController _nameController;
  late TextEditingController _personaController;
  late TextEditingController _modelIdController;
  late TextEditingController _apiBaseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _localModelPathController;

  late CoachProviderType _providerType;
  late String _fallbackCoachId;
  bool _hasExistingApiKey = false;
  bool _obscureApiKey = true;
  bool _saving = false;
  List<LocalModelInfo> _installedModels = const [];

  @override
  void initState() {
    super.initState();
    final c = widget.existingCoach;
    _nameController = TextEditingController(text: c?.name ?? '');
    _personaController = TextEditingController(
      text: c?.personaPrompt ??
          'You are a friendly, clear chess coach. Explain the tactical and positional point behind the Stockfish evaluation in 3-4 concise sentences.',
    );
    _modelIdController = TextEditingController(text: c?.modelId ?? '');
    _apiBaseUrlController = TextEditingController(
      text: c?.apiBaseUrl ?? CloudProviderPreset.presets.first.baseUrl,
    );
    _apiKeyController = TextEditingController();
    _localModelPathController =
        TextEditingController(text: c?.localModelPath ?? '');

    _providerType = c?.providerType ?? CoachProviderType.cloudApi;
    _fallbackCoachId = c?.fallbackCoachId ?? 'builtin_rule_coach';
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final models = await widget.services.storageService.getLocalModels();
    bool hasKey = false;
    if (widget.existingCoach != null &&
        widget.existingCoach!.secureKeyId.isNotEmpty) {
      hasKey = await widget.services.storageService
          .hasApiKey(widget.existingCoach!.secureKeyId);
    }
    if (!mounted) return;
    setState(() {
      _installedModels = models;
      _hasExistingApiKey = hasKey;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final id = widget.existingCoach?.id ?? _uuid.v4();
    final secureKeyId = _providerType == CoachProviderType.cloudApi
        ? (widget.existingCoach?.secureKeyId.isNotEmpty == true
            ? widget.existingCoach!.secureKeyId
            : 'coach_key_$id')
        : '';

    final profile = CoachProfile(
      id: id,
      name: _nameController.text.trim(),
      personaPrompt: _personaController.text.trim(),
      providerType: _providerType,
      modelId: _modelIdController.text.trim(),
      localModelPath: _localModelPathController.text.trim(),
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      secureKeyId: secureKeyId,
      fallbackCoachId: _fallbackCoachId,
      isBuiltIn: widget.existingCoach?.isBuiltIn ?? false,
    );

    await widget.services.storageService.upsertCoachProfile(profile);

    if (_providerType == CoachProviderType.cloudApi &&
        _apiKeyController.text.trim().isNotEmpty) {
      await widget.services.storageService
          .saveApiKey(secureKeyId, _apiKeyController.text.trim());
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _modelIdController.dispose();
    _apiBaseUrlController.dispose();
    _apiKeyController.dispose();
    _localModelPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackChoices = widget.allCoaches
        .where((c) => c.id != widget.existingCoach?.id)
        .toList();

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existingCoach == null ? 'Create Coach' : 'Edit Coach',
          ),
          actions: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Coach Name',
                    hintText: 'e.g., Endgame Mentor or Aggressive Tactician',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a coach name' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<CoachProviderType>(
                  value: _providerType,
                  decoration: const InputDecoration(
                    labelText: 'Engine Provider Type',
                    border: OutlineInputBorder(),
                  ),
                  items: CoachProviderType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: widget.existingCoach?.isBuiltIn == true
                      ? null
                      : (v) {
                          if (v != null) setState(() => _providerType = v);
                        },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _personaController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Coach Persona Prompt',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter persona instructions'
                      : null,
                ),
                const SizedBox(height: 16),

                // Cloud API BYOK Configuration (Zero-Update Editable Presets)
                if (_providerType == CoachProviderType.cloudApi) ...[
                  Text(
                    'Quick Editable Presets (Future-Proof)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CloudProviderPreset.presets.map((preset) {
                      return ActionChip(
                        label: Text(preset.name),
                        onPressed: () {
                          setState(() {
                            _apiBaseUrlController.text = preset.baseUrl;
                            if (preset.suggestedModelId.isNotEmpty) {
                              _modelIdController.text = preset.suggestedModelId;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _apiBaseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI-Compatible Base URL',
                      hintText: 'https://openrouter.ai/api/v1',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter API Base URL'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _modelIdController,
                    decoration: const InputDecoration(
                      labelText: 'Custom Model ID (any current or future model)',
                      hintText: 'e.g., google/gemini-2.5-flash, gpt-4o-mini',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter Model ID'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: _hasExistingApiKey
                          ? 'API Key (saved in Android Keystore — leave blank to keep)'
                          : 'API Key (stored encrypted in Android Keystore)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureApiKey = !_obscureApiKey),
                      ),
                    ),
                  ),
                ],

                // On-Device Model Configuration
                if (_providerType == CoachProviderType.onDevice) ...[
                  if (_installedModels.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _installedModels
                              .any((m) => m.filePath == _localModelPathController.text)
                          ? _localModelPathController.text
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Installed Local Model (.task / .bin)',
                        border: OutlineInputBorder(),
                      ),
                      items: _installedModels
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.filePath,
                              child: Text(
                                '${m.displayName} (${m.formattedSize})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _localModelPathController.text = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _localModelPathController,
                    decoration: const InputDecoration(
                      labelText: 'Local Model Path (optional — defaults to active model)',
                      hintText: 'Import or download models in Model Manager',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                if (fallbackChoices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: fallbackChoices.any((c) => c.id == _fallbackCoachId)
                        ? _fallbackCoachId
                        : fallbackChoices.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Offline Auto-Fallback Coach',
                      border: OutlineInputBorder(),
                    ),
                    items: fallbackChoices
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _fallbackCoachId = val);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
