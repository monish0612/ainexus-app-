package app.ainexus.ai_nexus.bubble

import android.view.accessibility.AccessibilityWindowInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WindowGateTest {

    @Test
    fun `IME typing events are allowed so a keyboard-open field still settles`() {
        assertTrue(
            WindowGate.shouldHandleTypingEvent(AccessibilityWindowInfo.TYPE_INPUT_METHOD),
        )
        assertTrue(
            WindowGate.shouldHandleTypingEvent(AccessibilityWindowInfo.TYPE_APPLICATION),
        )
        assertTrue(WindowGate.shouldHandleTypingEvent(null))
    }

    @Test
    fun `overlay and system windows never drive the tracker`() {
        assertFalse(
            WindowGate.shouldHandleTypingEvent(
                AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY,
            ),
        )
        assertFalse(
            WindowGate.shouldHandleTypingEvent(AccessibilityWindowInfo.TYPE_SYSTEM),
        )
    }

    @Test
    fun `unknown field window type is usable so a missing windows list cannot hide the bubble`() {
        assertTrue(WindowGate.isUsableFieldWindowType(null))
        assertTrue(
            WindowGate.isUsableFieldWindowType(AccessibilityWindowInfo.TYPE_APPLICATION),
        )
        assertFalse(
            WindowGate.isUsableFieldWindowType(AccessibilityWindowInfo.TYPE_INPUT_METHOD),
        )
        assertFalse(
            WindowGate.isUsableFieldWindowType(
                AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY,
            ),
        )
    }

    @Test
    fun `keyboard opening is not an app switch while WhatsApp is still on screen`() {
        assertFalse(
            WindowGate.isRealAppSwitch(
                targetPackage = "com.whatsapp",
                applicationPackages = setOf("com.whatsapp"),
            ),
        )
    }

    @Test
    fun `empty application window list is not an app switch`() {
        assertFalse(
            WindowGate.isRealAppSwitch(
                targetPackage = "com.whatsapp",
                applicationPackages = emptySet(),
            ),
        )
    }

    @Test
    fun `moving to another app is an app switch`() {
        assertTrue(
            WindowGate.isRealAppSwitch(
                targetPackage = "com.whatsapp",
                applicationPackages = setOf("com.android.chrome"),
            ),
        )
    }

    @Test
    fun `no target yet is never treated as a switch`() {
        assertFalse(
            WindowGate.isRealAppSwitch(
                targetPackage = null,
                applicationPackages = setOf("com.whatsapp"),
            ),
        )
        assertFalse(
            WindowGate.isRealAppSwitch(
                targetPackage = "",
                applicationPackages = setOf("com.whatsapp"),
            ),
        )
    }
}
