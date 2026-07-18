package app.ainexus.ai_nexus

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class ExpenseWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "NexusExpenseWidget"
        private const val PREFS = "FlutterSharedPreferences"
        const val ACTION_MIDNIGHT_REFRESH = "app.ainexus.ai_nexus.MIDNIGHT_WIDGET_REFRESH"
        private const val MIDNIGHT_REQUEST_CODE = 9001

        fun triggerUpdate(context: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = mgr.getAppWidgetIds(
                    ComponentName(context, ExpenseWidgetProvider::class.java)
                )
                if (ids.isNotEmpty()) {
                    val intent = Intent(context, ExpenseWidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    context.sendBroadcast(intent)
                    Log.d(TAG, "Triggered update for ${ids.size} widget(s)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "triggerUpdate failed", e)
            }
        }

        fun scheduleMidnightAlarm(context: Context) {
            try {
                val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

                val intent = Intent(context, ExpenseWidgetProvider::class.java).apply {
                    action = ACTION_MIDNIGHT_REFRESH
                }
                val pi = PendingIntent.getBroadcast(
                    context, MIDNIGHT_REQUEST_CODE, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val midnight = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, 1)
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 3)
                    set(Calendar.MILLISECOND, 0)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmMgr.canScheduleExactAlarms()) {
                        alarmMgr.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, midnight.timeInMillis, pi
                        )
                    } else {
                        alarmMgr.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, midnight.timeInMillis, pi
                        )
                    }
                } else {
                    alarmMgr.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, midnight.timeInMillis, pi
                    )
                }

                Log.d(TAG, "Midnight alarm scheduled for ${midnight.time}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule midnight alarm", e)
            }
        }

        private fun todayDateString(): String {
            return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Calendar.getInstance().time)
        }

        private fun currentMonthString(): String {
            return SimpleDateFormat("yyyy-MM", Locale.US).format(Calendar.getInstance().time)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MIDNIGHT_REFRESH) {
            Log.i(TAG, "Midnight refresh alarm fired")
            triggerUpdate(context)
            scheduleMidnightAlarm(context)
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
        for (id in appWidgetIds) {
            try {
                updateWidget(context, appWidgetManager, id)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $id", e)
                try {
                    val fallback = RemoteViews(context.packageName, R.layout.widget_expense)
                    fallback.setTextViewText(R.id.widget_expense_total, "₹0")
                    fallback.setTextViewText(R.id.widget_expense_subtitle, "Open app to load data")
                    fallback.setOnClickPendingIntent(
                        R.id.widget_expense_root,
                        buildLaunchIntent(context, id, ExpenseWidgetLogic.LANE_ROOT, emptyMap())
                    )
                    appWidgetManager.updateAppWidget(id, fallback)
                } catch (fallbackErr: Exception) {
                    Log.e(TAG, "Fallback also failed for $id", fallbackErr)
                }
            }
        }
        scheduleMidnightAlarm(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        Log.i(TAG, "First expense widget placed")
        scheduleMidnightAlarm(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        Log.i(TAG, "Last expense widget removed")
        try {
            val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, ExpenseWidgetProvider::class.java).apply {
                action = ACTION_MIDNIGHT_REFRESH
            }
            val pi = PendingIntent.getBroadcast(
                context, MIDNIGHT_REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmMgr.cancel(pi)
            Log.d(TAG, "Midnight alarm cancelled — no more widgets")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel midnight alarm", e)
        }
    }

    private fun safeParseDouble(prefs: android.content.SharedPreferences, key: String): Double {
        return try {
            val raw = prefs.getAll()[key]
            when (raw) {
                is String -> raw.toDoubleOrNull() ?: 0.0
                is Long -> java.lang.Double.longBitsToDouble(raw)
                is Float -> raw.toDouble()
                is Double -> raw
                else -> 0.0
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read $key", e)
            0.0
        }
    }

    private fun safeParseInt(prefs: android.content.SharedPreferences, key: String): Int {
        return try {
            val raw = prefs.getAll()[key]
            when (raw) {
                is Long -> raw.toInt()
                is Int -> raw
                is String -> raw.toIntOrNull() ?: 0
                else -> 0
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read $key", e)
            0
        }
    }

    /** Parses a `#RRGGBB` string, falling back to [fallback] on any malformed input. */
    private fun parseColorOr(hex: String, fallback: Int): Int =
        ExpenseWidgetLogic.parseHexColor(hex) ?: fallback

    private fun applyTimeProgress(views: RemoteViews, tp: ExpenseWidgetLogic.TimeProgress) {
        views.setTextViewText(R.id.widget_expense_month_label, tp.monthShort)
        views.setProgressBar(R.id.widget_expense_month_bar, 100, tp.monthPercent, false)
        views.setTextViewText(R.id.widget_expense_month_pct, "${tp.monthPercent}%")
        views.setTextViewText(R.id.widget_expense_month_left, "${tp.daysLeftMonth}d left")

        views.setTextViewText(R.id.widget_expense_year_label, tp.yearStr)
        views.setProgressBar(R.id.widget_expense_year_bar, 100, tp.yearPercent, false)
        views.setTextViewText(R.id.widget_expense_year_pct, "${tp.yearPercent}%")
        views.setTextViewText(R.id.widget_expense_year_left, "${tp.daysLeftYear}d left")
    }

    /**
     * Builds a tap target that re-launches the app with [extras] attached.
     *
     * Each ([appWidgetId], [lane]) pair gets a unique request code, which alone
     * makes the three PendingIntents distinct: PendingIntent identity is
     * (requestCode, Intent.filterEquals, flags), so different request codes never
     * collapse — even though extras aren't part of `filterEquals`. Mirrors the
     * proven [SearchWidgetProvider] scheme.
     *
     * IMPORTANT: do NOT set `intent.data` here. Flutter's deep-linking engine
     * forwards the launch Intent's data Uri to GoRouter as a navigation
     * location, which would surface a spurious "Page Not Found" route. The
     * action + extras + request code are sufficient and side-effect free.
     */
    private fun buildLaunchIntent(
        context: Context,
        appWidgetId: Int,
        lane: Int,
        extras: Map<String, String>,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "app.ainexus.SHORTCUT"
            putExtra("shortcut_tab", "0")
            for ((k, v) in extras) putExtra(k, v)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val requestCode = ExpenseWidgetLogic.launchRequestCode(appWidgetId, lane)
        return PendingIntent.getActivity(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val storedDate = prefs.getString("flutter.expense_widget_update_date", "") ?: ""
        val today = todayDateString()
        val currentMonth = currentMonthString()
        val isDateStale = ExpenseWidgetLogic.isDateStale(storedDate, today)
        val isMonthStale = ExpenseWidgetLogic.isMonthStale(storedDate, currentMonth)

        val rawTodayTotal = safeParseDouble(prefs, "flutter.expense_widget_today_total")
        val rawTodayCount = safeParseInt(prefs, "flutter.expense_widget_today_count")
        val rawMonthSpent = safeParseDouble(prefs, "flutter.expense_widget_month_spent")
        val monthBudget = safeParseDouble(prefs, "flutter.expense_widget_month_budget")
        val rawMonthCount = safeParseInt(prefs, "flutter.expense_widget_month_count")
        val rawTopName = prefs.getString("flutter.expense_widget_top_cat_name", "") ?: ""
        val rawTopEmoji = prefs.getString("flutter.expense_widget_top_cat_emoji", "") ?: ""
        val rawTopAmount = safeParseDouble(prefs, "flutter.expense_widget_top_cat_amount")
        val rawTopColor = prefs.getString("flutter.expense_widget_top_cat_color", "") ?: ""

        val todayTotal = if (isDateStale) 0.0 else rawTodayTotal
        val todayCount = if (isDateStale) 0 else rawTodayCount
        val monthSpent = if (isMonthStale) 0.0 else rawMonthSpent
        val monthCount = if (isMonthStale) 0 else rawMonthCount
        val topName = ExpenseWidgetLogic.effectiveTopName(rawTopName, isMonthStale)
        val topEmoji = ExpenseWidgetLogic.topEmoji(rawTopEmoji, isMonthStale)
        val topAmount = if (isMonthStale) 0.0 else rawTopAmount
        val topColor = if (isMonthStale) "" else rawTopColor

        if (isDateStale) {
            Log.d(TAG, "Date stale ($storedDate vs $today) — zeroing today's data for widget $appWidgetId")
        }

        val tp = ExpenseWidgetLogic.computeTimeProgress(Calendar.getInstance())

        val views = RemoteViews(context.packageName, R.layout.widget_expense)

        // ── Tap targets ──
        // Whole card → Expense Tracker.
        views.setOnClickPendingIntent(
            R.id.widget_expense_root,
            buildLaunchIntent(context, appWidgetId, ExpenseWidgetLogic.LANE_ROOT, emptyMap())
        )
        // "Add" pill → Expense Tracker + open the Add-expense sheet.
        views.setOnClickPendingIntent(
            R.id.widget_expense_action_add,
            buildLaunchIntent(context, appWidgetId, ExpenseWidgetLogic.LANE_ADD, mapOf("expense_action" to "add"))
        )
        // "Ask AI" pill → Expense Tracker + open the Ask-AI search (proven path).
        views.setOnClickPendingIntent(
            R.id.widget_expense_action_ai,
            buildLaunchIntent(context, appWidgetId, ExpenseWidgetLogic.LANE_AI, mapOf("widget_search_mode" to "expense"))
        )

        // ── Hero: today's spend ──
        views.setTextViewText(R.id.widget_expense_total, ExpenseWidgetLogic.formatInrCompact(todayTotal))
        if (todayCount == 0) {
            views.setTextViewText(
                R.id.widget_expense_subtitle,
                ExpenseWidgetLogic.emptyMessage(System.currentTimeMillis())
            )
        } else {
            views.setTextViewText(R.id.widget_expense_subtitle, ExpenseWidgetLogic.entrySubtitle(todayCount))
        }
        views.setTextViewText(R.id.widget_expense_count, ExpenseWidgetLogic.countChip(todayCount))

        val dailyAvg = ExpenseWidgetLogic.dailyAvg(monthSpent, tp.dayOfMonth)

        // ── Stat cards vs. empty state ──
        // With nothing logged this month the two stat cards read as broken
        // ("₹0" / "📦 —"), so swap in a single intentional "getting started"
        // panel that taps straight to Add. Once an entry syncs in, the real
        // cards return automatically.
        if (ExpenseWidgetLogic.isMonthEmpty(monthCount)) {
            views.setViewVisibility(R.id.widget_expense_stats_row, View.GONE)
            views.setViewVisibility(R.id.widget_expense_stats_empty, View.VISIBLE)
            views.setOnClickPendingIntent(
                R.id.widget_expense_stats_empty,
                buildLaunchIntent(context, appWidgetId, ExpenseWidgetLogic.LANE_ADD, mapOf("expense_action" to "add"))
            )
        } else {
            views.setViewVisibility(R.id.widget_expense_stats_row, View.VISIBLE)
            views.setViewVisibility(R.id.widget_expense_stats_empty, View.GONE)

            // ── This Month stat card ──
            views.setTextViewText(R.id.widget_expense_month_value, ExpenseWidgetLogic.formatInrCompact(monthSpent))
            views.setTextViewText(
                R.id.widget_expense_month_caption,
                ExpenseWidgetLogic.monthCaption(monthCount, dailyAvg)
            )

            // ── Top Category stat card ──
            views.setTextViewText(R.id.widget_expense_topcat_emoji, topEmoji)
            if (topName.isEmpty()) {
                views.setTextViewText(R.id.widget_expense_topcat_name, "—")
                views.setTextViewText(R.id.widget_expense_topcat_amount, "₹0")
                views.setTextColor(R.id.widget_expense_topcat_amount, 0xFF566377.toInt())
            } else {
                views.setTextViewText(R.id.widget_expense_topcat_name, topName)
                views.setTextViewText(R.id.widget_expense_topcat_amount, ExpenseWidgetLogic.formatInrCompact(topAmount))
                views.setTextColor(R.id.widget_expense_topcat_amount, parseColorOr(topColor, 0xFF8A95A6.toInt()))
            }
        }

        applyTimeProgress(views, tp)

        // ── Budget card ──
        val budget = ExpenseWidgetLogic.computeBudget(monthBudget, monthSpent, tp.daysLeftMonth, dailyAvg)
        when {
            !budget.hasBudget -> {
                views.setViewVisibility(R.id.widget_expense_progress_blue, View.VISIBLE)
                views.setViewVisibility(R.id.widget_expense_progress_red, View.GONE)
                views.setProgressBar(R.id.widget_expense_progress_blue, 100, 0, false)
                views.setTextColor(R.id.widget_expense_percent, 0xFF4C5A6E.toInt())
                views.setTextColor(R.id.widget_expense_budget_info, 0xFF566377.toInt())
            }
            budget.isOver -> {
                views.setViewVisibility(R.id.widget_expense_progress_blue, View.GONE)
                views.setViewVisibility(R.id.widget_expense_progress_red, View.VISIBLE)
                views.setProgressBar(R.id.widget_expense_progress_red, 100, budget.clampedPercent, false)
                views.setTextColor(R.id.widget_expense_percent, 0xFFFF6B6B.toInt())
                views.setTextColor(R.id.widget_expense_budget_info, 0xFFFF8787.toInt())
            }
            else -> {
                views.setViewVisibility(R.id.widget_expense_progress_blue, View.VISIBLE)
                views.setViewVisibility(R.id.widget_expense_progress_red, View.GONE)
                views.setProgressBar(R.id.widget_expense_progress_blue, 100, budget.clampedPercent, false)
                views.setTextColor(R.id.widget_expense_percent, 0xFF7C8BA0.toInt())
                views.setTextColor(R.id.widget_expense_budget_info, 0xFF566377.toInt())
            }
        }
        views.setTextViewText(R.id.widget_expense_percent, budget.percentText)
        views.setTextViewText(R.id.widget_expense_budget_info, budget.infoText)

        appWidgetManager.updateAppWidget(appWidgetId, views)
        Log.d(TAG, "Widget $appWidgetId updated OK: count=$todayCount total=$todayTotal budget=$monthBudget spent=$monthSpent month#=$monthCount top=$topName tp=$tp")
    }
}
