package app.ainexus.ai_nexus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews

/**
 * Home-screen "Nexus AI Web Search" widget.
 *
 * A single-row 4x1 AMOLED pill dedicated to the AI web (online) search — the
 * Expense widget already owns expense search, so this one is web-focused.
 * Tapping anywhere on the bar launches the app straight into the Tutor online
 * search via the proven [SearchWidgetLogic.MODE_WEB] launch contract, which
 * stays in lock-step with the Flutter routing on the other side.
 */
class SearchWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "NexusSearchWidget"

        private const val MODE_WEB = SearchWidgetLogic.MODE_WEB

        private fun drawWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_search)

            // The whole bar is one tap target → AI web search.
            views.setOnClickPendingIntent(
                R.id.widget_search_root,
                buildLaunchIntent(context, appWidgetId)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d(TAG, "Web search widget $appWidgetId drawn")
        }

        private fun buildLaunchIntent(
            context: Context,
            appWidgetId: Int
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "app.ainexus.SHORTCUT"
                for ((k, v) in SearchWidgetLogic.launchExtras(MODE_WEB)) putExtra(k, v)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val rc = SearchWidgetLogic.searchRequestCode(appWidgetId, MODE_WEB)
            return PendingIntent.getActivity(
                context, rc, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
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
        Log.i(TAG, "First web search widget placed on home screen")
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        Log.i(TAG, "Last web search widget removed from home screen")
    }
}
