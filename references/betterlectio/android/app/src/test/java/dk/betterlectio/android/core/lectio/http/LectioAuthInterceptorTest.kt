package dk.betterlectio.android.core.lectio.http

import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.session.InMemoryCredentialStore
import dk.betterlectio.android.core.model.Student
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

class LectioAuthInterceptorTest {

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
    fun defaultIsLectioHost_matches_lectio_domains() {
        assertTrue(LectioAuthInterceptor.defaultIsLectioHost("www.lectio.dk"))
        assertTrue(LectioAuthInterceptor.defaultIsLectioHost("www-sso.lectio.dk"))
        assertFalse(LectioAuthInterceptor.defaultIsLectioHost("example.com"))
        assertFalse(LectioAuthInterceptor.defaultIsLectioHost("gravatar.com"))
    }

    @Test
    fun intercept_adds_cookie_and_browser_headers_for_lectio_host() {
        val student = Student(studentId = "12345", gymId = 517, name = "Test")
        val creds = LectioCredentials(
            autologinkey = "auto-key-value",
            sessionId = "session-abc",
            additionalCookies = mapOf("isloggedin3" to "Y"),
        )
        store.saveStudent(student)
        store.saveCredentials(creds, student.studentId)

        server.enqueue(MockResponse().setBody("img-bytes").setResponseCode(200))
        val client = OkHttpClient.Builder()
            .addInterceptor(LectioAuthInterceptor(store) { true })
            .build()
        client.newCall(
            Request.Builder().url(server.url("/lectio/517/GetImage.aspx?pictureid=1")).build(),
        ).execute().close()

        val recorded = server.takeRequest()
        val cookie = recorded.getHeader("Cookie")!!
        assertTrue(cookie.contains("ASP.NET_SessionId=session-abc"))
        assertTrue(cookie.contains("autologinkeyV2=auto-key-value"))
        assertTrue(cookie.contains("isloggedin3=Y"))
        assertEquals(LectioUserAgent.VALUE, recorded.getHeader("User-Agent"))
        assertEquals(LectioUserAgent.REFERER, recorded.getHeader("Referer"))
    }

    @Test
    fun intercept_skips_non_lectio_hosts() {
        store.saveStudent(Student(studentId = "1", gymId = 1, name = "T"))
        store.saveCredentials(LectioCredentials(autologinkey = "k", sessionId = "s"), "1")

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(LectioAuthInterceptor(store) { false })
            .build()
        client.newCall(Request.Builder().url(server.url("/avatar.png")).build())
            .execute()
            .close()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Cookie"))
        // OkHttp may set its own default UA; Lectio-specific headers must not be applied.
        assertFalse(recorded.getHeader("User-Agent").orEmpty().contains("BetterLectio"))
        assertNull(recorded.getHeader("Referer"))
    }

    @Test
    fun intercept_skips_demo_students() {
        store.saveStudent(Student.Demo)
        store.saveCredentials(
            LectioCredentials(autologinkey = "should-not-send", sessionId = "nope"),
            Student.Demo.studentId,
        )

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(LectioAuthInterceptor(store) { true })
            .build()
        client.newCall(Request.Builder().url(server.url("/x")).build()).execute().close()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Cookie"))
        // Browser headers still apply for lectio-shaped hosts.
        assertEquals(LectioUserAgent.VALUE, recorded.getHeader("User-Agent"))
    }

    @Test
    fun intercept_preserves_explicit_cookie_header() {
        val student = Student(studentId = "9", gymId = 1, name = "X")
        store.saveStudent(student)
        store.saveCredentials(
            LectioCredentials(autologinkey = "stored", sessionId = "stored-sess"),
            "9",
        )

        server.enqueue(MockResponse().setBody("ok"))
        val client = OkHttpClient.Builder()
            .addInterceptor(LectioAuthInterceptor(store) { true })
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
            .addInterceptor(LectioAuthInterceptor(store) { true })
            .build()
        client.newCall(Request.Builder().url(server.url("/x")).build()).execute().close()
        assertNull(server.takeRequest().getHeader("Cookie"))
    }
}
