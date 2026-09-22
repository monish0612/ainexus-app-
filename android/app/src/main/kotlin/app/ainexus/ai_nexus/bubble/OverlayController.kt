package app.ainexus.ai_nexus.bubble

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the single overlay window that hosts the Flutter-rendered bubble/panel.
 *
 * Window type is TYPE_ACCESSIBILITY_OVERLAY: no SYSTEM_ALERT_WINDOW permission
 * needed and it can draw over the keyboard and status bar. The window is sized
 * to its content (a full-screen Flutter view would swallow every touch meant
 * for the app underneath) and kept non-focusable so the target field keeps input
 * focus — except for the brief moment the "Own" tone input needs the keyboard.
 */
class OverlayController(private val context: Context) {

    /** Bubble gestures (tap to expand, long-press to dismiss), handled natively. */
    interface GestureListener {
        fun onTap()

        fun onLongPress()
    }

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var root: BubbleTouchContainer? = null
    private var params: WindowManager.LayoutParams? = null
    private var added = false
    private var expanded = false
    private var focusable = false
    private var engineResumed = false

    private val idleHandler = Handler(Looper.getMainLooper())
    private val idleTeardown = Runnable { teardownIdleEngine() }

    /** Screen metrics frozen at drag start, so moves never hit the system per event. */
    private var dragScreen: BubbleLayout.Screen? = null

    var gestureListener: GestureListener? = null

    /** Last field anchor, so expand/collapse can re-place the window. */
    private var anchor: Rect? = null

    /**
     * Collapsed bubble window origin/size in dp, captured before expand grows
     * the overlay to a full-screen scrim. Flutter anchors the panel here.
     */
    private var bubbleAnchorXDp: Double = -1.0
    private var bubbleAnchorYDp: Double = -1.0
    private var bubbleAnchorSizeDp: Double = BUBBLE_WINDOW_DP.toDouble()

    val isShowing: Boolean get() = added

    val isExpanded: Boolean get() = added && expanded

    /** Finger is down on the collapsed bubble — layout must not fight the drag. */
    val isDragging: Boolean get() = dragScreen != null

    // ── Engine ───────────────────────────────────────────────────────────────

