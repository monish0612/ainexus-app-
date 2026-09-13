package app.ainexus.ai_nexus.bubble

/**
 * Pure geometry for the overlay window: where the bubble and panel sit, and how
 * big the panel may get.
 *
 * Deliberately free of Android types so it runs in plain JVM unit tests — this
 * is the code that decides whether the bubble ends up half off-screen on an odd
 * display, so it is worth testing exhaustively rather than by hand on one phone.
 *
 * All values are pixels. Every result is guaranteed on-screen: the clamps use
 * `coerceAtLeast` on the upper bound so a window larger than the screen still
 * yields a valid (top-left biased) position instead of throwing.
 */
object BubbleLayout {

    data class Bounds(val left: Int, val top: Int, val right: Int, val bottom: Int)

    /** Screen metrics plus the insets we must stay clear of. */
    data class Screen(
        val width: Int,
        val height: Int,
        val safeTop: Int,
        val safeBottom: Int = 0,
        val edge: Int,
        val gap: Int,
    )

    data class Position(val x: Int, val y: Int)

    data class Size(val width: Int, val height: Int)

    fun clampX(x: Int, width: Int, s: Screen): Int =
        x.coerceIn(s.edge, (s.width - width - s.edge).coerceAtLeast(s.edge))

    fun clampY(y: Int, height: Int, s: Screen): Int =
        y.coerceIn(
            s.safeTop,
            (s.height - height - s.safeBottom - s.edge).coerceAtLeast(s.safeTop),
        )

    /** Typical send / emoji hit target, in the same pixel space as [size]. */
    fun composerChrome(size: Int, s: Screen): Int =
        maxOf(s.gap * 6, size * 3 / 4)

    /**
     * First appearance (the user has never dragged): sit above the field when
     * there is room, otherwise below it. Horizontally it centres on the field
     * with a composer-chrome inset so it does not cover Send (right) or emoji
     * (left). A second screen-edge guard applies when the bubble sits in the
     * composer band.
     */
    fun bubble(field: Bounds, size: Int, s: Screen): Position {
        val chrome = composerChrome(size, s)
        val innerLeft = field.left + chrome
        val innerRight = field.right - size - chrome
        var x = if (innerRight >= innerLeft) {
            (innerLeft + innerRight) / 2
        } else {
            field.left + ((field.right - field.left) - size) / 2
        }
        val above = field.top - size - s.gap
        var y = if (above >= s.safeTop) above else field.bottom + s.gap
        x = clampX(x, size, s)
        y = clampY(y, size, s)

        val nearComposer = y + size >= field.top - s.gap && y <= field.bottom + s.gap
        val fieldWidth = (field.right - field.left).coerceAtLeast(0)
        val fullBleedComposer = fieldWidth >= s.width * 4 / 5
        if (nearComposer && fullBleedComposer) {
            val sendLeft = s.width - size - s.edge - chrome
            val emojiRight = s.edge + chrome
            if (sendLeft >= emojiRight) {
                if (x > sendLeft) x = clampX(sendLeft, size, s)
                if (x < emojiRight) x = clampX(emojiRight, size, s)
            } else {
                x = clampX((s.width - size) / 2, size, s)
            }
        }
        return Position(x, y)
    }

    /**
     * The panel is right-aligned to the field and flips above it once the field
     * is in the lower half of the screen, which is where the keyboard lives.
     */
    fun panel(field: Bounds?, size: Size, s: Screen): Position {
        val x = if (field == null) {
            (s.width - size.width) / 2
        } else {
            field.right - size.width
        }
        val preferAbove = field != null && field.top > s.height / 2
        val y = when {
            preferAbove -> field!!.top - size.height - s.gap
            field != null -> field.bottom + s.gap
            else -> s.height / 3
        }
        return Position(clampX(x, size.width, s), clampY(y, size.height, s))
    }

    /**
     * While the "Own" tone field has focus the panel is pinned to the top of the
     * screen, because the IME can otherwise cover it.
     */
    fun toneInput(size: Size, s: Screen): Position =
        Position(clampX((s.width - size.width) / 2, size.width, s), s.safeTop)

    /** Which side edge the bubble rests against. */
    enum class Side { LEFT, RIGHT }

    /** Chat-head fling: whichever side edge the bubble's centre is nearer. */
    fun snapTargetX(x: Int, width: Int, s: Screen): Int {
        val right = (s.width - width - s.edge).coerceAtLeast(s.edge)
        return if (snapSide(x, width, s) == Side.LEFT) s.edge else right
    }

    /** The side [snapTargetX] would choose — persisted so the choice survives. */
    fun snapSide(x: Int, width: Int, s: Screen): Side =
        if (x + width / 2 < s.width / 2) Side.LEFT else Side.RIGHT

    /**
     * Horizontal travel as a 0–1 fraction of the clamp range (left edge → right
     * edge). Survives rotation without jumping to a screen edge.
     */
    fun xFraction(x: Int, width: Int, s: Screen): Double {
        val min = s.edge
        val max = (s.width - width - s.edge).coerceAtLeast(min)
        if (max <= min) return 0.5
        return ((x - min).toDouble() / (max - min).toDouble()).coerceIn(0.0, 1.0)
    }

    fun yFraction(y: Int, s: Screen): Double =
        (y.toDouble() / s.height.coerceAtLeast(1)).coerceIn(0.0, 1.0)

    fun xFromFraction(fraction: Double, width: Int, s: Screen): Int {
        val min = s.edge
        val max = (s.width - width - s.edge).coerceAtLeast(min)
        val x = min + (fraction.coerceIn(0.0, 1.0) * (max - min)).toInt()
        return clampX(x, width, s)
    }

    /**
     * Re-create a remembered resting place on the current screen.
     *
     * X is a fraction of the horizontal clamp range; Y is a fraction of screen
     * height. Y is clamped against live [Screen.safeBottom] so an open keyboard
     * lifts the bubble without changing the saved fraction.
     */
    fun restored(xFraction: Double, yFraction: Double, size: Int, s: Screen): Position =
        Position(
            xFromFraction(xFraction, size, s),
            clampY((yFraction * s.height).toInt(), size, s),
        )

    /** Legacy edge restore for users who last snapped left/right before free-place. */
    fun restored(side: Side, yFraction: Double, size: Int, s: Screen): Position =
        restored(if (side == Side.LEFT) 0.0 else 1.0, yFraction, size, s)

    /**
     * Clamp the panel to the screen: never wider than the display minus its
     * margins, never taller than [maxHeightRatio] of it or the space between the
     * safe insets, whichever is smaller.
     */
    fun panelSize(
        desired: Size,
        s: Screen,
        maxHeightRatio: Double = 0.72,
    ): Size {
        val maxWidth = (s.width - s.edge * 2).coerceAtLeast(1)
        val maxHeight = minOf(
            (s.height * maxHeightRatio).toInt(),
            s.height - s.safeTop - s.safeBottom - s.edge,
        ).coerceAtLeast(1)
        return Size(
            desired.width.coerceIn(1, maxWidth),
            desired.height.coerceIn(1, maxHeight),
        )
    }

}
