package app.ainexus.ai_nexus.bubble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Exhaustive geometry checks for the overlay window across the display shapes we
 * realistically meet: tiny phones, tall modern phones, tablets, landscape, and
 * split-screen slivers. The invariant that matters is simple and absolute — the
 * window is always fully on screen and never under the status bar or the
 * navigation bar.
 */
class BubbleLayoutTest {

    private val bubbleSize = 76 * 3 // 76dp at xxhdpi
    private val panel = BubbleLayout.Size(324 * 3, 320 * 3)

    /** density-independent screen catalogue, expressed in physical pixels. */
    private val screens = mapOf(
        "small phone 320x480 mdpi" to screen(320, 480, safeTop = 25),
        "compact 720x1280 xhdpi" to screen(720, 1280, safeTop = 50),
        "modern 1080x2400 xxhdpi" to screen(1080, 2400, safeTop = 100, safeBottom = 48),
        "cutout 1440x3200" to screen(1440, 3200, safeTop = 140, safeBottom = 60),
        "tablet 1600x2560" to screen(1600, 2560, safeTop = 60),
        "landscape phone 2400x1080" to screen(2400, 1080, safeTop = 60, safeBottom = 48),
        "landscape small 800x480" to screen(800, 480, safeTop = 25),
        "split-screen sliver 1080x600" to screen(1080, 600, safeTop = 100),
        // Pathological: the panel is larger than the display.
        "degenerate 200x200" to screen(200, 200, safeTop = 40),
    )

    private fun screen(
        width: Int,
        height: Int,
        safeTop: Int = 0,
        safeBottom: Int = 0,
    ) = BubbleLayout.Screen(
        width = width,
        height = height,
        safeTop = safeTop,
        safeBottom = safeBottom,
        edge = 24,
        gap = 24,
    )

    private fun assertOnScreen(
        name: String,
        x: Int,
        y: Int,
        w: Int,
        h: Int,
        s: BubbleLayout.Screen,
    ) {
        assertTrue("$name: x=$x is off the left edge", x >= 0)
        assertTrue("$name: y=$y is above the safe top (${s.safeTop})", y >= 0)
        // A window bigger than the screen can only be top-left biased; it must
        // still start on screen.
        if (w <= s.width) {
            assertTrue("$name: right edge ${x + w} exceeds ${s.width}", x + w <= s.width)
        }
        if (h <= s.height - s.safeTop - s.safeBottom) {
            assertTrue(
                "$name: bottom edge ${y + h} intrudes on the nav bar",
                y + h <= s.height - s.safeBottom,
            )
        }
    }

    @Test
    fun `composer chrome is at least a send-button sized inset`() {
        screens.forEach { (name, s) ->
            val chrome = BubbleLayout.composerChrome(bubbleSize, s)
            assertTrue("$name chrome=$chrome", chrome >= s.gap * 6)
            assertTrue("$name chrome vs size", chrome >= bubbleSize * 3 / 4)
        }
    }

    @Test
    fun `bubble stays on screen for fields anywhere on any display`() {
        screens.forEach { (name, s) ->
            // Walk a field across the whole display, including fully off-screen
            // bounds, which stale accessibility nodes really do report.
            for (top in -200..s.height + 200 step 97) {
                for (right in -200..s.width + 200 step 89) {
                    val field = BubbleLayout.Bounds(right - 400, top, right, top + 120)
                    val p = BubbleLayout.bubble(field, bubbleSize, s)
                    assertOnScreen(name, p.x, p.y, bubbleSize, bubbleSize, s)
                }
            }
        }
    }

