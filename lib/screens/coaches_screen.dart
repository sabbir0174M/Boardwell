import 'package:flutter/material.dart';

import '../models/coach_profile.dart';
import '../services/app_services.dart';
import 'coach_editor_screen.dart';
import 'model_manager_screen.dart';

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  List<CoachProfile> _coaches = const [];
  String _activeCoachId = 'builtin_rule_coach';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCoaches();
  }

  Future<void> _loadCoaches() async {
    final list = await widget.services.storageService.getCoachProfiles();
    final activeId = await widget.services.storageService.getActiveCoachId();
    if (!mounted) return;
    setState(() {
      _coaches = list;
      _activeCoachId = activeId;
      _loading = false;
    });
  }

  Future<void> _selectActiveCoach(CoachProfile coach) async {
    await widget.services.storageService.setActiveCoachId(coach.id);
    if (!mounted) return;
    setState(() => _activeCoachId = coach.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Active coach switched to ${coach.name}.')),
    );
  }

  Future<void> _openEditor([CoachProfile? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CoachEditorScreen(
          services: widget.services,
          existingCoach: existing,
          allCoaches: _coaches,
        ),
      ),
    );
    if (saved == true) {
      await _loadCoaches();
    }
  }

  Future<void> _deleteCoach(CoachProfile coach) async {
    if (coach.isBuiltIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Coach?'),
        content: Text(
          'Delete "${coach.name}" and remove its stored API key from Android Keystore?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.services.storageService.deleteCoachProfile(coach.id);
      await _loadCoaches();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hybrid Coaches'),
        actions: [
          IconButton(
            tooltip: 'Model Manager',
            icon: const Icon(Icons.memory),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModelManagerScreen(services: widget.services),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Coach'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _coaches.length,
              itemBuilder: (context, index) {
                final coach = _coaches[index];
                final isActive = coach.id == _activeCoachId;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      child: Icon(
                        switch (coach.providerType) {
                          CoachProviderType.ruleBased => Icons.flash_on,
                          CoachProviderType.onDevice => Icons.memory,
                          CoachProviderType.cloudApi => Icons.cloud_outlined,
                        },
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            coach.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isActive)
                          Chip(
                            label: const Text('Active', style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(coach.providerType.displayName),
                        if (coach.modelId.isNotEmpty)
                          Text(
                            'Model: ${coach.modelId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    onTap: () => _selectActiveCoach(coach),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'activate') {
                          _selectActiveCoach(coach);
                        } else if (action == 'edit') {
                          _openEditor(coach);
                        } else if (action == 'delete') {
                          _deleteCoach(coach);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'activate',
                          child: Text('Set Active'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Coach'),
                        ),
                        if (!coach.isBuiltIn)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
