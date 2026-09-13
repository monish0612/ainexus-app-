package app.ainexus.ai_nexus.bubble

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

/**
 * A durable locator for the editable field the bubble is acting on, plus a
 * snapshot of its text.
 *
 * AccessibilityNodeInfo references go stale the moment the tree changes, so we
 * never keep one. Instead we remember where the node lived and re-find it right
 * before writing. The [snapshot] is the text we actually rephrase: taking it up
 * front means the request can't be corrupted by focus churn while the user is
 * typing an "Own" tone into the panel.
 */
data class TargetRef(
    val windowId: Int,
    val packageName: String,
    val viewId: String?,
    val bounds: Rect,
    val snapshot: String,
) {
    companion object {
        private const val TAG = "BubbleTarget"

        fun from(node: AccessibilityNodeInfo, text: String): TargetRef? = try {
            val bounds = Rect().also { node.getBoundsInScreen(it) }
            TargetRef(
                windowId = node.windowId,
                packageName = node.packageName?.toString() ?: "",
                viewId = node.viewIdResourceName,
                bounds = bounds,
                snapshot = text,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "capture failed", t)
            null
        }

        /**
         * Re-find the target field. Prefers the window we captured — its view
         * focus survives even while the overlay panel holds the window focus —
         * then falls back to the view id, matching bounds, and finally whatever
         * currently has input focus.
         */
        fun resolve(service: AccessibilityService, ref: TargetRef?): AccessibilityNodeInfo? {
            if (ref != null) {
                capturedWindowRoot(service, ref)?.let { root ->
                    focusedIn(root)?.let { return it }
                    ref.viewId?.let { id ->
                        try {
                            root.findAccessibilityNodeInfosByViewId(id)
                                .firstOrNull { usable(it) }
                                ?.let { return it }
                        } catch (t: Throwable) {
                            Log.w(TAG, "viewId lookup failed", t)
                        }
                    }
                    byBounds(root, ref.bounds)?.let { return it }
                }
            }

            return try {
                service.rootInActiveWindow
                    ?.let { focusedIn(it) }
                    ?.takeIf { !isOwnOverlay(service, it.windowId) }
            } catch (t: Throwable) {
                Log.w(TAG, "active-window fallback failed", t)
                null
            }
        }

        fun usable(node: AccessibilityNodeInfo?): Boolean {
            if (node == null) return false
            return try {
                node.isEditable && node.isEnabled && !node.isPassword
            } catch (t: Throwable) {
                false
            }
        }

        private fun capturedWindowRoot(
            service: AccessibilityService,
            ref: TargetRef,
        ): AccessibilityNodeInfo? = try {
            service.windows.firstOrNull { it.id == ref.windowId }?.root
        } catch (t: Throwable) {
            Log.w(TAG, "window lookup failed", t)
            null
        }

        private fun focusedIn(root: AccessibilityNodeInfo): AccessibilityNodeInfo? = try {
            root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.takeIf { usable(it) }
        } catch (t: Throwable) {
            null
        }

        /** Breadth-first search for an editable node overlapping [bounds]. */
        private fun byBounds(
            root: AccessibilityNodeInfo,
            bounds: Rect,
        ): AccessibilityNodeInfo? {
            val queue = ArrayDeque<AccessibilityNodeInfo>()
            queue.add(root)
            var visited = 0
            val rect = Rect()
            while (queue.isNotEmpty() && visited < 400) {
                val node = queue.removeFirst()
                visited++
                try {
                    if (usable(node)) {
                        node.getBoundsInScreen(rect)
                        if (Rect.intersects(rect, bounds)) return node
                    }
                    for (i in 0 until node.childCount) {
                        node.getChild(i)?.let { queue.add(it) }
                    }
                } catch (t: Throwable) {
                    // Stale subtree — keep scanning the rest.
                }
            }
            return null
        }

        private fun isOwnOverlay(service: AccessibilityService, windowId: Int): Boolean = try {
            service.windows.firstOrNull { it.id == windowId }?.type ==
                AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY
        } catch (t: Throwable) {
            false
        }
    }
}
