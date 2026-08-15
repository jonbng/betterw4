package dk.betterw4.android

import android.app.Application
import coil3.ImageLoader
import coil3.SingletonImageLoader
import dagger.hilt.android.HiltAndroidApp
import dk.betterw4.android.core.w4.session.SessionController
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class BetterW4App : Application(), SingletonImageLoader.Factory {

    @Inject
    lateinit var sessionController: SessionController

    @Inject
    lateinit var imageLoader: ImageLoader

    override fun onCreate() {
        plantLogging()
        super.onCreate()
    }

    private fun plantLogging() {
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
    }

    /** Coil uses the cookie-aware ImageLoader from [dk.betterw4.android.core.di.AppModule]. */
    override fun newImageLoader(context: android.content.Context): ImageLoader {
        return if (this::imageLoader.isInitialized) imageLoader
        else ImageLoader.Builder(context).build()
    }
}