    @Test
    fun `bubble sits above the field when there is room`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val field = BubbleLayout.Bounds(60, 1200, 1000, 1320)
        val p = BubbleLayout.bubble(field, bubbleSize, s)
        assertEquals(1200 - bubbleSize - s.gap, p.y)
        // Wide fields centre regardless of chrome (the insets cancel).
        assertEquals((field.left + field.right - bubbleSize) / 2, p.x)
        val chrome = BubbleLayout.composerChrome(bubbleSize, s)
        assertTrue("must clear send at field.right", p.x + bubbleSize <= field.right - chrome)
        assertTrue("must clear emoji at field.left", p.x >= field.left + chrome)
    }

    @Test
    fun `full-width bottom composer does not cover Send or emoji`() {
        screens.forEach { (name, s) ->
            if (s.height < bubbleSize * 3) return@forEach
            val fieldTop = s.height - s.safeBottom - 180
            val field = BubbleLayout.Bounds(0, fieldTop, s.width, fieldTop + 140)
            val p = BubbleLayout.bubble(field, bubbleSize, s)
            assertOnScreen(name, p.x, p.y, bubbleSize, bubbleSize, s)
            val chrome = BubbleLayout.composerChrome(bubbleSize, s)
            val sendLeft = s.width - bubbleSize - s.edge - chrome
            val emojiRight = s.edge + chrome
            if (sendLeft >= emojiRight) {
                assertTrue("$name: over Send x=${p.x} sendLeft=$sendLeft", p.x <= sendLeft)
                assertTrue("$name: over emoji x=${p.x} emojiRight=$emojiRight", p.x >= emojiRight)
            }
            assertTrue(
                "$name: must sit above the composer (y=${p.y} field.top=${field.top})",
                p.y + bubbleSize <= field.top || p.y >= field.bottom,
            )
        }
    }

    @Test
    fun `a drop in the geometric centre is not an edge park`() {
        screens.forEach { (name, s) ->
            val minX = s.edge
            val maxX = (s.width - bubbleSize - s.edge).coerceAtLeast(minX)
            if (maxX <= minX + 8) return@forEach
            val dropX = (minX + maxX) / 2
            val dropY = s.safeTop + (s.height - s.safeTop - s.safeBottom) / 3
            val xf = BubbleLayout.xFraction(dropX, bubbleSize, s)
            val yf = BubbleLayout.yFraction(dropY, s)
            val p = BubbleLayout.restored(xf, yf, bubbleSize, s)
            assertTrue("$name: x=${p.x} snapped left", p.x > minX)
            assertTrue("$name: x=${p.x} snapped right", p.x < maxX)
            assertOnScreen(name, p.x, p.y, bubbleSize, bubbleSize, s)
        }
    }

    @Test
    fun `bubble flips below a field pinned to the top of the screen`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val field = BubbleLayout.Bounds(60, s.safeTop, 1000, s.safeTop + 120)
        val p = BubbleLayout.bubble(field, bubbleSize, s)
        assertEquals(field.bottom + s.gap, p.y)
    }

    @Test
    fun `bubble never overlaps a field it is placed below`() {
        val s = screens.getValue("compact 720x1280 xhdpi")
        val field = BubbleLayout.Bounds(20, s.safeTop, 700, s.safeTop + 100)
        val p = BubbleLayout.bubble(field, bubbleSize, s)
        assertTrue("bubble top ${p.y} must clear field bottom ${field.bottom}", p.y >= field.bottom)
    }

    // ── Panel ────────────────────────────────────────────────────────────────

    @Test
    fun `panel stays on screen at its clamped size for fields anywhere`() {
        screens.forEach { (name, s) ->
            val size = BubbleLayout.panelSize(panel, s)
            for (top in -100..s.height + 100 step 83) {
                val field = BubbleLayout.Bounds(40, top, s.width - 40, top + 130)
                val p = BubbleLayout.panel(field, size, s)
                assertOnScreen(name, p.x, p.y, size.width, size.height, s)
            }
        }
    }

    @Test
    fun `panel flips above a field in the lower half so the keyboard misses it`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val size = BubbleLayout.panelSize(panel, s)
        val field = BubbleLayout.Bounds(40, 1800, 1040, 1900)
        val p = BubbleLayout.panel(field, size, s)
        assertTrue("panel should sit above y=1800, was ${p.y}", p.y + size.height <= 1800)
    }

    @Test
    fun `panel centres itself when the bubble was dragged and the anchor dropped`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val size = BubbleLayout.panelSize(panel, s)
        val p = BubbleLayout.panel(null, size, s)
        assertEquals((s.width - size.width) / 2, p.x)
        assertOnScreen("no anchor", p.x, p.y, size.width, size.height, s)
    }

    @Test
    fun `panel size never exceeds the display or its safe area`() {
        screens.forEach { (name, s) ->
            val size = BubbleLayout.panelSize(panel, s)
            assertTrue("$name: width ${size.width}", size.width <= s.width - s.edge * 2)
            assertTrue("$name: height ${size.height}", size.height <= (s.height * 0.72).toInt())
            assertTrue(
                "$name: height ${size.height} vs safe area",
                size.height <= s.height - s.safeTop - s.safeBottom - s.edge,
            )
            assertTrue("$name: must stay positive", size.width > 0 && size.height > 0)
        }
    }

    @Test
    fun `panel keeps its requested size when the display is roomy`() {
        val s = screens.getValue("tablet 1600x2560")
        val size = BubbleLayout.panelSize(panel, s)
        assertEquals(panel.width, size.width)
        assertEquals(panel.height, size.height)
    }

    @Test
    fun `landscape clamps panel height rather than letting it overflow`() {
        val s = screens.getValue("landscape small 800x480")
        val size = BubbleLayout.panelSize(panel, s)
        assertTrue("height ${size.height} must fit 480px", size.height < 480)
        val p = BubbleLayout.panel(BubbleLayout.Bounds(0, 300, 700, 400), size, s)
        assertOnScreen("landscape small", p.x, p.y, size.width, size.height, s)
    }

    @Test
    fun `tone input pins the panel to the safe top and centres it`() {
        screens.forEach { (name, s) ->
            val size = BubbleLayout.panelSize(panel, s)
            val p = BubbleLayout.toneInput(size, s)
            assertEquals("$name: must sit at the safe top", s.safeTop, p.y)
            assertOnScreen(name, p.x, p.y, size.width, size.height, s)
        }
    }

    // ── Drag and snap ────────────────────────────────────────────────────────

    @Test
    fun `snap picks the nearer edge`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        assertEquals(s.edge, BubbleLayout.snapTargetX(10, bubbleSize, s))
        assertEquals(
            s.width - bubbleSize - s.edge,
            BubbleLayout.snapTargetX(s.width - bubbleSize - 10, bubbleSize, s),
        )
    }

    @Test
    fun `snap target is always a valid on-screen position`() {
        screens.forEach { (name, s) ->
            for (x in -50..s.width + 50 step 37) {
                val target = BubbleLayout.snapTargetX(x, bubbleSize, s)
                assertOnScreen(name, target, s.safeTop, bubbleSize, bubbleSize, s)
            }
        }
    }

    // ── Remembered position ──────────────────────────────────────────────────

    @Test
    fun `snapSide agrees with snapTargetX on every display`() {
        screens.forEach { (name, s) ->
            for (x in -50..s.width + 50 step 37) {
                val side = BubbleLayout.snapSide(x, bubbleSize, s)
                val target = BubbleLayout.snapTargetX(x, bubbleSize, s)
                val expected = if (side == BubbleLayout.Side.LEFT) {
                    s.edge
                } else {
                    (s.width - bubbleSize - s.edge).coerceAtLeast(s.edge)
                }
                assertEquals("$name at x=$x", expected, target)
            }
        }
    }

    @Test
    fun `yFraction round-trips through restore on every display`() {
        screens.forEach { (name, s) ->
            val minY = s.safeTop
            val maxY = (s.height - bubbleSize - s.safeBottom - s.edge).coerceAtLeast(minY)
            for (y in listOf(minY, (minY + maxY) / 2, maxY)) {
                val f = BubbleLayout.yFraction(y, s)
                val back = BubbleLayout.restored(0.5, f, bubbleSize, s).y
                assertTrue(
                    "$name y=$y back=$back",
                    kotlin.math.abs(y - back) <= 1,
                )
            }
        }
    }

    @Test
    fun `IME lift keeps the parked X of a mid-screen drop`() {
        val closed = screen(1080, 2400, safeTop = 100, safeBottom = 48)
        val open = screen(1080, 2400, safeTop = 100, safeBottom = 900)
        val dropX = 400
        val dropY = 1800
        val xf = BubbleLayout.xFraction(dropX, bubbleSize, closed)
        val yf = BubbleLayout.yFraction(dropY, closed)
        val parked = BubbleLayout.restored(xf, yf, bubbleSize, closed)
        val lifted = BubbleLayout.restored(xf, yf, bubbleSize, open)
        assertEquals("X must not slide toward Send/emoji when the keyboard opens", parked.x, lifted.x)
        assertTrue("keyboard must lift Y (${lifted.y} vs ${parked.y})", lifted.y < parked.y)
        assertOnScreen("ime closed", parked.x, parked.y, bubbleSize, bubbleSize, closed)
        assertOnScreen("ime open", lifted.x, lifted.y, bubbleSize, bubbleSize, open)
    }

    @Test
    fun `IME open or closed never changes X for any saved fraction`() {
        screens.forEach { (name, s) ->
            val open = s.copy(safeBottom = (s.height * 2 / 5).coerceAtLeast(s.safeBottom))
            for (f in listOf(0.0, 0.22, 0.5, 0.78, 1.0)) {
                val a = BubbleLayout.restored(f, 0.7, bubbleSize, s)
                val b = BubbleLayout.restored(f, 0.7, bubbleSize, open)
                assertEquals("$name f=$f", a.x, b.x)
            }
        }
    }

    @Test
    fun `a drop Y is what restore uses even when the keyboard is up`() {
        // settleAtDrop now persists drop Y while the IME is open. Restoring
        // with that fraction on the same IME screen must land on the drop,
        // not jump to the 0.5 default.
        val open = screen(1080, 2400, safeTop = 100, safeBottom = 900)
        val dropY = BubbleLayout.clampY(1100, bubbleSize, open)
        val yf = BubbleLayout.yFraction(dropY, open)
        val p = BubbleLayout.restored(0.42, yf, bubbleSize, open)
        assertTrue(
            "restored Y=${p.y} should match drop Y=$dropY",
            kotlin.math.abs(p.y - dropY) <= 1,
        )
        assertTrue("must not collapse to the default mid-screen 0.5", p.y != (0.5 * open.height).toInt())
    }

    @Test
    fun `restored free position keeps an interior XY not an edge`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val p = BubbleLayout.restored(0.42, 0.37, bubbleSize, s)
        val left = s.edge
        val right = s.width - bubbleSize - s.edge
        assertTrue("x=${p.x} should not snap left", p.x > left)
        assertTrue("x=${p.x} should not snap right", p.x < right)
        assertEquals(BubbleLayout.xFromFraction(0.42, bubbleSize, s), p.x)
        assertEquals((0.37 * s.height).toInt(), p.y)
        assertOnScreen("free restore", p.x, p.y, bubbleSize, bubbleSize, s)
    }

    @Test
    fun `xFraction round-trips through restore on every display`() {
        screens.forEach { (name, s) ->
            for (f in listOf(0.0, 0.15, 0.5, 0.73, 1.0)) {
                val x = BubbleLayout.xFromFraction(f, bubbleSize, s)
                val back = BubbleLayout.xFraction(x, bubbleSize, s)
                val again = BubbleLayout.xFromFraction(back, bubbleSize, s)
                assertTrue(
                    "$name f=$f x=$x again=$again",
                    kotlin.math.abs(x - again) <= 1,
                )
                assertOnScreen("$name f=$f", x, s.safeTop, bubbleSize, bubbleSize, s)
            }
        }
    }

    @Test
    fun `restored position lands on the chosen edge at the remembered height`() {
        val s = screens.getValue("modern 1080x2400 xxhdpi")
        val left = BubbleLayout.restored(BubbleLayout.Side.LEFT, 0.5, bubbleSize, s)
        assertEquals(s.edge, left.x)
        assertEquals(s.height / 2, left.y)
        val right = BubbleLayout.restored(BubbleLayout.Side.RIGHT, 0.5, bubbleSize, s)
        assertEquals(s.width - bubbleSize - s.edge, right.x)
    }

    @Test
    fun `restored position is always on screen for any fraction on any display`() {
        screens.forEach { (name, s) ->
            for (fraction in listOf(-0.5, 0.0, 0.25, 0.5, 0.75, 1.0, 1.5)) {
                for (side in BubbleLayout.Side.entries) {
                    val p = BubbleLayout.restored(side, fraction, bubbleSize, s)
                    assertOnScreen("$name side=$side f=$fraction", p.x, p.y, bubbleSize, bubbleSize, s)
                }
            }
        }
    }

    @Test
    fun `a position saved on one display restores safely on a different one`() {
        // Saved on a tall phone at 90% height, restored on a short landscape
        // display: the fraction must clamp into the new safe area, not vanish.
        val saved = 0.9
        val landscape = screens.getValue("landscape small 800x480")
        val p = BubbleLayout.restored(BubbleLayout.Side.RIGHT, saved, bubbleSize, landscape)
        assertOnScreen("cross-display restore", p.x, p.y, bubbleSize, bubbleSize, landscape)
    }

    @Test
    fun `restored bubble stays above a large IME safeBottom`() {
        val open = screen(1080, 2400, safeTop = 100, safeBottom = 900) // keyboard up
        val p = BubbleLayout.restored(BubbleLayout.Side.RIGHT, 0.85, bubbleSize, open)
        assertTrue(
            "bubble bottom ${p.y + bubbleSize} must clear IME at ${open.height - open.safeBottom}",
            p.y + bubbleSize <= open.height - open.safeBottom,
        )
        assertOnScreen("ime open", p.x, p.y, bubbleSize, bubbleSize, open)
    }

    @Test
    fun `same fraction drops lower after the IME closes`() {
        val open = screen(1080, 2400, safeTop = 100, safeBottom = 900)
        val closed = screen(1080, 2400, safeTop = 100, safeBottom = 48)
        val fraction = 0.85
        val withIme = BubbleLayout.restored(BubbleLayout.Side.LEFT, fraction, bubbleSize, open)
        val without = BubbleLayout.restored(BubbleLayout.Side.LEFT, fraction, bubbleSize, closed)
        assertTrue(
            "after IME closes y should be >= the lifted y (${without.y} vs ${withIme.y})",
            without.y >= withIme.y,
        )
    }

    @Test
    fun `clamps keep a window larger than the screen at the top-left safe corner`() {
        val s = screens.getValue("degenerate 200x200")
        val huge = 900
        assertEquals(s.edge, BubbleLayout.clampX(-500, huge, s))
        assertEquals(s.safeTop, BubbleLayout.clampY(-500, huge, s))
        assertEquals(s.edge, BubbleLayout.clampX(5000, huge, s))
        assertEquals(s.safeTop, BubbleLayout.clampY(5000, huge, s))
    }
}
