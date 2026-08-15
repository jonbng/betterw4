package dk.betterlectio.android.core.i18n

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.res.stringResource

/**
 * User-facing text that can be resolved with the active app locale.
 *
 * Prefer [Res] for anything shown in the UI. Use [Raw] only for truly dynamic
 * content (e.g. Lectio-scraped titles) or temporary bridges during migration.
 */
sealed interface UiText {
    data class Res(
        @param:StringRes val id: Int,
        val args: List<Any> = emptyList(),
    ) : UiText {
        constructor(@StringRes id: Int, vararg args: Any) : this(id, args.toList())
    }

    data class Raw(val value: String) : UiText
}

fun UiText.resolve(context: Context): String = when (this) {
    is UiText.Res -> {
        if (args.isEmpty()) context.getString(id)
        else context.getString(id, *args.toTypedArray())
    }
    is UiText.Raw -> value
}

@Composable
@ReadOnlyComposable
fun UiText.asString(): String = when (this) {
    is UiText.Res -> {
        if (args.isEmpty()) stringResource(id)
        else stringResource(id, *args.toTypedArray())
    }
    is UiText.Raw -> value
}
