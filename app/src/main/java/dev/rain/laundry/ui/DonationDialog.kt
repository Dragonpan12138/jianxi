package dev.rain.laundry.ui

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.rain.laundry.R
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

private const val IMAGE_NAME = "简洗-支付宝收款码.jpg"

@Composable
internal fun DonationDialog(onClose: () -> Unit) {
    val context = LocalContext.current
    val image = remember(context) {
        context.resources.openRawResource(R.raw.donation_alipay).use {
            requireNotNull(BitmapFactory.decodeStream(it)).asImageBitmap()
        }
    }
    val scope = rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    var saved by rememberSaveable { mutableStateOf(false) }
    var status by rememberSaveable { mutableStateOf<String?>(null) }

    fun saveImage(destination: Uri? = null) {
        if (saving || saved) return
        saving = true
        scope.launch {
            try {
                status = withContext(Dispatchers.IO) {
                    if (destination != null) {
                        copyDonationImage(context, destination)
                        "收款码已保存"
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        saveDonationToGallery(context)
                        "已保存到相册，可在支付宝扫一扫中选择图片"
                    } else {
                        throw IOException("A document destination is required")
                    }
                }
                saved = true
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                status = "保存失败，请重试"
            } finally {
                saving = false
            }
        }
    }

    val saveDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/jpeg")) { uri ->
        if (uri != null) saveImage(uri)
    }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("打赏支持") },
        text = {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("感谢你对简洗的支持，打赏金额由你决定。")
                Image(
                    bitmap = image,
                    contentDescription = "支付宝打赏收款码",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp)
                )
                Text("使用支付宝扫一扫，或保存图片后识别。",
                    style = MaterialTheme.typography.bodySmall)
                status?.let { Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) saveImage()
                else saveDocument.launch(IMAGE_NAME)
            }, enabled = !saving && !saved) {
                Text(if (saving) "正在保存" else if (saved) "已保存" else "保存收款码")
            }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("关闭") } }
    )
}

private fun copyDonationImage(context: Context, destination: Uri) {
    val output = context.contentResolver.openOutputStream(destination, "w")
        ?: throw IOException("Could not open the image destination")
    output.use { target ->
        context.resources.openRawResource(R.raw.donation_alipay).use { it.copyTo(target) }
    }
}

@RequiresApi(Build.VERSION_CODES.Q)
private fun saveDonationToGallery(context: Context) {
    val resolver = context.contentResolver
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, IMAGE_NAME)
        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Jianxi")
        put(MediaStore.Images.Media.IS_PENDING, 1)
    }
    val destination = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        ?: throw IOException("Could not create the gallery image")
    try {
        copyDonationImage(context, destination)
        check(resolver.update(destination, ContentValues().apply {
            put(MediaStore.Images.Media.IS_PENDING, 0)
        }, null, null) == 1) { "Could not publish the gallery image" }
    } catch (error: Exception) {
        runCatching { resolver.delete(destination, null, null) }
        throw error
    }
}
