package app.ainexus.ai_nexus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import java.util.Calendar
import java.util.GregorianCalendar
import org.junit.Test

/**
 * Exhaustive JVM unit tests for [ExpenseWidgetLogic] — the pure format/decision
 * layer behind the Expense home-screen widget. Covers compact currency, time
 * progress (incl. leap years + month/year edges), staleness, the hero/month/
 * top-category text, the budget pill (under / over / no-budget / div-by-zero),
 * hex color parsing, and request-code uniqueness for the three tap lanes.
 */
class ExpenseWidgetLogicTest {

    // ── formatInrCompact ──────────────────────────────────────────────────────

    @Test
    fun format_zeroAndSmall() {
        assertEquals("\u20B90", ExpenseWidgetLogic.formatInrCompact(0.0))
        assertEquals("\u20B9999", ExpenseWidgetLogic.formatInrCompact(999.0))
    }

    @Test
    fun format_roundsToNearestRupee() {
        assertEquals("\u20B9100", ExpenseWidgetLogic.formatInrCompact(99.6))
        assertEquals("\u20B943", ExpenseWidgetLogic.formatInrCompact(42.5))
    }

    @Test
    fun format_groupsSubLakhThousands() {
        // Only sub-lakh values hit the grouped path (≥ ₹1L compacts to "L"),
        // and at ≤ 5 digits en-IN and Western grouping are identical.
        assertEquals("\u20B912,345", ExpenseWidgetLogic.formatInrCompact(12345.0))
        assertEquals("\u20B999,999", ExpenseWidgetLogic.formatInrCompact(99999.0))
    }

    @Test
    fun format_lakhBoundaryAndDecimals() {
        assertEquals("\u20B91L", ExpenseWidgetLogic.formatInrCompact(100000.0))
        assertEquals("\u20B91.2L", ExpenseWidgetLogic.formatInrCompact(123456.0)) // 1.23456L → 1.2L
        assertEquals("\u20B92.5L", ExpenseWidgetLogic.formatInrCompact(250000.0))
    }

    @Test
    fun format_croreBoundaryAndDecimals() {
        assertEquals("\u20B91Cr", ExpenseWidgetLogic.formatInrCompact(1_00_00_000.0))
        assertEquals("\u20B92.5Cr", ExpenseWidgetLogic.formatInrCompact(2_50_00_000.0))
    }

    @Test
    fun format_negativeFlagPrependsMinusOnMagnitude() {
        assertEquals("-\u20B91,500", ExpenseWidgetLogic.formatInrCompact(1500.0, negative = true))
        // The flag controls the sign; magnitude uses abs of the input too.
        assertEquals("\u20B91,500", ExpenseWidgetLogic.formatInrCompact(-1500.0))
    }

    // ── computeTimeProgress ───────────────────────────────────────────────────

    private fun calOf(year: Int, month0: Int, day: Int): Calendar =
        GregorianCalendar(year, month0, day, 10, 0, 0)

    @Test
    fun timeProgress_leapFebMidMonth() {
        val tp = ExpenseWidgetLogic.computeTimeProgress(calOf(2024, Calendar.FEBRUARY, 15))
        assertEquals("Feb", tp.monthShort)
        assertEquals("2024", tp.yearStr)
        assertEquals(15, tp.dayOfMonth)
        assertEquals(29, tp.daysInMonth) // 2024 is a leap year
        assertEquals(14, tp.daysLeftMonth)
        assertEquals((15 * 100) / 29, tp.monthPercent)
        // Day-of-year for 15 Feb 2024 = 31 + 15 = 46, leap → 366 days.
        assertEquals((46 * 100) / 366, tp.yearPercent)
        assertEquals(366 - 46, tp.daysLeftYear)
    }

    @Test
    fun timeProgress_lastDayOfNonLeapYear() {
        val tp = ExpenseWidgetLogic.computeTimeProgress(calOf(2025, Calendar.DECEMBER, 31))
        assertEquals("Dec", tp.monthShort)
        assertEquals(31, tp.dayOfMonth)
        assertEquals(31, tp.daysInMonth)
        assertEquals(0, tp.daysLeftMonth)
        assertEquals(100, tp.monthPercent)
        assertEquals(100, tp.yearPercent)
        assertEquals(0, tp.daysLeftYear)
    }

    @Test
    fun timeProgress_firstDayOfYear() {
        val tp = ExpenseWidgetLogic.computeTimeProgress(calOf(2026, Calendar.JANUARY, 1))
        assertEquals(1, tp.dayOfMonth)
        assertEquals(31, tp.daysInMonth)
        assertEquals(30, tp.daysLeftMonth)
        assertTrue(tp.monthPercent in 1..4)
        assertTrue(tp.yearPercent in 0..1)
    }

