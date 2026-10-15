package org.lotzapp.home_control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Nach dem Booten und nach App-Updates: Dienst wieder einschalten, falls er
 * deaktiviert wurde. Die App selbst wird dabei nicht angezeigt.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ServiceEnabler.ensureEnabled(context)
    }
}
