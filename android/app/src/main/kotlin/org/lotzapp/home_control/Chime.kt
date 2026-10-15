package org.lotzapp.home_control

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log

/**
 * Spielt den Tuerglocken-Gong.
 *
 * Fordert kurzzeitigen Audio-Fokus "mit Ducking" an: laufende Wiedergabe (Spotify,
 * Radio, …) wird vom System leiser gestellt statt gestoppt und danach wieder lauter.
 */
object Chime {
    private const val TAG = "HomeControl"
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        // SONIFICATION (nicht SPEECH), sonst duckt Android nicht automatisch.
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** @param times Anzahl Wiederholungen, @param volume 0..1 relativ zur Medienlautstaerke */
    fun play(context: Context, times: Int = 1, volume: Float = 1f) {
        stop()
        val am = context.getSystemService(AudioManager::class.java)
        requestFocus(am)
        try {
            val afd = context.resources.openRawResourceFd(R.raw.doorbell)
            val mp = MediaPlayer()
            mp.setAudioAttributes(attributes)
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setVolume(volume, volume)
            var remaining = times.coerceIn(1, 10) - 1
            mp.setOnCompletionListener {
                if (remaining > 0) {
                    remaining--
                    it.seekTo(0)
                    it.start()
                } else {
                    stop(am)
                }
            }
            mp.setOnErrorListener { _, _, _ -> stop(am); true }
            mp.prepare()
            mp.start()
            player = mp
        } catch (t: Throwable) {
            Log.w(TAG, "Gong konnte nicht abgespielt werden", t)
            stop(am)
        }
    }

    fun stop(am: AudioManager? = null) {
        player?.release()
        player = null
        val req = focusRequest ?: return
        focusRequest = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) am?.abandonAudioFocusRequest(req)
    }

    private fun requestFocus(am: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .setWillPauseWhenDucked(false)
                .build()
            am.requestAudioFocus(req)
            focusRequest = req
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }
}
