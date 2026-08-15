package dk.betterw4.android.core.w4.http

import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.session.InMemoryCredentialStore
import dk.betterw4.android.core.model.Student
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class W4AuthInterceptorTest {

    private lateinit var server: MockWebServer
    private lateinit var store: InMemoryCredentialStore

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = InMemoryCredentialStore()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun defaultIsW4Host_matches_w4_only() {
        assertTrue(W4AuthInterceptor.defaultIsW4Host("w4.uwcrcn.no"))
        assertFalse(W4AuthInterceptor.defaultIsW4Host("www-sso.lectio.dk"))
        assertFalse(W4AuthInterceptor.defaultIsW4Host("example.com"))
        assertFalse(W4AuthInterceptor.defaultIsW4Host("gravatar.com"))
    }

    @Test
    fun intercept_adds_phpsessid_and_browser_headers_for_w4_host() {
        val student = Student(studentId = "12345", gymId = 517, name = "Test")
        val creds = W4Credentials(
            autologinkey = "auto-key-value",
            sessionId = "session-abc",
            additionalCookies = mapOf("isloggedin3" to "Y"),
        )
        store.saveStudent(student)
        store.saveCredentials(creds, student.studentId)

        server.enqueue(MockResponse().setBody("img-bytes").setResponseCode(200))
        val client = OkHttpClient.Builder()
            .addInterceptor(W4AuthInterceptor(store) { true })
            .build()
        client.newCall(
            Request.Builder().url(server.url("/photos/nc26jban_thumb.jpg")).build(),
        ).execute().close()

        val recorded = server.takeRequest()
        val cookie = recorded.getHeader("Cookie")!!
        assertTrue(cookie.contains("PHPSESSID=session-abc"))
        assertFalse(cookie.contains("autologinkeyV2"))
        assertFalse(cookie.contains("isloggedin3"))
        assertEquals(W4UserAgent.VALUE, recorded.getHeader("User-Agent"))
        assertEquals(W4UserAgent.REFERER, recorded.getHeader("Referer"))
    }

    @Test
    fun intercept_skips_non_w4_hosts() {
        store.saveStudent(Student(studentId = "1", gymId = 1, name = "T"))
        store.saveCredentials(W4Credentials(autologinkey = "k", sessionId = "s"), "1")

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(W4AuthInterceptor(store) { false })
            .build()
        client.newCall(Request.Builder().url(server.url("/avatar.png")).build())
            .execute()
            .close()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Cookie"))
        assertFalse(recorded.getHeader("User-Agent").orEmpty().contains("BetterW4"))
        assertNull(recorded.getHeader("Referer"))
    }

    @Test
    fun intercept_skips_demo_students() {
        store.saveStudent(Student.Demo)
        store.saveCredentials(
            W4Credentials(autologinkey = "should-not-send", sessionId = "nope"),
            Student.Demo.studentId,
        )

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(W4AuthInterceptor(store) { true })
            .build()
        client.newCall(Request.Builder().url(server.url("/x")).build()).execute().close()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Cookie"))
        assertEquals(W4UserAgent.VALUE, recorded.getHeader("User-Agent"))
    }

    @Test
    fun intercept_preserves_explicit_cookie_header() {
        val student = Student(studentId = "9", gymId = 1, name = "X")
        store.saveStudent(student)
        store.saveCredentials(
            W4Credentials(autologinkey = "stored", sessionId = "stored-sess"),
            "9",
        )

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(W4AuthInterceptor(store) { true })
            .build()
        client.newCall(
            Request.Builder()
                .url(server.url("/x"))
                .header("Cookie", "manual=1")
                .build(),
        ).execute().close()

        assertEquals("manual=1", server.takeRequest().getHeader("Cookie"))
    }

    @Test
    fun intercept_no_cookie_when_no_session() {
        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(W4AuthInterceptor(store) { true })
            .build()
        client.newCall(Request.Builder().url(server.url("/x")).build()).execute().close()
        assertNull(server.takeRequest().getHeader("Cookie"))
    }
}
