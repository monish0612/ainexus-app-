package app.ainexus.ai_nexus.bubble

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel host on the overlay engine.
 *
 * The overlay Dart side owns the network call (it already has the API client,
 * the JWT and the model settings), so native only supplies primitives: hand out
 * the captured field text, write a result back, manage the window, and lend the
 * keyboard to the "Own" tone input.
 */
class OverlayBridgeHost(private val service: RephraseAccessibilityService) {

    private var channel: MethodChannel? = null

    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, Channels.OVERLAY_METHOD)
            .also { it.setMethodCallHandler(::onCall) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /** Tell Dart a fresh field was picked up, so the panel resets. */
    fun notifyTarget(payload: Map<String, Any?>) {
        invoke("onTarget", payload)
    }

    /** Tell Dart the bubble went away (window change, focus lost, dismissed). */
    fun notifyCollapse() {
        invoke("onCollapse", null)
    }

    /** Native tap on the collapsed bubble → Dart runs its expand flow. */
    fun notifyTap() {
        invoke("onTap", null)
    }

    /** Overlay window left the screen — Dart stops breath/sheen tickers. */
    fun notifyPause() {
        invoke("onPause", null)
    }

    /** Overlay window is about to show again — Dart may restart tickers. */
    fun notifyResume() {
        invoke("onResume", null)
    }

    private fun invoke(method: String, args: Any?) {
        try {
            channel?.invokeMethod(method, args)
        } catch (t: Throwable) {
            Log.w(TAG, "invoke $method failed", t)
        }
    }

    private fun onCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                // The text to rephrase, snapshotted when the bubble appeared.
                "target" -> result.success(service.targetPayload())

                "replace" -> {
                    val text = call.argument<String>("text") ?: ""
                    result.success(service.replaceFocused(text))
                }

                "copy" -> {
                    val text = call.argument<String>("text") ?: ""
                    service.copyText(text)
                    result.success(true)
                }

                "expand" -> {
                    service.onPanelExpanded()
                    result.success(service.targetPayload())
                    // After the panel is open, pick up keystrokes typed since
                    // the bubble appeared. Posted so it cannot block this tap.
                    Handler(Looper.getMainLooper()).post { service.refreshSnapshot() }
                }

                "collapse" -> {
                    service.collapsePanel()
                    result.success(true)
                }

                "resize" -> {
                    val w = call.argument<Double>("width") ?: 0.0
                    val h = call.argument<Double>("height") ?: 0.0
                    service.resizePanel(w, h)
                    result.success(true)
                }

                // Lend the keyboard to the "Own" tone field, then give it back.
                "setFocusable" -> {
                    val value = call.argument<Boolean>("value") ?: false
                    service.setOverlayFocusable(value)
                    result.success(true)
                }

                "hideKeyboard" -> {
                    service.hideKeyboard()
                    result.success(true)
                }

                "saveLastPlatform" -> {
                    val id = call.argument<String>("platform") ?: ""
                    service.saveLastPlatform(id)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "bridge call ${call.method} failed", t)
            result.error("BUBBLE_BRIDGE", t.message, null)
        }
    }

    companion object {
        private const val TAG = "BubbleBridge"
    }
}
