package app.ainexus.ai_nexus

/**
 * Pure, framework-free decision logic for the home-screen search widget.
 *
 * Everything here is deterministic and free of Android dependencies so it can
 * be unit-tested on a plain JVM (no Robolectric/emulator). [SearchWidgetProvider]
 * delegates all of its "what mode / where to launch / which request code"
 * decisions here and only keeps the RemoteViews / PendingIntent plumbing.
 */
object SearchWidgetLogic {

    const val MODE_EXPENSE = "expense"
    const val MODE_WEB = "web"

    // PendingIntent request-code lanes. The search-capsule launch encodes the
    // widget id (×2) plus the mode bit; the toggle broadcasts use separate
    // bases offset by the widget id. The lanes are spaced so they never
    // collide for any realistic widget-id count.
    const val RC_SEARCH = 5000
    const val RC_TOGGLE_EXPENSE = 6000
    const val RC_TOGGLE_WEB = 7000

    /** Coerces any stored/extra value to a valid mode; defaults to Expense. */
    fun normalizeMode(raw: String?): String =
        if (raw == MODE_WEB) MODE_WEB else MODE_EXPENSE

    fun isExpense(mode: String): Boolean = normalizeMode(mode) == MODE_EXPENSE

    /**
     * The activity intent extras used to launch the app for a given mode.
     *  - Expense → Expense Tracker "Ask AI" search (tab 0).
     *  - Web     → Tutor → Summarizer online search (tab 2, reusing the
     *              legacy widget-launch contract so the field auto-focuses).
     */
    fun launchExtras(mode: String): Map<String, String> {
        return if (normalizeMode(mode) == MODE_WEB) {
            mapOf(
                "widget_search_mode" to MODE_WEB,
                "shortcut_tab" to "2",
                "shortcut_subtab" to "0",
                "widget_launch" to "true",
            )
        } else {
            mapOf(
                "widget_search_mode" to MODE_EXPENSE,
                "shortcut_tab" to "0",
            )
        }
    }

    /** Stable, per-(widget, mode) request code for the search-capsule launch. */
    fun searchRequestCode(appWidgetId: Int, mode: String): Int =
        RC_SEARCH + appWidgetId * 2 + (if (normalizeMode(mode) == MODE_WEB) 1 else 0)

    /** Stable, per-(widget, mode) request code for a toggle-pill broadcast. */
    fun toggleRequestCode(appWidgetId: Int, mode: String): Int =
        (if (normalizeMode(mode) == MODE_EXPENSE) RC_TOGGLE_EXPENSE else RC_TOGGLE_WEB) + appWidgetId
}
