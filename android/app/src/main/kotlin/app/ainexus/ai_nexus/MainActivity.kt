package app.ainexus.ai_nexus

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import app.ainexus.ai_nexus.bubble.BubblePrefs
import app.ainexus.ai_nexus.bubble.Channels as BubbleChannels
import app.ainexus.ai_nexus.bubble.Watchdog
import app.ainexus.ai_nexus.sms.SmsAutoPrefs
import app.ainexus.ai_nexus.sms.SmsBridge
import app.ainexus.ai_nexus.sms.SmsQueue
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val TAG = "NexusShortcut"
        private const val CHANNEL = "app.ainexus.ai_nexus/process_text"
        private const val SHORTCUT_CHANNEL = "app.ainexus.ai_nexus/shortcuts"
        private const val EXPENSE_WIDGET_CHANNEL = "app.ainexus.ai_nexus/expense_widget"
        private const val SHORTCUT_ACTION = "app.ainexus.SHORTCUT"
        private const val SMS_PERM_REQ = 4401
    }

    private var processedText: String? = null
    private var methodChannel: MethodChannel? = null
    private var shortcutChannel: MethodChannel? = null
    private var nativeTtsPlugin: NativeTtsPlugin? = null
    private var pendingShortcut: Map<String, String>? = null

    private var sharedText: String? = null
    private var sharedImagePath: String? = null
    private var smsPermissionResult: MethodChannel.Result? = null
    private var pendingSmsOpenId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nativeTtsPlugin = NativeTtsPlugin(applicationContext, flutterEngine)

        handleProcessTextIntent(intent)
        handleSendIntent(intent)
        handleShortcutIntent(intent)
        handleSmsOpenIntent(intent)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getProcessedText" -> {
                        result.success(processedText)
                        processedText = null
                    }
                    "getSharedText" -> {
                        result.success(sharedText)
                        sharedText = null
                    }
                    "getSharedImagePath" -> {
                        result.success(sharedImagePath)
                        sharedImagePath = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        shortcutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHORTCUT_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "getShortcutAction") {
                    val data = pendingShortcut
                    pendingShortcut = null
                    Log.d(TAG, "getShortcutAction → $data")
                    result.success(data)
                } else {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXPENSE_WIDGET_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                if (call.method == "updateExpenseWidget") {
                    ExpenseWidgetProvider.triggerUpdate(applicationContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Expense widget channel error", e)
                result.error("WIDGET_ERROR", e.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BubbleChannels.SETTINGS_METHOD
        ).setMethodCallHandler(::handleBubbleCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SmsBridge.CHANNEL
        ).also { ch ->
            SmsBridge.methodChannel = ch
            ch.setMethodCallHandler(::handleSmsExpenseCall)
        }
    }

    /** Permissions + master toggle for the floating rephrase bubble. */
    private fun handleBubbleCall(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "serviceEnabled" to Watchdog.isEnabled(applicationContext),
                        "enabled" to BubblePrefs.isEnabled(applicationContext),
                        "minChars" to BubblePrefs.minChars(applicationContext),
                        "batteryUnrestricted" to isIgnoringBatteryOptimizations(),
                    )
                )

                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    BubblePrefs.setEnabled(applicationContext, enabled)
                    result.success(true)
                }

                "setMinChars" -> {
                    val value = call.argument<Int>("value") ?: BubblePrefs.DEFAULT_MIN_CHARS
                    BubblePrefs.setMinChars(applicationContext, value)
                    result.success(true)
                }

                "openAccessibilitySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(true)
                }

                // Sideloaded builds need App info -> menu -> "Allow restricted
                // settings" before the accessibility toggle can be flipped.
                "openAppInfo" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(Uri.fromParts("package", packageName, null))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(true)
                }

                "requestIgnoreBatteryOptimizations" -> {
                    if (isIgnoringBatteryOptimizations()) {
                        result.success(true)
                    } else {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.fromParts("package", packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Bubble channel error (${call.method})", e)
            result.error("BUBBLE_ERROR", e.message, null)
        }
    }

    private fun handleSmsExpenseCall(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "enabled" to SmsAutoPrefs.isEnabled(applicationContext),
                        "mode" to SmsAutoPrefs.mode(applicationContext),
                        "permissionGranted" to hasSmsPermission(),
                        "batteryUnrestricted" to isIgnoringBatteryOptimizations(),
                        "notificationGranted" to hasNotificationPermission(),
                    )
                )

                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    SmsAutoPrefs.setEnabled(applicationContext, enabled)
                    result.success(true)
                }

                "setMode" -> {
                    val mode = call.argument<String>("mode") ?: SmsAutoPrefs.MODE_ASK
                    SmsAutoPrefs.setMode(applicationContext, mode)
                    result.success(true)
                }

                "requestSmsPermission" -> {
                    val needSms = !hasSmsPermission()
                    val needNotif = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        !hasNotificationPermission()
                    if (!needSms && !needNotif) {
                        result.success(true)
                    } else {
                        smsPermissionResult = result
                        val perms = mutableListOf<String>()
                        if (needSms) perms.add(Manifest.permission.RECEIVE_SMS)
                        if (needNotif) perms.add(Manifest.permission.POST_NOTIFICATIONS)
                        requestPermissions(perms.toTypedArray(), SMS_PERM_REQ)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    if (isIgnoringBatteryOptimizations()) {
                        result.success(true)
                    } else {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.fromParts("package", packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(false)
                    }
                }

                "openAppInfo" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(Uri.fromParts("package", packageName, null))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(true)
                }

                "pending" -> {
                    result.success(SmsQueue.toFlutterList(applicationContext))
                }

                "remove" -> {
                    val id = call.argument<String>("id") ?: ""
                    if (id.isNotEmpty()) {
                        SmsQueue.remove(applicationContext, id)
                        SmsBridge.cancel(applicationContext, id)
                    }
                    result.success(true)
                }

                "showLogged" -> {
                    val id = call.argument<String>("id") ?: ""
                    val amount = (call.argument<Number>("amount") ?: 0).toDouble()
                    val merchant = call.argument<String>("merchant") ?: "a debit"
                    if (id.isNotEmpty()) {
                        SmsBridge.showLogged(applicationContext, id, amount, merchant)
                    }
                    result.success(true)
                }

                "markApproved" -> {
                    val id = call.argument<String>("id") ?: ""
                    if (id.isNotEmpty()) SmsQueue.updateStatus(applicationContext, id, "approved")
                    result.success(true)
                }

                "takeOpenId" -> {
                    val id = pendingSmsOpenId
                    pendingSmsOpenId = null
                    result.success(id)
                }

                "ready" -> {
                    SmsBridge.dartListening = true
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "SMS expense channel error (${call.method})", e)
            result.error("SMS_EXPENSE_ERROR", e.message, null)
        }
    }

    private fun hasSmsPermission(): Boolean = try {
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) {
        false
    }

    private fun hasNotificationPermission(): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            true
        } else {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
    } catch (_: Exception) {
        false
    }

    private fun isIgnoringBatteryOptimizations(): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            true
        } else {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        }
    } catch (e: Exception) {
        Log.w(TAG, "battery optimisation check failed", e)
        false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleProcessTextIntent(intent)
        handleSendIntent(intent)
        handleSmsOpenIntent(intent)

        if (processedText != null) {
            methodChannel?.invokeMethod("onProcessedText", processedText)
            processedText = null
        }

        if (sharedText != null) {
            methodChannel?.invokeMethod("onSharedText", sharedText)
            sharedText = null
        }

        if (sharedImagePath != null) {
            methodChannel?.invokeMethod("onSharedImage", sharedImagePath)
            sharedImagePath = null
        }

        try {
            if (handleShortcutIntent(intent)) {
                pendingShortcut?.let {
                    Log.d(TAG, "onNewIntent → pushing to Flutter: $it")
                    shortcutChannel?.invokeMethod("onShortcut", it)
                    pendingShortcut = null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNewIntent shortcut handling failed", e)
        }

        pendingSmsOpenId?.let { id ->
            SmsBridge.methodChannel?.invokeMethod("onSmsOpen", id)
            pendingSmsOpenId = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERM_REQ) {
            val smsIdx = permissions.indexOf(Manifest.permission.RECEIVE_SMS)
            val granted = if (smsIdx >= 0) {
                grantResults.getOrNull(smsIdx) == PackageManager.PERMISSION_GRANTED
            } else {
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            }
            smsPermissionResult?.success(granted)
            smsPermissionResult = null
        }
    }

    private fun handleSmsOpenIntent(intent: Intent?) {
        val id = intent?.getStringExtra(SmsBridge.EXTRA_ID) ?: return
        if (id.isNotEmpty()) pendingSmsOpenId = id
    }

    override fun onResume() {
        super.onResume()
        SmsBridge.activityResumed = true
    }

    override fun onPause() {
        SmsBridge.activityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        SmsBridge.dartListening = false
        if (SmsBridge.methodChannel != null) {
            SmsBridge.methodChannel = null
        }
        nativeTtsPlugin?.shutdown()
        super.onDestroy()
    }

    private fun handleProcessTextIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_PROCESS_TEXT) return

        processedText = intent
            .getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?.toString()
    }

    private fun handleSendIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
        if (!text.isNullOrBlank()) {
            Log.d(TAG, "ACTION_SEND text: $text")
            sharedText = text
        }

        val imageUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (imageUri != null) {
            val type = contentResolver.getType(imageUri) ?: ""
            if (type.startsWith("image/")) {
                try {
                    val ext = when {
                        type.contains("png") -> ".png"
                        type.contains("webp") -> ".webp"
                        else -> ".jpg"
                    }
                    val dest = File(cacheDir, "shared_img_${System.currentTimeMillis()}$ext")
                    contentResolver.openInputStream(imageUri)?.use { input ->
                        FileOutputStream(dest).use { output -> input.copyTo(output) }
                    }
                    sharedImagePath = dest.absolutePath
                    Log.d(TAG, "ACTION_SEND image → ${dest.absolutePath}")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to copy shared image", e)
                }
            }
        }

        // Consume so a later resume / engine recreate does not treat this
        // as a second share (which stacked another Watch on the same task).
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra(Intent.EXTRA_SUBJECT)
        intent.removeExtra(Intent.EXTRA_STREAM)
    }

    private fun handleShortcutIntent(intent: Intent): Boolean {
        try {
            Log.d(TAG, "handleShortcutIntent: action=${intent.action}, " +
                    "extras=${intent.extras?.keySet()?.joinToString()}")

            val extras = intent.extras ?: return false
            val tab = extras.get("shortcut_tab")?.toString()

            if (tab == null) {
                if (intent.action == SHORTCUT_ACTION) {
                    Log.w(TAG, "Custom action but no shortcut_tab extra")
                }
                return false
            }

            val subtab = extras.get("shortcut_subtab")?.toString()
            val widgetLaunch = extras.get("widget_launch")?.toString()
            val widgetSearchMode = extras.get("widget_search_mode")?.toString()
            val expenseAction = extras.get("expense_action")?.toString()

            val data = mutableMapOf("tab" to tab)
            if (subtab != null) data["subtab"] = subtab
            if (widgetLaunch != null) data["widget_launch"] = widgetLaunch
            if (widgetSearchMode != null) data["widget_search_mode"] = widgetSearchMode
            if (expenseAction != null) data["expense_action"] = expenseAction

            Log.d(TAG, "Shortcut detected: tab=$tab, subtab=$subtab, widget=$widgetLaunch, searchMode=$widgetSearchMode, expenseAction=$expenseAction")
            pendingShortcut = data

            intent.removeExtra("shortcut_tab")
            intent.removeExtra("shortcut_subtab")
            intent.removeExtra("widget_launch")
            intent.removeExtra("widget_search_mode")
            intent.removeExtra("expense_action")

            return true
        } catch (e: Exception) {
            Log.e(TAG, "handleShortcutIntent failed", e)
            return false
        }
    }
}
