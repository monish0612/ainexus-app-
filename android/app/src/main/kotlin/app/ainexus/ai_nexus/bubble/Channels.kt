package app.ainexus.ai_nexus.bubble

/**
 * Channel + entrypoint names shared between the accessibility service, the
 * overlay Flutter engine and MainActivity.
 *
 * Keep in sync with lib/bubble/overlay/overlay_bridge.dart and
 * lib/bubble/bubble_settings_channel.dart.
 */
object Channels {
    /** Overlay engine <-> accessibility service (bubble/panel commands). */
    const val OVERLAY_METHOD = "app.ainexus.ai_nexus/bubble_overlay"

    /** Main engine <-> MainActivity (permissions + master toggle). */
    const val SETTINGS_METHOD = "app.ainexus.ai_nexus/bubble"

    const val OVERLAY_ENGINE_ID = "nexus_bubble_overlay_engine"

    /** Top-level function annotated @pragma('vm:entry-point') in lib/main.dart. */
    const val OVERLAY_ENTRYPOINT = "overlayMain"
}
