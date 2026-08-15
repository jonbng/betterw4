package dk.betterlectio.android.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import dk.betterlectio.android.ui.theme.Dimens

@Composable
fun ListSkeleton(rows: Int = 8, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "skel")
    val alpha by transition.animateFloat(
        initialValue = 0.28f,
        targetValue = 0.55f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "alpha",
    )
    val color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = alpha)
    Column(modifier) {
        repeat(rows) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Dimens.rowHorizontal, vertical = Dimens.rowVertical),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(color),
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SkeletonBar(color, height = 14.dp, widthFraction = 0.72f)
                    SkeletonBar(color, height = 12.dp, widthFraction = 0.45f)
                }
            }
            HorizontalDivider(
                modifier = Modifier.padding(start = Dimens.dividerIndent),
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                thickness = 0.5.dp,
            )
        }
    }
}

@Composable
private fun SkeletonBar(
    color: Color,
    height: androidx.compose.ui.unit.Dp,
    widthFraction: Float = 1f,
) {
    Box(
        Modifier
            .fillMaxWidth(widthFraction)
            .height(height)
            .clip(RoundedCornerShape(4.dp))
            .background(color),
    )
}
