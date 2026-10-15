package org.lotzapp.home_control

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Hintergrunddienst.
 *
 * Faengt per Key-Filter die Panel-Tasten ab und blendet das Flutter-UI als
 * Accessibility-Overlay ueber dem aktuellen Bild ein (kein "Ueber anderen Apps anzeigen"
 * noetig, das laufende Video wird nicht pausiert).
 *
 * - kurzer Druck  -> Panel der Taste oeffnen
 * - langer Druck  -> (falls konfiguriert) Halte-Popup; Flutter fuehrt die Aktion aus,
 *                    wenn bis zum Ende gehalten wird, sonst "Abgebrochen"
 *
 * Solange das Overlay offen ist, werden die Steuertasten hier abgefangen und an Flutter
 * weitergereicht – das Overlay-Fenster selbst braucht dadurch keinen Fokus.
 */
class PanelAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "HomeControl"
        private const val CHANNEL = "home_control/overlay"

        /** Ab dieser Haltezeit gilt der Druck als lang. */
        private const val LONG_PRESS_MS = 500L

        @Volatile
        var instance: PanelAccessibilityService? = null
            private set

        /** Gesetzt, solange die App auf das Anlernen einer Taste wartet. */
        @Volatile
        var learnListener: ((Int) -> Unit)? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val windowManager by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var flutterView: FlutterView? = null

    /** Tasten, deren DOWN wir verschluckt haben – das passende UP wird ebenfalls verschluckt. */
    private val swallowedDown = mutableSetOf<Int>()

    /** Panel-Taste, die gerade gehalten wird (kurz/lang noch nicht entschieden oder Halte-Popup offen). */
    private var pressedKey: Int? = null
    private var holdActive = false
    private val longPressRunnable = Runnable {
        val key = pressedKey ?: return@Runnable
        holdActive = true
        showOverlay(mapOf("mode" to "hold", "key" to key))
    }

    val isOverlayVisible: Boolean get() = flutterView != null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        startEngine()
        Log.i(TAG, "Dienst verbunden, Tasten=${NativePrefs.bindings(this).keys.map(NativePrefs::keyName)}")
    }

    private fun startEngine() {
        if (engine != null) return
        // Engine wird vorgewaermt, damit das Panel beim Tastendruck sofort erscheint.
        val e = FlutterEngine(this)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "overlayMain"
            )
        )
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "close" -> {
                    hideOverlay()
                    result.success(null)
                }
                // Flutter oeffnet das Overlay selbst (z. B. Tuerglocke aus Home Assistant).
                "open" -> {
                    @Suppress("UNCHECKED_CAST")
                    showOverlay((call.arguments as? Map<String, Any>) ?: emptyMap())
                    result.success(null)
                }
                "playChime" -> {
                    Chime.play(
                        this,
                        times = call.argument<Int>("times") ?: 1,
                        volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    )
                    result.success(null)
                }
                "stopChime" -> {
                    Chime.stop(getSystemService(android.media.AudioManager::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        engine = e
        channel = ch
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN

        // Gehaltene Panel-Taste: Wiederholungen schlucken, beim Loslassen entscheiden.
        if (code == pressedKey) {
            if (!down) {
                pressedKey = null
                mainHandler.removeCallbacks(longPressRunnable)
                if (holdActive) {
                    holdActive = false
                    channel?.invokeMethod("holdRelease", null)
                } else {
                    showOverlay(mapOf("mode" to "panel", "key" to code))
                }
            }
            return true
        }

        if (!down && swallowedDown.remove(code)) return true

        // Anlernmodus: erste gedrueckte Taste melden und verschlucken.
        learnListener?.let { listener ->
            if (down && event.repeatCount == 0) {
                learnListener = null
                swallowedDown.add(code)
                mainHandler.post { listener(code) }
                return true
            }
        }

        val bindings = NativePrefs.bindings(this)

        if (isOverlayVisible) {
            if (isPassThrough(code)) return false
            if (down) {
                swallowedDown.add(code)
                if (event.repeatCount == 0 && bindings.containsKey(code)) {
                    hideOverlay()
                } else if (event.repeatCount == 0 && (code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_ESCAPE)) {
                    sendBack()
                } else {
                    panelKey(code)?.let { channel?.invokeMethod("key", it) }
                }
            }
            return true
        }

        val binding = bindings[code] ?: return false
        if (down && event.repeatCount == 0) {
            if (binding.hasLongPress) {
                pressedKey = code
                mainHandler.postDelayed(longPressRunnable, LONG_PRESS_MS)
            } else {
                // Ohne Lang-Druecken-Aktion sofort oeffnen.
                swallowedDown.add(code)
                showOverlay(mapOf("mode" to "panel", "key" to code))
            }
        }
        return true
    }

    /** Zurueck: Flutter entscheidet (Gruppe verlassen); sonst schliessen. */
    private fun sendBack() {
        val ch = channel ?: return hideOverlay()
        ch.invokeMethod("back", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result != true) hideOverlay()
            }

            override fun error(code: String, msg: String?, details: Any?) = hideOverlay()
            override fun notImplemented() = hideOverlay()
        })
    }

    /** Diese Tasten bleiben auch bei offenem Panel beim System (Lautstaerke etc.). */
    private fun isPassThrough(code: Int) = when (code) {
        KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE,
        KeyEvent.KEYCODE_POWER, KeyEvent.KEYCODE_HOME -> true
        else -> false
    }

    private fun panelKey(code: Int): String? = when (code) {
        KeyEvent.KEYCODE_DPAD_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "down"
        KeyEvent.KEYCODE_DPAD_LEFT -> "left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER,
        KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_SPACE -> "select"
        else -> null
    }

    /**
     * Zeigt das Overlay. [args]: mode = "panel" | "hold", key = Tastencode
     * (oder panelIndex beim Test aus der App).
     */
    fun showOverlay(args: Map<String, Any>) {
        startEngine()
        val e = engine ?: return
        if (!isOverlayVisible) {
            val view = FlutterView(this, FlutterTextureView(this))
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
            )
            try {
                windowManager.addView(view, params)
            } catch (t: Throwable) {
                Log.e(TAG, "Overlay konnte nicht angezeigt werden", t)
                return
            }
            view.attachToFlutterEngine(e)
            flutterView = view
            e.lifecycleChannel.appIsResumed()
        }
        channel?.invokeMethod("show", args)
    }

    /** Einstellungen wurden in der App geaendert -> Overlay-Engine laedt neu (HA-Verbindung, Tuerglocke). */
    fun reloadConfig() {
        channel?.invokeMethod("reload", null)
    }

    /** Test aus der App: Tuerglocke lokal ausloesen (ohne Home Assistant). */
    fun testDoorbell() {
        channel?.invokeMethod("testDoorbell", null)
    }

    fun hideOverlay() {
        val view = flutterView ?: return
        flutterView = null
        // holdActive bleibt bewusst stehen: wird die Taste nach Ausfuehrung noch gehalten,
        // darf das Loslassen nicht als kurzer Druck (Panel oeffnen) gewertet werden.
        channel?.invokeMethod("hidden", null)
        engine?.lifecycleChannel?.appIsInactive()
        view.detachFromFlutterEngine()
        try {
            windowManager.removeView(view)
        } catch (t: Throwable) {
            Log.w(TAG, "removeView", t)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        mainHandler.removeCallbacks(longPressRunnable)
        hideOverlay()
        engine?.destroy()
        engine = null
        channel = null
        instance = null
        super.onDestroy()
    }
}
