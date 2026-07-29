package com.bbdyno.starjunkyard.combat

import android.content.Context
import android.graphics.PixelFormat
import android.os.PowerManager
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.bbdyno.starjunkyard.content.VerticalSliceDecoder
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.LockSupport
import kotlin.math.min

class PixelCombatSurfaceView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : SurfaceView(context, attrs), SurfaceHolder.Callback {
    private val engine = context.assets.open(CONTENT_FILE).bufferedReader().use {
        CombatEngine(VerticalSliceDecoder.decode(it.readText()))
    }
    private val painter = DebugPixelPainter()
    private val overclockRequested = AtomicBoolean(false)
    private val powerManager = context.getSystemService(PowerManager::class.java)

    @Volatile
    private var running = false
    private var renderThread: Thread? = null

    init {
        holder.addCallback(this)
        // Compose hosts no visual layer above combat; keep the dedicated game surface explicit.
        setZOrderOnTop(true)
        holder.setFormat(PixelFormat.OPAQUE)
        setBackgroundColor(PixelPalette.Ink)
        keepScreenOn = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = "전투 화면. 자동 전투 중. 화면 오른쪽 아래를 눌러 오버클럭을 사용합니다."
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (running) return
        running = true
        renderThread = Thread(::renderLoop, "StarJunkyardPixelRenderer").also { it.start() }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        running = false
        renderThread?.interrupt()
        renderThread?.join(500)
        renderThread = null
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN && isOverclockHit(event.x, event.y)) {
            overclockRequested.set(true)
            performClick()
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        overclockRequested.set(true)
        return true
    }

    private fun renderLoop() {
        var nextSimulation = System.nanoTime()
        while (running) {
            val now = System.nanoTime()
            var simulationSteps = 0
            while (now >= nextSimulation && simulationSteps < MAX_CATCH_UP_STEPS) {
                if (overclockRequested.getAndSet(false)) engine.activateOverclock()
                engine.tick()
                nextSimulation += SIMULATION_STEP_NS
                simulationSteps += 1
            }
            if (simulationSteps == MAX_CATCH_UP_STEPS && now >= nextSimulation) {
                nextSimulation = now + SIMULATION_STEP_NS
            }
            drawFrame(engine.snapshot())
            val frameNs = if (powerManager.isPowerSaveMode) LOW_POWER_FRAME_NS else NORMAL_FRAME_NS
            LockSupport.parkNanos(frameNs)
        }
    }

    private fun drawFrame(snapshot: CombatSnapshot) {
        if (!holder.surface.isValid) return
        val canvas = holder.lockCanvas() ?: return
        try {
            painter.draw(canvas, canvas.width, canvas.height, snapshot)
        } finally {
            holder.unlockCanvasAndPost(canvas)
        }
    }

    private fun isOverclockHit(physicalX: Float, physicalY: Float): Boolean {
        if (width <= 0 || height <= 0) return false
        val scale = min(width / DebugPixelPainter.LOGICAL_WIDTH, height / DebugPixelPainter.LOGICAL_HEIGHT)
            .coerceAtLeast(1)
        val offsetX = (width - DebugPixelPainter.LOGICAL_WIDTH * scale) / 2
        val offsetY = (height - DebugPixelPainter.LOGICAL_HEIGHT * scale) / 2
        val logicalX = (physicalX - offsetX) / scale
        val logicalY = (physicalY - offsetY) / scale
        return logicalX in 264f..346f && logicalY in 650f..736f
    }

    private companion object {
        const val CONTENT_FILE = "r1_vertical_slice.json"
        const val SIMULATION_STEP_NS = 50_000_000L
        const val NORMAL_FRAME_NS = 16_666_667L
        const val LOW_POWER_FRAME_NS = 33_333_333L
        const val MAX_CATCH_UP_STEPS = 5
    }
}
