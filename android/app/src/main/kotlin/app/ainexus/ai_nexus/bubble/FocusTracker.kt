package app.ainexus.ai_nexus.bubble

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Debounces typing so the bubble only appears once the user pauses, then
 * re-resolves the focused editable node.
 *
 * Runs on the main looper: [onSettled] ends up calling WindowManager, which
 * requires a Looper thread.
 */
class FocusTracker(
    private val debounceMs: Long = 600,
    private val onSettled: (AccessibilityNodeInfo) -> Unit,
    private val onLeave: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null

    /** Call for TEXT_CHANGED / FOCUSED / SELECTION_CHANGED events. */
    fun onTyping(resolve: () -> AccessibilityNodeInfo?) {
        cancel()
        val runnable = Runnable {
            pending = null
            try {
                val node = resolve()
                if (node == null) onLeave() else onSettled(node)
            } catch (t: Throwable) {
                // Isolated: a stale tree must not crash the service's looper.
                Log.e(TAG, "settle failed", t)
                try {
                    onLeave()
                } catch (ignored: Throwable) {
                }
            }
        }
        pending = runnable
        handler.postDelayed(runnable, debounceMs)
    }

    fun cancel() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }

    private companion object {
        const val TAG = "BubbleFocusTracker"
    }
}
