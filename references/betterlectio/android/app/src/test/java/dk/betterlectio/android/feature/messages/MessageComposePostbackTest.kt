package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Pure tests for multi-step compose field discovery (iOS/Flutter/extension parity).
 */
class MessageComposePostbackTest {

    @Test
    fun findNewMessageTarget_desktop_newMessageLnk() {
        val html = """
            <a id="s_m_Content_Content_NewMessageLnk" href="javascript:WebForm_DoPostBackWithOptions(new WebForm_PostBackOptions(&quot;s${'$'}m${'$'}Content${'$'}Content${'$'}NewMessageLnk&quot;, &quot;&quot;, true, &quot;&quot;, &quot;&quot;, false, true))">Ny besked</a>
        """.trimIndent()
        assertEquals(
            MessagePostbackFields.NEW_MESSAGE_LNK,
            MessagePostbackFields.findNewMessageTarget(html),
        )
    }

    @Test
    fun findNewMessageTarget_mobile_header_btn() {
        val html = """
            <a onclick="__doPostBack('s${'$'}m${'$'}HeaderContent${'$'}NewMessageThreadBtn',''); return false;"
               id="s_m_HeaderContent_NewMessageThreadBtn">add</a>
        """.trimIndent()
        assertEquals(
            MessagePostbackFields.NEW_MESSAGE_THREAD_BTN,
            MessagePostbackFields.findNewMessageTarget(html),
        )
    }

    @Test
    fun findNewMessageTarget_skips_same_receivers() {
        val html = """
            <a onclick="__doPostBack('s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}NewMessageSameReceiversBtnDesktop','')">same</a>
            <a onclick="__doPostBack('s${'$'}m${'$'}Content${'$'}Content${'$'}NewThreadBtn','')">new</a>
        """.trimIndent()
        assertEquals(
            MessagePostbackFields.NEW_THREAD_BTN,
            MessagePostbackFields.findNewMessageTarget(html),
        )
    }

    @Test
    fun looksLikeComposeForm_real_compose_markers() {
        val html = """
            <input name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}addRecipientDD${'$'}inp" />
            <input name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}MessagesGV${'$'}ctl02${'$'}EditModeHeaderTitleTB${'$'}tb" />
            <a id="s_m_Content_Content_MessageThreadCtrl_MessagesGV_ctl02_SendMessageBtn"
               onclick="__doPostBack('s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}MessagesGV${'$'}ctl02${'$'}SendMessageBtn','')">Send</a>
        """.trimIndent()
        assertTrue(MessagePostbackFields.looksLikeComposeForm(html))
    }

    @Test
    fun looksLikeComposeForm_list_page_false() {
        val html = """
            <table id="s_m_Content_Content_threadGV_ctl00"><tr><td>Emne</td></tr></table>
        """.trimIndent()
        assertFalse(MessagePostbackFields.looksLikeComposeForm(html))
    }

    @Test
    fun looksLikeComposeSendSuccess_thread_view() {
        val html = """
            <div class="message-thread-message-content">Hej</div>
            <div class="message-thread-message-sender">A, 01-01-2026</div>
            <table id="s_m_Content_Content_MessageThreadCtrl_MessagesGV"></table>
        """.trimIndent()
        assertTrue(MessagePostbackFields.looksLikeComposeSendSuccess(html))
    }

    @Test
    fun looksLikeComposeSendSuccess_still_on_compose_false() {
        val html = """
            <input name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}addRecipientDD${'$'}inp" />
            <input name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}MessagesGV${'$'}ctl02${'$'}EditModeHeaderTitleTB${'$'}tb" />
            <a onclick="__doPostBack('s${'$'}m${'$'}…${'$'}SendMessageBtn','')" id="x_SendMessageBtn">Send</a>
        """.trimIndent()
        assertFalse(MessagePostbackFields.looksLikeComposeSendSuccess(html))
    }

    @Test
    fun looksLikeComposeSendSuccess_fejlhandled_false() {
        assertFalse(
            MessagePostbackFields.looksLikeComposeSendSuccess(
                """<html><a href="fejlhandled.aspx?title=Fejl">x</a></html>""",
            ),
        )
    }

    @Test
    fun compose_field_constants_match_ios_flutter() {
        assertEquals(
            "s\$m\$Content\$Content\$MessageThreadCtrl\$AddRecipientBtn",
            MessagePostbackFields.ADD_RECIPIENT_BTN,
        )
        assertEquals(
            "s\$m\$Content\$Content\$MessageThreadCtrl\$addRecipientDD\$inpid",
            MessagePostbackFields.RECIPIENT_INPID,
        )
        assertEquals(
            "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$SendMessageBtn",
            MessagePostbackFields.COMPOSE_SEND,
        )
        assertTrue(MessagePostbackFields.COMPOSE_TITLE.contains("EditModeHeaderTitleTB"))
        assertTrue(MessagePostbackFields.COMPOSE_BODY.contains("EditModeContentBBTB"))
    }

    @Test
    fun compose_source_is_multistep_not_type_nybesked() {
        val candidates = listOf(
            "src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "../app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "android/app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
        )
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: File(
                System.getProperty("user.dir")!!,
                "src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            )
        assertTrue(file.exists())
        val src = file.readText()
        assertFalse(
            "compose must not request one-shot nybesked query",
            src.contains("beskeder2.aspx?type=nybesked") ||
                src.contains("\"type=nybesked\""),
        )
        assertTrue(src.contains("ADD_RECIPIENT_BTN") || src.contains("AddRecipientBtn"))
        assertTrue(src.contains("postFromHtml"))
        assertTrue(src.contains("COMPOSE_SEND") || src.contains("SendMessageBtn"))
        assertTrue(src.contains("findNewMessageTarget"))
    }

    @Test
    fun compose_path_is_bare_beskeder2() {
        assertEquals("beskeder2.aspx", MessageRepository.COMPOSE_PATH)
        assertFalse(MessageRepository.COMPOSE_PATH.contains("type="))
    }
}
