package app.ainexus.ai_nexus.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BankSmsParserTest {

    private val received = 1_757_000_000_000L

    @Test
    fun `T7 E-Mandate is discarded`() {
        val body = "E-Mandate!\nRs.95.70 will be deducted on 03/08/26, 00:00:00\nFor GOOGLECLOUD mandate"
        assertNull(BankSmsParser.parse(body, received))
    }

    @Test
    fun `T1 Sent Rs from account`() {
        val body = "Sent Rs.2822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\nOn 10/09/26\nRef 859114032536"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(2822.0, p.amount, 0.001)
        assertEquals("Scapia", p.merchantRaw)
        assertEquals("DB", p.cardType)
        assertEquals("T1", p.templateId)
        assertEquals("7372", p.instrumentLast4)
    }

    @Test
    fun `T1b UPI Mandate`() {
        val body = "UPI Mandate:\nSent Rs.95.70\nfrom HDFC Bank A/c 7372\nTo GOOGLECLOUD\n03/08/26\nRef 441122334455"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(95.70, p.amount, 0.001)
        assertEquals("Googlecloud", p.merchantRaw)
    }

    @Test
    fun `T3 spent on card uses BLOCK CC`() {
        val body = "Spent Rs.211 On HDFC Bank Card 6177 At SWIGGY ADD MONEY On 2026-09-04:13:32:18.Not You? SMS BLOCK CC 5901"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(211.0, p.amount, 0.001)
        assertEquals("Swiggy Add Money", p.merchantRaw)
        assertEquals("CC", p.cardType)
    }

    @Test
    fun `T4 debit card from BLOCK DC not x prefix`() {
        val body = "Spent Rs.2.69 From HDFC Bank Card x3805 At WWW AMAZON IN On 2026-08-22:09:22:25 Bal Rs.2124.58 SMS BLOCK DC 3805"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(2.69, p.amount, 0.001)
        assertEquals("DB", p.cardType)
        assertEquals("DEBIT_CARD", p.instrument)
    }

    @Test
    fun `OTP is ignored`() {
        assertNull(
            BankSmsParser.parse(
                "HDFC Bank: 482911 is your OTP. Do not share with anyone.",
                received,
            ),
        )
    }

    @Test
    fun `credit SMS is ignored`() {
        assertNull(
            BankSmsParser.parse("Rs.50000.00 credited to HDFC Bank A/C *7372", received),
        )
    }

    @Test
    fun `bank senders`() {
        assertTrue(KnownBankSenders.isBank("JM-HDFCBK"))
        assertTrue(KnownBankSenders.isBank("AX-AXISBK"))
        assertTrue(KnownBankSenders.isBank("VM-FEDBNK"))
        assertTrue(KnownBankSenders.isBank("VM-ICICIB"))
        assertFalse(KnownBankSenders.isBank("+919840012345"))
    }

    @Test
    fun `Axis Bharat Petr is CC`() {
        val body = """Spent INR 4173.16
Axis Bank Card no. XX7159
15-08-26 13:44:31 IST
Bharat Petr
Avl Limit: INR 57827.35
Not you? SMS BLOCK 7159 to 919951860002"""
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(4173.16, p.amount, 0.001)
        assertEquals("AXIS", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("7159", p.instrumentLast4)
        assertEquals("Bharat Petr", p.merchantRaw)
        assertEquals("AXIS", p.templateId)
    }

    @Test
    fun `ICICI Amazon ignores available limit`() {
        val body = "Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21. To dispute, call 18002662/SMS BLOCK 7003 to 9215676766."
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(8153.0, p.amount, 0.001)
        assertEquals("ICICI", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("7003", p.instrumentLast4)
        assertEquals("ICICI", p.templateId)
        assertTrue(p.merchantRaw.lowercase().contains("amazon"))
    }

    @Test
    fun `Axis STAR FUEL S is CC`() {
        val body = """Spent INR 3790.37
Axis Bank Card no. XX7159
19-06-26 15:37:26 IST
STAR FUEL S
Avl Limit: INR 50884.25
Not you? SMS BLOCK 7159 to 919951860002"""
        val p = BankSmsParser.parse(body, received, "AX-AXISBK")!!
        assertEquals(3790.37, p.amount, 0.001)
        assertEquals("AXIS", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("7159", p.instrumentLast4)
        assertEquals("Star Fuel S", p.merchantRaw)
        assertEquals("AXIS", p.templateId)
        assertTrue(p.amount != 50884.25)
    }

    @Test
    fun `ICICI spent using INR 1004 is CC`() {
        val body = "INR 1,004.00 spent using ICICI Bank Card XX7003 on 01-Sep-26 on AMAZON PAY IN E. Avl Limit: INR 17,10,251.21. If not you, call 1800 2662/SMS BLOCK 7003 to 9215676766."
        val p = BankSmsParser.parse(body, received, "VM-ICICIB")!!
        assertEquals(1004.0, p.amount, 0.001)
        assertEquals("ICICI", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("7003", p.instrumentLast4)
        assertEquals("ICICI", p.templateId)
        assertTrue(p.merchantRaw.lowercase().contains("amazon"))
        assertTrue(p.amount != 1710251.21)
    }

    @Test
    fun `ICICI 18525 Amazon ignores Avl Lmt`() {
        val body = "Rs 18,525.84 spent on ICICI Bank Card XX7003 on 15-Aug-26 at AMAZON PAY IN E. Avl Lmt: Rs 16,76,317.21. To dispute, call 18002662/SMS BLOCK 7003 to 9215676766."
        val p = BankSmsParser.parse(body, received, "VM-ICICIB")!!
        assertEquals(18525.84, p.amount, 0.001)
        assertEquals("ICICI", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("ICICI", p.templateId)
        assertTrue(p.amount != 1676317.21)
    }

    @Test
    fun `Axis and ICICI DLT plus numeric senders pass the gate`() {
        val axis = """Spent INR 4173.16
Axis Bank Card no. XX7159
15-08-26 13:44:31 IST
Bharat Petr
Avl Limit: INR 57827.35"""
        val icici = "Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21."
        assertTrue(KnownBankSenders.isBank("AX-AXISBK"))
        assertTrue(KnownBankSenders.isBank("VM-ICICIB"))
        assertTrue(KnownBankSenders.shouldAccept("AX-AXISBK", axis))
        assertTrue(KnownBankSenders.shouldAccept("VM-ICICIB", icici))
        assertTrue(KnownBankSenders.shouldAccept("+919840012345", axis))
        assertTrue(KnownBankSenders.shouldAccept("+919840012345", icici))
        assertTrue(KnownBankSenders.shouldAccept("", axis))
        assertTrue(KnownBankSenders.shouldAccept("", icici))
        assertFalse(KnownBankSenders.shouldAccept("+919840012345", "Dinner at 8?"))
    }

    @Test
    fun `Scapia Anthropic strips plus Us`() {
        val body = "Hi! Your txn of ₹669.04 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received, "VM-FEDBNK")!!
        assertEquals(669.04, p.amount, 0.001)
        assertEquals("SCAPIA", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("Anthropic", p.merchantRaw)
        assertEquals("SCAPIA", p.templateId)
    }

    @Test
    fun `live miss 791-32 Anthropic is Scapia CC`() {
        val body = "Hi! Your txn of \u20B9791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received, "VM-FEDBNK")!!
        assertEquals(791.32, p.amount, 0.001)
        assertEquals("SCAPIA", p.bank)
        assertEquals("CC", p.cardType)
        assertEquals("Anthropic", p.merchantRaw)
        assertEquals("SCAPIA", p.templateId)
    }

    @Test
    fun `live miss 565-23 Anthropic is Scapia CC`() {
        val body = "Hi! Your txn of \u20B9565.23 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(565.23, p.amount, 0.001)
        assertEquals("SCAPIA", p.bank)
        assertEquals("Anthropic", p.merchantRaw)
        assertEquals("SCAPIA", p.templateId)
    }

    @Test
    fun `Scapia Rs prefix still matches`() {
        val body = "Hi! Your txn of Rs.791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(791.32, p.amount, 0.001)
        assertEquals("SCAPIA", p.templateId)
        assertEquals("Anthropic", p.merchantRaw)
    }

    @Test
    fun `Scapia NBSP after rupee still matches`() {
        val body = "Hi! Your txn of \u20B9\u00A0791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(791.32, p.amount, 0.001)
        assertEquals("SCAPIA", p.templateId)
    }

    @Test
    fun `Scapia truncated UCS-2 segment still matches`() {
        val body = "Hi! Your txn of \u20B9791.32 at Anthropic + Us on your Scapia Federal Visa cr"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(791.32, p.amount, 0.001)
        assertEquals("SCAPIA", p.templateId)
        assertEquals("Anthropic", p.merchantRaw)
    }

    @Test
    fun `Scapia RuPay is still a debit`() {
        val body = "Hi! Your txn of \u20B9565.23 at Anthropic + Us on your Scapia Federal RuPay credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(565.23, p.amount, 0.001)
        assertEquals("SCAPIA", p.templateId)
        assertEquals("CC", p.cardType)
    }

    @Test
    fun `Scapia card payment received is ignored`() {
        val body = "Yay! We've received your payment of \u20B9791.32 towards your Scapia Federal credit card. -Federal Bank"
        assertNull(BankSmsParser.parse(body, received))
    }

    @Test
    fun `numeric sender is accepted from Scapia body`() {
        val body = "Hi! Your txn of \u20B9791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank"
        assertTrue(KnownBankSenders.shouldAccept("+919840012345", body))
        assertTrue(KnownBankSenders.shouldAccept("", body))
        assertFalse(KnownBankSenders.shouldAccept("+919840012345", "Dinner at 8?"))
        assertTrue(KnownBankSenders.isBank("AX-FEDADV"))
        assertTrue(KnownBankSenders.isBank("VM-FDRLBN"))
    }

    @Test
    fun `Scapia rewards txn is still a debit`() {
        val body = "Your txn of ₹6,840.00 at Scapia on your Scapia Federal Visa credit card earned you 20% rewards! Not you? Call 18002961199. - Federal Bank"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(6840.0, p.amount, 0.001)
        assertEquals("SCAPIA", p.bank)
        assertEquals("Scapia", p.merchantRaw)
    }

    @Test
    fun `T8 HDFC a c debit is UPI Transfer`() {
        val body = "HDFC Bank:Rs. 589.00 debited from a/c *7372 on 27/08/26 to a/c **8640 (UPI Ref No. 233824882396). Not you? Call on 18002586161 to report"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(589.0, p.amount, 0.001)
        assertEquals("HDFC", p.bank)
        assertEquals("DB", p.cardType)
        assertEquals("UPI Transfer", p.merchantRaw)
        assertEquals("T8", p.templateId)
        assertEquals("7372", p.instrumentLast4)
    }

    @Test
    fun `truncated merchant is cleaned`() {
        assertEquals("Sundaram Medical", BankSmsParser.cleanMerchant("..SUNDARAM MEDICAL_"))
    }

    @Test
    fun `opaque VPA is kept`() {
        assertEquals("paytmqr5yt66v@ptys", BankSmsParser.cleanMerchant("paytmqr5yt66v@ptys"))
    }

    @Test
    fun `paytm brand VPA collapses`() {
        assertEquals("Paytm", BankSmsParser.cleanMerchant("paytm.s29gayk@pty"))
    }

    @Test
    fun `comma grouped T1 amount`() {
        val body = "Sent Rs.2,822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\nOn 10/09/26\nRef 859114032536"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals(2822.0, p.amount, 0.001)
    }

    @Test
    fun `T7 then T1b does not double count the notice`() {
        val notice = "E-Mandate!\nRs.95.70 will be deducted on 03/08/26, 00:00:00\nFor GOOGLECLOUD mandate"
        val debit = "UPI Mandate:\nSent Rs.95.70\nfrom HDFC Bank A/c 7372\nTo GOOGLECLOUD\n03/08/26\nRef 441122334455"
        assertNull(BankSmsParser.parse(notice, received))
        val p = BankSmsParser.parse(debit, received)!!
        assertEquals(95.70, p.amount, 0.001)
    }

    @Test
    fun `dedupe bucket collapses the same minute`() {
        val base = 1_200_000L
        val a = SmsDeduper.bucketKey("HDFCBK", 20.0, base)
        val b = SmsDeduper.bucketKey("HDFCBK", 20.0, base + 30_000)
        val c = SmsDeduper.bucketKey("HDFCBK", 20.0, base + 90_000)
        assertEquals(a, b)
        assertNotNull(c)
        assertTrue(a != c)
    }

    @Test
    fun `Axis collect request is not a debit`() {
        val body = "Axis Bank: Collect request of INR 1,933.00 sent by DIGITALAGERETAILPRIVATECA. Accept in your UPI app."
        assertNull(BankSmsParser.parse(body, received, "AX-AXISBK"))
    }

    @Test
    fun `HDFC payment request is not a debit`() {
        val body = "HDFC Bank: You have received a payment request of Rs.1933.00 from DIGITALAGERETAILPRIVATECA. Approve using UPI PIN."
        assertNull(BankSmsParser.parse(body, received))
    }

    @Test
    fun `declined spend is not a debit`() {
        val body = "Spent Rs.1933 On HDFC Bank Card 5901 At DIGITALAGE On 2026-09-11:12:00:00. Declined. Insufficient funds."
        assertNull(BankSmsParser.parse(body, received))
    }

    @Test
    fun `T1 Sent Rs is still a debit after request filter`() {
        val body = "Sent Rs.2822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\nOn 10/09/26\nRef 859114032536"
        val p = BankSmsParser.parse(body, received)!!
        assertEquals("T1", p.templateId)
        assertEquals(2822.0, p.amount, 0.001)
    }

    @Test
    fun `accept in UPI app without request is not a debit`() {
        val body = "Axis Bank: INR 1,933.00 sent by DIGITALAGERETAILPRIVATECA. Accept in your UPI app."
        assertNull(BankSmsParser.parse(body, received, "AX-AXISBK"))
    }

    @Test
    fun `gold corpus original inbox still classifies`() {
        data class Row(
            val sender: String,
            val body: String,
            val amount: Double,
            val bank: String,
            val card: String,
            val template: String,
            val last4: String?,
        )
        val rows = listOf(
            Row(
                "AX-AXISBK",
                "Spent INR 4173.16\nAxis Bank Card no. XX7159\n15-08-26 13:44:31 IST\nBharat Petr\nAvl Limit: INR 57827.35\nNot you? SMS BLOCK 7159 to 919951860002",
                4173.16, "AXIS", "CC", "AXIS", "7159",
            ),
            Row(
                "AX-AXISBK",
                "Spent INR 3790.37\nAxis Bank Card no. XX7159\n19-06-26 15:37:26 IST\nSTAR FUEL S\nAvl Limit: INR 50884.25",
                3790.37, "AXIS", "CC", "AXIS", "7159",
            ),
            Row(
                "VM-ICICIB",
                "Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21.",
                8153.0, "ICICI", "CC", "ICICI", "7003",
            ),
            Row(
                "VM-ICICIB",
                "INR 1,004.00 spent using ICICI Bank Card XX7003 on 01-Sep-26 on AMAZON PAY IN E. Avl Limit: INR 17,10,251.21.",
                1004.0, "ICICI", "CC", "ICICI", "7003",
            ),
            Row(
                "VM-ICICIB",
                "Rs 18,525.84 spent on ICICI Bank Card XX7003 on 15-Aug-26 at AMAZON PAY IN E. Avl Lmt: Rs 16,76,317.21.",
                18525.84, "ICICI", "CC", "ICICI", "7003",
            ),
            Row(
                "VM-FEDBNK",
                "Hi! Your txn of \u20B9791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank",
                791.32, "SCAPIA", "CC", "SCAPIA", null,
            ),
            Row(
                "VM-FEDBNK",
                "Hi! Your txn of \u20B9565.23 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank",
                565.23, "SCAPIA", "CC", "SCAPIA", null,
            ),
            Row(
                "JM-HDFCBK",
                "HDFC Bank:Rs. 589.00 debited from a/c *7372 on 27/08/26 to a/c **8640 (UPI Ref No. 233824882396). Not you? Call on 18002586161 to report",
                589.0, "HDFC", "DB", "T8", "7372",
            ),
        )
        for (row in rows) {
            assertTrue(KnownBankSenders.shouldAccept(row.sender, row.body))
            assertTrue(KnownBankSenders.shouldAccept("+919000000000", row.body))
            assertTrue(KnownBankSenders.shouldAccept("", row.body))
            val p = BankSmsParser.parse(row.body, received, row.sender)!!
            assertEquals(row.amount, p.amount, 0.001)
            assertEquals(row.bank, p.bank)
            assertEquals(row.card, p.cardType)
            assertEquals(row.template, p.templateId)
            if (row.last4 != null) assertEquals(row.last4, p.instrumentLast4)
        }
        assertNull(
            BankSmsParser.parse(
                "Axis Bank: Collect request of INR 1,933.00 sent by DIGITALAGERETAILPRIVATECA. Accept in your UPI app.",
                received,
                "AX-AXISBK",
            ),
        )
        assertNull(
            BankSmsParser.parse(
                "Yay! We've received your payment of \u20B9791.32 towards your Scapia Federal credit card. -Federal Bank",
                received,
            ),
        )
    }

    @Test
    fun `has sent you is not a debit`() {
        val body = "HDFC Bank: MONISH has sent you Rs.500.00 via UPI."
        assertNull(BankSmsParser.parse(body, received))
    }
}
