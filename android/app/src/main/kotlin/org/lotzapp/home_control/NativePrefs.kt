package org.lotzapp.home_control

import android.content.Context
import android.view.KeyEvent

/** Einstellungen, die der Hintergrunddienst direkt (ohne Flutter) braucht. */
object NativePrefs {
    private const val FILE = "home_control_native"
    private const val KEY_TRIGGER = "trigger_key"

    fun triggerKey(context: Context): Int =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getInt(KEY_TRIGGER, KeyEvent.KEYCODE_UNKNOWN)

    fun setTriggerKey(context: Context, keyCode: Int) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putInt(KEY_TRIGGER, keyCode).apply()
    }

    fun keyName(keyCode: Int): String =
        if (keyCode == KeyEvent.KEYCODE_UNKNOWN) "" else KeyEvent.keyCodeToString(keyCode).removePrefix("KEYCODE_")
}
