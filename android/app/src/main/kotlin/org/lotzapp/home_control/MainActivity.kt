package org.lotzapp.home_control

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "home_control/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isServiceEnabled" -> result.success(PanelAccessibilityService.instance != null)

                    "openAccessibilitySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    }

                    "getTriggerKey" -> {
                        val code = NativePrefs.triggerKey(this)
                        result.success(mapOf("code" to code, "name" to NativePrefs.keyName(code)))
                    }

                    "setTriggerKey" -> {
                        NativePrefs.setTriggerKey(this, call.argument<Int>("code") ?: 0)
                        result.success(null)
                    }

                    "learnKey" -> {
                        if (PanelAccessibilityService.instance == null) {
                            result.error("NO_SERVICE", "Hintergrunddienst ist nicht aktiv", null)
                        } else {
                            var answered = false
                            PanelAccessibilityService.learnListener = { code ->
                                if (!answered) {
                                    answered = true
                                    result.success(mapOf("code" to code, "name" to NativePrefs.keyName(code)))
                                }
                            }
                        }
                    }

                    "cancelLearn" -> {
                        PanelAccessibilityService.learnListener = null
                        result.success(null)
                    }

                    "showOverlay" -> {
                        val service = PanelAccessibilityService.instance
                        service?.showOverlay()
                        result.success(service != null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
