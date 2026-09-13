package app.ainexus.ai_nexus.bubble

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Reads and replaces text in the focused editable node of any app.
 *
 * Replacement contract:
 *   1) ACTION_SET_TEXT — if performAction returns true, we STOP. Never fall
 *      through to PASTE (that was the double-paste bug: verify failed on
 *      trailing newlines / ZWSP and PASTE then appended).
 *   2) select-all + clipboard + ACTION_PASTE — only when SET_TEXT is unsupported
 *      or performAction returned false. Select-all must succeed or we BLOCKED.
 *   3) BLOCKED — the panel then auto-copies and says so
 *
 * Nothing here throws: a stale node must never take down the service.
 */
object NodeTextIO {
    private const val TAG = "BubbleNodeIO"

    enum class Outcome { REPLACED_SET_TEXT, REPLACED_PASTE, BLOCKED }

    /** Safe read of the current text. Never returns password content. */
    fun readText(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        return try {
            node.refresh()
            if (node.isPassword) null else node.text?.toString()
        } catch (t: Throwable) {
            Log.w(TAG, "readText on stale node", t)
            null
        }
    }

    /** True if we must not touch this field. */
    fun isProtected(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return true
        return try {
            node.isPassword || !node.isEditable || !node.isEnabled
        } catch (t: Throwable) {
            true
        }
    }

    fun copyToClipboard(context: Context, text: String) {
        try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("rephrase", text))
        } catch (t: Throwable) {
            Log.w(TAG, "clipboard write failed", t)
        }
    }

    fun replace(
        context: Context,
        node: AccessibilityNodeInfo?,
        newText: String,
    ): Outcome {
        if (node == null || isProtected(node) || newText.isEmpty()) return Outcome.BLOCKED

        // Primary: ACTION_SET_TEXT.
        try {
            node.refresh()
            val supportsSetText = node.actionList.any {
                it.id == AccessibilityNodeInfo.ACTION_SET_TEXT
            }
            if (supportsSetText) {
                val args = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        newText,
                    )
                }
                val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                // Critical: a successful SET_TEXT must never fall through to PASTE.
                // verify() can false-fail on trailing newlines / zero-width spaces;
                // pasting after a real write is what produced the duplicate text.
                if (ok) {
                    if (!verify(node, newText)) {
                        Log.w(TAG, "SET_TEXT ok but verify soft-failed; not pasting")
                    }
                    restoreCaret(node, newText.length)
                    return Outcome.REPLACED_SET_TEXT
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "SET_TEXT failed", t)
        }

        // Fallback: select-all + clipboard + PASTE. Needs the node focused.
        // Append-proof: if we cannot select the full existing text, abort —
        // PASTEing without a full selection would append and duplicate.
        try {
            node.refresh()
            node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            node.refresh()
            val len = node.text?.length ?: 0
            if (len > 0) {
                val sel = Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, len)
                }
                val selected = node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, sel)
                if (!selected) {
                    Log.w(TAG, "select-all failed; refusing PASTE to avoid append")
                    return Outcome.BLOCKED
                }
            }
            copyToClipboard(context, newText)
            val pasted = node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            if (pasted) {
                if (!verify(node, newText)) {
                    Log.w(TAG, "PASTE ok but verify soft-failed")
                }
                restoreCaret(node, newText.length)
                return Outcome.REPLACED_PASTE
            }
        } catch (t: Throwable) {
            Log.w(TAG, "PASTE fallback failed", t)
        }

        return Outcome.BLOCKED
    }

    /**
     * Soft equality for write-back verification: trim, strip trailing newlines
     * and zero-width spaces that some editors inject after SET_TEXT / PASTE.
     */
    fun normalizeForCompare(text: String): String =
        text
            .replace("\u200B", "")
            .replace("\uFEFF", "")
            .trim()
            .trimEnd('\n', '\r')

    private fun verify(node: AccessibilityNodeInfo, expected: String): Boolean = try {
        node.refresh()
        val actual = node.text?.toString()
        actual != null && normalizeForCompare(actual) == normalizeForCompare(expected)
    } catch (t: Throwable) {
        // Can't verify; assume success rather than double-writing.
        true
    }

    private fun restoreCaret(node: AccessibilityNodeInfo, pos: Int) {
        try {
            val args = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, pos)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, pos)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, args)
        } catch (t: Throwable) {
            // Non-fatal.
        }
    }
}
