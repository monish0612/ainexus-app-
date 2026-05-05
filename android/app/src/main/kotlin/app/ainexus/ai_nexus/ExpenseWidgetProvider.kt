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
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToLong

class ExpenseWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "NexusExpenseWidget"
        private const val PREFS = "FlutterSharedPreferences"
        const val ACTION_MIDNIGHT_REFRESH = "app.ainexus.ai_nexus.MIDNIGHT_WIDGET_REFRESH"
        private const val MIDNIGHT_REQUEST_CODE = 9001

        private val emptyMessages = listOf(
            "no expenses yet — wallet's happy",
            "clean slate today!",
            "zero logged — saving champ!",
            "all quiet on the wallet front",
            "no spends yet — keeping it tight!",
        )

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

        fun formatInrCompact(value: Double, negative: Boolean = false): String {
            val sign = if (negative) "-" else ""
            val v = abs(value)
            val fmt = NumberFormat.getInstance(Locale("en", "IN"))

            return when {
                v >= 1_00_00_000 -> {
                    val cr = v / 1_00_00_000.0
                    if (cr == cr.toLong().toDouble()) "${sign}\u20B9${cr.toLong()}Cr"
                    else "${sign}\u20B9${"%.1f".format(cr)}Cr"
                }
                v >= 1_00_000 -> {
                    val l = v / 1_00_000.0
                    if (l == l.toLong().toDouble()) "${sign}\u20B9${l.toLong()}L"
                    else "${sign}\u20B9${"%.1f".format(l)}L"
                }
                else -> "${sign}\u20B9${fmt.format(v.roundToLong())}"
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
                    fallback.setViewVisibility(R.id.widget_expense_empty, View.VISIBLE)
                    fallback.setViewVisibility(R.id.widget_expense_stats, View.GONE)
                    fallback.setTextViewText(R.id.widget_expense_empty_msg, "Open app to load data")
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

    private data class TimeProgress(
        val dateLabel: String,
        val monthShort: String,
        val yearStr: String,
        val monthPercent: Int,
        val yearPercent: Int,
        val daysLeftMonth: Int,
        val daysLeftYear: Int,
        val dayOfMonth: Int,
        val daysInMonth: Int,
    )

    private fun computeTimeProgress(): TimeProgress {
        val cal = Calendar.getInstance()
        val dateFmt = SimpleDateFormat("EEE, d MMM", Locale.ENGLISH)
        val monthFmt = SimpleDateFormat("MMM", Locale.ENGLISH)

        val dayOfMonth = cal.get(Calendar.DAY_OF_MONTH)
        val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val daysLeftMonth = daysInMonth - dayOfMonth
        val monthPct = (dayOfMonth * 100) / daysInMonth

        val dayOfYear = cal.get(Calendar.DAY_OF_YEAR)
        val year = cal.get(Calendar.YEAR)
        val isLeap = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))
        val daysInYear = if (isLeap) 366 else 365
        val daysLeftYear = daysInYear - dayOfYear
        val yearPct = (dayOfYear * 100) / daysInYear

        return TimeProgress(
            dateLabel = dateFmt.format(cal.time),
            monthShort = monthFmt.format(cal.time),
            yearStr = year.toString(),
            monthPercent = monthPct,
            yearPercent = yearPct,
            daysLeftMonth = daysLeftMonth,
            daysLeftYear = daysLeftYear,
            dayOfMonth = dayOfMonth,
            daysInMonth = daysInMonth,
        )
    }

    private fun applyTimeProgress(views: RemoteViews, tp: TimeProgress, empty: Boolean) {
        if (empty) {
            views.setTextViewText(R.id.widget_expense_empty_month_label, tp.monthShort)
            views.setProgressBar(R.id.widget_expense_empty_month_bar, 100, tp.monthPercent, false)
            views.setTextViewText(R.id.widget_expense_empty_month_pct, "${tp.monthPercent}%")
            views.setTextViewText(R.id.widget_expense_empty_month_left, "${tp.daysLeftMonth}d left")

            views.setTextViewText(R.id.widget_expense_empty_year_label, tp.yearStr)
            views.setProgressBar(R.id.widget_expense_empty_year_bar, 100, tp.yearPercent, false)
            views.setTextViewText(R.id.widget_expense_empty_year_pct, "${tp.yearPercent}%")
            views.setTextViewText(R.id.widget_expense_empty_year_left, "${tp.daysLeftYear}d left")
        } else {
            views.setTextViewText(R.id.widget_expense_month_label, tp.monthShort)
            views.setProgressBar(R.id.widget_expense_month_bar, 100, tp.monthPercent, false)
            views.setTextViewText(R.id.widget_expense_month_pct, "${tp.monthPercent}%")
            views.setTextViewText(R.id.widget_expense_month_left, "${tp.daysLeftMonth}d left")

            views.setTextViewText(R.id.widget_expense_year_label, tp.yearStr)
            views.setProgressBar(R.id.widget_expense_year_bar, 100, tp.yearPercent, false)
            views.setTextViewText(R.id.widget_expense_year_pct, "${tp.yearPercent}%")
            views.setTextViewText(R.id.widget_expense_year_left, "${tp.daysLeftYear}d left")
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val storedDate = prefs.getString("flutter.expense_widget_update_date", "") ?: ""
        val today = todayDateString()
        val storedMonth = if (storedDate.length >= 7) storedDate.substring(0, 7) else ""
        val currentMonth = currentMonthString()
        val isDateStale = storedDate != today
        val isMonthStale = storedMonth != currentMonth

        val rawTodayTotal = safeParseDouble(prefs, "flutter.expense_widget_today_total")
        val rawTodayCount = safeParseInt(prefs, "flutter.expense_widget_today_count")
        val rawMonthSpent = safeParseDouble(prefs, "flutter.expense_widget_month_spent")
        val monthBudget = safeParseDouble(prefs, "flutter.expense_widget_month_budget")

        val todayTotal = if (isDateStale) 0.0 else rawTodayTotal
        val todayCount = if (isDateStale) 0 else rawTodayCount
        val monthSpent = if (isMonthStale) 0.0 else rawMonthSpent

        if (isDateStale) {
            Log.d(TAG, "Date stale ($storedDate vs $today) — zeroing today's data for widget $appWidgetId")
        }

        val tp = computeTimeProgress()

        val intent = Intent(context, MainActivity::class.java).apply {
            action = "app.ainexus.SHORTCUT"
            putExtra("shortcut_tab", "0")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 1000 + appWidgetId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val views = RemoteViews(context.packageName, R.layout.widget_expense)
        views.setOnClickPendingIntent(R.id.widget_expense_root, pendingIntent)

        if (todayCount == 0) {
            // ── Empty state ──
            views.setViewVisibility(R.id.widget_expense_empty, View.VISIBLE)
            views.setViewVisibility(R.id.widget_expense_stats, View.GONE)
            val idx = (System.currentTimeMillis() % emptyMessages.size).toInt()
            views.setTextViewText(R.id.widget_expense_empty_msg, emptyMessages[idx])
            applyTimeProgress(views, tp, empty = true)
        } else {
            // ── Content state ──
            views.setViewVisibility(R.id.widget_expense_empty, View.GONE)
            views.setViewVisibility(R.id.widget_expense_stats, View.VISIBLE)

            // Hero amount
            views.setTextViewText(R.id.widget_expense_total, formatInrCompact(todayTotal))

            // Entry count pill
            val entryText = if (todayCount == 1) "1 entry" else "$todayCount entries"
            views.setTextViewText(R.id.widget_expense_count, entryText)

            applyTimeProgress(views, tp, empty = false)

            // Month spending summary inside time card
            val dailyAvg = if (tp.dayOfMonth > 0) monthSpent / tp.dayOfMonth else 0.0
            views.setTextViewText(
                R.id.widget_expense_month_spent_text,
                "This month  ${formatInrCompact(monthSpent)}"
            )
            views.setTextViewText(
                R.id.widget_expense_daily_avg_text,
                "${formatInrCompact(dailyAvg)}/day"
            )

            // Budget section
            if (monthBudget > 0) {
                val balance = monthBudget - monthSpent
                val isOver = balance < 0
                val percent = ((monthSpent / monthBudget) * 100).toInt()
                val clampedPercent = min(percent, 100)

                if (isOver) {
                    views.setViewVisibility(R.id.widget_expense_progress_blue, View.GONE)
                    views.setViewVisibility(R.id.widget_expense_progress_red, View.VISIBLE)
                    views.setProgressBar(R.id.widget_expense_progress_red, 100, clampedPercent, false)
                    views.setTextColor(R.id.widget_expense_percent, 0xFFFF6B6B.toInt())
                    views.setTextColor(R.id.widget_expense_budget_info, 0xFFFF6B6B.toInt())
                    views.setInt(
                        R.id.widget_expense_budget_section, "setBackgroundResource",
                        R.drawable.widget_expense_stat_red_bg
                    )
                } else {
                    views.setViewVisibility(R.id.widget_expense_progress_blue, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_expense_progress_red, View.GONE)
                    views.setProgressBar(R.id.widget_expense_progress_blue, 100, clampedPercent, false)
                    views.setTextColor(R.id.widget_expense_percent, 0xFF64748B.toInt())
                    views.setTextColor(R.id.widget_expense_budget_info, 0xFF64748B.toInt())
                    views.setInt(
                        R.id.widget_expense_budget_section, "setBackgroundResource",
                        R.drawable.widget_expense_stat_bg
                    )
                }

                views.setTextViewText(R.id.widget_expense_percent, "${percent}%")

                val budgetStr = formatInrCompact(monthBudget)
                val diffStr = formatInrCompact(abs(balance))
                val infoText = if (isOver) {
                    "Budget $budgetStr  ·  $diffStr over"
                } else {
                    "Budget $budgetStr  ·  $diffStr left"
                }
                views.setTextViewText(R.id.widget_expense_budget_info, infoText)
            } else {
                views.setViewVisibility(R.id.widget_expense_progress_blue, View.VISIBLE)
                views.setViewVisibility(R.id.widget_expense_progress_red, View.GONE)
                views.setProgressBar(R.id.widget_expense_progress_blue, 100, 0, false)
                views.setTextViewText(R.id.widget_expense_percent, "—")
                views.setTextViewText(R.id.widget_expense_budget_info, "No budget set")
                views.setTextColor(R.id.widget_expense_percent, 0xFF3D3D4A.toInt())
                views.setTextColor(R.id.widget_expense_budget_info, 0xFF3D3D4A.toInt())
                views.setInt(
                    R.id.widget_expense_budget_section, "setBackgroundResource",
                    R.drawable.widget_expense_stat_bg
                )
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
        Log.d(TAG, "Widget $appWidgetId updated OK: count=$todayCount total=$todayTotal budget=$monthBudget spent=$monthSpent tp=$tp")
    }
}
