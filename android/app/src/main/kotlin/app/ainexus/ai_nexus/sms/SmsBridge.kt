package app.ainexus.ai_nexus.sms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import app.ainexus.ai_nexus.MainActivity
import app.ainexus.ai_nexus.R
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object SmsBridge {
    const val CHANNEL = "app.ainexus.ai_nexus/sms_expense"

    const val ACTION_APPROVE = "app.ainexus.ai_nexus.SMS_APPROVE"
    const val ACTION_REJECT = "app.ainexus.ai_nexus.SMS_REJECT"
    const val EXTRA_ID = "sms_id"

    private const val NOTIF_CHANNEL = "nexus_sms_expense"
    private const val NOTIF_ID = 9300

    @Volatile
    var methodChannel: MethodChannel? = null

    @Volatile
    var activityResumed: Boolean = false

    /** Dart has registered the MethodChannel handler. Channel non-null is not enough. */
    @Volatile
    var dartListening: Boolean = false

    fun dispatchToFlutter(payload: Map<String, Any?>): Boolean {
        if (!dartListening) return false
        val ch = methodChannel ?: return false
        Handler(Looper.getMainLooper()).post {
            try {
                ch.invokeMethod("onSmsDebit", payload)
            } catch (_: Throwable) {
            }
        }
        return true
    }

    fun showReviewNotification(context: Context, item: JSONObject, kind: String) {
        ensureChannel(context)
        val id = item.optString("id")
        val amount = item.optDouble("amount", 0.0)
        val merchant = item.optString("merchantRaw").ifBlank { "a debit" }
        val rupees = if (amount == amount.toLong().toDouble()) {
            amount.toLong().toString()
        } else {
            String.format(java.util.Locale.US, "%.2f", amount)
        }

        val notifId = notifIdFor(id)

        val tap = PendingIntent.getActivity(
            context,
            id.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_ID, id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val title: String
        val text: String
        val withActions: Boolean
        when (kind) {
            "queued" -> {
                title = "₹$rupees queued"
                text = "$merchant — saved when you open Nexus"
                withActions = false
            }
            "logged" -> {
                title = "Logged ₹$rupees"
                text = merchant
                withActions = false
            }
            "finish" -> {
                title = "Approved ₹$rupees"
                text = "Open Nexus to finish saving"
                withActions = false
            }
            else -> {
                title = "₹$rupees at $merchant"
                text = "Log this as an expense?"
                withActions = true
            }
        }

        builder
            .setSmallIcon(R.drawable.ic_widget_wallet)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setContentTitle(title)
            .setContentText(text)
            .setGroup("nexus_sms_expense")

        if (withActions) {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val approve = PendingIntent.getBroadcast(
                context,
                id.hashCode() + 1,
                Intent(ACTION_APPROVE).setPackage(context.packageName).putExtra(EXTRA_ID, id),
                flags,
            )
            val reject = PendingIntent.getBroadcast(
                context,
                id.hashCode() + 2,
                Intent(ACTION_REJECT).setPackage(context.packageName).putExtra(EXTRA_ID, id),
                flags,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                builder.addAction(
                    Notification.Action.Builder(null, "Approve", approve).build(),
                )
                builder.addAction(
                    Notification.Action.Builder(null, "Reject", reject).build(),
                )
            }
        }

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            nm.notify(notifId, builder.build())
        } catch (_: Throwable) {
        }
    }

    fun showLogged(context: Context, id: String, amount: Double, merchant: String) {
        val item = JSONObject().apply {
            put("id", id)
            put("amount", amount)
            put("merchantRaw", merchant)
        }
        showReviewNotification(context, item, kind = "logged")
    }

    fun cancel(context: Context, id: String? = null) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (id == null) {
            nm.cancel(NOTIF_ID)
        } else {
            nm.cancel(notifIdFor(id))
        }
    }

    private fun notifIdFor(id: String): Int {
        val h = id.hashCode() and 0x7fffffff
        return if (h == 0) NOTIF_ID + 1 else h
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(NOTIF_CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                NOTIF_CHANNEL,
                "SMS expense",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Approve or confirm expenses parsed from bank debit SMS"
            },
        )
    }
}

class SmsActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(SmsBridge.EXTRA_ID) ?: return
        when (intent.action) {
            SmsBridge.ACTION_APPROVE -> {
                SmsQueue.updateStatus(context, id, "approved")
                SmsBridge.cancel(context, id)
                val delivered = SmsBridge.dispatchToFlutter(mapOf("id" to id, "action" to "approved"))
                if (!delivered) {
                    SmsQueue.get(context, id)?.let {
                        SmsBridge.showReviewNotification(context, it, kind = "finish")
                    }
                }
            }
            SmsBridge.ACTION_REJECT -> {
                SmsQueue.updateStatus(context, id, "rejected")
                SmsQueue.remove(context, id)
                SmsBridge.cancel(context, id)
                SmsBridge.dispatchToFlutter(mapOf("id" to id, "action" to "rejected"))
            }
        }
    }
}
