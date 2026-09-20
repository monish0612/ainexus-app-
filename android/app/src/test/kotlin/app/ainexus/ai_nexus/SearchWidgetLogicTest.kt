package app.ainexus.ai_nexus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Exhaustive JVM unit tests for [SearchWidgetLogic] — the pure decision layer
 * behind the home-screen search widget. Covers mode normalization (the toggle),
 * per-mode launch extras, and request-code uniqueness/stability.
 */
class SearchWidgetLogicTest {

    // ── normalizeMode (the toggle) ──────────────────────────────────────────

    @Test
    fun normalizeMode_web_staysWeb() {
        assertEquals(SearchWidgetLogic.MODE_WEB, SearchWidgetLogic.normalizeMode("web"))
    }

    @Test
    fun normalizeMode_expense_staysExpense() {
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode("expense"))
    }

    @Test
    fun normalizeMode_null_defaultsExpense() {
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode(null))
    }

    @Test
    fun normalizeMode_garbageAndCasing_defaultExpense() {
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode(""))
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode("WEB"))
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode(" web "))
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode("anything"))
    }

    @Test
    fun isExpense_matchesNormalize() {
        assertTrue(SearchWidgetLogic.isExpense("expense"))
        assertTrue(SearchWidgetLogic.isExpense("garbage")) // defaults to expense
        assertFalse(SearchWidgetLogic.isExpense("web"))
    }

    @Test
    fun toggle_flipsBothWays() {
        // Simulate the user tapping each pill.
        assertEquals(SearchWidgetLogic.MODE_WEB, SearchWidgetLogic.normalizeMode("web"))
        assertEquals(SearchWidgetLogic.MODE_EXPENSE, SearchWidgetLogic.normalizeMode("expense"))
    }

    // ── launchExtras ────────────────────────────────────────────────────────

    @Test
    fun launchExtras_expense_opensTab0AskAi() {
        val extras = SearchWidgetLogic.launchExtras("expense")
        assertEquals("0", extras["shortcut_tab"])
        assertEquals("expense", extras["widget_search_mode"])
        // Must NOT carry the web widget-launch flag (would double-trigger).
        assertNull(extras["widget_launch"])
        assertNull(extras["shortcut_subtab"])
    }

    @Test
    fun launchExtras_web_opensTutorSummarizerWithLaunchFlag() {
        val extras = SearchWidgetLogic.launchExtras("web")
        assertEquals("2", extras["shortcut_tab"])
        assertEquals("0", extras["shortcut_subtab"])
        assertEquals("true", extras["widget_launch"])
        assertEquals("web", extras["widget_search_mode"])
    }

    @Test
    fun launchExtras_garbageMode_treatedAsExpense() {
        assertEquals("0", SearchWidgetLogic.launchExtras("nonsense")["shortcut_tab"])
    }

    // ── request codes: uniqueness + stability ────────────────────────────────

    @Test
    fun requestCodes_areUniqueAcrossLanesAndModes() {
        val seen = HashSet<Int>()
        for (id in 0..200) {
            val codes = listOf(
                SearchWidgetLogic.searchRequestCode(id, "expense"),
                SearchWidgetLogic.searchRequestCode(id, "web"),
                SearchWidgetLogic.toggleRequestCode(id, "expense"),
                SearchWidgetLogic.toggleRequestCode(id, "web"),
            )
            for (c in codes) {
                assertTrue("Duplicate request code $c at widget id=$id", seen.add(c))
            }
        }
    }

    @Test
    fun searchRequestCode_isModeSensitive() {
        // A mode flip must yield a different code so FLAG_UPDATE_CURRENT
        // refreshes the cached PendingIntent extras.
        assertTrue(
            SearchWidgetLogic.searchRequestCode(7, "expense") !=
                SearchWidgetLogic.searchRequestCode(7, "web")
        )
    }

    @Test
    fun requestCodes_areStableForSameInput() {
        assertEquals(
            SearchWidgetLogic.searchRequestCode(42, "web"),
            SearchWidgetLogic.searchRequestCode(42, "web")
        )
        assertEquals(
            SearchWidgetLogic.toggleRequestCode(42, "expense"),
            SearchWidgetLogic.toggleRequestCode(42, "expense")
        )
    }

    // ── layout / provider contract (visual polish must not break taps) ───────

    @Test
    fun liveLayout_keepsLoadBearingIds() {
        val xml = readModuleFile("src/main/res/layout/widget_search.xml")
        assertTrue(xml.contains("android:id=\"@+id/widget_search_root\""))
        assertTrue(xml.contains("android:id=\"@+id/widget_search_globe\""))
        assertTrue(xml.contains("android:id=\"@+id/widget_search_hint\""))
        assertTrue(xml.contains("android:id=\"@+id/widget_search_go\""))
        assertTrue(xml.contains("@string/widget_search_hint_web"))
        assertTrue(xml.contains("@dimen/widget_search_bar_height"))
    }

    @Test
    fun provider_stillLaunchesWebSearchFromRootOnly() {
        val kt = readModuleFile(
            "src/main/kotlin/app/ainexus/ai_nexus/SearchWidgetProvider.kt"
        )
        assertTrue(kt.contains("R.layout.widget_search"))
        assertTrue(kt.contains("R.id.widget_search_root"))
        assertTrue(kt.contains("SearchWidgetLogic.MODE_WEB"))
        assertTrue(kt.contains("SearchWidgetLogic.launchExtras(MODE_WEB)"))
        assertTrue(kt.contains("SearchWidgetLogic.searchRequestCode(appWidgetId, MODE_WEB)"))
        assertTrue(kt.contains("FLAG_ACTIVITY_NEW_TASK"))
        assertTrue(kt.contains("FLAG_UPDATE_CURRENT"))
        assertTrue(kt.contains("FLAG_IMMUTABLE"))
    }

    @Test
    fun providerInfo_keepsFourByOneSearchContract() {
        val xml = readModuleFile("src/main/res/xml/widget_search_info.xml")
        assertTrue(xml.contains("android:initialLayout=\"@layout/widget_search\""))
        assertTrue(xml.contains("android:previewLayout=\"@layout/widget_search_preview\""))
        assertTrue(xml.contains("android:targetCellWidth=\"4\""))
        assertTrue(xml.contains("android:targetCellHeight=\"1\""))
        assertTrue(xml.contains("android:resizeMode=\"horizontal\""))
        assertTrue(xml.contains("android:updatePeriodMillis=\"0\""))
    }

    private fun readModuleFile(relative: String): String {
        val candidates = listOf(
            java.io.File(relative),
            java.io.File("android/app/$relative"),
            java.io.File("ai_nexus/android/app/$relative"),
        )
        val file = candidates.firstOrNull { it.exists() }
        assertTrue("Missing $relative (cwd=${java.io.File(".").absolutePath})", file != null)
        return file!!.readText()
    }
}
