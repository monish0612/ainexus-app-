package app.ainexus.ai_nexus.bubble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Absolute finger tracking for the collapsed bubble. The previous delta-based
 * path lagged behind the finger and drifted; these tests pin the contract that
 * replaced it.
 */
class DragSessionTest {

    private fun session(
        slop: Float = 16f,
        startX: Int = 100,
        startY: Int = 200,
        downX: Float = 140f,
        downY: Float = 240f,
    ) = DragSession(slop, startX, startY, downX, downY)

    @Test
    fun `moves inside tap slop are ignored so a tap does not become a drag`() {
        val s = session(slop = 16f)
        assertNull(s.onMove(145f, 245f)) // 5√2 ≈ 7px
        assertFalse(s.dragging)
        assertNull(s.onMove(150f, 248f)) // still under 16
        assertFalse(s.dragging)
    }

    @Test
    fun `crossing slop latches dragging and returns an absolute window position`() {
        val s = session(slop = 16f, startX = 100, startY = 200, downX = 140f, downY = 240f)
        val pos = s.onMove(180f, 280f) // Δ = (40, 40)
        assertNotNull(pos)
        assertTrue(s.dragging)
        assertEquals(140, pos!!.x) // 100 + 40
        assertEquals(240, pos.y) // 200 + 40
    }

    @Test
    fun `once dragging every move tracks the finger with no lag or drift`() {
        val s = session(slop = 8f, startX = 50, startY = 80, downX = 60f, downY = 90f)
        // Leave slop.
        s.onMove(80f, 90f)
        assertTrue(s.dragging)

        // Walk the finger along a path; the window must follow exactly.
        val path = listOf(
            100f to 120f,
            101.4f to 120.6f, // fractional — Math.round
            250f to 40f,
            10f to 300f,
        )
        for ((rawX, rawY) in path) {
            val pos = s.onMove(rawX, rawY)!!
            assertEquals(Math.round(50 + (rawX - 60f)), pos.x)
            assertEquals(Math.round(80 + (rawY - 90f)), pos.y)
        }
    }

    @Test
    fun `slow precise placement still moves one pixel at a time after latch`() {
        val s = session(slop = 4f, startX = 0, startY = 0, downX = 0f, downY = 0f)
        // Latch.
        assertNotNull(s.onMove(5f, 0f))
        // Tiny moves must not be discarded.
        val a = s.onMove(5.4f, 0f)!!
        val b = s.onMove(5.6f, 0f)!!
        assertEquals(5, a.x)
        assertEquals(6, b.x)
    }

    @Test
    fun `negative directions are tracked symmetrically`() {
        val s = session(slop = 4f, startX = 200, startY = 200, downX = 200f, downY = 200f)
        val pos = s.onMove(160f, 150f)!!
        assertEquals(160, pos.x)
        assertEquals(150, pos.y)
    }

    @Test
    fun `a finger that stays inside slop never latches dragging`() {
        val s = session(slop = 20f)
        repeat(30) { i ->
            assertNull(s.onMove(140f + i * 0.4f, 240f))
        }
        assertFalse(s.dragging)
    }
}
