package app.ainexus.ai_nexus.bubble

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Rect
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Watches typing in any app, shows the rephrase bubble next to the focused
 * field, and writes the chosen rephrasing back into that field.
 *
 * Everything that touches a node or a window is wrapped: a failure here must
 * never tear down the service, because the user cannot re-grant accessibility
 * without a trip to Settings.
 */
class RephraseAccessibilityService : AccessibilityService() {

    private var overlay: OverlayController? = null
    private var tracker: FocusTracker? = null
    private var bridge: OverlayBridgeHost? = null

    private var target: TargetRef? = null

    /** Set when the user long-presses the bubble away; cleared on a real app switch. */
    private var suppressedUntilWindowChange = false

    /** When we last touched the overlay window, for the self-event grace period. */
    private var lastOverlayChangeAt = 0L

    private var windowsCachedAt = 0L
    private var windowsCache: List<AccessibilityWindowInfo> = emptyList()

    /** Guards against a double-tap on Use writing the same text twice. */
    private val replaceInFlight = AtomicBoolean(false)

    override fun onServiceConnected() {
        super.onServiceConnected()
        // XML flags can be dropped by some OEMs after a package replace. Re-apply
        // so getWindows() and "not important" messenger fields keep working.
        try {
            val info = serviceInfo
            if (info != null) {
                info.flags = info.flags or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                serviceInfo = info
            }
        } catch (t: Throwable) {
            Log.w(TAG, "could not refresh service flags", t)
        }
        val controller = OverlayController(this)
        controller.gestureListener = object : OverlayController.GestureListener {
            // Native detected a tap on the collapsed bubble; Dart runs the same
            // expand flow it used to trigger from its own gesture detector.
            override fun onTap() {
                // Dart owns the expand. Growing the window here, before Dart
                // paints the panel, left a full-screen overlay that swallowed
                // the tap and never opened the dialog.
                safe { bridge?.notifyTap() }
            }

            override fun onLongPress() {
                dismissBubble()
            }
        }
        overlay = controller
        tracker = FocusTracker(
            debounceMs = DEBOUNCE_MS,
            onSettled = ::onFieldSettled,
            onLeave = ::onFocusLost,
        )
        Log.i(TAG, "rephrase bubble service connected")
    }

