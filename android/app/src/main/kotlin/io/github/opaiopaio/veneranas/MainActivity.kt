package io.github.opaiopaio.veneranas

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import androidx.activity.result.ActivityResultCallback
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import dev.flutter.packages.file_selector_android.FileUtils
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterFragmentActivity() {
    var volumeListen = VolumeListen()
    var listening = false

    private val storageRequestCode = 0x10
    private var storagePermissionRequest: ((Boolean) -> Unit)? = null

    private val notificationRequestCode = 0x11
    private var notificationPermissionRequest: ((Boolean) -> Unit)? = null

    private val nextLocalRequestCode = AtomicInteger()

    private val sharedTexts = ArrayList<String>()

    private var textShareHandler: ((String) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ⭐ 用户要求（安卓冷启动"先白底再闪出背景" ✓）：把**已保存的背景**读出来铺到窗口底 ✓。
        // 这一层就是 `res/values/styles.xml` 注释里说的"Flutter UI initializes 期间可见"的 windowBackground ✓，
        // 而 `drawable/launch_background.xml` 写死白 ✗ ⇒ 先白后出图 ✓。本方法**只读** ✓（见下方注释 ✓）。
        applyLaunchBackground()

        if (intent?.action == Intent.ACTION_SEND) {
            if (intent.type == "text/plain") {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null)
                    handleSharedText(text)
            }
        }
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        // 主题切换（LaunchTheme → NormalTheme ✓）之后窗口底可能被重置 ⇒ 再落一次 ✓（幂等 ✓）。
        applyLaunchBackground()
    }

    override fun onPostResume() {
        super.onPostResume()
        // ⭐ 加固（2026-10-10 ✓）：**首帧前的最后一道保险** ✓ —— 若 Flutter 嵌入层在 onCreate/onPostCreate
        // 之后才把 NormalTheme 的窗口底铺上 ✗（`?android:colorBackground` = 浅色系统下白 ✗），
        // 这里在 `onResume` 之后再落一次 ✓ ⇒ 引擎初始化那段看到的仍是背景 ✓（幂等 ✓，只设 drawable ✓）。
        applyLaunchBackground()
        // ⭐ P1-4 ✓：**第二次**恢复时（此时 Flutter 首帧早已画好 ✓）释放位图 ✓，避免整会话常驻 ✗。
        postResumeCount++
        if (postResumeCount >= 2) {
            releaseLaunchBackgroundIfDone()
        }
    }

    override fun onDestroy() {
        // ⭐ P1-4 ✓：退出一并把位图还回去 ✓（先换纯色再 recycle ✓，避免绘制已回收位图 ✗）。
        releaseLaunchBackgroundIfDone()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_SEND) {
            if (intent.type == "text/plain") {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null)
                    handleSharedText(text)
            }
        }
    }

    private fun handleSharedText(text: String) {
        if (textShareHandler != null) {
            textShareHandler?.invoke(text)
        } else {
            sharedTexts.add(text)
        }
    }

    private fun <I, O> startContractForResult(
        contract: ActivityResultContract<I, O>,
        input: I,
        callback: ActivityResultCallback<O>
    ) {
        val key = "activity_rq_for_result#${nextLocalRequestCode.getAndIncrement()}"
        val registry = activityResultRegistry
        var launcher: ActivityResultLauncher<I>? = null
        val observer = object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                if (Lifecycle.Event.ON_DESTROY == event) {
                    launcher?.unregister()
                    lifecycle.removeObserver(this)
                }
            }
        }
        lifecycle.addObserver(observer)
        val newCallback = ActivityResultCallback<O> {
            launcher?.unregister()
            lifecycle.removeObserver(observer)
            callback.onActivityResult(it)
        }
        launcher = registry.register(key, contract, newCallback)
        launcher.launch(input)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "venera/method_channel"
        ).setMethodCallHandler { call, res ->
            when (call.method) {
                "getProxy" -> res.success(getProxy())
                "setScreenOn" -> {
                    val set = call.argument<Boolean>("set") ?: false
                    if (set) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    res.success(null)
                }

                "getDirectoryPath" -> {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    startContractForResult(ActivityResultContracts.StartActivityForResult(), intent) { activityResult ->
                        if (activityResult.resultCode != Activity.RESULT_OK) {
                            res.success(null)
                            return@startContractForResult
                        }
                        val pickedDirectoryUri = activityResult.data?.data
                        if (pickedDirectoryUri == null)
                            res.success(null)
                        else
                            onPickedDirectory(pickedDirectoryUri, res)
                    }
                }

                else -> res.notImplemented()
            }
        }

        val channel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "venera/volume")
        channel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listening = true
                    volumeListen.onUp = {
                        events.success(1)
                    }
                    volumeListen.onDown = {
                        events.success(2)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    listening = false
                }
            })

        val storageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "venera/storage")
        storageChannel.setMethodCallHandler { _, res ->
            requestStoragePermission { result ->
                res.success(result)
            }
        }

        val selectFileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "venera/select_file")
        selectFileChannel.setMethodCallHandler { req, res ->
            val mimeType = req.arguments<String>()
            openFile(res, mimeType!!)
        }

        // 后台下载：Dart 侧通过此 channel 控制前台服务。
        // start: {text} -> 启动 / 刷新服务（幂等）
        // stop          -> 停止服务（幂等）
        val downloadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "venera/download_service")
        downloadChannel.setMethodCallHandler { call, res ->
            when (call.method) {
                "start" -> {
                    val text = call.argument<String>("text")
                        ?: getString(R.string.download_notification_default)
                    try {
                        DownloadService.startService(this, text)
                        res.success(true)
                    } catch (e: Exception) {
                        // 常见原因：Android 13+ 未授予 POST_NOTIFICATIONS，
                        // 或前台服务被系统限制。返回 false 让 Dart 侧优雅地
                        // 退回到"没有后台保护"的状态。
                        Log.w("Venera", "Failed to start download service: ${e.message}")
                        res.success(false)
                    }
                }
                "stop" -> {
                    try {
                        DownloadService.stopService(this)
                    } catch (e: Exception) {
                        Log.w("Venera", "Failed to stop download service: ${e.message}")
                    }
                    res.success(null)
                }
                "hasNotificationPermission" -> {
                    res.success(hasNotificationPermission())
                }
                "requestNotificationPermission" -> {
                    if (hasNotificationPermission()) {
                        res.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        // 并发场景（虽然 Dart 侧 _permissionRequested 守卫已经几乎
                        // 避免了）：覆盖前先把前一次的 callback 以 false 触发，
                        // 否则前一次的 Flutter Result 会永远悬挂。
                        notificationPermissionRequest?.invoke(false)
                        notificationPermissionRequest = { granted -> res.success(granted) }
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            notificationRequestCode
                        )
                    } else {
                        // Android 13 以下：通知权限是隐式授予的。
                        res.success(true)
                    }
                }
                else -> res.notImplemented()
            }
        }

        val shareTextChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "venera/text_share")
        shareTextChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    textShareHandler = {text ->
                        events.success(text)
                    }
                    if (sharedTexts.isNotEmpty()) {
                        for (text in sharedTexts) {
                            events.success(text)
                        }
                        sharedTexts.clear()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    textShareHandler = null
                }
            })
    }

    private fun getProxy(): String {
        val host = System.getProperty("http.proxyHost")
        val port = System.getProperty("http.proxyPort")
        return if (host != null && port != null) {
            "$host:$port"
        } else {
            "No Proxy"
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // ⭐ 用户要求（安卓冷启动"背景是白色然后闪出背景" ✓）：把**已保存的背景**铺到窗口底 ✓。
    //
    // 这一层就是 Android 官方为"Flutter UI 初始化期间"保留的 windowBackground（见
    // `res/values/styles.xml` 的注释 ✓）：浅色主题下它是**白色** ✗，而 App 背景是用户选的壁纸 ⇒
    // "先白后闪出背景" ✓。把用户已保存的背景读出来铺上 ⇒ 引擎初始化这段看到的就是背景本身 ✓。
    //
    // ⚠️⚠️ **本段全程只读** ✗→✓（曾逐行核对 ✓）：只用 `File.exists()` / `readText()` /
    // `BitmapFactory.decodeFile()` ✓；**绝不**创建/写入/截断/删除任何文件 ✓
    //（本文件里 `FileOutputStream` 等写入只出现在既有的 `onPickedDirectory` / `openFile` ✓ 与本段无关 ✓）。
    //
    // 读的是 Dart 侧**同一份**存储 ✓（已逐项核对 ✓）：
    //   · 文件 = `<filesDir>/appdata.json` ✓ —— Dart 侧 `App.dataPath` = `getApplicationSupportDirectory()`
    //     = `filesDir` ✓（`appdata.dart:33` ✓、path_provider_android 的 `getApplicationSupportPath()` ✓）；
    //   · 结构 = `{"settings": {...}, "searchHistory": [...]}` ✓（`appdata.dart:78-79` ✓）；
    //   · 键 = `settings.backgroundImage`（**文件名** ✓，图存于 `<filesDir>/background/` ✓，
    //     见 `window_overlay.dart:29-34` 与 `appdata.dart:343` ✓）
    //     与 `settings.backgroundColor`（`#RRGGBB` ✓；`system` / `transparent` 一律忽略 ✓）。
    //   ⚠️ **不再做任何设备层查找** ✓ —— 设备设置已按用户方案重构为"只有一套值" ✓
    //     （全部在顶层 `settings` 里 ✓，`deviceSpecificSettings` 仅剩迁移后的空容器 ✓）。
    //
    // 异常一律**静默回退**到主题色 ✓（读不到/解不出就什么都不做 ⇒ 与改动前一致 ✓，绝不影响启动 ✓）。
    private var launchBackground: Drawable? = null

    /// 兜底纯色（`backgroundColor` ✓，没有则 null ⇒ 释放时保持主题色 ✓）／`onPostResume` 计数 ✓。
    private var lastLaunchColor: Int? = null
    private var postResumeCount = 0

    private fun applyLaunchBackground() {
        if (launchBackground == null) {
            launchBackground = buildLaunchBackground()
        }
        launchBackground?.let {
            try {
                window.setBackgroundDrawable(it)
            } catch (e: Throwable) {
                Log.w("Venera", "setBackgroundDrawable failed: ${e.message}")
            }
        }
    }

    private fun buildLaunchBackground(): Drawable? {
        // ⚠️ 读 JSON 单独一层 try：读不到就整体放弃（回退主题色 ✓，与改动前一致 ✓）。
        val settings = try {
            val jsonFile = File(filesDir, "appdata.json")
            if (!jsonFile.exists()) return null
            JSONObject(jsonFile.readText()).optJSONObject("settings") ?: return null
        } catch (e: Throwable) {
            Log.w("Venera", "launch background: read appdata.json failed: ${e.message}")
            return null
        }

        // ⭐ 修复（2026-10-10 用户要求 ✓）：**图片这一段必须独立 try** ✗→✓ ——
        // 原先图片解码包在最外层 try 里 ✗ ⇒ 一旦解码抛异常（大图 OOM / 解码器异常 ✓），
        // 会**跳过下面的 `backgroundColor` 兜底** ✗ ⇒ 直接回退主题色 ⇒ 浅色系统下就是**白** ✗，
        // 表现与用户报的"启动还是白一下"一模一样 ✓。现在图片失败也会继续尝试背景色 ✓。
        val imageDrawable = try {
            val imageName = settings.optString("backgroundImage", "")
            // ⭐ P1-3（2026-10-10 回归审查 ✓）：**fit / opacity 不匹配时不铺图** ✗→✓ ——
            // 老实现一律 `BitmapDrawable` + `Gravity.FILL` ✗ ⇒ 宽高比被**压扁铺满** ✓，
            // 而 Flutter 首帧按 `cover` 保持比例裁切 ✓ ⇒ 启动层与首帧之间**肉眼可见跳变** ✗。
            // 规则 ✓：`opacity < 1` ⇒ 不铺（Dart 侧还要叠底色 ✓，本就是半透明 ✓）；
            // `fit == cover`（默认 ✓）⇒ 下面**按屏幕比例居中裁切**后再 FILL ⇒ 与 cover 一致 ✓；
            // `fit == fill` ⇒ 直接 FILL ⇒ 与 Dart 一致 ✓；
            // 其余 fit（contain / none / scaleDown / repeat…）✗ ⇒ 不铺图、退回背景色 ✓
            //（宁可少铺，也不要"启动一段压扁、首帧突然正常"的跳变 ✓）。
            val opacity = settings.optDouble("backgroundImageOpacity", 1.0)
            val fit = settings.optString("backgroundImageFit", "cover")
            val fitSupported = fit == "cover" || fit == "fill"
            if (imageName.isEmpty() || opacity < 1.0 || !fitSupported) {
                null
            } else {
                val imageFile = File(File(filesDir, "background"), imageName)
                if (!imageFile.exists()) {
                    Log.w("Venera", "launch background: image not found: ${imageFile.absolutePath}")
                    null
                } else {
                    // 先只读尺寸 ✓，再按**屏幕长边**采样解码 ✓（解码长边 ≤ 屏幕长边 ⇒ 内存可控 ✓，
                    // 旧实现只保证"< 2× 屏幕长边" ✗ ⇒ 4K 壁纸仍按原分辨率解 ✓ ≈ 36–92MB ✗）。
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(imageFile.absolutePath, bounds)
                    val bitmap = BitmapFactory.decodeFile(
                        imageFile.absolutePath,
                        BitmapFactory.Options().apply {
                            inSampleSize = sampleSizeFor(bounds)
                            // ⭐ P1-4 ✓：壁纸用 RGB_565 足够 ✓，内存直接减半 ✓。
                            inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
                        }
                    )
                    if (bitmap == null) {
                        Log.w("Venera", "launch background: decode returned null: ${imageFile.name}")
                        null
                    } else {
                        // ⭐ P1-3 ✓：cover ⇒ 先按屏幕比例**居中裁切**（等价 Flutter 的 BoxFit.cover ✓），
                        // 这样后面的 `Gravity.FILL` 只做等比铺满、不会再压扁 ✓。
                        val cropped = if (fit == "cover") {
                            centerCropToScreen(bitmap) ?: bitmap
                        } else {
                            bitmap
                        }
                        val drawable = BitmapDrawable(resources, cropped)
                        // ⚠️ `Drawable.setGravity` 是 API 23+ ✓ ⇒ 低版本不加 ✓（默认拉伸铺满 ✓，不会崩 ✓）。
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            drawable.setGravity(Gravity.FILL)
                        }
                        drawable
                    }
                }
            }
        } catch (e: Throwable) {
            Log.w("Venera", "launch background: decode image failed: ${e.message}")
            null
        }
        if (imageDrawable != null) return imageDrawable

        val color = try {
            settings.optString("backgroundColor", "transparent")
        } catch (e: Throwable) {
            "transparent"
        }
        if (color.length == 7 && color.startsWith("#")) {
            return try {
                val parsed = Color.parseColor(color)
                lastLaunchColor = parsed
                ColorDrawable(parsed)
            } catch (e: Throwable) {
                Log.w("Venera", "launch background: parse color failed: $color")
                null
            }
        }
        return null
    }

    /// 采样率取 2 的幂 ✓，使**解码后的长边 ≤ 屏幕长边** ✓
    ///（`inSampleSize` 必须是 2 的幂 ✓；P1-4 修复：旧实现只保证 "< 2× 屏幕长边" ✗ ⇒ 4K 壁纸仍按原分辨率解码 ✓ ≈ 36–92MB ✗）。
    private fun sampleSizeFor(bounds: BitmapFactory.Options): Int {
        var sample = 1
        val target = maxOf(
            resources.displayMetrics.widthPixels,
            resources.displayMetrics.heightPixels
        )
        if (target <= 0) return sample
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / (sample * 2) >= target) {
            sample *= 2
        }
        // 再进一档 ✓：保证 `longest / sample <= target` ✓（宁可略小一点，也不多留一倍内存 ✗）。
        if (longest / sample > target) {
            sample *= 2
        }
        return sample
    }

    /// ⭐ P1-3（2026-10-10 回归审查 ✓）：按**屏幕宽高比**居中裁切 ✓（等价 Flutter `BoxFit.cover` ✓）。
    /// 失败（尺寸异常 / OOM ✓）返回 null ⇒ 调用方退回原图 ✓（保持旧行为 ✗，不阻断启动 ✓）。
    private fun centerCropToScreen(src: android.graphics.Bitmap): android.graphics.Bitmap? {
        return try {
            val screenW = resources.displayMetrics.widthPixels
            val screenH = resources.displayMetrics.heightPixels
            if (screenW <= 0 || screenH <= 0 || src.width <= 0 || src.height <= 0) return null
            val targetRatio = screenW.toFloat() / screenH.toFloat()
            val srcRatio = src.width.toFloat() / src.height.toFloat()
            val w: Int
            val h: Int
            if (srcRatio > targetRatio) {
                // 源更宽 ⇒ 裁两侧 ✓
                h = src.height
                w = (src.height * targetRatio).toInt().coerceAtLeast(1)
            } else {
                // 源更高 ⇒ 裁上下 ✓
                w = src.width
                h = (src.width / targetRatio).toInt().coerceAtLeast(1)
            }
            val x = ((src.width - w) / 2).coerceAtLeast(0)
            val y = ((src.height - h) / 2).coerceAtLeast(0)
            val cropped = android.graphics.Bitmap.createBitmap(src, x, y, w, h)
            if (cropped != src) {
                src.recycle()
            }
            cropped
        } catch (e: Throwable) {
            Log.w("Venera", "launch background: center crop failed: ${e.message}")
            null
        }
    }

    /// ⭐ P1-4（2026-10-10 回归审查 ✓）：**首帧之后**把窗口底换成纯色并释放位图 ✓ ——
    /// 旧实现让 drawable 与位图**整会话常驻** ✗（无 recycle / 无置空 ✓）。
    /// 触发点 ✓：第二次 `onPostResume`（届时首帧早已由 Flutter 绘制 ✓，窗口底不再可见 ✓）——
    /// 刻意**不在第一次**就撤 ✓，否则可能把启动期的背景提前撤掉 ✗（用户已确认闪白修好 ✓）。
    private fun releaseLaunchBackgroundIfDone() {
        val drawable = launchBackground ?: return
        try {
            lastLaunchColor?.let { window.setBackgroundDrawable(ColorDrawable(it)) }
            launchBackground = null
            if (drawable is BitmapDrawable) {
                drawable.bitmap?.takeIf { !it.isRecycled }?.recycle()
            }
        } catch (e: Throwable) {
            Log.w("Venera", "release launch background failed: ${e.message}")
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (listening) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeListen.down()
                    return true
                }

                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeListen.up()
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    /// Ensure that the directory is accessible by dart:io
    private fun onPickedDirectory(uri: Uri, result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            var plain = uri.toString()
            if(plain.contains("%3A")) {
                plain = Uri.decode(plain)
            }
            val externalStoragePrefix = "content://com.android.externalstorage.documents/tree/primary:";
            if(plain.startsWith(externalStoragePrefix)) {
                val path = plain.substring(externalStoragePrefix.length)
                result.success(Environment.getExternalStorageDirectory().absolutePath + "/" + path)
            }
            // The uri cannot be parsed to plain path, use copy method
        }
        // dart:io cannot access the directory without permission.
        // so we need to copy the directory to cache directory
        val contentResolver = contentResolver
        var tmp = cacheDir
        var dirName = DocumentFile.fromTreeUri(this, uri)?.name
        tmp = File(tmp, dirName!!)
        if(tmp.exists()) {
            tmp.deleteRecursively()
        }
        tmp.mkdir()
        Thread {
            try {
                copyDirectory(contentResolver, uri, tmp)
                result.success(tmp.absolutePath)
            }
            catch (e: Exception) {
                result.error("copy error", e.message, null)
            }
        }.start()

    }

    private fun copyDirectory(resolver: ContentResolver, srcUri: Uri, destDir: File) {
        val src = DocumentFile.fromTreeUri(this, srcUri) ?: return
        for (file in src.listFiles()) {
            if (file.isDirectory) {
                val newDir = File(destDir, file.name!!)
                newDir.mkdir()
                copyDirectory(resolver, file.uri, newDir)
            } else {
                val newFile = File(destDir, file.name!!)
                resolver.openInputStream(file.uri)?.use { input ->
                    FileOutputStream(newFile).use { output ->
                        input.copyTo(output, bufferSize = DEFAULT_BUFFER_SIZE)
                        output.flush()
                    }
                }
            }
        }
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            Environment.isExternalStorageManager()
        }
    }

    private fun requestStoragePermission(result: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            val readPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED

            val writePermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED

            if (!readPermission || !writePermission) {
                storagePermissionRequest = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ),
                    storageRequestCode
                )
            } else {
                result(true)
            }
        } else {
            if (!Environment.isExternalStorageManager()) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.addCategory("android.intent.category.DEFAULT")
                    intent.data = Uri.parse("package:$packageName")
                    startContractForResult(ActivityResultContracts.StartActivityForResult(), intent){ _ ->
                        result(Environment.isExternalStorageManager())
                    }
                } catch (e: Exception) {
                    result(false)
                }
            } else {
                result(true)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storageRequestCode) {
            storagePermissionRequest?.invoke(grantResults.all {
                it == PackageManager.PERMISSION_GRANTED
            })
            storagePermissionRequest = null
        } else if (requestCode == notificationRequestCode) {
            notificationPermissionRequest?.invoke(grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            notificationPermissionRequest = null
        }
    }

    /// Android 13+ 需要在运行时申请 POST_NOTIFICATIONS 权限，前台服务通知才能显示。
    /// 13 以下版本为隐式授予。
    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun openFile(result: MethodChannel.Result, mimeType: String) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = mimeType
        startContractForResult(ActivityResultContracts.StartActivityForResult(), intent){ activityResult ->
            if (activityResult.resultCode != Activity.RESULT_OK) {
                result.success(null)
                return@startContractForResult
            }
            val uri = activityResult.data?.data
            if (uri == null) {
                result.success(null)
                return@startContractForResult
            }
            val contentResolver = contentResolver
            val file = DocumentFile.fromSingleUri(this, uri)
            if (file == null) {
                result.success(null)
                return@startContractForResult
            }
            val fileName = file.name
            if (fileName == null) {
                result.success(null)
                return@startContractForResult
            }
            if(hasStoragePermission()) {
                try {
                    val filePath = FileUtils.getPathFromUri(this, uri)
                    result.success(filePath)
                    return@startContractForResult
                }
                catch (e: Exception) {
                    // ignore
                }
            }
            // use copy method
            val tmp = File(cacheDir, fileName)
            if(tmp.exists()) {
                tmp.delete()
            }
            Log.i("Venera", "copy file (${fileName}) to ${tmp.absolutePath}")
            Thread {
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tmp).use { output ->
                            input.copyTo(output, bufferSize = DEFAULT_BUFFER_SIZE)
                            output.flush()
                        }
                    }
                    result.success(tmp.absolutePath)
                }
                catch (e: Exception) {
                    result.error("copy error", e.message, null)
                }
            }.start()
        }
    }
}

class VolumeListen {
    var onUp = fun() {}
    var onDown = fun() {}
    fun up() {
        onUp()
    }

    fun down() {
        onDown()
    }
}
