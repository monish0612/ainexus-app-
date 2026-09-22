package app.ainexus.ai_nexus.bubble

import android.content.Context
import android.content.SharedPreferences

/**
 * Master switch + gates for the floating bubble, stored natively.
 *
 * Native owns this flag (rather than Flutter's shared_preferences) because the
 * accessibility service can be running long before — or entirely without — the
 * Flutter UI having been launched. MainActivity mirrors it into the settings
 * screen over [Channels.SETTINGS_METHOD].
 */
object BubblePrefs {
    private const val FILE = "bubble_prefs"
    private const val KEY_ENABLED = "bubble_enabled"
    private const val KEY_MIN_CHARS = "bubble_min_chars"
    private const val KEY_SKIP_PACKAGES = "bubble_skip_packages"
    private const val KEY_POS_SIDE = "bubble_pos_side"
    private const val KEY_POS_X_FRACTION = "bubble_pos_x_fraction"
    private const val KEY_POS_Y_FRACTION = "bubble_pos_y_fraction"
    private const val KEY_LAST_PLATFORM = "bubble_last_platform"

    const val DEFAULT_MIN_CHARS = 8

    @Volatile private var enabledCache: Boolean? = null
    @Volatile private var minCharsCache: Int? = null

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Defaults on: enabling the accessibility service is already an opt-in. */
    fun isEnabled(context: Context): Boolean {
        enabledCache?.let { return it }
        val value = prefs(context).getBoolean(KEY_ENABLED, true)
        enabledCache = value
        return value
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        enabledCache = enabled
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    /** Shortest field text that is worth offering a rephrase for. */
    fun minChars(context: Context): Int {
        minCharsCache?.let { return it }
        val value = prefs(context).getInt(KEY_MIN_CHARS, DEFAULT_MIN_CHARS).coerceAtLeast(1)
        minCharsCache = value
        return value
    }

    fun setMinChars(context: Context, value: Int) {
        val clamped = value.coerceIn(1, 500)
        minCharsCache = clamped
        prefs(context).edit().putInt(KEY_MIN_CHARS, clamped).apply()
    }

    @Volatile private var skipRaw: String? = null
    @Volatile private var skipParsed: Set<String> = emptySet()

    /**
     * Packages the bubble must never appear over (comma separated).
     *
     * Consulted on every keystroke in every app, so the parsed set is memoised
     * against the stored string rather than rebuilt each time.
     */
    fun skipPackages(context: Context): Set<String> {
        val raw = prefs(context).getString(KEY_SKIP_PACKAGES, "") ?: ""
        if (raw == skipRaw) return skipParsed
        val parsed = raw.split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()
        skipRaw = raw
        skipParsed = parsed
        return parsed
    }

    fun setSkipPackages(context: Context, packages: Collection<String>) {
        prefs(context)
            .edit()
            .putString(KEY_SKIP_PACKAGES, packages.joinToString(","))
            .apply()
    }

    // ── Remembered bubble position ───────────────────────────────────────────

    /** True once the user has freely placed the bubble. Legacy left/right snaps
     *  are ignored so a previous chat-head park does not pin it to Send/emoji. */
    fun hasSavedPosition(context: Context): Boolean =
        prefs(context).contains(KEY_POS_X_FRACTION)

    /**
     * Horizontal resting place as a 0–1 fraction of the clamp range.
     * Legacy left/right snaps map to 0 / 1 until the user drags again.
     */
    fun savedXFraction(context: Context): Double {
        val p = prefs(context)
        if (p.contains(KEY_POS_X_FRACTION)) {
            return p.getFloat(KEY_POS_X_FRACTION, 0.5f).toDouble().coerceIn(0.0, 1.0)
        }
        return when (p.getString(KEY_POS_SIDE, null)) {
            "left" -> 0.0
            "right" -> 1.0
            else -> 0.5
        }
    }

    /** Vertical resting place as a fraction of screen height (rotation-proof). */
    fun savedYFraction(context: Context): Double =
        prefs(context).getFloat(KEY_POS_Y_FRACTION, 0.5f).toDouble().coerceIn(0.0, 1.0)

    fun saveFreePosition(context: Context, xFraction: Double, yFraction: Double) {
        prefs(context)
            .edit()
            .putFloat(KEY_POS_X_FRACTION, xFraction.toFloat().coerceIn(0f, 1f))
            .putFloat(KEY_POS_Y_FRACTION, yFraction.toFloat().coerceIn(0f, 1f))
            .remove(KEY_POS_SIDE)
            .apply()
    }

    // ── Last-used rephrase chip ──────────────────────────────────────────────

    /** Platform id of the last successful rephrase, or null if never used. */
    fun lastPlatformId(context: Context): String? =
        prefs(context).getString(KEY_LAST_PLATFORM, null)?.takeIf { it.isNotBlank() }

    fun setLastPlatformId(context: Context, platformId: String) {
        val id = platformId.trim()
        if (id.isEmpty()) return
        prefs(context).edit().putString(KEY_LAST_PLATFORM, id).apply()
    }
}
