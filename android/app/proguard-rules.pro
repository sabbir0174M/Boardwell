# Keep Flutter wrapper and native FFI / MediaPipe / Stockfish symbols
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep MediaPipe & Flutter Edge AI native bridges
-keep class com.google.mediapipe.** { *; }
-keep class dev.fluttercommunity.** { *; }
-dontwarn com.google.mediapipe.**

# Keep Stockfish FFI symbols
-keep class com.boardwell.app.** { *; }
