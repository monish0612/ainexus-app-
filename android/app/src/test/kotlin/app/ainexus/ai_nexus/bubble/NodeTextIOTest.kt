package app.ainexus.ai_nexus.bubble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-logic coverage for write-back normalisation. The SET_TEXT-never-falls-
 * through contract is enforced in [NodeTextIO.replace] itself: once
 * performAction(SET_TEXT) returns true the method returns REPLACED_SET_TEXT
 * without attempting PASTE — that is what stopped the duplicate-paste bug.
 */
class NodeTextIOTest {

    @Test
    fun `normalize strips trailing newlines and zero-width spaces`() {
        assertEquals(
            "hello",
            NodeTextIO.normalizeForCompare("hello\n"),
        )
        assertEquals(
            "hello",
            NodeTextIO.normalizeForCompare("hello\u200B"),
        )
        assertEquals(
            "hello",
            NodeTextIO.normalizeForCompare("  hello  \r\n"),
        )
        assertEquals(
            "hey 😊",
            NodeTextIO.normalizeForCompare("hey 😊\n\uFEFF"),
        )
    }

    @Test
    fun `normalize treats equivalent editor variants as equal`() {
        val expected = "hey, fancy grabbing lunch from Starbucks?"
        val editorVariants = listOf(
            expected,
            "$expected\n",
            " $expected ",
            "$expected\u200B",
            "$expected\n\n",
        )
        for (variant in editorVariants) {
            assertEquals(
                NodeTextIO.normalizeForCompare(expected),
                NodeTextIO.normalizeForCompare(variant),
            )
        }
    }

    @Test
    fun `normalize does not equate genuinely different text`() {
        assertFalse(
            NodeTextIO.normalizeForCompare("hello") ==
                NodeTextIO.normalizeForCompare("hello hello"),
        )
    }

    @Test
    fun `outcome names stay stable for the Dart bridge`() {
        // The overlay bridge maps these exact strings; renaming would silently
        // break the panel's Use → close path.
        assertEquals("REPLACED_SET_TEXT", NodeTextIO.Outcome.REPLACED_SET_TEXT.name)
        assertEquals("REPLACED_PASTE", NodeTextIO.Outcome.REPLACED_PASTE.name)
        assertEquals("BLOCKED", NodeTextIO.Outcome.BLOCKED.name)
    }

    @Test
    fun `set-text success must not be followed by paste — contract documented`() {
        // Documented invariant of NodeTextIO.replace:
        //   if (ok) { ...; return REPLACED_SET_TEXT }
        // A verify soft-failure after ok==true must NOT fall through to PASTE.
        // This test locks the outcome enum so a future refactor that adds a
        // "VERIFY_FAILED_RETRY_PASTE" path is forced to update the suite.
        val outcomes = NodeTextIO.Outcome.entries.map { it.name }.toSet()
        assertTrue(outcomes.contains("REPLACED_SET_TEXT"))
        assertTrue(outcomes.contains("REPLACED_PASTE"))
        assertTrue(outcomes.contains("BLOCKED"))
        assertEquals(3, outcomes.size)
    }
}
