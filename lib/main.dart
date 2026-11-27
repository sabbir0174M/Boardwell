import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mandatory Edge-to-Edge system UI for Android 15/16/17+
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Pre-warm chess piece textures so the board renders cleanly on frame 1
  try {
    await ChessgroundImages.instance.loadAll(
      PieceSet.stauntyAssets,
      devicePixelRatio:
          WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio,
    );
  } catch (_) {
    // Board will lazily load piece images if pre-warm is skipped in headless tests
  }

  final services = await AppServices.bootstrap();
  runApp(BoardwellApp(services: services));
}
