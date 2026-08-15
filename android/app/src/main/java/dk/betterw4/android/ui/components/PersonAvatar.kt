package dk.betterw4.android.ui.components

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
import dk.betterw4.android.feature.directory.AvatarRepository
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind

@EntryPoint
@InstallIn(SingletonComponent::class)
interface AvatarRepositoryEntryPoint {
    fun avatarRepository(): AvatarRepository
}

/**
 * Circular person photo with initials fallback.
 *
 * Resolves W4 thumb URLs via [AvatarRepository] (cookie-aware Coil).
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
        val resolved = repo.resolveUrl(
            entityId = entityId,
            name = name.takeIf { it.isNotBlank() },
            kind = kind,
            teacherNumericId = teacherNumericId,
            knownUrl = knownUrl ?: url,
        )
        if (!resolved.isNullOrBlank()) url = resolved
    }

    val boxModifier = modifier
        .size(size)
        .clip(CircleShape)

    if (!url.isNullOrBlank()) {
        SubcomposeAsyncImage(
            model = ImageRequest.Builder(context)
                .data(url)
                .crossfade(true)
                .build(),
            contentDescription = name,
            contentScale = ContentScale.Crop,
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
