package app.ainexus.ai_nexus.bubble

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityManager

/**
 * Reports whether our accessibility service is currently enabled.
 *
 * Aggressive OEMs (Samsung One UI, Xiaomi MIUI) kill background work and can
 * silently revoke accessibility permission. We cannot re-grant it ourselves, so
 * the settings screen polls this and walks the user back to Settings.
 */
object Watchdog {
    private const val TAG = "BubbleWatchdog"

    fun component(context: Context): ComponentName =
        ComponentName(context, RephraseAccessibilityService::class.java)

    /**
     * Android stores the enabled-services setting as
     * [ComponentName.flattenToShortString] (`pkg/.bubble.Class`), while
     * [AccessibilityServiceInfo.id] is the same short form. Matching only the
     * long `pkg/full.class.Name` form made Settings claim the service was off
     * while it was actually running.
     */
    fun idsMatch(enabledId: String, component: ComponentName): Boolean =
        idsMatch(enabledId, component.packageName.orEmpty(), component.className.orEmpty())

    fun idsMatch(enabledId: String, packageName: String, className: String): Boolean {
        val id = enabledId.trim()
        if (id.isEmpty() || packageName.isEmpty() || className.isEmpty()) return false
        val longId = "$packageName/$className"
        if (id.equals(longId, ignoreCase = true)) return true
        val shortClass = if (className.startsWith("$packageName.")) {
            className.substring(packageName.length)
        } else {
            className
        }
        if (id.equals("$packageName/$shortClass", ignoreCase = true)) return true
        return try {
            val parsed = ComponentName.unflattenFromString(id) ?: return false
            parsed.packageName.equals(packageName, ignoreCase = true) &&
                parsed.className.equals(className, ignoreCase = true)
        } catch (_: Throwable) {
            false
        }
    }

    fun isEnabled(context: Context): Boolean {
        val cn = component(context)
        try {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
                as AccessibilityManager
            val enabled = am.getEnabledAccessibilityServiceList(
                AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
            )
            if (enabled.any { idsMatch(it.id, cn) }) return true
        } catch (t: Throwable) {
            Log.w(TAG, "manager query failed, falling back to secure setting", t)
        }
        return isInSecureSetting(context, cn)
    }

    private fun isInSecureSetting(context: Context, component: ComponentName): Boolean {
        return try {
            val setting = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(setting)
            while (splitter.hasNext()) {
                if (idsMatch(splitter.next(), component)) return true
            }
            false
        } catch (t: Throwable) {
            Log.w(TAG, "secure setting read failed", t)
            false
        }
    }
}
