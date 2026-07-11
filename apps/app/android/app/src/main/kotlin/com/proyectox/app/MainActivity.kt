package com.proyectox.app

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val iconChannel = "com.proyectox.app/icon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setDiscreetIcon" -> {
                        val discreet = call.arguments as? Boolean ?: false
                        try {
                            applyDiscreetIcon(discreet)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Swap the visible launcher icon by toggling the two activity-aliases.
     * Enables the target alias first so there is always at least one launcher
     * entry, and uses DONT_KILL_APP so the running app is not restarted.
     */
    private fun applyDiscreetIcon(discreet: Boolean) {
        val pm = packageManager
        val pkg = packageName
        val defaultAlias = ComponentName(pkg, "$pkg.DefaultAlias")
        val discreetAlias = ComponentName(pkg, "$pkg.DiscreetAlias")
        val enable = if (discreet) discreetAlias else defaultAlias
        val disable = if (discreet) defaultAlias else discreetAlias

        pm.setComponentEnabledSetting(
            enable,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            disable,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
