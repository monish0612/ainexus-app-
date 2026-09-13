package app.ainexus.ai_nexus.bubble

import android.view.accessibility.AccessibilityWindowInfo

/**
 * Pure window-type and app-switch rules for the rephrase bubble.
 *
 * Kept off [RephraseAccessibilityService] so the cases that used to swallow the
 * bubble (IME becoming "the active window", an empty `windows` list) can be
 * locked down without a device.
 */
object WindowGate {

    /**
     * Whether a typing event may drive the tracker.
     *
     * IME-sourced TEXT_CHANGED is allowed: with the keyboard open, Android often
     * tags keystrokes as the input-method window, not WhatsApp. Overlay and
     * system UI must still be dropped so our own panel cannot re-feed the
     * tracker. Unknown type is allowed so a missing window list cannot kill it.
     */
    fun shouldHandleTypingEvent(windowType: Int?): Boolean {
        if (windowType == null) return true
        return windowType != AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY &&
            windowType != AccessibilityWindowInfo.TYPE_SYSTEM
    }

    /**
     * Whether a focused node is in a window we may rephrase.
     *
     * Unknown (null) is allowed — matching [shouldHandleTypingEvent] — so
     * `getWindows()` lag cannot reject every field.
     */
    fun isUsableFieldWindowType(windowType: Int?): Boolean {
        if (windowType == null) return true
        return windowType == AccessibilityWindowInfo.TYPE_APPLICATION
    }

    /**
     * True only when the user has actually left the app that owns [targetPackage].
     *
     * The IME, status bar, and our overlay all change the "active" window without
     * replacing the application window. If we treated that as an app switch the
     * bubble vanished the moment the keyboard opened — the exact moment you type.
     */
    fun isRealAppSwitch(
        targetPackage: String?,
        applicationPackages: Set<String>,
    ): Boolean {
        if (applicationPackages.isEmpty()) return false
        val target = targetPackage?.takeIf { it.isNotEmpty() } ?: return false
        return target !in applicationPackages
    }
}
