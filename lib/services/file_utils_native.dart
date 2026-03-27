import 'dart:io';

/// Native (macOS/iOS/Android) — check if file exists on disk.
bool fileExists(String path) => File(path).existsSync();