    @Test
    fun timeProgress_centuryLeapRule_2000isLeap_1900isNot() {
        assertEquals(366 - 1, ExpenseWidgetLogic.computeTimeProgress(calOf(2000, Calendar.JANUARY, 1)).daysLeftYear)
        assertEquals(365 - 1, ExpenseWidgetLogic.computeTimeProgress(calOf(1900, Calendar.JANUARY, 1)).daysLeftYear)
    }

    // ── staleness ─────────────────────────────────────────────────────────────

    @Test
    fun staleness_dateAndMonth() {
        assertFalse(ExpenseWidgetLogic.isDateStale("2026-06-29", "2026-06-29"))
        assertTrue(ExpenseWidgetLogic.isDateStale("2026-06-28", "2026-06-29"))
        assertTrue(ExpenseWidgetLogic.isDateStale("", "2026-06-29"))

        assertEquals("2026-06", ExpenseWidgetLogic.monthOf("2026-06-29"))
        assertEquals("", ExpenseWidgetLogic.monthOf("bad"))
        assertFalse(ExpenseWidgetLogic.isMonthStale("2026-06-29", "2026-06"))
        assertTrue(ExpenseWidgetLogic.isMonthStale("2026-05-31", "2026-06"))
        assertTrue(ExpenseWidgetLogic.isMonthStale("", "2026-06"))
    }

    // ── hero ────────────────────────────────────────────────────────────────--

    @Test
    fun emptyMessage_inRangeAndDeterministicAndNegativeSafe() {
        for (ms in longArrayOf(0L, 1L, 4L, 5L, 123456789L, -7L, Long.MAX_VALUE)) {
            val msg = ExpenseWidgetLogic.emptyMessage(ms)
            assertTrue(ExpenseWidgetLogic.EMPTY_MESSAGES.contains(msg))
        }
        // Deterministic for the same input.
        assertEquals(ExpenseWidgetLogic.emptyMessage(42L), ExpenseWidgetLogic.emptyMessage(42L))
    }

    @Test
    fun entrySubtitle_pluralization() {
        assertEquals("", ExpenseWidgetLogic.entrySubtitle(0))
        assertEquals("", ExpenseWidgetLogic.entrySubtitle(-3))
        assertEquals("1 entry today", ExpenseWidgetLogic.entrySubtitle(1))
        assertEquals("7 entries today", ExpenseWidgetLogic.entrySubtitle(7))
    }

    @Test
    fun countChip_neverNegative() {
        assertEquals("0", ExpenseWidgetLogic.countChip(0))
        assertEquals("0", ExpenseWidgetLogic.countChip(-2))
        assertEquals("12", ExpenseWidgetLogic.countChip(12))
    }

    // ── this-month card ─────────────────────────────────────────────────────--

    @Test
    fun dailyAvg_guardsDayZero() {
        assertEquals(0.0, ExpenseWidgetLogic.dailyAvg(1000.0, 0), 0.0001)
        assertEquals(200.0, ExpenseWidgetLogic.dailyAvg(1000.0, 5), 0.0001)
    }

    @Test
    fun isMonthEmpty_gatesTheGettingStartedPanel() {
        assertTrue(ExpenseWidgetLogic.isMonthEmpty(0))
        assertTrue(ExpenseWidgetLogic.isMonthEmpty(-1)) // defensive
        assertFalse(ExpenseWidgetLogic.isMonthEmpty(1))
        assertFalse(ExpenseWidgetLogic.isMonthEmpty(50))
    }

    @Test
    fun monthCaption_states() {
        assertEquals("no entries yet", ExpenseWidgetLogic.monthCaption(0, 0.0))
        assertEquals("1 entry · \u20B9100/day", ExpenseWidgetLogic.monthCaption(1, 100.0))
        assertEquals("9 entries · \u20B9250/day", ExpenseWidgetLogic.monthCaption(9, 250.0))
    }

    // ── top-category card ─────────────────────────────────────────────────────

    @Test
    fun topEmoji_fallbacks() {
        assertEquals("🍽️", ExpenseWidgetLogic.topEmoji("🍽️", isMonthStale = false))
        assertEquals(ExpenseWidgetLogic.FALLBACK_EMOJI, ExpenseWidgetLogic.topEmoji("🍽️", isMonthStale = true))
        assertEquals(ExpenseWidgetLogic.FALLBACK_EMOJI, ExpenseWidgetLogic.topEmoji("", isMonthStale = false))
    }

    @Test
    fun effectiveTopName_clearedOnMonthRollover() {
        assertEquals("Food", ExpenseWidgetLogic.effectiveTopName("Food", isMonthStale = false))
        assertEquals("", ExpenseWidgetLogic.effectiveTopName("Food", isMonthStale = true))
    }

    // ── budget pill ─────────────────────────────────────────────────────────--

    @Test
    fun budget_noBudget_noSpend() {
        val b = ExpenseWidgetLogic.computeBudget(0.0, 0.0, 10, 0.0)
        assertFalse(b.hasBudget)
        assertEquals("—", b.percentText)
        assertEquals("Set a monthly budget to track your pace", b.infoText)
    }

