package at.jaycloud.home.control

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App-Updates fuer den Dart-UpdateService (lib/core/update_service.dart): die
 * heruntergeladene APK geht an den PackageInstaller des Systems.
 *
 * Ab Android 12 aktualisiert sich die App ohne Rueckfrage (Selbst-Update mit
 * USER_ACTION_NOT_REQUIRED), davor zeigt das System seine "Aktualisieren?"-
 * Bestaetigung. Einmalig noetig: "Unbekannte Apps installieren" fuer diese
 * App - auf TV-Boxen ohne die Einstellungsseite per adb:
 *   adb shell appops set at.jaycloud.home.control REQUEST_INSTALL_PACKAGES allow
 *
 * Wird in beiden Engines registriert (Einstellungs-App und Hintergrunddienst).
 */
class UpdatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "home_control/update")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appVersion" -> {
                val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
                @Suppress("DEPRECATION")
                val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
                result.success(mapOf("name" to info.versionName, "code" to code))
            }
            "cacheDir" -> result.success(appContext.cacheDir.absolutePath)
            "canInstall" -> result.success(canInstall())
            "openInstallPermission" -> {
                var opened = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        appContext.startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${appContext.packageName}"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        opened = true
                    } catch (e: Exception) {
                        Log.w(TAG, "keine Einstellungsseite fuer unbekannte Apps", e)
                    }
                }
                result.success(opened)
            }
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ARGS", "path fehlt", null)
                    return
                }
                Thread {
                    try {
                        install(appContext, File(path))
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        Log.e(TAG, "Installation fehlgeschlagen", e)
                        mainHandler.post { result.error("INSTALL", e.message, null) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || appContext.packageManager.canRequestPackageInstalls()

    companion object {
        const val TAG = "UpdatePlugin"

        fun install(context: Context, apk: File) {
            val installer = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            val sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                session.openWrite("home_control.apk", 0, apk.length()).use { out ->
                    apk.inputStream().use { it.copyTo(out) }
                    session.fsync(out)
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                val pending = PendingIntent.getBroadcast(
                    context,
                    sessionId,
                    Intent(context, UpdateInstallReceiver::class.java),
                    flags,
                )
                session.commit(pending.intentSender)
            }
        }
    }
}

/**
 * Antworten des PackageInstallers: zeigt die System-Bestaetigung, wenn sie
 * verlangt wird (vor Android 12). Nach dem Update schaltet der BootReceiver
 * (MY_PACKAGE_REPLACED) den Dienst wieder ein.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                } catch (e: Exception) {
                    Log.w(UpdatePlugin.TAG, "Bestaetigung konnte nicht angezeigt werden", e)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Log.i(UpdatePlugin.TAG, "Update installiert")
            else -> Log.w(
                UpdatePlugin.TAG,
                "Installationsstatus $status: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}",
            )
        }
    }
}
