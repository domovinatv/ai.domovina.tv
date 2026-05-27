package ai.domovina

import android.content.pm.PackageManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (not FlutterActivity) so the audio_service
// plugin can attach its FlutterEngine for background playback. Required by
// lib/services/background_audio.dart.
class MainActivity : AudioServiceActivity() {
    private val tvModeChannel = "ai.domovina/tv_mode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, tvModeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLeanback" -> {
                        val isTv = packageManager
                            .hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        result.success(isTv)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
