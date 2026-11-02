package dev.rain.laundry.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val Light = lightColorScheme(
    primary = Color(0xFF276B53), onPrimary = Color.White,
    primaryContainer = Color(0xFFD9EDDF), onPrimaryContainer = Color(0xFF113C2C),
    secondary = Color(0xFF52645A), secondaryContainer = Color(0xFFE0E9E1),
    background = Color(0xFFF7F9F5), surface = Color(0xFFF7F9F5),
    surfaceContainer = Color(0xFFEBF0E9), surfaceContainerLow = Color(0xFFF1F5EF),
    outline = Color(0xFF77847C), outlineVariant = Color(0xFFD2DBD3)
)
private val Dark = darkColorScheme(primary = Color(0xFFA3D5B5), primaryContainer = Color(0xFF174E38),
    background = Color(0xFF101612), surface = Color(0xFF101612), surfaceContainer = Color(0xFF202923))

@Composable
fun LaundryTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    // A consistent green palette keeps the glass controls legible in both modes.
    MaterialTheme(colorScheme = if (dark) Dark else Light, content = content)
}
