import 'package:flutter/material.dart';

import '../models/coach_profile.dart';
import '../models/game_record.dart';
import '../models/opening_entry.dart';
import '../services/app_services.dart';
import 'model_manager_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.services,
    required this.onNavigateTab,
  });

  final AppServices services;
  final void Function(int tabIndex, {String? fen}) onNavigateTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CoachProfile? _activeCoach;
  List<GameRecord> _recentGames = const [];
  int _solvedPuzzleCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final activeId = await widget.services.storageService.getActiveCoachId();
    final coach = await widget.services.storageService.getCoachById(activeId);
    final games = await widget.services.storageService.getSavedGames(limit: 5);
    final solved = await widget.services.storageService.getSolvedPuzzleIds();

    if (!mounted) return;
    setState(() {
      _activeCoach = coach;
      _recentGames = games;
      _solvedPuzzleCount = solved.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.services.capabilityService.capability;
    final openings = widget.services.openingPuzzleService.openings;
    final totalPuzzles = widget.services.openingPuzzleService.puzzles.length;
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Boardwell'),
            actions: [
              IconButton(
                tooltip: 'On-Device Model Manager',
                icon: const Icon(Icons.memory),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ModelManagerScreen(services: widget.services),
                    ),
                  );
                },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Hardware auto-tuning summary banner
                Card(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              cap.isLowMemoryProfile
                                  ? Icons.speed
                                  : Icons.bolt,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${cap.tierLabel} • ${cap.architectureLabel}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RAM: ${cap.totalRamGb.toStringAsFixed(1)} GB • '
                          'Android ${cap.androidRelease} (API ${cap.sdkInt})\n'
                          'Stockfish Auto-Tuned: ${cap.stockfishThreads} thread(s), '
                          '${cap.stockfishHashMb} MB hash, depth ${cap.stockfishMaxDepth}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => widget.onNavigateTab(1),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play Chess'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => widget.onNavigateTab(2),
                              icon: const Icon(Icons.extension),
                              label: Text(
                                'Puzzles ($_solvedPuzzleCount/$totalPuzzles)',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Active Coach Quick Card
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.psychology,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    title: Text(
                      _activeCoach?.name ?? 'Boardwell Tactician (Instant)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _activeCoach?.providerType.displayName ??
                          'Rule-Based (Offline, 0 MB RAM)',
                    ),
                    trailing: TextButton(
                      onPressed: () => widget.onNavigateTab(3),
                      child: const Text('Switch'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Starter ECO Openings Explorer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Offline ECO Openings (${openings.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Tap to practice',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 146,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: openings.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final OpeningEntry opening = openings[index];
                      return SizedBox(
                        width: 230,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => widget.onNavigateTab(
                              1,
                              fen: opening.fen,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          opening.eco,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          opening.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    opening.formattedLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontFamily: 'monospace',
                                          color: colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: Text(
                                      opening.summary,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Recent Saved Games
                Text(
                  'Recent Local Games',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_recentGames.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No saved games yet. Finish or save a game in Play to build your offline history.',
                      ),
                    ),
                  )
                else
                  ..._recentGames.map(
                    (game) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(game.title),
                        subtitle: Text(
                          '${game.opponentLabel} • ${game.moveCount} plies • Result: ${game.result}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_circle_outline),
                          tooltip: 'Resume from final position',
                          onPressed: () =>
                              widget.onNavigateTab(1, fen: game.finalFen),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
