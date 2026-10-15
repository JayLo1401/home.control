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
 * Faengt per Key-Filter die angelernte Fernbedienungstaste ab und blendet das Flutter-Panel
 * als Accessibility-Overlay ueber dem aktuellen Bild ein (kein "Ueber anderen Apps anzeigen"
 * noetig, das laufende Video wird nicht pausiert). Solange das Panel offen ist, werden die
 * Steuertasten hier abgefangen und an Flutter weitergereicht – das Overlay-Fenster selbst
 * braucht dadurch keinen Fokus.
 */
class PanelAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "HomeControl"
        private const val CHANNEL = "home_control/overlay"

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

    val isOverlayVisible: Boolean get() = flutterView != null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        startEngine()
        Log.i(TAG, "Dienst verbunden, Taste=${NativePrefs.keyName(NativePrefs.triggerKey(this))}")
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
                else -> result.notImplemented()
            }
        }
        engine = e
        channel = ch
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN

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

        val trigger = NativePrefs.triggerKey(this)

        if (isOverlayVisible) {
            if (isPassThrough(code)) return false
            if (down) {
                swallowedDown.add(code)
                if (event.repeatCount == 0 && (code == trigger || code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_ESCAPE)) {
                    hideOverlay()
                } else {
                    panelKey(code)?.let { channel?.invokeMethod("key", it) }
                }
            }
            return true
        }

        if (trigger != KeyEvent.KEYCODE_UNKNOWN && code == trigger) {
            if (down) {
                swallowedDown.add(code)
                if (event.repeatCount == 0) showOverlay()
            }
            return true
        }
        return false
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

    fun showOverlay() {
        if (isOverlayVisible) return
        startEngine()
        val e = engine ?: return
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
        channel?.invokeMethod("shown", null)
    }

    fun hideOverlay() {
        val view = flutterView ?: return
        flutterView = null
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
        hideOverlay()
        engine?.destroy()
        engine = null
        channel = null
        instance = null
        super.onDestroy()
    }
}
