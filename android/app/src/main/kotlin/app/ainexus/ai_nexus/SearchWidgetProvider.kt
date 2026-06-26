package app.ainexus.ai_nexus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews

/**
 * Home-screen "Nexus AI Search" widget.
 *
 * The widget is a small AMOLED glass card with a segmented Expense / Web
 * toggle and a tappable search capsule:
 *  - Tapping a toggle pill broadcasts [ACTION_SET_MODE] back to this provider,
 *    which persists the chosen mode and redraws every widget instance.
 *  - Tapping the capsule launches the app straight into the search that
 *    matches the active mode: the Expense Tracker "Ask AI" search, or the
 *    Tutor online (web) search.
 *
 * Mode is held in a tiny dedicated prefs file so it survives reboots and is
 * independent of the Flutter shared-prefs store.
 */
class SearchWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "NexusSearchWidget"

        private const val PREFS = "NexusSearchWidgetPrefs"
        private const val KEY_MODE = "search_mode"

        const val ACTION_SET_MODE = "app.ainexus.ai_nexus.SEARCH_WIDGET_SET_MODE"
        const val EXTRA_MODE = "mode"

        private const val MODE_EXPENSE = SearchWidgetLogic.MODE_EXPENSE
        private const val MODE_WEB = SearchWidgetLogic.MODE_WEB

        // Accent tint applied to the capsule icons (indigo — matches the AI
        // gradient used across the app).
        private const val ACCENT = 0xFF818CF8.toInt()

        private fun readMode(context: Context): String {
            return try {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                SearchWidgetLogic.normalizeMode(prefs.getString(KEY_MODE, MODE_EXPENSE))
            } catch (e: Exception) {
                Log.w(TAG, "readMode failed — defaulting to expense", e)
                MODE_EXPENSE
            }
        }

        private fun writeMode(context: Context, mode: String) {
            try {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_MODE, mode)
                    .apply()
            } catch (e: Exception) {
                Log.e(TAG, "writeMode failed", e)
            }
        }

        private fun updateAll(context: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = mgr.getAppWidgetIds(
                    ComponentName(context, SearchWidgetProvider::class.java)
                )
                for (id in ids) {
                    try {
                        drawWidget(context, mgr, id)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to redraw widget $id", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "updateAll failed", e)
            }
        }

        private fun drawWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val mode = readMode(context)
            val isExpense = SearchWidgetLogic.isExpense(mode)

            val views = RemoteViews(context.packageName, R.layout.widget_search)

            // ── Segmented toggle visuals ──
            if (isExpense) {
                views.setInt(
                    R.id.widget_search_toggle_expense, "setBackgroundResource",
                    R.drawable.widget_search_toggle_active
                )
                views.setInt(
                    R.id.widget_search_toggle_web, "setBackgroundResource",
                    android.R.color.transparent
                )
                views.setTextColor(R.id.widget_search_toggle_expense, Color.WHITE)
                views.setTextColor(R.id.widget_search_toggle_web, 0xFF6A7187.toInt())
            } else {
                views.setInt(
                    R.id.widget_search_toggle_web, "setBackgroundResource",
                    R.drawable.widget_search_toggle_active
                )
                views.setInt(
                    R.id.widget_search_toggle_expense, "setBackgroundResource",
                    android.R.color.transparent
                )
                views.setTextColor(R.id.widget_search_toggle_web, Color.WHITE)
                views.setTextColor(R.id.widget_search_toggle_expense, 0xFF6A7187.toInt())
            }

            // ── Capsule: mode icon + hint + accent tints ──
            views.setImageViewResource(
                R.id.widget_search_mode_icon,
                if (isExpense) R.drawable.ic_widget_wallet else R.drawable.ic_widget_globe
            )
            views.setInt(R.id.widget_search_mode_icon, "setColorFilter", ACCENT)
            views.setInt(R.id.widget_search_go, "setColorFilter", ACCENT)
            views.setTextViewText(
                R.id.widget_search_hint,
                context.getString(
                    if (isExpense) R.string.widget_search_hint_expense
                    else R.string.widget_search_hint_web
                )
            )

            // ── Click targets ──
            views.setOnClickPendingIntent(
                R.id.widget_search_bar,
                buildLaunchIntent(context, appWidgetId, mode)
            )
            views.setOnClickPendingIntent(
                R.id.widget_search_toggle_expense,
                buildToggleIntent(context, appWidgetId, MODE_EXPENSE)
            )
            views.setOnClickPendingIntent(
                R.id.widget_search_toggle_web,
                buildToggleIntent(context, appWidgetId, MODE_WEB)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d(TAG, "Widget $appWidgetId drawn (mode=$mode)")
        }

        private fun buildLaunchIntent(
            context: Context,
            appWidgetId: Int,
            mode: String
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "app.ainexus.SHORTCUT"
                // The launch contract per mode lives in the pure, tested
                // SearchWidgetLogic so it stays in lock-step with the Flutter
                // routing on the other side.
                for ((k, v) in SearchWidgetLogic.launchExtras(mode)) putExtra(k, v)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            // Include the mode in the request code so a mode flip refreshes the
            // cached PendingIntent extras deterministically.
            val rc = SearchWidgetLogic.searchRequestCode(appWidgetId, mode)
            return PendingIntent.getActivity(
                context, rc, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun buildToggleIntent(
            context: Context,
            appWidgetId: Int,
            mode: String
        ): PendingIntent {
            val intent = Intent(context, SearchWidgetProvider::class.java).apply {
                action = ACTION_SET_MODE
                putExtra(EXTRA_MODE, mode)
            }
            val rc = SearchWidgetLogic.toggleRequestCode(appWidgetId, mode)
            return PendingIntent.getBroadcast(
                context, rc, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_SET_MODE) {
            val mode = SearchWidgetLogic.normalizeMode(intent.getStringExtra(EXTRA_MODE))
            Log.i(TAG, "Mode toggled → $mode")
            writeMode(context, mode)
            updateAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate: ${appWidgetIds.size} widget(s)")
        for (appWidgetId in appWidgetIds) {
            try {
                drawWidget(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $appWidgetId", e)
            }
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        Log.i(TAG, "First search widget placed on home screen")
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        Log.i(TAG, "Last search widget removed from home screen")
    }
}
