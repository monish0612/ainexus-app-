package app.ainexus.ai_nexus.sms

/**
 * On-device debit SMS parser. Mirrors lib/data/services/sms_auto_expense/sms_parser.dart
 * so the BroadcastReceiver can decide in milliseconds without starting Flutter.
 */
object BankSmsParser {

    private val futureMandate = Regex("will be deducted|E-Mandate!", RegexOption.IGNORE_CASE)
    private val otp = Regex(
        """\bOTP\b|one[ -]?time password|verification code""",
        RegexOption.IGNORE_CASE,
    )
    private val nonCompleted = Regex(
        """collect request|payment request|request to (?:pay|accept)|requested (?:you |to pay|rs\.?|inr|₹)|has requested|\bto accept\b|accept in (?:your )?upi|tap to (?:pay|approve|accept)|enter upi pin|upi pin to|approve (?:in|using|via|the)|kindly (?:approve|accept)|\bcollect of\b|\bsent you\b|has sent (?:you |rs\.?|inr|₹)|being processed|under process|\bdeclined\b|\bfailed\b|\bfailure\b|unsuccessful|\bcancelled\b|\bcanceled\b|\breversed\b|insufficient funds|not successful|could not (?:be )?process|\bexpired\b|\binitiated\b|pending (?:collect|request|payment)|awaiting (?:payee|confirmation)|waiting for|mandate request""",
        RegexOption.IGNORE_CASE,
    )
    private val credit = Regex(
        """\bcredited\b|\breceived\b|\bdeposited\b|\brefund(?:ed)?\b""",
        RegexOption.IGNORE_CASE,
    )
    private val debitHint = Regex(
        """\bspent\b|\bsent\b|\btxn\b|\bdeducted\b|\bdebited\b|\bwithdrawn\b|\bpaid\b|\bpurchase\b""",
        RegexOption.IGNORE_CASE,
    )

    private val t1 = Regex(
        """Sent Rs\.?\s*([\d,]+(?:\.\d+)?)\s*(?:F|f)rom HDFC Bank A[/]?[Cc]\s*\*?(\d{4}).*?(?:T|t)o\s+(.+?)\s*(?:On\s*)?(\d{2}/\d{2}/\d{2}).*?Ref\s+(\d+)""",
        setOf(RegexOption.DOT_MATCHES_ALL),
    )
    private val t2 = Regex(
        """Txn Rs\.?\s*([\d,]+(?:\.\d+)?)\s*On HDFC Bank Card\s+([xX]?\d{4})\s*At\s+(.+?)\s*by UPI\s+(\d+)\s*On\s+(\d{2}-\d{2})""",
        setOf(RegexOption.DOT_MATCHES_ALL),
    )
    private val t3t4 = Regex(
        """Spent Rs\.?\s*([\d,]+(?:\.\d+)?)\s+(?:On|From)\s+HDFC Bank Card\s+[xX]?(\d{4})\s+At\s+(.+?)\s+On\s+(\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2})(?:\s+Bal\s+Rs\.?\s*([\d,]+(?:\.\d+)?))?""",
    )
    private val t5 = Regex(
        """Rs\.?\s*([\d,]+(?:\.\d+)?)\s+spent\s+on\s+HDFC Bank Card\s+[xX]?(\d{4})\s+at\s+(.+?)\s+on\s+(\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2})(?:\s+Avl bal:\s*([\d,]+(?:\.\d+)?))?""",
        RegexOption.IGNORE_CASE,
    )
    private val t6 = Regex(
        """INR\s+([\d,]+(?:\.\d+)?)\s+deducted from HDFC Bank A/C No\s+(\d+)\s+towards\s+(.+?)\s+UMRN""",
        RegexOption.IGNORE_CASE,
    )
    private val t8 = Regex(
        """HDFC Bank:\s*Rs\.?\s*([\d,]+(?:\.\d+)?)\s+debited from a/c\s*\*?(\d{4})\s+on\s+(\d{2}/\d{2}/\d{2})""",
        RegexOption.IGNORE_CASE,
    )
    private val axis = Regex(
        """Spent\s+(?:INR|Rs\.?)\s*([\d,]+(?:\.\d+)?)\s+Axis Bank Card no\.?\s*XX(\d{4})\s+(\d{2}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s*IST\s+(.+?)\s+Avl Limit""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )
    private val icici = Regex(
        """(?:Rs\.?|INR)\s*([\d,]+(?:\.\d+)?)\s+spent\s+(?:on|using)\s+ICICI Bank Card\s+XX(\d{4})\s+on\s+(\d{2}-[A-Za-z]{3}-\d{2})\s+(?:at|on)\s+(.+?)\.?\s*Avl""",
        RegexOption.IGNORE_CASE,
    )
    private val scapia = Regex(
        """Your txn of\s*(?:(?:rs\.?|inr)\s*)?[\u20B9\u20A8]?\s*([\d,]+(?:\.\d+)?)\s+at\s+(.+?)\s+on your\s+Scapia""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
    )
    private val blockCode = Regex("""SMS BLOCK (CC|DC)\s+(\d{4})""", RegexOption.IGNORE_CASE)
    private val genericAmount = Regex(
        """(?:rs\.?|inr|[\u20B9\u20A8])\s*([\d,]+(?:\.\d{1,2})?)""",
        RegexOption.IGNORE_CASE,
    )
    private val genericMerchant = Regex(
        """\b(?:at|to|towards)\s+(.+?)(?:\s+(?:by\b|on\b|ref\b|not\s+you|avl\b|to\s+block|umrn\b)|$)""",
        RegexOption.IGNORE_CASE,
    )

