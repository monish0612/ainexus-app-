package app.ainexus.ai_nexus.sms

import org.junit.Assert.assertEquals
import org.junit.Test

class SmsNotifyPolicyTest {

    @Test
    fun `auto with dart alive is silent even in background`() {
        assertEquals(
            SmsNotifyPolicy.NONE,
            SmsNotifyPolicy.kind(
                auto = true,
                dartListening = true,
                activityResumed = false,
            ),
        )
    }

    @Test
    fun `auto with engine dead queues until open`() {
        assertEquals(
            SmsNotifyPolicy.QUEUED,
            SmsNotifyPolicy.kind(
                auto = true,
                dartListening = false,
                activityResumed = false,
            ),
        )
    }

    @Test
    fun `ask while UI visible stays in-app`() {
        assertEquals(
            SmsNotifyPolicy.NONE,
            SmsNotifyPolicy.kind(
                auto = false,
                dartListening = true,
                activityResumed = true,
            ),
        )
    }

    @Test
    fun `ask in background uses tray approve`() {
        assertEquals(
            SmsNotifyPolicy.ASK,
            SmsNotifyPolicy.kind(
                auto = false,
                dartListening = true,
                activityResumed = false,
            ),
        )
    }
}
