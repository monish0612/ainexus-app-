package app.ainexus.ai_nexus.bubble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchdogTest {

    private val pkg = "app.ainexus.ai_nexus"
    private val cls = "app.ainexus.ai_nexus.bubble.RephraseAccessibilityService"

    @Test
    fun `matches both flatten forms Android stores in the enabled-services setting`() {
        assertTrue(
            Watchdog.idsMatch(
                "$pkg/$cls",
                pkg,
                cls,
            ),
        )
        assertTrue(
            Watchdog.idsMatch(
                "$pkg/.bubble.RephraseAccessibilityService",
                pkg,
                cls,
            ),
        )
    }

    @Test
    fun `does not match a different service`() {
        assertFalse(Watchdog.idsMatch("$pkg/.SomeOtherService", pkg, cls))
        assertFalse(Watchdog.idsMatch("", pkg, cls))
        assertFalse(
            Watchdog.idsMatch(
                "com.other/.bubble.RephraseAccessibilityService",
                pkg,
                cls,
            ),
        )
    }
}