    data class Debit(
        val amount: Double,
        val merchantRaw: String,
        val instrument: String,
        val instrumentLast4: String?,
        val transactionDateMs: Long,
        val bank: String,
        val cardType: String,
        val referenceId: String?,
        val balanceAfter: Double?,
        val templateId: String,
        val rawBody: String,
    )

    fun parse(body: String, smsReceivedAt: Long, sender: String? = null): Debit? {
        val text = normalizeSms(body)
        if (text.isEmpty()) return null
        if (futureMandate.containsMatchIn(text)) return null
        if (otp.containsMatchIn(text)) return null
        if (nonCompleted.containsMatchIn(text)) return null

        val block = blockCode.find(text)
        val blockKind = block?.groupValues?.getOrNull(1)?.uppercase()
        val fromBlock = when (blockKind) {
            "CC" -> "CREDIT_CARD"
            "DC" -> "DEBIT_CARD"
            else -> null
        }

        t1.find(text)?.let { m ->
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2],
                merchant = m.groupValues[3],
                dateMs = parseDdMmYy(m.groupValues[4], smsReceivedAt),
                ref = m.groupValues[5],
                instrument = "BANK_ACCOUNT",
                cardType = "DB",
                template = "T1",
                body = text,
            )
        }
        t2.find(text)?.let { m ->
            val instrument = fromBlock ?: "CREDIT_CARD"
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2].replace(Regex("[xX]"), ""),
                merchant = m.groupValues[3],
                dateMs = parseDdMmInferYear(m.groupValues[5], smsReceivedAt),
                ref = m.groupValues[4],
                instrument = instrument,
                cardType = if (instrument == "CREDIT_CARD") "CC" else "DB",
                template = "T2",
                body = text,
            )
        }
        (t3t4.find(text) ?: t5.find(text))?.let { m ->
            val instrument = fromBlock ?: "CREDIT_CARD"
            val bal = m.groupValues.getOrNull(5)?.takeIf { it.isNotBlank() }
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2],
                merchant = m.groupValues[3],
                dateMs = parseIsoDateTime(m.groupValues[4]),
                ref = null,
                instrument = instrument,
                cardType = if (instrument == "CREDIT_CARD") "CC" else "DB",
                template = "T3",
                body = text,
                balanceAfter = num(bal),
            )
        }
        t6.find(text)?.let { m ->
            val acct = m.groupValues[2]
            return hdfc(
                amount = m.groupValues[1],
                last4 = if (acct.length >= 4) acct.takeLast(4) else acct,
                merchant = m.groupValues[3],
                dateMs = smsReceivedAt,
                ref = null,
                instrument = "BANK_ACCOUNT",
                cardType = "DB",
                template = "T6",
                body = text,
            )
        }
        t8.find(text)?.let { m ->
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2],
                merchant = "UPI Transfer",
                dateMs = parseDdMmYy(m.groupValues[3], smsReceivedAt),
                ref = null,
                instrument = "BANK_ACCOUNT",
                cardType = "DB",
                template = "T8",
                body = text,
            )
        }
        axis.find(text)?.let { m ->
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2],
                merchant = m.groupValues[5],
                dateMs = parseDdMmYyLoose(m.groupValues[3], smsReceivedAt),
                ref = null,
                instrument = "CREDIT_CARD",
                cardType = "CC",
                template = "AXIS",
                body = text,
                bank = "AXIS",
            )
        }
        icici.find(text)?.let { m ->
            return hdfc(
                amount = m.groupValues[1],
                last4 = m.groupValues[2],
                merchant = m.groupValues[4],
                dateMs = parseDdMonYy(m.groupValues[3], smsReceivedAt),
                ref = null,
                instrument = "CREDIT_CARD",
                cardType = "CC",
                template = "ICICI",
                body = text,
                bank = "ICICI",
            )
        }
        scapia.find(text)?.let { m ->
            return hdfc(
                amount = m.groupValues[1],
                last4 = null,
                merchant = cleanScapiaMerchant(m.groupValues[2]),
                dateMs = smsReceivedAt,
                ref = null,
                instrument = "CREDIT_CARD",
                cardType = "CC",
                template = "SCAPIA",
                body = text,
                bank = "SCAPIA",
            )
        }

        if (credit.containsMatchIn(text) && !debitHint.containsMatchIn(text)) return null
        if (!debitHint.containsMatchIn(text)) return null
        return generic(text, smsReceivedAt, sender, fromBlock)
    }

    private fun generic(
        text: String,
        smsReceivedAt: Long,
        sender: String?,
        fromBlock: String?,
    ): Debit? {
        val amt = genericAmount.find(text) ?: return null
        val amount = num(amt.groupValues[1]) ?: return null
        if (amount <= 0) return null
        var merchant = ""
        val flat = text.replace('\n', ' ')
        for (m in genericMerchant.findAll(flat)) {
            val candidate = cleanMerchant(m.groupValues[1])
            if (candidate.length >= 2 && candidate.any { it.isLetter() }) {
                merchant = candidate
                break
            }
        }
        val instrument = fromBlock
            ?: if (Regex("""block\s+cc|\bcredit\s*card\b""", RegexOption.IGNORE_CASE).containsMatchIn(text)) {
                "CREDIT_CARD"
            } else {
                "BANK_ACCOUNT"
            }
        return Debit(
            amount = amount,
            merchantRaw = merchant,
            instrument = instrument,
            instrumentLast4 = null,
            transactionDateMs = smsReceivedAt,
            bank = bankFrom(text, sender),
            cardType = if (instrument == "CREDIT_CARD") "CC" else "DB",
            referenceId = null,
            balanceAfter = null,
            templateId = "GENERIC",
            rawBody = text,
        )
    }

    private fun hdfc(
        amount: String,
        last4: String?,
        merchant: String,
        dateMs: Long,
        instrument: String,
        cardType: String,
        template: String,
        body: String,
        ref: String?,
        balanceAfter: Double? = null,
        bank: String = "HDFC",
    ): Debit? {
        val n = num(amount) ?: return null
        if (n <= 0) return null
        val cleaned = if (template == "T8") "UPI Transfer" else cleanMerchant(merchant)
        return Debit(
            amount = n,
            merchantRaw = cleaned,
            instrument = instrument,
            instrumentLast4 = last4,
            transactionDateMs = dateMs,
            bank = bank,
            cardType = cardType,
            referenceId = ref,
            balanceAfter = balanceAfter,
            templateId = template,
            rawBody = body,
        )
    }

    private fun num(raw: String?): Double? {
        if (raw.isNullOrBlank()) return null
        return raw.replace(",", "").toDoubleOrNull()
    }

    fun cleanMerchant(raw: String): String {
        var s = raw.trim()
        while (s.startsWith('.')) s = s.drop(1).trim()
        if (s.endsWith('_')) s = s.dropLast(1).trim()
        s = s.replace(Regex("""\s+\+\s*U[s]?\s*$"""), "")
        s = s.replace(Regex("""\s+\+\s*$"""), "")
        s = s.replace(Regex("""\s+"""), " ").trim()
        if (s.isEmpty()) return ""
        if (s.contains('@')) {
            val local = s.substringBefore('@')
            val brand = local.split(Regex("""[.\d]""")).firstOrNull()?.trim()?.lowercase().orEmpty()
            val known = setOf(
                "paytm", "phonepe", "gpay", "amazon", "bhim",
                "okbizaxis", "okicici", "okhdfcbank", "okaxis", "apl",
            )
            s = if (brand in known) brand else return s.lowercase()
        }
        s = s.replace(Regex("""\s*\.\s*"""), ". ").replace(Regex("""\s+"""), " ").trim()
        return s.split(' ').filter { it.isNotEmpty() }.joinToString(" ") { w ->
            if (w.length == 1) w.uppercase()
            else w[0].uppercaseChar() + w.substring(1).lowercase()
        }
    }

    fun bankFrom(body: String, sender: String?): String {
        val hay = "${body.lowercase()} ${(sender ?: "").lowercase()}"
        return when {
            "hdfc" in hay -> "HDFC"
            "icici" in hay -> "ICICI"
            "axis" in hay -> "AXIS"
            "scapia" in hay -> "SCAPIA"
            "federal" in hay -> "SCAPIA"
            else -> "HDFC"
        }
    }

    fun parseDdMmYy(ddMmYy: String, smsReceivedAt: Long): Long {
        val p = ddMmYy.split('/')
        if (p.size != 3) return smsReceivedAt
        val d = p[0].toIntOrNull() ?: 1
        val m = p[1].toIntOrNull() ?: 1
        var y = p[2].toIntOrNull() ?: return smsReceivedAt
        if (y < 100) y += 2000
        return java.util.Calendar.getInstance().apply {
            set(y, m - 1, d, 0, 0, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    fun parseDdMmYyLoose(raw: String, smsReceivedAt: Long): Long {
        return parseDdMmYy(raw.replace("-", "/"), smsReceivedAt)
    }

    fun parseDdMonYy(raw: String, smsReceivedAt: Long): Long {
        val months = mapOf(
            "jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4,
            "may" to 5, "jun" to 6, "jul" to 7, "aug" to 8,
            "sep" to 9, "oct" to 10, "nov" to 11, "dec" to 12,
        )
        val m = Regex("""^(\d{1,2})-([A-Za-z]{3})-(\d{2})$""").find(raw.trim())
            ?: return smsReceivedAt
        val d = m.groupValues[1].toIntOrNull() ?: 1
        val month = months[m.groupValues[2].lowercase()] ?: return smsReceivedAt
        var y = m.groupValues[3].toIntOrNull() ?: return smsReceivedAt
        if (y < 100) y += 2000
        return java.util.Calendar.getInstance().apply {
            set(y, month - 1, d, 0, 0, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun cleanScapiaMerchant(raw: String): String {
        var s = raw.trim()
        s = s.replace(Regex("""\s+\+\s*U[s]?\s*$"""), "")
        s = s.replace(Regex("""\s+\+\s*$"""), "")
        return s.trim()
    }

    fun normalizeSms(body: String): String {
        var s = body
            .replace('\u00A0', ' ')
            .replace('\u202F', ' ')
            .replace('\u2007', ' ')
            .replace('\u2008', ' ')
            .replace('\u2009', ' ')
            .replace('\u0085', ' ')
            .replace("\r\n", " ")
            .replace('\n', ' ')
            .replace('\r', ' ')
            .replace("\u200B", "")
            .replace("\uFEFF", "")
            .replace("\u00AD", "")
            .replace('\u20A8', '\u20B9')
            .replace("\u00E2\u201A\u00B9", "\u20B9")
            .replace("\u00E2\u0082\u00B9", "\u20B9")
        return s.trim().replace(Regex(" {2,}"), " ")
    }

    fun parseDdMmInferYear(ddMm: String, smsReceivedAt: Long): Long {
        val p = ddMm.split('-')
        if (p.size != 2) return smsReceivedAt
        val d = p[0].toIntOrNull() ?: 1
        val m = p[1].toIntOrNull() ?: 1
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = smsReceivedAt }
        val year = cal.get(java.util.Calendar.YEAR)
        val inferred = java.util.Calendar.getInstance().apply {
            set(year, m - 1, d, 0, 0, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val deltaDays = (inferred.timeInMillis - smsReceivedAt) / 86_400_000L
        if (deltaDays > 14) inferred.add(java.util.Calendar.YEAR, -1)
        return inferred.timeInMillis
    }

    fun parseIsoDateTime(raw: String): Long {
        val normalized = raw.replaceFirst(Regex("""^(\d{4}-\d{2}-\d{2}):"""), "$1T")
        return try {
            java.time.LocalDateTime.parse(normalized).atZone(java.time.ZoneId.systemDefault())
                .toInstant().toEpochMilli()
        } catch (_: Throwable) {
            System.currentTimeMillis()
        }
    }
}

object KnownBankSenders {
    private val tokens = listOf(
        "HDFC", "ICICI", "AXIS", "SCAPIA", "SCPIA", "SCPCRD",
        "SBI", "KOTAK", "IDFC", "PAYTM",
        "CITI", "HSBC", "INDUS", "FEDERAL", "FEDBNK", "FEDBANK",
        "FEDADV", "FEDOTP", "FDRL",
        "CANBNK", "UNIONB", "PNB", "BOB",
        "YESB", "IDBI", "UPI",
    )

    fun isBank(sender: String): Boolean {
        val n = sender.uppercase().replace(Regex("[^A-Z0-9]"), "")
        if (n.isEmpty()) return false
        return tokens.any { n.contains(it) }
    }

    fun shouldAccept(sender: String, body: String): Boolean {
        if (isBank(sender)) return true
        return bodyLooksLikeBankDebit(body)
    }

    fun bodyLooksLikeScapiaOrFederal(body: String): Boolean = bodyLooksLikeBankDebit(body)

    fun bodyLooksLikeBankDebit(body: String): Boolean {
        val hay = body.lowercase()
        if ("on your scapia" in hay) return true
        if ("scapia federal" in hay) return true
        if (Regex("""[-–—]\s*federal bank\s*$""").containsMatchIn(hay.trim())) return true
        if ("axis bank" in hay) return true
        if ("icici bank" in hay) return true
        if ("hdfc bank" in hay) return true
        return false
    }
}