    @Test
    fun budget_noBudget_withSpendShowsAvg() {
        val b = ExpenseWidgetLogic.computeBudget(0.0, 3000.0, 10, 300.0)
        assertFalse(b.hasBudget)
        assertEquals("No budget set · \u20B9300/day avg", b.infoText)
    }

    @Test
    fun budget_underBudget_dailyAllowance() {
        // ₹10,000 budget, ₹4,000 spent, 9 days left → +1 = 10 days, ₹6,000/10 = ₹600/day.
        val b = ExpenseWidgetLogic.computeBudget(10000.0, 4000.0, 9, 0.0)
        assertTrue(b.hasBudget)
        assertFalse(b.isOver)
        assertEquals(40, b.percent)
        assertEquals(40, b.clampedPercent)
        assertEquals("40%", b.percentText)
        assertEquals("\u20B96,000 left · \u20B9600/day to stay on track", b.infoText)
    }

    @Test
    fun budget_overBudget_clampsBarAndShowsOver() {
        val b = ExpenseWidgetLogic.computeBudget(5000.0, 7500.0, 4, 0.0)
        assertTrue(b.isOver)
        assertEquals(150, b.percent)        // raw percent can exceed 100
        assertEquals(100, b.clampedPercent) // bar is clamped
        assertEquals("150%", b.percentText)
        assertEquals("\u20B92,500 over budget · \u20B95,000", b.infoText)
    }

    @Test
    fun budget_exactlyAtBudget_isNotOver() {
        val b = ExpenseWidgetLogic.computeBudget(5000.0, 5000.0, 0, 0.0)
        assertFalse(b.isOver)
        assertEquals(100, b.percent)
        // daysLeft 0 → +1 = 1, balance 0 → ₹0/day, never divides by zero.
        assertEquals("\u20B90 left · \u20B90/day to stay on track", b.infoText)
    }

    @Test
    fun budget_lastDayNoDivByZero() {
        val b = ExpenseWidgetLogic.computeBudget(10000.0, 4000.0, 0, 0.0)
        assertFalse(b.isOver)
        // 6,000 left / (0+1) day = ₹6,000/day.
        assertEquals("\u20B96,000 left · \u20B96,000/day to stay on track", b.infoText)
    }

    // ── hex color parsing ─────────────────────────────────────────────────────

    @Test
    fun parseHex_rrggbb_isOpaque() {
        assertEquals(0xFFFF6B6B.toInt(), ExpenseWidgetLogic.parseHexColor("#FF6B6B"))
        assertEquals(0xFF51CF66.toInt(), ExpenseWidgetLogic.parseHexColor("51CF66"))
    }

    @Test
    fun parseHex_aarrggbb_preservesAlpha() {
        assertEquals(0x80FF6B6B.toInt(), ExpenseWidgetLogic.parseHexColor("#80FF6B6B"))
    }

    @Test
    fun parseHex_caseAndWhitespaceTolerant() {
        assertEquals(0xFFABCDEF.toInt(), ExpenseWidgetLogic.parseHexColor("  #abcdef  "))
    }

    @Test
    fun parseHex_invalidReturnsNull() {
        assertNull(ExpenseWidgetLogic.parseHexColor(null))
        assertNull(ExpenseWidgetLogic.parseHexColor(""))
        assertNull(ExpenseWidgetLogic.parseHexColor("#FFF"))      // 3 digits unsupported
        assertNull(ExpenseWidgetLogic.parseHexColor("#GGGGGG"))   // non-hex
        assertNull(ExpenseWidgetLogic.parseHexColor("zzz"))
    }

    // ── request codes (tap lanes) ──────────────────────────────────────────────

    @Test
    fun requestCodes_uniqueAcrossLanesAndWidgetIds() {
        val seen = HashSet<Int>()
        for (id in 0..500) {
            for (lane in intArrayOf(
                ExpenseWidgetLogic.LANE_ROOT,
                ExpenseWidgetLogic.LANE_ADD,
                ExpenseWidgetLogic.LANE_AI,
            )) {
                val rc = ExpenseWidgetLogic.launchRequestCode(id, lane)
                assertTrue("Duplicate request code $rc (id=$id lane=$lane)", seen.add(rc))
            }
        }
    }

    @Test
    fun requestCodes_clearOfSearchWidgetLanes() {
        // Expense lanes start at 10_000; search widget uses 5_000–7_999 + id.
        for (id in 0..200) {
            assertTrue(ExpenseWidgetLogic.launchRequestCode(id, ExpenseWidgetLogic.LANE_ROOT) >= 10_000)
        }
    }

    @Test
    fun requestCodes_stableForSameInput() {
        assertEquals(
            ExpenseWidgetLogic.launchRequestCode(42, ExpenseWidgetLogic.LANE_ADD),
            ExpenseWidgetLogic.launchRequestCode(42, ExpenseWidgetLogic.LANE_ADD),
        )
    }
}
