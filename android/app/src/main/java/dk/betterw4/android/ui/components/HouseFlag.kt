package dk.betterw4.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dk.betterw4.android.feature.directory.HouseFlagKind

private val FlagShape = RoundedCornerShape(4.dp)

/** Drawn Nordic flag (or a mortarboard tile for Graduated). */
@Composable
fun HouseFlag(
    kind: HouseFlagKind,
    modifier: Modifier = Modifier,
    width: Dp = 36.dp,
) {
    Canvas(
        modifier
            .size(width = width, height = width * 16f / 21f)
            .clip(FlagShape)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, FlagShape)
            .semantics { contentDescription = kind.emoji },
    ) {
        drawHouseFlag(kind)
    }
}

@Composable
fun HouseFlag(
    houseIdOrName: String,
    modifier: Modifier = Modifier,
    width: Dp = 36.dp,
) {
    val kind = HouseFlagKind.of(houseIdOrName) ?: return
    HouseFlag(kind = kind, modifier = modifier, width = width)
}

private fun DrawScope.drawHouseFlag(kind: HouseFlagKind) {
    when (kind) {
        HouseFlagKind.DENMARK -> nordicCross(
            field = Color(0xFFC8102E),
            cross = Color.White,
        )
        HouseFlagKind.FINLAND -> nordicCross(
            field = Color(0xFFFFFFFF),
            cross = Color(0xFF002F6C),
        )
        HouseFlagKind.SWEDEN -> nordicCross(
            field = Color(0xFF006AA7),
            cross = Color(0xFFFECC00),
        )
        HouseFlagKind.NORWAY -> nordicCross(
            field = Color(0xFFBA0C2F),
            cross = Color.White,
            inner = Color(0xFF00205B),
        )
        HouseFlagKind.ICELAND -> nordicCross(
            field = Color(0xFF02529C),
            cross = Color.White,
            inner = Color(0xFFDC1E35),
        )
        HouseFlagKind.GRADUATED -> {
            drawRect(Color(0xFF5C6370))
            val cap = Color(0xFFE8E4D9)
            val cx = size.width / 2f
            val cy = size.height / 2f
            val w = size.width * 0.42f
            drawRect(
                color = cap,
                topLeft = Offset(cx - w / 2f, cy - size.height * 0.06f),
                size = Size(w, size.height * 0.08f),
            )
            drawCircle(cap, radius = size.minDimension * 0.07f, center = Offset(cx, cy - size.height * 0.14f))
        }
    }
}

/**
 * Nordic cross: vertical bar sits toward the hoist (left).
 * [inner] is the thinner second cross on Norway and Iceland.
 */
private fun DrawScope.nordicCross(
    field: Color,
    cross: Color,
    inner: Color? = null,
) {
    drawRect(field)
    val t = size.height / 5f
    val vx = size.width * 0.30f - t / 2f
    drawRect(cross, topLeft = Offset(vx, 0f), size = Size(t, size.height))
    drawRect(cross, topLeft = Offset(0f, size.height / 2f - t / 2f), size = Size(size.width, t))
    if (inner != null) {
        val ti = t * 0.48f
        val vxi = vx + (t - ti) / 2f
        drawRect(inner, topLeft = Offset(vxi, 0f), size = Size(ti, size.height))
        drawRect(inner, topLeft = Offset(0f, size.height / 2f - ti / 2f), size = Size(size.width, ti))
    }
}
