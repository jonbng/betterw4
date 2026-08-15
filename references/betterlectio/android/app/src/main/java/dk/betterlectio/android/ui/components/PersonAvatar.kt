package dk.betterlectio.android.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dk.betterlectio.android.feature.directory.AvatarRepository
import dk.betterlectio.android.feature.directory.DirectoryEntity
import dk.betterlectio.android.feature.directory.DirectoryEntityKind

@EntryPoint
@InstallIn(SingletonComponent::class)
interface AvatarRepositoryEntryPoint {
    fun avatarRepository(): AvatarRepository
}

/**
 * Circular person photo with initials fallback.
 *
 * Lazily resolves Lectio `GetImage` URLs via [AvatarRepository] (cookie-aware Coil
 * singleton loads the bitmap). Use for directory, messages, and schedule teachers.
 *
 * Photos are cropped with [Alignment.TopCenter] so heads stay visible in portraits.
 */
@Composable
fun PersonAvatar(
    name: String,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    entityId: String? = null,
    kind: DirectoryEntityKind? = null,
    teacherNumericId: String? = null,
    knownUrl: String? = null,
) {
    val context = LocalContext.current
    val repo = remember {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            AvatarRepositoryEntryPoint::class.java,
        ).avatarRepository()
    }

    var url by remember(entityId, name, teacherNumericId, knownUrl) {
        mutableStateOf(
            repo.peekUrl(
                entityId = entityId,
                name = name,
                teacherNumericId = teacherNumericId,
                knownUrl = knownUrl,
            ),
        )
    }

    LaunchedEffect(entityId, name, teacherNumericId, knownUrl, kind) {
        // Always re-resolve so catalog index / offline cache can fill after first paint.
        // Network work is app-scoped inside AvatarRepository so list recycle cancel is OK.
        val resolved = repo.resolveUrl(
            entityId = entityId,
            name = name.takeIf { it.isNotBlank() },
            kind = kind,
            teacherNumericId = teacherNumericId,
            knownUrl = knownUrl ?: url,
        )
        if (resolved != null && resolved != url) {
            url = resolved
        } else if (url.isNullOrBlank()) {
            // Re-peek after await (sibling row may have finished the same entity).
            val peeked = repo.peekUrl(
                entityId = entityId,
                name = name,
                teacherNumericId = teacherNumericId,
                knownUrl = knownUrl,
            )
            if (!peeked.isNullOrBlank()) url = peeked
        }
    }

    val boxModifier = modifier
        .size(size)
        .clip(CircleShape)

    val resolvedUrl = url
    if (!resolvedUrl.isNullOrBlank()) {
        SubcomposeAsyncImage(
            model = ImageRequest.Builder(context)
                .data(resolvedUrl)
                .crossfade(true)
                .build(),
            contentDescription = name,
            contentScale = ContentScale.Crop,
            // Prefer the top of the portrait so faces aren't cropped out.
            alignment = Alignment.TopCenter,
            modifier = boxModifier,
            loading = { InitialsAvatar(label = name, modifier = boxModifier) },
            error = { InitialsAvatar(label = name, modifier = boxModifier) },
        )
    } else {
        InitialsAvatar(label = name, modifier = boxModifier)
    }
}

@Composable
fun PersonAvatar(
    entity: DirectoryEntity,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
) {
    PersonAvatar(
        name = entity.name,
        modifier = modifier,
        size = size,
        entityId = entity.id,
        kind = entity.kind,
        knownUrl = entity.avatarUrl,
    )
}
