package app.ainexus.ai_nexus.sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

object SmsAutoPrefs {
    private const val FILE = "sms_auto_expense"
    const val MODE_ASK = "ask"
    const val MODE_AUTO = "auto"

    /** Off until the user finishes setup — SMS is a dangerous permission. */
    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean("enabled", false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean("enabled", enabled).apply()
    }

    fun mode(context: Context): String =
        prefs(context).getString("mode", MODE_ASK) ?: MODE_ASK

    fun setMode(context: Context, mode: String) {
        val v = if (mode == MODE_AUTO) MODE_AUTO else MODE_ASK
        prefs(context).edit().putString("mode", v).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}

object SmsDeduper {
    private const val KEY = "hashes"
    private const val WEEK_MS = 7L * 24 * 60 * 60 * 1000

    fun bucketKey(sender: String, amount: Double, timestampMs: Long): String {
        val bucket = timestampMs / 60_000L
        return "$sender|$amount|$bucket"
    }

    fun isDuplicate(context: Context, sender: String, amount: Double, timestampMs: Long): Boolean {
        val key = bucketKey(sender, amount, timestampMs)
        val now = System.currentTimeMillis()
        val stored = prefs(context).getStringSet(KEY, emptySet()) ?: emptySet()
        val kept = LinkedHashSet<String>()
        var found = false
        for (line in stored) {
            val idx = line.lastIndexOf("::")
            if (idx < 0) continue
            val storedKey = line.substring(0, idx)
            val seenAt = line.substring(idx + 2).toLongOrNull() ?: continue
            if (now - seenAt > WEEK_MS) continue
            if (storedKey == key) found = true
            kept.add(line)
        }
        if (!found) {
            kept.add("$key::$now")
            prefs(context).edit().putStringSet(KEY, kept).commit()
        }
        return found
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("sms_auto_expense", Context.MODE_PRIVATE)
}

object SmsQueue {
    private const val FILE_NAME = "sms_auto_expense_queue.json"
    private const val MAX = 40
    private val lock = Any()

    fun enqueue(context: Context, item: JSONObject) = synchronized(lock) {
        val src = load(context)
        val arr = JSONArray()
        val start = (src.length() - (MAX - 1)).coerceAtLeast(0)
        for (i in start until src.length()) arr.put(src.getJSONObject(i))
        arr.put(item)
        save(context, arr)
    }

    fun all(context: Context): List<JSONObject> = synchronized(lock) {
        val arr = load(context)
        (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    fun get(context: Context, id: String): JSONObject? = synchronized(lock) {
        allUnlocked(context).firstOrNull { it.optString("id") == id }
    }

    fun toFlutterList(context: Context): List<HashMap<String, Any?>> =
        synchronized(lock) { allUnlocked(context).map { SmsJson.toFlutterMap(it) } }

    fun updateStatus(context: Context, id: String, status: String) = synchronized(lock) {
        val arr = load(context)
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.optString("id") == id) {
                o.put("status", status)
            }
        }
        save(context, arr)
    }

    fun remove(context: Context, id: String) = synchronized(lock) {
        val arr = JSONArray()
        val src = load(context)
        for (i in 0 until src.length()) {
            val o = src.getJSONObject(i)
            if (o.optString("id") != id) arr.put(o)
        }
        save(context, arr)
    }

    fun pending(context: Context): List<JSONObject> =
        synchronized(lock) {
            allUnlocked(context).filter { it.optString("status", "pending") == "pending" }
        }

    fun approved(context: Context): List<JSONObject> =
        synchronized(lock) {
            allUnlocked(context).filter { it.optString("status") == "approved" }
        }

    private fun allUnlocked(context: Context): List<JSONObject> {
        val arr = load(context)
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    private fun load(context: Context): JSONArray = try {
        val f = file(context)
        if (!f.exists()) JSONArray() else JSONArray(f.readText())
    } catch (_: Throwable) {
        JSONArray()
    }

    private fun save(context: Context, arr: JSONArray) {
        file(context).writeText(arr.toString())
    }

    fun newId(): String = UUID.randomUUID().toString()
}

object SmsJson {
    fun toFlutterMap(o: JSONObject): HashMap<String, Any?> {
        val out = HashMap<String, Any?>()
        val keys = o.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            out[k] = flutterValue(o.opt(k))
        }
        return out
    }

    private fun flutterValue(v: Any?): Any? {
        if (v == null || v === JSONObject.NULL) return null
        return when (v) {
            is Boolean, is String -> v
            is Int -> v
            is Long -> v
            is Float -> v.toDouble()
            is Double -> v
            is Number -> v.toDouble()
            else -> v.toString()
        }
    }
}
