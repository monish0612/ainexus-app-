package app.ainexus.ai_nexus.bubble

/**
 * One finger-down-to-up interaction with the collapsed bubble.
 *
 * The window position is computed from the *absolute* finger position against
 * where the window was at touch-down. The previous implementation accumulated
 * per-event deltas across a Dart round trip, which lagged behind the finger and
 * drifted with rounding — the classic "rubber band" drag. Absolute tracking
 * means the bubble is always exactly under the finger, every frame.
 *
 * Pure Kotlin (no Android types) so the tap/drag decision and the tracking math
 * are unit-tested on the JVM.
 */
class DragSession(
    private val slop: Float,
    private val startWindowX: Int,
    private val startWindowY: Int,
    private val downRawX: Float,
    private val downRawY: Float,
) {
    /** Latched once the finger travels past [slop]; a tap never sets it. */
    var dragging = false
        private set

    /**
     * Window position for this finger position, or null while the gesture is
     * still within tap slop. Once dragging, every move produces a position —
     * there is no minimum step, so slow precise placement works.
     */
    fun onMove(rawX: Float, rawY: Float): BubbleLayout.Position? {
        val dx = rawX - downRawX
        val dy = rawY - downRawY
        if (!dragging && dx * dx + dy * dy < slop * slop) return null
        dragging = true
        return BubbleLayout.Position(
            startWindowX + Math.round(dx),
            startWindowY + Math.round(dy),
        )
    }
}
