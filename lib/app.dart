import 'package:flutter/material.dart';

import 'screens/coaches_screen.dart';
import 'screens/home_screen.dart';
import 'screens/play_screen.dart';
import 'screens/puzzles_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_services.dart';

class BoardwellApp extends StatefulWidget {
  const BoardwellApp({super.key, required this.services});

  final AppServices services;

  @override
  State<BoardwellApp> createState() => _BoardwellAppState();
}

class _BoardwellAppState extends State<BoardwellApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Strictly release on-device LLM RAM when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.services.onDeviceCoachEngine.releaseMemory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1B5E20);

    return MaterialApp(
      title: 'Boardwell',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
        ),
      ),
      home: BoardwellShell(services: widget.services),
    );
  }
}

class BoardwellShell extends StatefulWidget {
  const BoardwellShell({super.key, required this.services});

  final AppServices services;

  @override
  State<BoardwellShell> createState() => _BoardwellShellState();
}

class _BoardwellShellState extends State<BoardwellShell> {
  int _selectedIndex = 0;
  String? _initialOpeningFen;

  void _navigateToTab(int index, {String? openingFen}) {
    setState(() {
      _initialOpeningFen = openingFen;
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(
        services: widget.services,
        onNavigateTab: (idx, {String? fen}) =>
            _navigateToTab(idx, openingFen: fen),
      ),
      PlayScreen(
        key: ValueKey(_initialOpeningFen ?? 'standard_play'),
        services: widget.services,
        initialFen: _initialOpeningFen,
      ),
      PuzzlesScreen(services: widget.services),
      CoachesScreen(services: widget.services),
      SettingsScreen(services: widget.services),
    ];

    // Predictive Back gesture support via PopScope
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: screens,
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => _navigateToTab(index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_on_outlined),
                selectedIcon: Icon(Icons.grid_on),
                label: 'Play',
              ),
              NavigationDestination(
                icon: Icon(Icons.extension_outlined),
                selectedIcon: Icon(Icons.extension),
                label: 'Puzzles',
              ),
              NavigationDestination(
                icon: Icon(Icons.psychology_outlined),
                selectedIcon: Icon(Icons.psychology),
                label: 'Coaches',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
