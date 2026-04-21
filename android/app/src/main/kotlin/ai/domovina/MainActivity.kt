package ai.domovina

import com.ryanheise.audioservice.AudioServiceActivity

// Extends AudioServiceActivity (not FlutterActivity) so the audio_service
// plugin can attach its FlutterEngine for background playback. Required by
// lib/services/background_audio.dart.
class MainActivity : AudioServiceActivity()
