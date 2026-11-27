import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_services.dart';
import 'model_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final jsonStr = await widget.services.storageService.exportBackupJson();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath = p.join(tempDir.path, 'boardwell_backup_$timestamp.json');
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: 'Boardwell Local Backup (Games, Puzzles & Coach Profiles — No API Keys)',
          subject: 'Boardwell Backup JSON',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final rawJson = await File(path).readAsString();
      final summary =
          await widget.services.storageService.importBackupJson(rawJson);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${summary.coachesImported} coaches, '
            '${summary.gamesImported} games, '
            '${summary.puzzlesImported} puzzles.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.services.capabilityService.capability;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Storage')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Device Hardware Diagnostics
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device Auto-Tuning Diagnostics',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow('Device', cap.deviceModel),
                  _InfoRow('Profile', cap.tierLabel),
                  _InfoRow('Architecture', cap.architectureLabel),
                  _InfoRow('Total RAM', '${cap.totalRamGb.toStringAsFixed(2)} GB'),
                  _InfoRow('Android', '${cap.androidRelease} (API ${cap.sdkInt})'),
                  _InfoRow(
                    'Stockfish Config',
                    'Threads=${cap.stockfishThreads}, Hash=${cap.stockfishHashMb} MB, Depth=${cap.stockfishMaxDepth}',
                  ),
                  _InfoRow(
                    'Board Animations',
                    cap.enableHeavyAnimations ? 'Full' : 'Minimal (Low-RAM)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // On-Device Model Manager shortcut
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('On-Device Model Manager'),
              subtitle: const Text(
                'Download, import (.task / .bin), switch, or delete local LLMs',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ModelManagerScreen(services: widget.services),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // User-Owned Local Backup (SAF + SharePlus, Zero Storage Permissions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User-Owned Local Backup (JSON)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Export or restore your games, puzzle progress, and Coach Profiles via Android\'s Storage Access Framework. Raw API keys remain strictly inside Android Keystore and are never exported.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _exportBackup,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Export JSON'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _importBackup,
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: const Text('Import JSON'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Privacy & Permissions Notice + Developer Credit
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About Boardwell',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '100% free, offline-first chess and hybrid multi-coach training app. '
                    'Declares zero dangerous permissions (only INTERNET and ACCESS_NETWORK_STATE).',
                  ),
                  const SizedBox(height: 12),
                  const _InfoRow('Developer', 'Md. Sabbir Mia'),
                  const _InfoRow('GitHub', 'https://github.com/sabbir404M'),
                  const _InfoRow('Version', '1.0.0'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
