mkdir -p GameTurbo/app/src/main/java/com/gameturbo/moto
cd GameTurbo

cat > settings.gradle.kts <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "GameTurbo"
include(":app")
EOF

cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
EOF

cat > gradle.properties <<'EOF'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2g
EOF

cat > app/build.gradle.kts <<'EOF'
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.gameturbo.moto"
    compileSdk = 34
    defaultConfig { applicationId = "com.gameturbo.moto"; minSdk = 29; targetSdk = 34; versionCode = 1; versionName = "1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
    <application android:label="Game Turbo" android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".OverlayService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="game_overlay_panel" />
        </service>
        <provider android:name="rikka.shizuku.ShizukuProvider" android:authorities="${applicationId}.shizuku"
            android:multiprocess="false" android:enabled="true" android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
    </application>
</manifest>
EOF

cd app/src/main/java/com/gameturbo/moto

cat > Shell.kt <<'EOF'
package com.gameturbo.moto

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Environment
import android.os.StatFs
import rikka.shizuku.Shizuku

object Shell {
    fun ready(): Boolean = try {
        Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (e: Throwable) { false }

    fun run(cmd: String): String {
        val m = Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java)
        m.isAccessible = true
        val p = m.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
        val out = p.inputStream.bufferedReader().readText()
        p.waitFor()
        return out.trim()
    }
}

object Cmd {
    private val protectedApps = setOf("com.whatsapp", "org.telegram.messenger", "moe.shizuku.privileged.api")

    fun ramPct(c: Context): Int {
        val mi = ActivityManager.MemoryInfo()
        (c.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
        return (100 - mi.availMem * 100 / mi.totalMem).toInt()
    }
    private fun availMb(c: Context): Long {
        val mi = ActivityManager.MemoryInfo()
        (c.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
        return mi.availMem / 1048576
    }
    private fun freeStorageMb(): Long = StatFs(Environment.getDataDirectory().path).availableBytes / 1048576
    fun storagePct(): Int {
        val s = StatFs(Environment.getDataDirectory().path)
        return (100 - s.availableBytes * 100 / s.totalBytes).toInt()
    }

    fun foregroundPkg(): String {
        val o = Shell.run("dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'")
        return Regex("([a-zA-Z0-9_.]+)/").find(o)?.groupValues?.get(1) ?: ""
    }

    fun freeRam(c: Context): String {
        val fg = foregroundPkg()
        val ime = Shell.run("settings get secure default_input_method").substringBefore("/")
        val before = availMb(c)
        val pkgs = Shell.run("pm list packages -3").lines().map { it.removePrefix("package:").trim() }
            .filter { it.isNotEmpty() && it != c.packageName && it != fg && it != ime && it !in protectedApps }
        pkgs.forEach { Shell.run("am force-stop $it") }
        Shell.run("am kill-all")
        Thread.sleep(600)
        val freed = availMb(c) - before
        return "RAM: ${pkgs.size} apps encerrados, ${if (freed > 0) freed else 0} MB liberados"
    }

    fun clearCache(): String {
        val before = freeStorageMb()
        Shell.run("pm trim-caches 100G")
        val freed = freeStorageMb() - before
        return "Cache limpo: ${if (freed > 0) freed else 0} MB liberados"
    }

    fun optimizeApps(): String {
        Shell.run("cmd package bg-dexopt-job")
        return "Apps otimizados (dexopt executado)"
    }

    fun performance(on: Boolean): String {
        val pkg = foregroundPkg()
        val s = if (on) "0.5" else "1.0"
        Shell.run("cmd game mode ${if (on) "performance" else "standard"} $pkg")
        for (k in listOf("window_animation_scale", "transition_animation_scale", "animator_duration_scale"))
            Shell.run("settings put global $k $s")
        return if (on) "Modo desempenho ligado para $pkg" else "Modo desempenho desligado"
    }

    private var oldBright = ""
    fun brightness(on: Boolean): String {
        if (on) {
            oldBright = Shell.run("settings get system screen_brightness")
            Shell.run("settings put system screen_brightness_mode 0")
            Shell.run("settings put system screen_brightness 255")
        } else if (oldBright.isNotEmpty()) Shell.run("settings put system screen_brightness $oldBright")
        return if (on) "Brilho no máximo" else "Brilho restaurado"
    }

    fun screenshot(): String {
        Shell.run("screencap -p /sdcard/Pictures/GameTurbo_${System.currentTimeMillis()}.png")
        return "Captura salva em Imagens"
    }
}
EOF

cat > MainActivity.kt <<'EOF'
package com.gameturbo.moto

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import rikka.shizuku.Shizuku

class MainActivity : Activity() {
    private lateinit var info: TextView

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(40, 60, 40, 40) }
        info = TextView(this).apply { textSize = 16f }
        col.addView(info)
        fun btn(t: String, f: () -> Unit) = col.addView(Button(this).apply { text = t; isAllCaps = false; setOnClickListener { f() } },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        btn("1. Autorizar Shizuku") {
            try { if (!Shizuku.pingBinder()) info.append("\nAbra o app Shizuku e inicie ele primeiro.") else Shizuku.requestPermission(1) }
            catch (e: Throwable) { info.append("\nInstale e inicie o Shizuku.") }
        }
        btn("2. Permitir exibir sobre outros apps") {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        btn("3. Acesso ao Não perturbe") { startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) }
        btn("4. Permitir notificações") {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
        btn("Iniciar Game Turbo") { startForegroundService(Intent(this, OverlayService::class.java)) }
        btn("Parar Game Turbo") { stopService(Intent(this, OverlayService::class.java)) }
        setContentView(ScrollView(this).apply { addView(col) })
    }

    override fun onResume() {
        super.onResume()
        val nm = getSystemService(NotificationManager::class.java)
        info.text = "Shizuku: " + (if (Shell.ready()) "OK" else "pendente") +
            "\nExibir sobre apps: " + (if (Settings.canDrawOverlays(this)) "OK" else "pendente") +
            "\nNão perturbe: " + (if (nm.isNotificationPolicyAccessGranted) "OK" else "pendente") + "\n"
    }
}
EOF

cat > OverlayService.kt <<'EOF'
package com.gameturbo.moto

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.view.*
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.*
import java.util.concurrent.Executors

class RingView(c: Context, private val label: String) : View(c) {
    var value = 0
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 16f; strokeCap = Paint.Cap.ROUND }
    private val t = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textAlign = Paint.Align.CENTER }
    override fun onDraw(cv: Canvas) {
        val r = RectF(14f, 14f, width - 14f, height - 14f)
        p.color = 0xFF24141A.toInt(); cv.drawArc(r, 0f, 360f, false, p)
        p.color = 0xFFFF2A3C.toInt(); cv.drawArc(r, -90f, value * 3.6f, false, p)
        t.textSize = height * 0.26f; cv.drawText("$value%", width / 2f, height / 2f + height * 0.06f, t)
        t.textSize = height * 0.13f; t.color = 0xFF8B8B98.toInt(); cv.drawText(label, width / 2f, height * 0.72f, t); t.color = Color.WHITE
    }
}

class OverlayService : Service() {
    private lateinit var wm: WindowManager
    private val h = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var handle: View? = null
    private var panel: View? = null
    private val edges = mutableListOf<View>()
    private val on = mutableMapOf<String, Boolean>()
    private val log = ArrayDeque<String>()
    private var ram: RingView? = null
    private var sto: RingView? = null
    private var status: TextView? = null
    private var bottom: TextView? = null
    private val ticker = object : Runnable { override fun run() { refresh(); h.postDelayed(this, 3000) } }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    override fun onBind(i: Intent?): IBinder? = null
    override fun onStartCommand(i: Intent?, f: Int, id: Int) = START_STICKY

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("turbo", "Game Turbo", NotificationManager.IMPORTANCE_LOW))
        val n = Notification.Builder(this, "turbo").setContentTitle("Game Turbo ativo")
            .setContentText("Puxe a alça vermelha na borda esquerda").setSmallIcon(android.R.drawable.ic_media_play).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1, n)
        addHandle()
    }

    override fun onDestroy() {
        hidePanel(); setEdges(false)
        handle?.let { wm.removeView(it) }; handle = null
        super.onDestroy()
    }

    private fun lp(w: Int, hh: Int, flags: Int, g: Int) = WindowManager.LayoutParams(
        w, hh, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT).apply { gravity = g }

    private fun addHandle() {
        val box = FrameLayout(this)
        val bar = View(this).apply {
            background = GradientDrawable().apply { setColor(0xFFFF2A3C.toInt()); cornerRadii = floatArrayOf(0f, 0f, 24f, 24f, 24f, 24f, 0f, 0f) }
        }
        box.addView(bar, FrameLayout.LayoutParams(dp(10), dp(76), Gravity.START))
        var x0 = 0f
        box.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> x0 = e.rawX
                MotionEvent.ACTION_MOVE -> if (e.rawX - x0 > dp(30)) showPanel()
                MotionEvent.ACTION_UP -> if (Math.abs(e.rawX - x0) < dp(8)) showPanel()
            }
            true
        }
        handle = box
        wm.addView(box, lp(dp(28), dp(76), 0, Gravity.START or Gravity.CENTER_VERTICAL))
    }

    private fun setEdges(enable: Boolean) {
        edges.forEach { wm.removeView(it) }; edges.clear()
        if (!enable) return
        for (g in listOf(Gravity.START, Gravity.END)) {
            val v = View(this)
            edges.add(v)
            wm.addView(v, lp(dp(22), MATCH_PARENT, WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, g))
        }
    }

    private fun showPanel() {
        if (panel != null) return
        val p = buildPanel(); panel = p
        wm.addView(p, lp(MATCH_PARENT, MATCH_PARENT, WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS, Gravity.START))
        handle?.visibility = View.GONE
        h.post(ticker)
    }

    private fun hidePanel() {
        h.removeCallbacks(ticker)
        panel?.let { wm.removeView(it) }; panel = null
        handle?.visibility = View.VISIBLE
    }

    private fun say(t: String) {
        log.addLast("● $t"); while (log.size > 4) log.removeFirst()
        status?.text = log.joinToString("\n")
    }

    private fun refresh() {
        ram?.apply { value = Cmd.ramPct(this@OverlayService); invalidate() }
        sto?.apply { value = Cmd.storagePct(); invalidate() }
        val bat = (getSystemService(BATTERY_SERVICE) as BatteryManager).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val c = java.util.Calendar.getInstance()
        bottom?.text = "%02d:%02d     Bateria %d%%     Shizuku: %s".format(c.get(11), c.get(12), bat, if (Shell.ready()) "ativo" else "inativo")
    }

    private fun style(b: Button, color: Int) {
        b.background = GradientDrawable().apply { setColor(color); setStroke(dp(1), 0xFF2E2E38.toInt()); cornerRadius = dp(6).toFloat() }
    }

    private fun add(parent: LinearLayout, v: View) =
        parent.addView(v, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { setMargins(0, dp(3), 0, dp(3)) })

    private fun btn(t: String, job: () -> String): Button {
        val b = Button(this).apply { text = t; isAllCaps = false; setTextColor(Color.WHITE); textSize = 14f }
        style(b, 0xFF16161C.toInt())
        b.setOnClickListener {
            if (!Shell.ready()) { say("Shizuku inativo. Inicie o Shizuku e autorize."); return@setOnClickListener }
            b.isEnabled = false; b.text = "trabalhando…"
            io.execute {
                val r = try { job() } catch (e: Throwable) { "Erro: ${e.message}" }
                h.post { b.text = t; b.isEnabled = true; say(r); refresh() }
            }
        }
        return b
    }

    private fun tog(name: String, needShell: Boolean, fn: (Boolean) -> String): Button {
        val b = Button(this).apply { text = name; isAllCaps = false; setTextColor(Color.WHITE); textSize = 13f }
        fun paint() = style(b, if (on[name] == true) 0xFF8A0C1A.toInt() else 0xFF16161C.toInt())
        paint()
        b.setOnClickListener {
            if (needShell && !Shell.ready()) { say("Shizuku inativo."); return@setOnClickListener }
            val want = on[name] != true
            io.execute {
                val r = try { fn(want) } catch (e: Throwable) { "Erro: ${e.message}" }
                h.post { if (!r.startsWith("Erro") && !r.startsWith("Libere")) on[name] = want; paint(); say(r) }
            }
        }
        return b
    }

    private fun buildPanel(): View {
        val land = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xF2070709.toInt()); setPadding(dp(14), dp(10), dp(14), dp(8)) }
        val top = LinearLayout(this)
        top.addView(TextView(this).apply { text = "GAME TURBO · Moto G14"; setTextColor(Color.WHITE); textSize = 18f }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        top.addView(TextView(this).apply { text = "✕"; setTextColor(Color.WHITE); textSize = 22f; setPadding(dp(14), 0, dp(6), 0); setOnClickListener { hidePanel() } })
        root.addView(top)

        val left = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        add(left, btn("Otimizar RAM") { Cmd.freeRam(this) })
        add(left, btn("Limpar cache") { Cmd.clearCache() })
        add(left, btn("Otimizar apps e armazenamento") { Cmd.optimizeApps() })

        val mid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL }
        val rings = LinearLayout(this)
        ram = RingView(this, "RAM"); sto = RingView(this, "ARMAZ.")
        rings.addView(ram, LinearLayout.LayoutParams(dp(96), dp(96)).apply { setMargins(dp(10), 0, dp(10), 0) })
        rings.addView(sto, LinearLayout.LayoutParams(dp(96), dp(96)).apply { setMargins(dp(10), 0, dp(10), 0) })
        mid.addView(rings)
        mid.addView(TextView(this).apply { text = "TURBO CUBE"; setTextColor(Color.WHITE); textSize = 22f; letterSpacing = 0.15f; gravity = Gravity.CENTER; setPadding(0, dp(8), 0, dp(4)) })
        status = TextView(this).apply { setTextColor(0xFF8B8B98.toInt()); textSize = 12f; text = log.joinToString("\n").ifEmpty { "● Pronto" } }
        mid.addView(status)

        val right = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        add(right, tog("Não perturbe", false) { w ->
            val nm = getSystemService(NotificationManager::class.java)
            if (!nm.isNotificationPolicyAccessGranted) "Libere o acesso ao Não perturbe no app Game Turbo"
            else { nm.setInterruptionFilter(if (w) NotificationManager.INTERRUPTION_FILTER_NONE else NotificationManager.INTERRUPTION_FILTER_ALL); if (w) "Não perturbe ligado" else "Não perturbe desligado" }
        })
        add(right, tog("Bloquear bordas", false) { w -> h.post { setEdges(w) }; if (w) "Bordas bloqueadas" else "Bordas liberadas" })
        add(right, tog("Modo desempenho", true) { w -> Cmd.performance(w) })
        add(right, tog("Brilho máximo", true) { w -> Cmd.brightness(w) })
        add(right, btn("Captura de tela") { Cmd.screenshot() })

        val body = LinearLayout(this).apply { orientation = if (land) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL }
        for ((v, w) in listOf(left to 1f, mid to 1.4f, right to 1f)) {
            body.addView(v, if (land) LinearLayout.LayoutParams(0, WRAP_CONTENT, w).apply { setMargins(dp(5), 0, dp(5), 0) }
                              else LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { setMargins(0, dp(8), 0, dp(8)) })
        }
        root.addView(ScrollView(this).ap
