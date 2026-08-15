package dk.betterw4.android.core.di

import android.content.Context
import androidx.room.Room
import coil3.ImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dk.betterw4.android.core.cache.EntityOfflineStore
import dk.betterw4.android.core.w4.http.W4AuthInterceptor
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.feature.offline.OfflineDatabase
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton

/**
 * App-wide bindings. W4 networking lives in [dk.betterw4.android.core.w4.di.W4Module].
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideAppContext(@ApplicationContext context: Context): Context = context

    @Provides
    @Singleton
    fun provideOfflineDatabase(@ApplicationContext context: Context): OfflineDatabase =
        Room.databaseBuilder(context, OfflineDatabase::class.java, "betterw4_offline.db")
            .fallbackToDestructiveMigration(dropAllTables = true)
            .build()

    /**
     * Non-W4 HTTP (public Google Calendar ICS, etc.). Follow redirects, no W4 cookies.
     */
    @Provides
    @Singleton
    @Named("external")
    fun provideExternalOkHttpClient(): OkHttpClient =
        OkHttpClient.Builder()
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .build()

    /**
     * Coil ImageLoader for authenticated W4 assets.
     * Cookie injection is required — Coil does not share [dk.betterw4.android.core.w4.http.W4HttpEngine].
     */
    @Provides
    @Singleton
    fun provideImageLoader(
        @ApplicationContext context: Context,
        credentialStore: CredentialStore,
    ): ImageLoader {
        val authInterceptor = W4AuthInterceptor(credentialStore)
        val okHttp = OkHttpClient.Builder()
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .addInterceptor(authInterceptor)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build()
        return ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { okHttp }))
            }
            .build()
    }

    @Provides
    @Singleton
    @Named("entityOffline")
    fun provideEntityOfflineStore(@ApplicationContext context: Context): EntityOfflineStore {
        val dir = File(context.filesDir, "entity_offline").apply { mkdirs() }
        return EntityOfflineStore(
            backend = object : EntityOfflineStore.DiskBackend {
                private fun file(key: String) =
                    File(dir, key.replace(Regex("[^a-zA-Z0-9._-]"), "_") + ".txt")

                override fun write(key: String, value: String) {
                    file(key).writeText(value)
                }

                override fun read(key: String): String? {
                    val f = file(key)
                    return if (f.exists()) f.readText() else null
                }

                override fun delete(key: String) {
                    file(key).delete()
                }

                override fun clear() {
                    dir.listFiles()?.forEach { it.delete() }
                }
            },
        )
    }
}
