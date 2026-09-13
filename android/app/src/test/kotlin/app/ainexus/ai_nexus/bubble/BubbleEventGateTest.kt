package app.ainexus.ai_nexus.bubble

import android.view.accessibility.AccessibilityWindowInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Gate that decides whether a typing event may drive the bubble. Locks the
 * "bubble works inside Nexus" fix: APPLICATION windows from our own package are
 * allowed; IME-sourced keystrokes are allowed (keyboard-open typing); overlay
 * and system windows are not.
 */
class BubbleEventGateTest {

    private val own = "app.ainexus.ai_nexus"

    @Test
    fun `Nexus APPLICATION window is allowed`() {
        assertTrue(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = own,
                ownPackage = own,
                windowId = 1,
                windowType = AccessibilityWindowInfo.TYPE_APPLICATION,
            ),
        )
    }

    @Test
    fun `foreign APPLICATION window is allowed`() {
        assertTrue(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = "com.whatsapp",
                ownPackage = own,
                windowId = 2,
                windowType = AccessibilityWindowInfo.TYPE_APPLICATION,
            ),
        )
    }

    @Test
    fun `accessibility overlay window is rejected even from our package`() {
        assertFalse(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = own,
                ownPackage = own,
                windowId = 3,
                windowType = AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY,
            ),
        )
    }

    @Test
    fun `IME window is allowed so typing with the keyboard open still settles`() {
        assertTrue(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = "com.google.android.inputmethod.latin",
                ownPackage = own,
                windowId = 4,
                windowType = AccessibilityWindowInfo.TYPE_INPUT_METHOD,
            ),
        )
    }

    @Test
    fun `system window is rejected`() {
        assertFalse(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = "com.android.systemui",
                ownPackage = own,
                windowId = 5,
                windowType = AccessibilityWindowInfo.TYPE_SYSTEM,
            ),
        )
    }

    @Test
    fun `unknown window type is allowed so a missing window list never kills the bubble`() {
        assertTrue(
            RephraseAccessibilityService.shouldHandleTypingEvent(
                sourcePackage = "com.whatsapp",
                ownPackage = own,
                windowId = 6,
                windowType = null,
            ),
        )
    }
}
