package org.lotzapp.home_control

import android.content.Intent
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nach "Beenden erzwingen" ist der Dienst aus – mit adb-Berechtigung selbst wieder einschalten.
        ServiceEnabler.ensureEnabled(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "home_control/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isServiceEnabled" -> result.success(PanelAccessibilityService.instance != null)

                    "canAutoEnable" -> result.success(ServiceEnabler.canWriteSecureSettings(this))

                    "openAccessibilitySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    }

                    "getLegacyTriggerKey" -> {
                        val code = NativePrefs.legacyTriggerKey(this)
                        result.success(mapOf("code" to code, "name" to NativePrefs.keyName(code)))
                    }

                    "setKeyBindings" -> {
                        val list = call.argument<List<Map<String, Any>>>("bindings") ?: emptyList()
                        NativePrefs.setBindings(this, list.map {
                            KeyBinding((it["code"] as Number).toInt(), it["longPress"] == true)
                        })
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
                        service?.showOverlay(mapOf("mode" to "panel", "panelIndex" to (call.argument<Int>("panelIndex") ?: 0)))
                        result.success(service != null)
                    }

                    "openUrl" -> {
                        val ok = try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.argument<String>("url")))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            true
                        } catch (_: Exception) {
                            false // z. B. kein Browser auf dem TV
                        }
                        result.success(ok)
                    }

                    "reloadOverlayConfig" -> {
                        PanelAccessibilityService.instance?.reloadConfig()
                        result.success(null)
                    }

                    "testDoorbell" -> {
                        val service = PanelAccessibilityService.instance
                        service?.testDoorbell()
                        result.success(service != null)
                    }

                    "deviceInfo" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "osVersion" to Build.VERSION.RELEASE,
                            "appVersion" to packageManager.getPackageInfo(packageName, 0).versionName,
                        )
                    )

                    "discoverHomeAssistant" -> {
                        val timeout = call.argument<Int>("timeoutMs") ?: 4000
                        discoverHomeAssistant(timeout.toLong(), result)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Sucht Home-Assistant-Instanzen per mDNS (`_home-assistant._tcp`).
     * Gefundene Dienste werden nacheinander aufgeloest (aeltere Android-Versionen
     * koennen nur einen Resolve gleichzeitig).
     */
    @Suppress("DEPRECATION")
    private fun discoverHomeAssistant(timeoutMs: Long, result: MethodChannel.Result) {
        val nsd = getSystemService(NSD_SERVICE) as NsdManager
        val main = Handler(Looper.getMainLooper())
        val found = mutableListOf<Map<String, Any?>>()
        val queue = ArrayDeque<NsdServiceInfo>()
        var resolving = false
        var finished = false

        fun resolveNext() {
            if (resolving || finished) return
            val service = queue.removeFirstOrNull() ?: return
            resolving = true
            nsd.resolveService(service, object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                    main.post { resolving = false; resolveNext() }
                }

                override fun onServiceResolved(info: NsdServiceInfo) {
                    val attrs = info.attributes.mapValues { (_, v) -> v?.toString(Charsets.UTF_8) }
                    main.post {
                        found.add(
                            mapOf(
                                "name" to (attrs["location_name"] ?: info.serviceName),
                                "host" to info.host?.hostAddress,
                                "port" to info.port,
                                "internalUrl" to attrs["internal_url"],
                                "baseUrl" to attrs["base_url"],
                                "version" to attrs["version"],
                            )
                        )
                        resolving = false
                        resolveNext()
                    }
                }
            })
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                main.post { queue.add(info); resolveNext() }
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                main.post {
                    if (!finished) {
                        finished = true
                        result.success(found.toList())
                    }
                }
            }

            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        nsd.discoverServices("_home-assistant._tcp", NsdManager.PROTOCOL_DNS_SD, listener)
        main.postDelayed({
            if (finished) return@postDelayed
            finished = true
            try {
                nsd.stopServiceDiscovery(listener)
            } catch (_: Exception) {
            }
            result.success(found.toList())
        }, timeoutMs)
    }
}
