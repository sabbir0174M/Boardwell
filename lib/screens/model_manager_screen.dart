import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/local_model_info.dart';
import '../services/app_services.dart';

class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<LocalModelInfo> _installedModels = const [];
  bool _loading = true;
  bool _downloading = false;
  double _downloadProgress = 0.0;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadInstalledModels();
  }

  Future<void> _loadInstalledModels() async {
    final models = await widget.services.storageService.getLocalModels();
    if (!mounted) return;
    setState(() {
      _installedModels = models;
      _loading = false;
    });
  }

  Future<void> _downloadModel() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid HTTPS model URL (.task or .bin).')),
      );
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Downloading MediaPipe model...';
    });

    try {
      await widget.services.onDeviceCoachEngine.downloadModelFromUrl(
        displayName: _nameController.text.trim().isEmpty
            ? 'Custom MediaPipe Model'
            : _nameController.text.trim(),
        downloadUrl: url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _downloadProgress = p);
        },
      );
      await _loadInstalledModels();
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Model downloaded and set active.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Download failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _importLocalFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;

    setState(() {
      _downloading = true;
      _statusMessage = 'Importing ${picked.name} into app storage...';
    });

    try {
      await widget.services.onDeviceCoachEngine.importLocalModelFile(
        sourceFilePath: path,
        customName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : picked.name,
      );
      await _loadInstalledModels();
      if (!mounted) return;
      setState(() => _statusMessage = 'Imported "${picked.name}" successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _activateModel(LocalModelInfo model) async {
    setState(() => _statusMessage = 'Switching active model (unloading previous)...');
    try {
      await widget.services.onDeviceCoachEngine.activateInstalledModel(model);
      await _loadInstalledModels();
      if (!mounted) return;
      setState(() => _statusMessage = '"${model.displayName}" is now active.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Activation error: $e');
    }
  }

  Future<void> _deleteModel(LocalModelInfo model) async {
    await widget.services.onDeviceCoachEngine.deleteLocalModel(model);
    await _loadInstalledModels();
    if (!mounted) return;
    setState(() => _statusMessage = 'Deleted "${model.displayName}".');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capService = widget.services.capabilityService;
    final cap = capService.capability;
    final canUseLocal = capService.canUseLocalLlm;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_downloading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('On-Device Model Manager'),
          actions: [
            IconButton(
              tooltip: 'Release Model RAM Now',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                await widget.services.onDeviceCoachEngine.releaseMemory();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Released loaded on-device model from RAM.'),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Low-RAM Device Warning Badge + Advanced Override
              if (!cap.localLlmRecommended)
                Card(
                  color: colorScheme.errorContainer.withValues(alpha: 0.65),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Local LLMs Require 4 GB+ RAM & 64-bit CPU',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Detected ${cap.totalRamGb.toStringAsFixed(1)} GB RAM (${cap.architectureLabel}). '
                          'Boardwell defaults to the zero-RAM Rule-Based Coach offline to prevent crashes.',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Advanced Override: Unlock Local LLMs Anyway',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                          value: capService.allowLowRamLocalLlmOverride,
                          onChanged: (val) async {
                            await capService.setLowRamLocalLlmOverride(val);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('On-Device LLM Ready (MediaPipe .task/.bin)'),
                    subtitle: Text(
                      '${cap.totalRamGb.toStringAsFixed(1)} GB RAM • ${cap.architectureLabel} • Single-model RAM guard active',
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Starter Suggestions (Editable, Zero-Update Design)
              Text(
                'Starter Suggestions (Editable URLs)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...SuggestedModelCatalogItem.starterCatalog.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.description} (${item.estimatedSizeLabel}, ${item.minRamGb.toStringAsFixed(0)} GB+ RAM)',
                    ),
                    trailing: TextButton(
                      onPressed: canUseLocal
                          ? () {
                              setState(() {
                                _nameController.text = item.name;
                                _urlController.text = item.defaultDownloadUrl;
                              });
                            }
                          : null,
                      child: const Text('Fill'),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Custom Download or Local File Import
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Download or Import Any .task / .bin Model',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        enabled: canUseLocal && !_downloading,
                        decoration: const InputDecoration(
                          labelText: 'Model Display Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _urlController,
                        enabled: canUseLocal && !_downloading,
                        decoration: const InputDecoration(
                          labelText: 'Direct HTTPS Download URL (.task / .bin)',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_downloading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _downloadProgress > 0 ? _downloadProgress : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colorScheme.primary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (canUseLocal && !_downloading)
                                  ? _downloadModel
                                  : null,
                              icon: const Icon(Icons.download),
                              label: const Text('Download URL'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (canUseLocal && !_downloading)
                                  ? _importLocalFile
                                  : null,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Import File'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),
              Text(
                'Installed Local Models (${_installedModels.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_installedModels.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No on-device models installed yet. Download a .task model above or import a local file via Storage Access Framework.',
                    ),
                  ),
                )
              else
                ..._installedModels.map(
                  (m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        m.isActive ? Icons.check_circle : Icons.memory,
                        color: m.isActive ? colorScheme.primary : null,
                      ),
                      title: Text(m.displayName),
                      subtitle: Text(
                        '${m.formattedSize}${m.isActive ? " • Active" : ""}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!m.isActive)
                            TextButton(
                              onPressed: () => _activateModel(m),
                              child: const Text('Use'),
                            ),
                          IconButton(
                            tooltip: 'Delete model',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteModel(m),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
