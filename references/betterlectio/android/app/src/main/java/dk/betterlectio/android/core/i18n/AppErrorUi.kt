package dk.betterlectio.android.core.i18n

import dk.betterlectio.android.R
import dk.betterlectio.android.core.result.AppError

fun AppError.toUiText(): UiText = when (this) {
    AppError.Offline -> UiText.Res(R.string.error_offline)
    AppError.SessionExpired, AppError.Unauthorized -> UiText.Res(R.string.error_session_expired)
    AppError.RobotDetection -> UiText.Res(R.string.error_robot)
    is AppError.Network -> message?.let { UiText.Raw(it) } ?: UiText.Res(R.string.error_network)
    is AppError.Parsing -> UiText.Raw(message)
    is AppError.Unknown -> message?.let { UiText.Raw(it) } ?: UiText.Res(R.string.error_generic)
}
