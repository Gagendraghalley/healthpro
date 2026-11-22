package bt.healthpro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * Push notifications' channel (send-push's channel_id, and the manifest's
     * default): they pop up, with sound. Android 8 and later; making it again
     * changes nothing, and the person's own settings for it stay.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel("health_pro", "Notifications", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Join requests, payments, packages ending, trainers, classes and reviews"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
