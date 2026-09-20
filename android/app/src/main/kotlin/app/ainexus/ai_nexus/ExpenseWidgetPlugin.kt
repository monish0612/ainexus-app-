package app.ainexus.ai_nexus

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/// Home-screen expense widget redraw. Registered as a [FlutterPlugin] so the
/// channel exists on the audio_service cached engine, not only after
/// [MainActivity.configureFlutterEngine].
class ExpenseWidgetPlugin : FlutterPlugin {
    companion object {
        const val CHANNEL = "app.ainexus.ai_nexus/expense_widget"

        fun registerWith(engine: FlutterEngine) {
            if (!engine.plugins.has(ExpenseWidgetPlugin::class.java)) {
                engine.plugins.add(ExpenseWidgetPlugin())
            }
        }
    }

    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "updateExpenseWidget") {
                    ExpenseWidgetProvider.triggerUpdate(binding.applicationContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
