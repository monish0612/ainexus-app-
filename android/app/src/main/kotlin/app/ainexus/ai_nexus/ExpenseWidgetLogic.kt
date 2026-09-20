package app.ainexus.ai_nexus

import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * Pure, framework-free decision/format logic for the Expense home-screen widget.
 *
 * Everything here is deterministic and free of Android `View`/`RemoteViews`
 * dependencies so it can be unit-tested on a plain JVM (no Robolectric /
 * emulator). [ExpenseWidgetProvider] delegates all of its number-crunching and
 * text-building here and only keeps the RemoteViews / PendingIntent plumbing.
 */
object ExpenseWidgetLogic {

    /** Friendly rotating copy for the zero-spend hero subtitle. */
    val EMPTY_MESSAGES = listOf(
        "no expenses yet — wallet's happy",
        "clean slate today!",
        "zero logged — saving champ!",
        "all quiet on the wallet front",
        "no spends yet — keeping it tight!",
    )

    /** Shown when there is no top category (or month rolled over). */
    const val FALLBACK_EMOJI = "📦"

    // ── Tap-target lanes / request codes ─────────────────────────────────────
    // Each widget exposes three independent tap targets. Request codes are
    // spaced by 4 per widget id so lanes never collide, and the 10_000 base
    // keeps them clear of the search widget's 5_000–7_999 lanes.
    const val LANE_ROOT = 0
    const val LANE_ADD = 1
    const val LANE_AI = 2
    const val RC_BASE = 10_000

    fun launchRequestCode(appWidgetId: Int, lane: Int): Int = RC_BASE + appWidgetId * 4 + lane

    // ── INR compact formatting ───────────────────────────────────────────────

    /**
     * Compact Indian-locale currency: `₹999`, `₹12,345`, `₹1.2L`, `₹3Cr`.
     * Shared by the hero (today) and the donut hole (month) so a lakh-scale
     * amount like 120345 becomes `₹1.2L` — never a full `₹1,20,345` that
     * would paint over the ring.
     */
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

    // ── Time progress (month / year bars) ────────────────────────────────────

