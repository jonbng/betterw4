package dk.betterw4.android.core.w4.di

import android.content.Context
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dk.betterw4.android.BuildConfig
import dk.betterw4.android.core.w4.DefaultLectioClient
import dk.betterw4.android.core.w4.DefaultW4Client
import dk.betterw4.android.core.w4.LectioClient
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.auth.AndroidDeviceAuthenticator
import dk.betterw4.android.core.w4.auth.DefaultSessionExternalWiper
import dk.betterw4.android.core.w4.auth.DeviceAuthenticator
import dk.betterw4.android.core.w4.http.PriorityRequestLimiter
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.core.w4.session.EncryptedCredentialStore
import dk.betterw4.android.core.w4.session.EncryptedSavedLoginStore
import dk.betterw4.android.core.w4.session.LastSchoolStore
import dk.betterw4.android.core.w4.session.SavedLoginStore
import dk.betterw4.android.core.w4.session.SessionExternalWiper
import dk.betterw4.android.core.w4.session.SharedPrefsLastSchoolStore
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class W4BindModule {
    @Binds
    @Singleton
    abstract fun bindW4Client(impl: DefaultW4Client): W4Client

    @Binds
    @Singleton
    abstract fun bindLectioClient(impl: DefaultLectioClient): LectioClient

    @Binds
    @Singleton
    abstract fun bindSessionExternalWiper(impl: DefaultSessionExternalWiper): SessionExternalWiper

    @Binds
    @Singleton
    abstract fun bindLastSchoolStore(impl: SharedPrefsLastSchoolStore): LastSchoolStore

    @Binds
    @Singleton
    abstract fun bindDeviceAuthenticator(impl: AndroidDeviceAuthenticator): DeviceAuthenticator
}

@Module
@InstallIn(SingletonComponent::class)
object W4Module {

    @Provides
    @Singleton
    fun provideCredentialStore(@ApplicationContext context: Context): CredentialStore =
        EncryptedCredentialStore(context)

    @Provides
    @Singleton
    fun provideSavedLoginStore(@ApplicationContext context: Context): SavedLoginStore =
        EncryptedSavedLoginStore(context)

    @Provides
    @Singleton
    fun providePriorityRequestLimiter(): PriorityRequestLimiter = PriorityRequestLimiter()

    /**
     * Dedicated OkHttp client for W4: no system cookie jar, no auto-redirects.
     * Cookie header is the single source of truth (`PHPSESSID` only).
     */
    @Provides
    @Singleton
    @Named("w4")
    fun provideW4OkHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(true)
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
