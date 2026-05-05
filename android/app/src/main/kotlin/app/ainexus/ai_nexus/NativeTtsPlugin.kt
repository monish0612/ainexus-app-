package app.ainexus.ai_nexus

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class NativeTtsPlugin(
    private val context: Context,
    flutterEngine: FlutterEngine,
) {
    companion object {
        private const val TAG = "NativeTTS"
        private const val CHANNEL = "app.ainexus.ai_nexus/native_tts"
        private const val GOOGLE_ENGINE = "com.google.android.tts"
    }

    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var utteranceId = 0
    private var volume = 1.0f

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    private fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initEngine(result)
            "speak" -> speak(call.argument<String>("text") ?: "", result)
            "stop" -> stop(result)
            "setLanguage" -> {
                val lang = call.argument<String>("language") ?: "en-US"
                val locale = if (lang == "en-US") Locale.US else Locale.forLanguageTag(lang)
                tts?.setLanguage(locale)
                result.success(1)
            }
            "setSpeechRate" -> {
                tts?.setSpeechRate((call.argument<Double>("rate") ?: 0.5).toFloat())
                result.success(1)
            }
            "setVolume" -> {
                volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                result.success(1)
            }
            "setPitch" -> {
                tts?.setPitch((call.argument<Double>("pitch") ?: 1.0).toFloat())
                result.success(1)
            }
            "getEngines" -> {
                result.success(tts?.engines?.map { it.name } ?: emptyList<String>())
            }
            "shutdown" -> {
                shutdown()
                result.success(1)
            }
            else -> result.notImplemented()
        }
    }

    private fun initEngine(result: MethodChannel.Result) {
        shutdown()

        tryEngine(GOOGLE_ENGINE) { success ->
            if (success) {
                mainHandler.post { result.success(1) }
            } else {
                Log.w(TAG, "Google TTS failed, trying system default")
                tryEngine(null) { fallbackSuccess ->
                    mainHandler.post { result.success(if (fallbackSuccess) 1 else 0) }
                }
            }
        }
    }

    private fun tryEngine(engine: String?, onResult: (Boolean) -> Unit) {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false

        val initListener = TextToSpeech.OnInitListener { status ->
            val ok = status == TextToSpeech.SUCCESS
            if (ok) {
                ready = true
                tts?.setOnUtteranceProgressListener(progressListener)
            } else {
                Log.e(TAG, "Engine init failed (${engine ?: "default"}): status=$status")
            }
            onResult(ok)
        }

        tts = if (engine != null) {
            TextToSpeech(context, initListener, engine)
        } else {
            TextToSpeech(context, initListener)
        }
    }

    private fun speak(text: String, result: MethodChannel.Result) {
        if (!ready || tts == null) {
            Log.w(TAG, "speak() called but engine not ready")
            result.success(0)
            return
        }

        val id = "utt_${utteranceId++}"
        val code = tts!!.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        result.success(if (code == TextToSpeech.SUCCESS) 1 else code)
    }

    private fun stop(result: MethodChannel.Result) {
        tts?.stop()
        result.success(1)
    }

    fun shutdown() {
        ready = false
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    private val progressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            mainHandler.post { channel.invokeMethod("onStart", null) }
        }

        override fun onDone(utteranceId: String?) {
            mainHandler.post { channel.invokeMethod("onDone", null) }
        }

        @Deprecated("Deprecated in API")
        override fun onError(utteranceId: String?) {
            Log.e(TAG, "onError(deprecated): $utteranceId")
            mainHandler.post { channel.invokeMethod("onError", "Unknown TTS error") }
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            Log.e(TAG, "onError: errorCode=$errorCode")
            mainHandler.post { channel.invokeMethod("onError", "TTS error code: $errorCode") }
        }

        override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
            mainHandler.post { channel.invokeMethod("onRange", mapOf("start" to start, "end" to end)) }
        }
    }
}
