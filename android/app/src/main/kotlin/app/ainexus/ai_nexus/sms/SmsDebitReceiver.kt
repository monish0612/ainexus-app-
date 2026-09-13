package app.ainexus.ai_nexus.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject

/**
 * Manifest-registered. Exempt from Android 8 implicit-broadcast limits for
 * SMS_RECEIVED, so this fires even when the UI process is dead. The work is
 * a few regexes + a tiny JSON append — no Flutter engine, no wake lock,
 * no foreground service.
 */
class SmsDebitReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!SmsAutoPrefs.isEnabled(context)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return
        val sender = messages.firstOrNull()?.originatingAddress
            ?: messages.mapNotNull { it.originatingAddress }.firstOrNull()
            ?: ""
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
        if (body.isBlank()) return
        if (!KnownBankSenders.shouldAccept(sender, body)) return

        val timestamp = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()

        val parsed = BankSmsParser.parse(body, timestamp, sender) ?: return
        if (SmsDeduper.isDuplicate(context, sender, parsed.amount, timestamp)) return

        val id = SmsQueue.newId()
        val item = JSONObject().apply {
            put("id", id)
            put("sender", sender)
            put("amount", parsed.amount)
            put("merchantRaw", parsed.merchantRaw)
            put("instrument", parsed.instrument)
            put("instrumentLast4", parsed.instrumentLast4 ?: JSONObject.NULL)
            put("transactionDate", parsed.transactionDateMs)
            put("bank", parsed.bank)
            put("cardType", parsed.cardType)
            put("referenceId", parsed.referenceId ?: JSONObject.NULL)
            put("balanceAfter", parsed.balanceAfter ?: JSONObject.NULL)
            put("templateId", parsed.templateId)
            put("receivedAt", timestamp)
            put("rawBody", parsed.rawBody)
            put("status", "pending")
        }
        SmsQueue.enqueue(context, item)

        val payload = SmsJson.toFlutterMap(item)
        val auto = SmsAutoPrefs.mode(context) == SmsAutoPrefs.MODE_AUTO
        SmsBridge.dispatchToFlutter(payload)
        val kind = SmsNotifyPolicy.kind(
            auto = auto,
            dartListening = SmsBridge.dartListening,
            activityResumed = SmsBridge.activityResumed,
        )
        if (kind != SmsNotifyPolicy.NONE) {
            SmsBridge.showReviewNotification(context, item, kind = kind)
        }
    }
}
