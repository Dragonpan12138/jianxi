package dev.rain.laundry.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.LocalLaundryService
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.rain.laundry.BuildConfig
import dev.rain.laundry.R
import kotlinx.coroutines.launch

private const val SOURCE_URL = "https://github.com/xiyuchengxu/jianxi"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val colors = MaterialTheme.colorScheme
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var licenseOpen by rememberSaveable { mutableStateOf(false) }
    var donationOpen by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        containerColor = colors.background,
        topBar = {
            TopAppBar(
                title = { Text("关于简洗") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.background)
            )
        },
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding)
                .verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(
                modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier.size(88.dp)
                            .background(colors.primaryContainer, RoundedCornerShape(28.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Outlined.LocalLaundryService, contentDescription = null,
                            tint = colors.primary, modifier = Modifier.size(44.dp))
                    }
                    Text("简洗", style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.SemiBold)
                    Text("把洗衣，变简单", color = colors.onSurfaceVariant)
                    Text("版本 ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                        style = MaterialTheme.typography.labelLarge, color = colors.onSurfaceVariant)
                }

                Text("使用 Kotlin 与 Jetpack Compose 构建的独立 Android 洗衣客户端。",
                    style = MaterialTheme.typography.bodyLarge)

                OutlinedCard(
                    onClick = {
                        runCatching { uriHandler.openUri(SOURCE_URL) }.onFailure {
                            scope.launch { snackbar.showSnackbar("未找到可打开 GitHub 链接的应用") }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(24.dp)
                ) {
                    Row(modifier = Modifier.padding(20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Icon(Icons.Outlined.Code, contentDescription = null, tint = colors.primary)
                        Column(modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("GitHub · 项目源码", style = MaterialTheme.typography.titleMedium)
                            Text("github.com/xiyuchengxu/jianxi",
                                style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
                        }
                        Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = "在浏览器中打开")
                    }
                }

                FilledTonalButton(
                    onClick = { donationOpen = true },
                    modifier = Modifier.fillMaxWidth().height(54.dp)
                ) {
                    Icon(Icons.Outlined.FavoriteBorder, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(10.dp))
                    Text("打赏支持", style = MaterialTheme.typography.titleMedium)
                }

                Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp),
                    colors = CardDefaults.cardColors(containerColor = colors.surfaceContainerLow)) {
                    Column(modifier = Modifier.fillMaxWidth().padding(22.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("开源协议", style = MaterialTheme.typography.labelLarge, color = colors.primary)
                        Text("MIT License", style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold)
                        Text("本项目源码采用 MIT 开源协议。完整许可及版权声明可离线查看。",
                            color = colors.onSurfaceVariant)
                        TextButton(onClick = { licenseOpen = true }) { Text("阅读完整协议") }
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("第三方组件", style = MaterialTheme.typography.titleMedium)
                    Text("AndroidX / Jetpack Compose、OkHttp、Gson、ZXing Embedded 和支付宝 Android SDK 等组件遵循各自的许可，详见仓库中的 THIRD_PARTY_NOTICES.md。",
                        style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
                }
                Text("简洗是独立开源项目，与原服务平台无隶属关系。",
                    style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
            }
        }
    }

    if (donationOpen) DonationDialog(onClose = { donationOpen = false })

    if (licenseOpen) {
        val license = remember(context) {
            context.resources.openRawResource(R.raw.mit_license).bufferedReader().use { it.readText() }
        }
        AlertDialog(
            onDismissRequest = { licenseOpen = false },
            title = { Text("MIT License") },
            text = {
                SelectionContainer {
                    Text(license, style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()))
                }
            },
            confirmButton = { TextButton(onClick = { licenseOpen = false }) { Text("完成") } }
        )
    }
}
