package org.lotzapp.home_control

import android.content.Context
import android.view.KeyEvent

/** Tastenbelegung eines Panels: kurzer Druck oeffnet es, langer Druck (falls gesetzt) loest eine Aktion aus. */
data class KeyBinding(val keyCode: Int, val hasLongPress: Boolean)

/** Einstellungen, die der Hintergrunddienst direkt (ohne Flutter) braucht. */
object NativePrefs {
    private const val FILE = "home_control_native"
    private const val KEY_BINDINGS = "bindings"
    private const val KEY_LEGACY_TRIGGER = "trigger_key"

    /** Format: "keyCode:0|1,keyCode:0|1" */
    fun bindings(context: Context): Map<Int, KeyBinding> {
        val raw = prefs(context).getString(KEY_BINDINGS, "") ?: ""
        return raw.split(',').mapNotNull { entry ->
            val parts = entry.split(':')
            val code = parts.getOrNull(0)?.toIntOrNull() ?: return@mapNotNull null
            KeyBinding(code, parts.getOrNull(1) == "1")
        }.associateBy { it.keyCode }
    }

    fun setBindings(context: Context, bindings: List<KeyBinding>) {
        val raw = bindings.filter { it.keyCode != KeyEvent.KEYCODE_UNKNOWN }
            .joinToString(",") { "${it.keyCode}:${if (it.hasLongPress) 1 else 0}" }
        prefs(context).edit().putString(KEY_BINDINGS, raw).apply()
    }

    /** Taste aus Version 0.1 (nur fuer die Migration). */
    fun legacyTriggerKey(context: Context): Int =
        prefs(context).getInt(KEY_LEGACY_TRIGGER, KeyEvent.KEYCODE_UNKNOWN)

    fun keyName(keyCode: Int): String =
        if (keyCode == KeyEvent.KEYCODE_UNKNOWN) "" else KeyEvent.keyCodeToString(keyCode).removePrefix("KEYCODE_")

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
