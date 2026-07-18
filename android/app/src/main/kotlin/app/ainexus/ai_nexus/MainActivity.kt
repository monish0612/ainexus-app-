package app.ainexus.ai_nexus

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "NexusShortcut"
        private const val CHANNEL = "app.ainexus.ai_nexus/process_text"
        private const val SHORTCUT_CHANNEL = "app.ainexus.ai_nexus/shortcuts"
        private const val EXPENSE_WIDGET_CHANNEL = "app.ainexus.ai_nexus/expense_widget"
        private const val SHORTCUT_ACTION = "app.ainexus.SHORTCUT"
    }

    private var processedText: String? = null
    private var methodChannel: MethodChannel? = null
    private var shortcutChannel: MethodChannel? = null
    private var nativeTtsPlugin: NativeTtsPlugin? = null
    private var pendingShortcut: Map<String, String>? = null

    private var sharedText: String? = null
    private var sharedImagePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nativeTtsPlugin = NativeTtsPlugin(applicationContext, flutterEngine)

        handleProcessTextIntent(intent)
        handleSendIntent(intent)
        handleShortcutIntent(intent)

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleProcessTextIntent(intent)
        handleSendIntent(intent)

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
    }

    override fun onDestroy() {
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
