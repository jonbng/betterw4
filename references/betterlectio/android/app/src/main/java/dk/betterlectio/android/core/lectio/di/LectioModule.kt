package dk.betterlectio.android.core.lectio.di

import android.content.Context
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.core.lectio.DefaultLectioClient
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.auth.AndroidWebViewCookieExtractor
import dk.betterlectio.android.core.lectio.auth.DefaultSessionExternalWiper
import dk.betterlectio.android.core.lectio.auth.WebViewCookieExtractor
import dk.betterlectio.android.core.lectio.http.PriorityRequestLimiter
import dk.betterlectio.android.core.lectio.session.CredentialStore
import dk.betterlectio.android.core.lectio.session.EncryptedCredentialStore
import dk.betterlectio.android.core.lectio.session.LastSchoolStore
import dk.betterlectio.android.core.lectio.session.SessionExternalWiper
import dk.betterlectio.android.core.lectio.session.SharedPrefsLastSchoolStore
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class LectioBindModule {
    @Binds
    @Singleton
    abstract fun bindLectioClient(impl: DefaultLectioClient): LectioClient

    @Binds
    @Singleton
    abstract fun bindWebViewCookieExtractor(impl: AndroidWebViewCookieExtractor): WebViewCookieExtractor

    @Binds
    @Singleton
    abstract fun bindSessionExternalWiper(impl: DefaultSessionExternalWiper): SessionExternalWiper

    @Binds
    @Singleton
    abstract fun bindLastSchoolStore(impl: SharedPrefsLastSchoolStore): LastSchoolStore
}

@Module
@InstallIn(SingletonComponent::class)
object LectioModule {

    @Provides
    @Singleton
    fun provideCredentialStore(@ApplicationContext context: Context): CredentialStore =
        EncryptedCredentialStore(context)

    @Provides
    @Singleton
    fun providePriorityRequestLimiter(): PriorityRequestLimiter = PriorityRequestLimiter()

    /**
     * Dedicated OkHttp client for Lectio: no system cookie jar, no auto-redirects.
     * Cookie header is the single source of truth (iOS URLSession parity).
     */
    @Provides
    @Singleton
    @Named("lectio")
    fun provideLectioOkHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(true)
            // Explicitly no cookie jar — we inject Cookie header ourselves.
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)

        if (BuildConfig.DEBUG) {
            val logging = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            }
            builder.addInterceptor(logging)
        }

        return builder.build()
    }
}