    data class TimeProgress(
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

    /** Computes month/year elapsed progress for the given calendar instant. */
    fun computeTimeProgress(cal: Calendar): TimeProgress {
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

    // ── Staleness (zeroing yesterday's / last month's data) ──────────────────

    fun monthOf(date: String): String = if (date.length >= 7) date.substring(0, 7) else ""

    fun isDateStale(storedDate: String, today: String): Boolean = storedDate != today

    fun isMonthStale(storedDate: String, currentMonth: String): Boolean =
        monthOf(storedDate) != currentMonth

    // ── Hero (today's spend) ─────────────────────────────────────────────────

    /** Deterministic rotation; safe for any (even negative) clock value. */
    fun emptyMessage(nowMs: Long): String =
        EMPTY_MESSAGES[Math.floorMod(nowMs, EMPTY_MESSAGES.size.toLong()).toInt()]

    fun entrySubtitle(todayCount: Int): String = when {
        todayCount <= 0 -> ""
        todayCount == 1 -> "1 entry today"
        else -> "$todayCount entries today"
    }

    fun countChip(todayCount: Int): String = todayCount.coerceAtLeast(0).toString()

    // ── This-month stat card ─────────────────────────────────────────────────

    fun dailyAvg(monthSpent: Double, dayOfMonth: Int): Double =
        if (dayOfMonth > 0) monthSpent / dayOfMonth else 0.0

    /**
     * True when there's nothing to show in the stat cards this month, so the
     * widget should render the friendly "getting started" panel instead of two
     * empty cards. Defensive against negative counts.
     */
    fun isMonthEmpty(monthCount: Int): Boolean = monthCount <= 0

    fun monthCaption(monthCount: Int, dailyAvg: Double): String = when {
        monthCount <= 0 -> "no entries yet"
        monthCount == 1 -> "1 entry · ${formatInrCompact(dailyAvg)}/day"
        else -> "$monthCount entries · ${formatInrCompact(dailyAvg)}/day"
    }

    // ── Top-category stat card ───────────────────────────────────────────────

    /** Effective emoji: real emoji, or 📦 when missing / month rolled over. */
    fun topEmoji(rawEmoji: String, isMonthStale: Boolean): String =
        if (isMonthStale || rawEmoji.isEmpty()) FALLBACK_EMOJI else rawEmoji

    /** Effective name after month-staleness gating. */
    fun effectiveTopName(rawName: String, isMonthStale: Boolean): String =
        if (isMonthStale) "" else rawName

    // ── Budget card ──────────────────────────────────────────────────────────

    data class BudgetDisplay(
        val hasBudget: Boolean,
        val isOver: Boolean,
        val percent: Int,        // raw, may exceed 100
        val clampedPercent: Int, // for the progress bar (0..100)
        val percentText: String, // "42%" or "—"
        val infoText: String,
    )

    /**
     * The single source of truth for the budget pill: percent, over/under, the
     * progress value, and the human-readable "₹X left · ₹Y/day to stay on track"
     * (or over-budget / no-budget) line.
     */
    fun computeBudget(
        monthBudget: Double,
        monthSpent: Double,
        daysLeftMonth: Int,
        dailyAvg: Double,
    ): BudgetDisplay {
        if (monthBudget <= 0) {
            val info = if (monthSpent > 0) {
                "No budget set · ${formatInrCompact(dailyAvg)}/day avg"
            } else {
                "Set a monthly budget to track your pace"
            }
            return BudgetDisplay(
                hasBudget = false,
                isOver = false,
                percent = 0,
                clampedPercent = 0,
                percentText = "—",
                infoText = info,
            )
        }

        val balance = monthBudget - monthSpent
        val isOver = balance < 0
        val percent = ((monthSpent / monthBudget) * 100).toInt()
        val clampedPercent = min(percent, 100).coerceAtLeast(0)

        // +1 so the current day counts; never divide by zero on the last day.
        val daysLeft = (daysLeftMonth + 1).coerceAtLeast(1)
        val info = if (isOver) {
            "${formatInrCompact(abs(balance))} over budget · ${formatInrCompact(monthBudget)}"
        } else {
            val perDay = balance / daysLeft
            "${formatInrCompact(balance)} left · ${formatInrCompact(perDay)}/day to stay on track"
        }

        return BudgetDisplay(
            hasBudget = true,
            isOver = isOver,
            percent = percent,
            clampedPercent = clampedPercent,
            percentText = "$percent%",
            infoText = info,
        )
    }

    // ── Color ────────────────────────────────────────────────────────────────

    /**
     * Parses `#RRGGBB` / `#AARRGGBB` to an ARGB int, or null on any malformed
     * input. Framework-free (no `android.graphics.Color`) so it unit-tests on a
     * plain JVM; [ExpenseWidgetProvider] wraps it with a fallback color.
     */
    fun parseHexColor(hex: String?): Int? {
        val s = hex?.trim()?.removePrefix("#") ?: return null
        val hexDigits = when (s.length) {
            6 -> "FF$s"   // RRGGBB → opaque
            8 -> s        // AARRGGBB
            else -> return null
        }
        return try {
            hexDigits.toLong(16).toInt()
        } catch (e: NumberFormatException) {
            null
        }
    }

    // ── Spend-mix donut ──────────────────────────────────────────────────────

    /** One category (or Other) slice persisted by Flutter for the widget donut. */
    data class PieSlice(
        val name: String,
        val emoji: String,
        val colorHex: String,
        val amount: Double,
    )

    /** Slice plus the arc it occupies, starting at 12 o'clock (−90°). */
    data class PieSweep(
        val slice: PieSlice,
        val startAngle: Float,
        val sweep: Float,
        val percent: Int,
    )

    /**
     * Parses the Flutter `expense_widget_pie` payload. Records are `\u001e`-
     * separated; fields inside a record are `\u001f`-separated:
     * `name, emoji, #RRGGBB, amount`. Caps at 4 slices; skips junk.
     */
    fun parsePiePayload(raw: String?): List<PieSlice> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split('\u001e').mapNotNull { rec ->
            if (rec.isBlank()) return@mapNotNull null
            val p = rec.split('\u001f')
            if (p.size < 4) return@mapNotNull null
            val amount = p[3].trim().toDoubleOrNull() ?: return@mapNotNull null
            if (!amount.isFinite() || amount <= 0.0) return@mapNotNull null
            val name = p[0].trim()
            if (name.isEmpty()) return@mapNotNull null
            PieSlice(
                name = name,
                emoji = p[1].trim(),
                colorHex = p[2].trim(),
                amount = amount,
            )
        }.take(4)
    }

    /** Single-slice fallback so an older snapshot without a pie payload still draws. */
    fun pieFallbackFromTop(
        name: String,
        emoji: String,
        colorHex: String,
        amount: Double,
    ): List<PieSlice> {
        if (name.isBlank() || !amount.isFinite() || amount <= 0.0) return emptyList()
        return listOf(PieSlice(name.trim(), emoji, colorHex, amount))
    }

    /** Month-stale widgets get no mix; otherwise parse, then fall back to top cat. */
    fun effectivePie(
        payload: String?,
        isMonthStale: Boolean,
        fallbackName: String,
        fallbackEmoji: String,
        fallbackColor: String,
        fallbackAmount: Double,
    ): List<PieSlice> {
        if (isMonthStale) return emptyList()
        val parsed = parsePiePayload(payload)
        if (parsed.isNotEmpty()) return parsed
        return pieFallbackFromTop(fallbackName, fallbackEmoji, fallbackColor, fallbackAmount)
    }

    /**
     * Largest-remainder percents that always sum to 100 (or all zeros).
     * A single positive amount is 100 even if other zeros are present.
     */
    fun piePercents(amounts: List<Double>): List<Int> {
        if (amounts.isEmpty()) return emptyList()
        if (amounts.any { !it.isFinite() }) return List(amounts.size) { 0 }
        val total = amounts.sum()
        if (!total.isFinite() || total <= 0.0) return List(amounts.size) { 0 }
        if (amounts.size == 1) return listOf(100)
        val exact = amounts.map { it / total * 100.0 }
        val floors = exact.map { kotlin.math.floor(it).toInt() }.toMutableList()
        var rem = 100 - floors.sum()
        val order = exact.indices.sortedWith(
            compareByDescending<Int> { exact[it] - floors[it] }.thenBy { it }
        )
        var i = 0
        while (rem > 0 && order.isNotEmpty()) {
            floors[order[i % order.size]]++
            rem--
            i++
        }
        return floors
    }

    /**
     * Arc list for the donut. One slice is a seamless 360° ring; multiple
     * slices share a 3° gap so the ring reads as separate chips, not a blob.
     */
    fun pieSweeps(slices: List<PieSlice>): List<PieSweep> {
        val positive = slices.filter { it.amount.isFinite() && it.amount > 0.0 }.take(4)
        if (positive.isEmpty()) return emptyList()
        val percents = piePercents(positive.map { it.amount })
        if (positive.size == 1) {
            return listOf(PieSweep(positive[0], -90f, 360f, 100))
        }
        val gap = 3.0f
        val usable = (360f - gap * positive.size).coerceAtLeast(1f)
        var cursor = -90f
        return positive.mapIndexed { i, slice ->
            val sweep = (usable * (percents[i] / 100f)).coerceAtLeast(1.4f)
            val item = PieSweep(slice, cursor, sweep, percents[i])
            cursor += sweep + gap
            item
        }
    }

    /** Compact legend: `₹1,200 · 42%` (or `· <1%` when remainder rounded to 0). */
    fun legendLine(amount: Double, percent: Int): String {
        val pct = if (percent < 1) "<1%" else "$percent%"
        return "${formatInrCompact(amount)} · $pct"
    }
}
