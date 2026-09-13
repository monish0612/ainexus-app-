package app.ainexus.ai_nexus.bubble

import android.annotation.SuppressLint
import android.content.Context
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.FrameLayout

/**
 * Root view of the overlay window. While the bubble is collapsed it intercepts
 * every touch and handles drag / tap / long-press natively, moving the window
 * directly — no per-frame trip through the Flutter engine, which is what made
 * dragging feel laggy and rubbery. When the panel is expanded it stays out of
 * the way and lets the Flutter view handle everything.
 */
@SuppressLint("ViewConstructor")
class BubbleTouchContainer(
    context: Context,
    private val host: Host,
) : FrameLayout(context) {

    interface Host {
        /** Current window position, read at finger-down. */
        fun windowPosition(): BubbleLayout.Position

        fun onDragStart()

        fun onDragMove(x: Int, y: Int)

        fun onDragEnd()

        fun onTap()

        fun onLongPress()
    }

    /** True while collapsed: the bubble is a native gesture surface. */
    var interceptTouches = false

    private var session: DragSession? = null
    private var pendingLongPress: Runnable? = null
    private val slop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private val longPressMs = ViewConfiguration.getLongPressTimeout().toLong()

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = interceptTouches

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (!interceptTouches) return super.onTouchEvent(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val start = host.windowPosition()
                session = DragSession(slop, start.x, start.y, ev.rawX, ev.rawY)
                host.onDragStart()
                scheduleLongPress()
            }

            MotionEvent.ACTION_MOVE -> {
                val active = session ?: return true
                val wasDragging = active.dragging
                val position = active.onMove(ev.rawX, ev.rawY) ?: return true
                if (!wasDragging) {
                    // The finger left tap slop: this is a drag, not a long-press.
                    cancelPendingLongPress()
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                }
                host.onDragMove(position.x, position.y)
            }

            MotionEvent.ACTION_UP -> {
                cancelPendingLongPress()
                val finished = session
                session = null
                when {
                    finished == null -> Unit // long-press already consumed it
                    finished.dragging -> {
                        performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        host.onDragEnd()
                    }
                    else -> {
                        performClick()
                        host.onTap()
                    }
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                cancelPendingLongPress()
                val finished = session
                session = null
                if (finished?.dragging == true) {
                    performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    host.onDragEnd()
                }
            }
        }
        return true
    }

    private fun scheduleLongPress() {
        cancelPendingLongPress()
        val runnable = Runnable {
            pendingLongPress = null
            if (session?.dragging == false) {
                session = null // consume: the following UP must not become a tap
                performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                host.onLongPress()
            }
        }
        pendingLongPress = runnable
        postDelayed(runnable, longPressMs)
    }

    private fun cancelPendingLongPress() {
        pendingLongPress?.let { removeCallbacks(it) }
        pendingLongPress = null
    }

    override fun onDetachedFromWindow() {
        cancelPendingLongPress()
        session = null
        super.onDetachedFromWindow()
    }
}
