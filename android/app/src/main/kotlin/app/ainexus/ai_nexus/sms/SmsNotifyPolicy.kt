package app.ainexus.ai_nexus.sms

/**
 * Tray vs silent-save. Must match Dart [SmsIntakePolicy.onArrival].
 * Auto never asks. Dart-alive auto never shows "queued".
 */
object SmsNotifyPolicy {
    const val NONE = "none"
    const val QUEUED = "queued"
    const val ASK = "ask"
    const val LOGGED = "logged"

    fun kind(
        auto: Boolean,
        dartListening: Boolean,
        activityResumed: Boolean,
    ): String {
        if (auto) {
            return if (dartListening) NONE else QUEUED
        }
        if (dartListening && activityResumed) return NONE
        return ASK
    }
}