    fun warm(): FlutterEngine? {
        if (!BubblePrefs.isEnabled(context)) return null
        engine?.let { return it }
        return try {
            FlutterEngineCache.getInstance().get(Channels.OVERLAY_ENGINE_ID)?.let {
                engine = it
                return it
            }
            val app = context.applicationContext
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
            }
            val entry = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                Channels.OVERLAY_ENTRYPOINT,
            )
            val created = FlutterEngineGroup(app).createAndRunEngine(app, entry)
            FlutterEngineCache.getInstance().put(Channels.OVERLAY_ENGINE_ID, created)
            engine = created
            created
        } catch (t: Throwable) {
            Log.e(TAG, "overlay engine warm-up failed", t)
            null
        }
    }

    // ── Show / hide ──────────────────────────────────────────────────────────

    /** Show (or move) the collapsed bubble anchored to [fieldBounds]. */
    fun showBubble(fieldBounds: Rect) {
        cancelIdleTeardown()
        val eng = warm() ?: return
        anchor = Rect(fieldBounds)
        // Typing debounce / field-bounds updates must not yank the window out
        // from under the finger. The drop is committed in settleAtDrop.
        if (dragScreen != null && added) return
        expanded = false

        if (root == null) {
            // TextureView must not be opaque — an opaque layer paints a solid
            // rectangular plate behind the round glass bubble.
            val textureView = FlutterTextureView(context).apply {
                isOpaque = false
            }
            val fv = FlutterView(context, textureView).apply {
                setBackgroundColor(Color.TRANSPARENT)
                attachToFlutterEngine(eng)
            }
            flutterView = fv
            root = BubbleTouchContainer(context, touchHost).apply {
                setBackgroundColor(Color.TRANSPARENT)
                addView(fv)
            }
        }
        resumeEngineIfNeeded()
        root?.interceptTouches = true

        val lp = params ?: newParams().also { params = it }
        applyFocusable(lp, false)
        lp.width = dp(BUBBLE_WINDOW_DP)
        lp.height = dp(BUBBLE_WINDOW_DP)
        placeBubbleWindow(lp)
        rememberBubbleAnchor(lp)
        attachOrUpdate(lp)
    }

    /**
     * The user's chosen resting place wins over the field anchor: once they have
     * dragged the bubble anywhere, every future appearance restores that XY
     * (fractions, so it survives rotation). The keyboard only lifts Y.
     */
    private fun placeBubbleWindow(lp: WindowManager.LayoutParams) {
        if (BubblePrefs.hasSavedPosition(context)) {
            val position = BubbleLayout.restored(
                BubblePrefs.savedXFraction(context),
                BubblePrefs.savedYFraction(context),
                lp.width,
                screen(),
            )
            lp.x = position.x
            lp.y = position.y
        } else {
            anchor?.let { placeBubble(lp, it) }
        }
    }

    /**
     * Grow to a full-screen transparent scrim so Flutter can receive outside taps
     * and swipe-down to dismiss. The panel paints itself inside that window; we
     * deliberately do not shrink back to content size while expanded.
     */
    fun expand() {
        val lp = params ?: return
        if (!added) return
        // Capture the resting bubble spot before the scrim overwrites x/y to 0.
        rememberBubbleAnchor(lp)
        expanded = true
        // The panel handles its own touches in Flutter.
        root?.interceptTouches = false
        applyScrimWindow(lp)
        attachOrUpdate(lp)
    }

    fun collapse() {
        val lp = params ?: return
        if (!added) return
        setFocusable(false)
        expanded = false
        root?.interceptTouches = true
        lp.width = dp(BUBBLE_WINDOW_DP)
        lp.height = dp(BUBBLE_WINDOW_DP)
        placeBubbleWindow(lp)
        rememberBubbleAnchor(lp)
        attachOrUpdate(lp)
    }

    /** Collapsed bubble origin/size in logical pixels for Dart panel anchoring. */
    fun bubbleAnchorDp(): Triple<Double, Double, Double> =
        Triple(bubbleAnchorXDp, bubbleAnchorYDp, bubbleAnchorSizeDp)

    private fun rememberBubbleAnchor(lp: WindowManager.LayoutParams) {
        if (expanded) return
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.01f)
        bubbleAnchorXDp = lp.x / density.toDouble()
        bubbleAnchorYDp = lp.y / density.toDouble()
        bubbleAnchorSizeDp = lp.width / density.toDouble()
    }

    /**
     * Dart still reports the panel's measured size (used for layout budgets),
     * but while expanded the window stays full-screen so outside taps work.
     * Shrinking here would recreate the "tiny panel" race and kill outside-tap.
     */
    @Suppress("UNUSED_PARAMETER")
    fun resizePanel(widthDp: Double, heightDp: Double) {
        // no-op in scrim mode
    }

    /**
     * Re-place the collapsed bubble against live insets (IME, rotation). Never
     * called while expanded — the scrim stays put — or while the user is
     * dragging, which would steal the window from under the finger.
     */
    fun reclampForIme() {
        val lp = params ?: return
        if (!added || expanded) return
        if (dragScreen != null) return
        placeBubbleWindow(lp)
        rememberBubbleAnchor(lp)
        attachOrUpdate(lp)
    }

    /** Rotation / multi-window: keep the parked XY, resize the expanded scrim. */
    fun onDisplayChanged() {
        val lp = params ?: return
        if (!added) return
        if (expanded) {
            applyScrimWindow(lp)
            attachOrUpdate(lp)
            return
        }
        reclampForIme()
    }

    fun hide() {
        dragScreen = null
        if (focusable) hideKeyboard()
        if (added && root != null) {
            try {
                wm.removeView(root)
            } catch (t: Throwable) {
                Log.w(TAG, "removeView failed", t)
            }
            added = false
        }
        // Reset flags directly rather than via setFocusable, which would try to
        // update — and so re-add — the window we just removed.
        params?.let { applyFocusable(it, false) }
        expanded = false
        pauseEngineIfNeeded()
        scheduleIdleTeardown()
    }

    fun destroy() {
        cancelIdleTeardown()
        hide()
        cancelIdleTeardown()
        teardownEngine()
    }

    private fun resumeEngineIfNeeded() {
        val eng = engine ?: return
        if (engineResumed) return
        try {
            eng.lifecycleChannel.appIsResumed()
        } catch (t: Throwable) {
            Log.w(TAG, "engine resume failed", t)
        }
        engineResumed = true
    }

    private fun pauseEngineIfNeeded() {
        val eng = engine ?: return
        if (!engineResumed) return
        try {
            eng.lifecycleChannel.appIsPaused()
        } catch (t: Throwable) {
            Log.w(TAG, "engine pause failed", t)
        }
        engineResumed = false
    }

    private fun scheduleIdleTeardown() {
        idleHandler.removeCallbacks(idleTeardown)
        if (engine == null) return
        idleHandler.postDelayed(idleTeardown, IDLE_DESTROY_MS)
    }

    private fun cancelIdleTeardown() {
        idleHandler.removeCallbacks(idleTeardown)
    }

    private fun teardownIdleEngine() {
        if (added) return
        teardownEngine()
    }

    private fun teardownEngine() {
        try {
            flutterView?.detachFromFlutterEngine()
        } catch (t: Throwable) {
            Log.w(TAG, "detach failed", t)
        }
        flutterView = null
        root = null
        params = null
        anchor = null
        engineResumed = false
        val eng = engine
        engine = null
        if (eng == null) return
        try {
            FlutterEngineCache.getInstance().remove(Channels.OVERLAY_ENGINE_ID)
        } catch (t: Throwable) {
            Log.w(TAG, "engine cache remove failed", t)
        }
        try {
            eng.destroy()
        } catch (t: Throwable) {
            Log.w(TAG, "engine destroy failed", t)
        }
    }

    // ── Focus (the "Own" tone input) ─────────────────────────────────────────

    /**
     * Give the overlay keyboard focus so a Flutter TextField can be typed into,
     * or hand focus back to the app underneath.
     *
     * While focusable the panel is pinned near the top of the screen so the IME
     * cannot cover it.
     */
    fun setFocusable(value: Boolean) {
        val lp = params ?: return
        if (focusable == value || !added) return
        applyFocusable(lp, value)
        if (value) {
            // While expanded the window is already a full-screen scrim at (0,0);
            // Flutter pins the panel to the top for the IME. Moving a full-screen
            // window would shift the whole coordinate space and break anchoring.
            if (!expanded) {
                val position = BubbleLayout.toneInput(
                    BubbleLayout.Size(lp.width, lp.height),
                    screen(),
                )
                lp.x = position.x
                lp.y = position.y
            }
        } else {
            hideKeyboard()
            if (expanded) applyScrimWindow(lp) else placeBubbleWindow(lp)
        }
        attachOrUpdate(lp)
        if (value) {
            try {
                flutterView?.requestFocus()
            } catch (t: Throwable) {
                Log.w(TAG, "requestFocus failed", t)
            }
        }
    }

    fun hideKeyboard() {
        try {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            root?.let { imm.hideSoftInputFromWindow(it.windowToken, 0) }
        } catch (t: Throwable) {
            Log.w(TAG, "hideKeyboard failed", t)
        }
    }

    // ── Drag / drop (driven natively by BubbleTouchContainer) ────────────────

    private val touchHost = object : BubbleTouchContainer.Host {
        override fun windowPosition(): BubbleLayout.Position {
            val lp = params
            return BubbleLayout.Position(lp?.x ?: 0, lp?.y ?: 0)
        }

        override fun onDragStart() {
            dragScreen = screen()
        }

        override fun onDragMove(x: Int, y: Int) = moveTo(x, y)

        override fun onDragEnd() {
            dragScreen = null
            settleAtDrop()
        }

        override fun onTap() {
            dragScreen = null
            gestureListener?.onTap()
        }

        override fun onLongPress() {
            dragScreen = null
            gestureListener?.onLongPress()
        }
    }

    /** Absolute move from the native drag; clamped, straight to the window. */
    private fun moveTo(x: Int, y: Int) {
        val lp = params ?: return
        if (!added || expanded) return
        val screen = dragScreen ?: screen()
        lp.x = BubbleLayout.clampX(x, lp.width, screen)
        lp.y = BubbleLayout.clampY(y, lp.height, screen)
        rememberBubbleAnchor(lp)
        attachOrUpdate(lp)
    }

    /** Remember the drop spot as-is. Never fling to a screen edge. */
    fun settleAtDrop() {
        val lp = params ?: return
        if (!added || expanded) return
        val s = screen()
        lp.x = BubbleLayout.clampX(lp.x, lp.width, s)
        lp.y = BubbleLayout.clampY(lp.y, lp.height, s)
        val xFraction = BubbleLayout.xFraction(lp.x, lp.width, s)
        // The drop is the user's chosen home — including while the keyboard is
        // open. IME reclamp lifts without saving; only a drag writes Y.
        val yFraction = BubbleLayout.yFraction(lp.y, s)
        BubblePrefs.saveFreePosition(context, xFraction, yFraction)
        rememberBubbleAnchor(lp)
        attachOrUpdate(lp)
        anchor = null // the user chose this position; don't fight them
    }

    // ── Placement ────────────────────────────────────────────────────────────

    private fun placeBubble(lp: WindowManager.LayoutParams, bounds: Rect) {
        val position = BubbleLayout.bubble(bounds.toLayoutBounds(), lp.width, screen())
        lp.x = position.x
        lp.y = position.y
    }

    private fun placePanel(lp: WindowManager.LayoutParams) {
        val position = BubbleLayout.panel(
            anchor?.toLayoutBounds(),
            BubbleLayout.Size(lp.width, lp.height),
            screen(),
        )
        lp.x = position.x
        lp.y = position.y
    }

    /** Full-screen transparent hit target for outside-tap dismiss. */
    private fun applyScrimWindow(lp: WindowManager.LayoutParams) {
        lp.width = screenWidth()
        lp.height = screenHeight()
        lp.x = 0
        lp.y = 0
    }

    private fun panelSize(desiredWidthPx: Int, desiredHeightPx: Int): BubbleLayout.Size =
        BubbleLayout.panelSize(
            BubbleLayout.Size(desiredWidthPx, desiredHeightPx),
            screen(),
        )

    /**
     * The largest panel this display allows, in dp, handed to Dart so it can lay
     * out to a fixed budget in one pass. Without it Dart would have to infer the
     * budget from the current window size and grow over several frames.
     */
    fun maxPanelDp(): Pair<Double, Double> {
        val size = panelSize(dp(PANEL_WIDTH_DP), Int.MAX_VALUE / 4)
        val density = context.resources.displayMetrics.density
        return (size.width / density).toDouble() to (size.height / density).toDouble()
    }

    private fun Rect.toLayoutBounds() = BubbleLayout.Bounds(left, top, right, bottom)

    /**
     * Live screen metrics. Read per call rather than cached so a rotation or a
     * multi-window resize can never leave the bubble placed off-screen.
     */
    private fun screen(): BubbleLayout.Screen {
        val insets = safeInsets()
        return BubbleLayout.Screen(
            width = screenWidth(),
            height = screenHeight(),
            safeTop = insets.first.coerceAtLeast(dp(TOP_SAFE_DP)),
            safeBottom = insets.second,
            edge = dp(EDGE_DP),
            gap = dp(GAP_DP),
        )
    }

    /**
     * Status bar / cutout, navigation bar, and IME insets. FLAG_LAYOUT_NO_LIMITS
     * lets the window sit under them, so we keep clear of them ourselves. The
     * IME bottom is what lifts a remembered bubble above the keyboard and drops
     * it back when the keyboard closes.
     */
    private fun safeInsets(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return dp(TOP_SAFE_DP) to dp(EDGE_DP)
        }
        return try {
            val metrics = wm.currentWindowMetrics.windowInsets
            val bars = metrics.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            val ime = metrics.getInsets(WindowInsets.Type.ime()).bottom
            bars.top to maxOf(bars.bottom, ime)
        } catch (t: Throwable) {
            Log.w(TAG, "inset query failed", t)
            dp(TOP_SAFE_DP) to dp(EDGE_DP)
        }
    }

    // ── Window plumbing ──────────────────────────────────────────────────────

    private fun attachOrUpdate(lp: WindowManager.LayoutParams) {
        val v = root ?: return
        try {
            if (!added) {
                wm.addView(v, lp)
                added = true
            } else {
                wm.updateViewLayout(v, lp)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "window update failed", t)
            added = false
        }
    }

    private fun newParams(): WindowManager.LayoutParams {
        val lp = WindowManager.LayoutParams(
            dp(BUBBLE_WINDOW_DP),
            dp(BUBBLE_WINDOW_DP),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            BASE_FLAGS,
            PixelFormat.TRANSLUCENT,
        )
        // LEFT, not START: x/y here are absolute screen coordinates, and START
        // would mirror them under an RTL locale.
        lp.gravity = Gravity.TOP or Gravity.LEFT
        return lp
    }

    private fun applyFocusable(lp: WindowManager.LayoutParams, value: Boolean) {
        focusable = value
        lp.flags = if (value) {
            (BASE_FLAGS and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()) or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        } else {
            BASE_FLAGS
        }
        lp.softInputMode = if (value) {
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        } else {
            WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED
        }
    }

    // No FLAG_BLUR_BEHIND anywhere: window blur applies to the whole rectangular
    // window, which painted a visible frosted square around the round bubble.
    // The glass look is drawn inside the bubble itself, on transparent pixels.

    private fun screenWidth(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wm.currentWindowMetrics.bounds.width()
        } else {
            context.resources.displayMetrics.widthPixels
        }

    private fun screenHeight(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wm.currentWindowMetrics.bounds.height()
        } else {
            context.resources.displayMetrics.heightPixels
        }

    private fun dp(v: Int): Int = (v * context.resources.displayMetrics.density).toInt()

    private fun dpF(v: Double): Int =
        (v * context.resources.displayMetrics.density).toInt()

    companion object {
        private const val TAG = "BubbleOverlay"

        /** Room for the 44-56dp bubble plus its breathing scale and shadow. */
        private const val BUBBLE_WINDOW_DP = 76
        /** 308dp of panel plus the 10dp shadow margin Dart lays out on each side. */
        private const val PANEL_WIDTH_DP = 328
        private const val PANEL_HEIGHT_DP = 320

        /** The smallest window an expanded panel may ever be resized to. */
        private const val PANEL_MIN_WIDTH_DP = 240
        private const val PANEL_MIN_HEIGHT_DP = 140
        private const val EDGE_DP = 8
        private const val GAP_DP = 8

        /** Fallback status-bar clearance when insets can't be queried. */
        private const val TOP_SAFE_DP = 36

        /** Tear down the paused overlay engine after this idle stretch. */
        private const val IDLE_DESTROY_MS = 120_000L

        private const val BASE_FLAGS =
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
    }
}