    // ── Events ───────────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        safe {
            when (event.eventType) {
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
                AccessibilityEvent.TYPE_VIEW_FOCUSED,
                AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED -> {
                    // Master gates before any window/node API so a disabled
                    // bubble never calls getWindows() on every keystroke.
                    if (!gatesOpen(event.packageName?.toString())) {
                        hideBubble()
                        return@safe
                    }
                    // Drop overlay / system windows, but ALLOW Nexus app fields
                    // and IME-sourced keystrokes (Android often tags typing as
                    // the keyboard window once it is open).
                    if (!shouldHandleTypingEvent(
                            sourcePackage = event.packageName?.toString(),
                            ownPackage = packageName,
                            windowId = event.windowId,
                            windowType = windowTypeOf(event.windowId),
                        )
                    ) {
                        return@safe
                    }
                    tracker?.onTyping { resolveFocusedInput() }
                }

                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
                AccessibilityEvent.TYPE_WINDOWS_CHANGED -> {
                    // Adding or moving our own overlay window itself raises
                    // window-change events, sometimes without a package name —
                    // a short grace period stops the bubble cancelling itself.
                    if (SystemClock.uptimeMillis() - lastOverlayChangeAt <
                        OVERLAY_GRACE_MS
                    ) {
                        return@safe
                    }
                    // Keep WINDOWS_CHANGED subscribed so IME open/close can
                    // reclamp while showing. When the bubble is gone, skip
                    // the window walk entirely except a real app switch on
                    // WINDOW_STATE_CHANGED (clears the long-press suppress).
                    if (overlay?.isShowing != true) {
                        if (event.eventType ==
                            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                            isRealAppSwitch()
                        ) {
                            suppressedUntilWindowChange = false
                            target = null
                            tracker?.cancel()
                        }
                        return@safe
                    }
                    // IME open/close is not an app switch — just reclamp the
                    // collapsed bubble above/below the keyboard.
                    if (!isRealAppSwitch()) {
                        overlay?.reclampForIme()
                        return@safe
                    }
                    suppressedUntilWindowChange = false
                    target = null
                    tracker?.cancel()
                    hideBubble()
                }
            }
        }
    }

    /** Master toggle, per-app skip list, and the manual dismiss. */
    private fun gatesOpen(sourcePackage: String?): Boolean =
        WindowGate.eventGatesOpen(
            enabled = BubblePrefs.isEnabled(this),
            suppressed = suppressedUntilWindowChange,
            skipped = sourcePackage != null &&
                sourcePackage in BubblePrefs.skipPackages(this),
        )

    private fun cachedWindows(): List<AccessibilityWindowInfo> {
        val now = SystemClock.uptimeMillis()
        if (windowsCachedAt != 0L && now - windowsCachedAt < WINDOWS_CACHE_MS) {
            return windowsCache
        }
        windowsCachedAt = now
        windowsCache = try {
            windows ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
        return windowsCache
    }

    /**
     * Find the editable field even while the IME is the "active" window.
     *
     * `rootInActiveWindow` is often Gboard once the keyboard is open, so looking
     * only there made every typing pause look like "no field" and hid the bubble.
     */
    private fun resolveFocusedInput(): AccessibilityNodeInfo? {
        return try {
            val snapshot = cachedWindows()
            for (window in snapshot) {
                if (!WindowGate.isUsableFieldWindowType(window.type)) continue
                val focused = window.root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                if (TargetRef.usable(focused)) return focused
            }
            val node = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (TargetRef.usable(node) &&
                WindowGate.isUsableFieldWindowType(windowTypeOfNode(node))
            ) {
                node
            } else {
                null
            }
        } catch (t: Throwable) {
            Log.w(TAG, "focus resolve failed", t)
            null
        }
    }

    /**
     * True only when the user has actually moved to a different app.
     *
     * The keyboard opening or closing, and our own overlay taking focus for the
     * "Own" tone input, both churn the window list constantly; treating that as
     * "user left" would yank the panel away mid-interaction.
     */
    private fun isRealAppSwitch(): Boolean =
        WindowGate.isRealAppSwitch(target?.packageName, applicationPackages())

    private fun applicationPackages(): Set<String> = try {
        cachedWindows().mapNotNull { window ->
            if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) return@mapNotNull null
            window.root?.packageName?.toString()?.takeIf { it.isNotEmpty() }
        }.toSet()
    } catch (t: Throwable) {
        emptySet()
    }

    private fun windowTypeOfNode(node: AccessibilityNodeInfo?): Int? {
        if (node == null) return null
        return try {
            node.window?.type ?: windowTypeOf(node.windowId)
        } catch (t: Throwable) {
            windowTypeOf(node.windowId)
        }
    }

    private fun windowTypeOf(windowId: Int): Int? = try {
        cachedWindows().firstOrNull { it.id == windowId }?.type
    } catch (t: Throwable) {
        null
    }

    private fun onFieldSettled(node: AccessibilityNodeInfo) {
        val text = NodeTextIO.readText(node)
        if (text == null || text.trim().length < BubblePrefs.minChars(this)) {
            if (overlay?.isDragging == true) return
            hideBubble()
            return
        }
        val ref = TargetRef.from(node, text)
        if (ref == null) {
            if (overlay?.isDragging == true) return
            hideBubble()
            return
        }
        // IME-sourced events carry the keyboard package, so skip is checked
        // against the resolved field, not the event source.
        if (ref.packageName.isNotEmpty() &&
            ref.packageName in BubblePrefs.skipPackages(this)
        ) {
            if (overlay?.isDragging == true) return
            hideBubble()
            return
        }
        target = ref

        // Our own write-back makes the field emit TEXT_CHANGED. Re-showing the
        // bubble here would shrink the window and wipe the result the user is
        // still reading, so while the panel is open we only refresh the text.
        if (overlay?.isExpanded == true) return
        // A typing pause must not hide, re-place, or remount the bubble while
        // the user is dragging it to a new home.
        if (overlay?.isDragging == true) return

        lastOverlayChangeAt = SystemClock.uptimeMillis()
        overlay?.showBubble(Rect(ref.bounds))
        ensureBridge()
        bridge?.notifyResume()
        bridge?.notifyTarget(targetPayload())
    }

    /**
     * The focused field went away. While the panel is open this is expected —
     * the "Own" tone input holds focus itself — so only the collapsed bubble
     * reacts, otherwise the panel would vanish as the user starts typing a tone.
     */
    private fun onFocusLost() {
        if (overlay?.isExpanded == true) return
        if (overlay?.isDragging == true) return
        hideBubble()
    }

    private fun hideBubble() {
        safe {
            lastOverlayChangeAt = SystemClock.uptimeMillis()
            if (overlay?.isShowing == true) {
                bridge?.notifyCollapse()
                bridge?.notifyPause()
            }
            overlay?.hide()
        }
    }

    // ── Bridge surface (called from the overlay Dart side) ───────────────────

    /** Text to rephrase, its source app, and the panel's size budget in dp. */
    fun targetPayload(): Map<String, Any?> {
        val ref = target
        val (maxWidth, maxHeight) = overlay?.maxPanelDp() ?: (0.0 to 0.0)
        val (bubbleX, bubbleY, bubbleSize) =
            overlay?.bubbleAnchorDp() ?: Triple(-1.0, -1.0, 76.0)
        return mapOf(
            "text" to (ref?.snapshot ?: ""),
            "package" to (ref?.packageName ?: ""),
            "maxWidth" to maxWidth,
            "maxHeight" to maxHeight,
            "lastPlatformId" to (BubblePrefs.lastPlatformId(this) ?: ""),
            // Captured before expand so the panel opens next to the bubble.
            "bubbleX" to bubbleX,
            "bubbleY" to bubbleY,
            "bubbleSize" to bubbleSize,
        )
    }

    fun saveLastPlatform(platformId: String) = safe {
        BubblePrefs.setLastPlatformId(this, platformId)
    }

    /**
     * Grow the window first and return. The text snapshot was taken when the
     * bubble appeared. A live node read (getWindows + refresh) on this call
     * stalls the click, so it runs after the panel is already open.
     */
    fun onPanelExpanded() {
        safe {
            lastOverlayChangeAt = SystemClock.uptimeMillis()
            overlay?.expand()
        }
    }

    /** Best-effort newer text. Never called on the tap that opens the panel. */
    fun refreshSnapshot() {
        safe {
            val ref = target ?: return@safe
            val node = TargetRef.resolve(this, ref) ?: return@safe
            val live = NodeTextIO.readText(node) ?: return@safe
            if (live.isNotBlank() && live != ref.snapshot) {
                target = ref.copy(snapshot = live)
                bridge?.notifyTarget(targetPayload())
            }
        }
    }

    fun collapsePanel() = safe {
        lastOverlayChangeAt = SystemClock.uptimeMillis()
        overlay?.collapse()
    }

    fun dismissBubble() {
        safe {
            suppressedUntilWindowChange = true
            hideBubble()
        }
    }

    fun resizePanel(width: Double, height: Double) = safe {
        lastOverlayChangeAt = SystemClock.uptimeMillis()
        overlay?.resizePanel(width, height)
    }

    /** Flipping focusable adds/removes the IME, which churns the window list. */
    fun setOverlayFocusable(value: Boolean) = safe {
        lastOverlayChangeAt = SystemClock.uptimeMillis()
        overlay?.setFocusable(value)
    }

    fun hideKeyboard() = safe { overlay?.hideKeyboard() }

    /** If connect-time engine warm-up failed, retry once a field actually settles. */
    private fun ensureBridge() {
        if (bridge != null) return
        overlay?.warm()?.let { engine ->
            bridge = OverlayBridgeHost(this).also { it.attach(engine) }
        }
    }

    fun copyText(text: String) = safe { NodeTextIO.copyToClipboard(applicationContext, text) }

    /** Write [text] into the target field. Returns the outcome name for the panel. */
    fun replaceFocused(text: String): String {
        if (!replaceInFlight.compareAndSet(false, true)) {
            Log.w(TAG, "replace ignored — already in flight")
            return NodeTextIO.Outcome.BLOCKED.name
        }
        return try {
            val node = TargetRef.resolve(this, target)
            val outcome = NodeTextIO.replace(applicationContext, node, text)
            if (outcome == NodeTextIO.Outcome.BLOCKED) {
                // Can't edit the field — make sure the user still gets the text.
                NodeTextIO.copyToClipboard(applicationContext, text)
            } else {
                target = target?.copy(snapshot = text)
            }
            Log.i(TAG, "replace outcome=$outcome")
            outcome.name
        } catch (t: Throwable) {
            Log.e(TAG, "replace failed", t)
            NodeTextIO.copyToClipboard(applicationContext, text)
            NodeTextIO.Outcome.BLOCKED.name
        } finally {
            replaceInFlight.set(false)
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onInterrupt() {
        hideBubble()
    }

    /**
     * Rotation or a multi-window resize moves the field we anchored to, and the
     * window-change events that follow come from the same package so they don't
     * read as an app switch. Drop the bubble and let the next typing pause place
     * a fresh one.
     */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        // Keep the user's parked spot (fractions re-fit the new display). Hiding
        // on rotation felt like the bubble had a mind of its own.
        safe { overlay?.onDisplayChanged() }
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        safe {
            tracker?.cancel()
            bridge?.detach()
            overlay?.destroy()
        }
        bridge = null
        overlay = null
        tracker = null
        return super.onUnbind(intent)
    }

    private inline fun safe(block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e(TAG, "isolated failure", t)
        }
    }

    companion object {
        private const val TAG = "BubbleService"

        /** Typing pause before the bubble appears. */
        private const val DEBOUNCE_MS = 500L

        /** How long to ignore window churn caused by our own overlay. */
        private const val OVERLAY_GRACE_MS = 500L

        /** Reuse getWindows() snapshots across a burst of accessibility events. */
        private const val WINDOWS_CACHE_MS = 250L

        /**
         * Pure gate for typing events. Allows Nexus APPLICATION windows and
         * IME-sourced keystrokes, while rejecting our overlay and system UI so
         * Flutter semantics never re-feed the tracker.
         *
         * [windowType] null means "unknown" — treated as allowed so a missing
         * window list never silently kills the bubble.
         */
        @Suppress("UNUSED_PARAMETER")
        fun shouldHandleTypingEvent(
            sourcePackage: String?,
            ownPackage: String,
            windowId: Int,
            windowType: Int?,
        ): Boolean = WindowGate.shouldHandleTypingEvent(windowType)
    }
}
