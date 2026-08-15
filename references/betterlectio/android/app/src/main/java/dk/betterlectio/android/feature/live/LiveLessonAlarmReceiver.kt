package dk.betterlectio.android.feature.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Alarm fires at lesson boundary; kicks WorkManager for Hilt-injected refresh.
 */
class LiveLessonAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val req = OneTimeWorkRequestBuilder<LiveLessonRefreshWorker>().build()
        WorkManager.getInstance(context).enqueue(req)
    }
}
