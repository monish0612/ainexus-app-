package app.ainexus.ai_nexus

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-arms the midnight widget alarm after device reboot or app update.
 * Also triggers an immediate refresh so widgets show correct data right away.
 */
class WidgetBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NexusWidgetBoot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        Log.i(TAG, "Boot/update received ($action) — rescheduling widget alarm")

        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(
            ComponentName(context, ExpenseWidgetProvider::class.java)
        )

        if (ids.isEmpty()) {
            Log.d(TAG, "No expense widgets placed — skipping")
            return
        }

        ExpenseWidgetProvider.scheduleMidnightAlarm(context)
        ExpenseWidgetProvider.triggerUpdate(context)
    }
}
