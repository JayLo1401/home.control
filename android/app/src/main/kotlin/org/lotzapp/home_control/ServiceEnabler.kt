package org.lotzapp.home_control

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.Log

/**
 * Schaltet den Hintergrunddienst (Bedienungshilfe) selbst wieder ein.
 *
 * Android deaktiviert eine Bedienungshilfe, wenn die App "beendet erzwungen" wird.
 * Mit der per adb erteilten Berechtigung WRITE_SECURE_SETTINGS kann die App ihren
 * Dienst wieder in die Liste eintragen (wie Key Mapper / Button Mapper):
 *
 *   adb shell pm grant org.lotzapp.home_control android.permission.WRITE_SECURE_SETTINGS
 */
object ServiceEnabler {
    private const val TAG = "HomeControl"

    private fun component(context: Context) = ComponentName(context, PanelAccessibilityService::class.java)

    fun canWriteSecureSettings(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    fun isEnabledInSettings(context: Context): Boolean {
        val own = component(context)
        return enabledServices(context).any { ComponentName.unflattenFromString(it) == own }
    }

    /** @return true, wenn der Dienst danach in den Einstellungen aktiv ist. */
    fun ensureEnabled(context: Context): Boolean {
        if (isEnabledInSettings(context)) return true
        if (!canWriteSecureSettings(context)) return false
        return try {
            val list = enabledServices(context) + component(context).flattenToShortString()
            val resolver = context.contentResolver
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, list.joinToString(":"))
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            Log.i(TAG, "Hintergrunddienst automatisch eingeschaltet")
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Dienst konnte nicht eingeschaltet werden", t)
            false
        }
    }

    private fun enabledServices(context: Context): List<String> =
        (Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "")
            .split(':')
            .filter { it.isNotBlank() }
}
