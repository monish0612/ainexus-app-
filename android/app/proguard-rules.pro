-keep class app.ainexus.ai_nexus.sms.** { *; }
-keep class app.ainexus.ai_nexus.ExpenseWidget** { *; }
-keep class app.ainexus.ai_nexus.SearchWidget** { *; }
-keep class app.ainexus.ai_nexus.WidgetBootReceiver { *; }
-keep class com.ryanheise.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# ── flutter_local_notifications 17.2.4 (Gson) ─────────────────────────────
# Verified against the 1.0.50 release mapping: the three receivers are
# already kept by the merged manifest, but Gson models are not. R8 renamed
# NotificationAction$NotificationActionInput → e2.a and its fields to
# l/m/n/o, which breaks Gson restore of scheduled notifications and action
# buttons. The plugin uses Gson + RuntimeTypeAdapterFactory and does not
# ship consumer-rules.pro; these lines are the plugin example's Gson rules
# plus a keep of the plugin package so model field names stay stable.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# ── workmanager 0.6.0 ─────────────────────────────────────────────────────
# AndroidX Work already keeps ListenableWorker subclasses (the 1.0.50
# mapping left BackgroundWorker un-obfuscated). Named keep so a plugin
# upgrade cannot drop the class WorkManager instantiates by name.
-keep class dev.fluttercommunity.workmanager.BackgroundWorker { *; }
