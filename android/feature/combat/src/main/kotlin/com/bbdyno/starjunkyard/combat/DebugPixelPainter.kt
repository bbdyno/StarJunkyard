package com.bbdyno.starjunkyard.combat

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import kotlin.math.min

internal class DebugPixelPainter {
    private val blockPaint = Paint().apply {
        isAntiAlias = false
        isDither = false
        isFilterBitmap = false
    }
    private val textPaint = Paint().apply {
        isAntiAlias = false
        isDither = false
        isSubpixelText = false
        color = PixelPalette.WorkWhite
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }

    fun draw(canvas: Canvas, physicalWidth: Int, physicalHeight: Int, state: CombatSnapshot) {
        canvas.drawColor(PixelPalette.Ink)
        val scale = min(physicalWidth / LOGICAL_WIDTH, physicalHeight / LOGICAL_HEIGHT).coerceAtLeast(1)
        val offsetX = (physicalWidth - LOGICAL_WIDTH * scale) / 2
        val offsetY = (physicalHeight - LOGICAL_HEIGHT * scale) / 2

        canvas.save()
        canvas.translate(offsetX.toFloat(), offsetY.toFloat())
        canvas.scale(scale.toFloat(), scale.toFloat())
        drawLogicalScene(canvas, state)
        canvas.restore()
    }

    private fun drawLogicalScene(canvas: Canvas, state: CombatSnapshot) {
        block(canvas, 0, 0, LOGICAL_WIDTH, LOGICAL_HEIGHT, PixelPalette.DeepNavy)
        drawBackAlley(canvas, state.tick)
        drawHeader(canvas, state)
        drawFactory(canvas)
        drawCombatants(canvas, state)
        drawControls(canvas, state)
        drawBottomTabs(canvas)
    }

    private fun drawBackAlley(canvas: Canvas, tick: Int) {
        block(canvas, 0, 70, 360, 230, PixelPalette.DarkRust)
        block(canvas, 0, 294, 360, 6, PixelPalette.Rust)
        repeat(12) { index ->
            val color = if (index % 3 == 0) PixelPalette.WarningAmber else PixelPalette.DarkIron
            block(canvas, 12 + index * 29, 134 + (index % 2) * 20, 12, 18, color)
        }
        repeat(20) { index ->
            val x = (index * 19 + tick / 2) % 360
            val y = 78 + (index * 31 + tick * 2) % 208
            block(canvas, x, y, 1, 5 + index % 3, PixelPalette.WorkBlue)
        }
        block(canvas, 8, 203, 70, 64, PixelPalette.DarkIron)
        block(canvas, 14, 209, 58, 6, PixelPalette.Teal)
        block(canvas, 92, 230, 32, 36, PixelPalette.DarkRust)
        block(canvas, 105, 237, 5, 5, PixelPalette.WarningAmber)
        block(canvas, 8, 272, 190, 8, PixelPalette.MidIron)
        repeat(8) { block(canvas, 14 + it * 22, 274, 10, 4, PixelPalette.LightIron) }
    }

    private fun drawHeader(canvas: Canvas, state: CombatSnapshot) {
        panel(canvas, 8, 8, 344, 56)
        text(canvas, "R1  STAGE %03d".format(state.stage), 18, 34, 12, PixelPalette.WorkWhite)
        text(canvas, "C %03d  P %03d".format(state.credits, state.parts), 254, 33, 9, PixelPalette.WarningAmber)
        text(canvas, "DEBUG PIXEL ART", 264, 53, 6, PixelPalette.MemoryMagenta)
    }

    private fun drawFactory(canvas: Canvas) {
        block(canvas, 0, 300, 360, 10, PixelPalette.Ink)
        block(canvas, 0, 310, 360, 332, PixelPalette.DeepNavy)
        block(canvas, 14, 598, 332, 8, PixelPalette.Ink)
        block(canvas, 20, 606, 320, 6, PixelPalette.DarkIron)
        repeat(16) { block(canvas, 24 + it * 20, 608, 12, 2, PixelPalette.LightIron) }
        block(canvas, 14, 330, 4, 268, PixelPalette.DarkIron)
        block(canvas, 342, 330, 4, 268, PixelPalette.DarkIron)
        block(canvas, 18, 330, 324, 4, PixelPalette.DarkIron)
        repeat(5) { index ->
            block(canvas, 46 + index * 63, 360, 3, 3, PixelPalette.WarningAmber)
            block(canvas, 47 + index * 63, 363, 1, 38, PixelPalette.DarkIron)
        }
    }

    private fun drawCombatants(canvas: Canvas, state: CombatSnapshot) {
        drawMechanic(canvas, 66, 532)
        drawDrone(canvas, 112, 438)
        drawEnemy(canvas, state.enemyId, 262, 516)
        drawHealthBar(canvas, state)

        val shotOffset = (state.tick * 4) % 128
        block(canvas, 100 + shotOffset, 538 - shotOffset / 6, 3, 2, PixelPalette.WarningAmber)
        if (state.scrapTicks > 0) {
            repeat(7) { index ->
                block(
                    canvas,
                    258 + (index * 13 + state.scrapTicks * 3) % 58,
                    520 + (index % 3) * 9 - state.scrapTicks,
                    3 + index % 2,
                    3,
                    if (index % 2 == 0) PixelPalette.SparkOrange else PixelPalette.LightIron,
                )
            }
        }
    }

    private fun drawMechanic(canvas: Canvas, x: Int, y: Int) {
        block(canvas, x + 5, y, 18, 6, PixelPalette.Ink)
        block(canvas, x + 7, y - 20, 15, 20, PixelPalette.DarkIron)
        block(canvas, x + 9, y - 32, 12, 12, PixelPalette.Rust)
        block(canvas, x + 10, y - 31, 10, 8, PixelPalette.SparkOrange)
        block(canvas, x + 12, y - 29, 2, 2, PixelPalette.WorkWhite)
        block(canvas, x + 7, y - 18, 4, 14, PixelPalette.Teal)
        block(canvas, x, y - 17, 8, 8, PixelPalette.Ink)
        block(canvas, x + 1, y - 15, 9, 4, PixelPalette.LightIron)
        block(canvas, x, y - 14, 3, 2, PixelPalette.WarningAmber)
    }

    private fun drawDrone(canvas: Canvas, x: Int, y: Int) {
        block(canvas, x + 5, y, 14, 14, PixelPalette.Ink)
        block(canvas, x + 7, y + 2, 10, 10, PixelPalette.Teal)
        block(canvas, x + 9, y + 5, 6, 4, PixelPalette.WorkWhite)
        block(canvas, x + 11, y + 6, 3, 2, PixelPalette.WarningAmber)
        block(canvas, x + 3, y - 2, 18, 2, PixelPalette.LightIron)
        block(canvas, x + 2, y - 4, 4, 2, PixelPalette.Rust)
        block(canvas, x + 18, y - 4, 4, 2, PixelPalette.Rust)
        block(canvas, x + 10, y + 14, 3, 6, PixelPalette.DarkIron)
        block(canvas, x + 7, y + 19, 3, 5, PixelPalette.SparkOrange)
        block(canvas, x + 13, y + 19, 3, 5, PixelPalette.Teal)
    }

    private fun drawEnemy(canvas: Canvas, enemyId: String, x: Int, y: Int) {
        when (enemyId) {
            "umbrella_crab" -> {
                block(canvas, x - 18, y - 16, 36, 5, PixelPalette.Ink)
                block(canvas, x - 15, y - 26, 30, 10, PixelPalette.WorkBlue)
                block(canvas, x - 10, y - 11, 20, 12, PixelPalette.Rust)
                block(canvas, x - 15, y, 5, 7, PixelPalette.DarkIron)
                block(canvas, x + 10, y, 5, 7, PixelPalette.DarkIron)
                block(canvas, x - 3, y - 9, 3, 3, PixelPalette.WorkWhite)
            }
            "fan_bat" -> {
                block(canvas, x - 7, y - 14, 14, 14, PixelPalette.Ink)
                block(canvas, x - 5, y - 12, 10, 10, PixelPalette.LightIron)
                block(canvas, x - 2, y - 11, 4, 8, PixelPalette.DeepNavy)
                block(canvas, x - 16, y - 11, 10, 5, PixelPalette.DarkTeal)
                block(canvas, x + 6, y - 11, 10, 5, PixelPalette.DarkTeal)
                block(canvas, x - 1, y - 8, 2, 2, PixelPalette.WarningAmber)
            }
            "vending_knight" -> {
                block(canvas, x - 20, y - 52, 40, 52, PixelPalette.Ink)
                block(canvas, x - 17, y - 49, 34, 46, PixelPalette.DarkRust)
                block(canvas, x - 13, y - 44, 26, 16, PixelPalette.DeepNavy)
                block(canvas, x - 11, y - 41, 5, 5, PixelPalette.WarningAmber)
                block(canvas, x - 3, y - 41, 5, 5, PixelPalette.Teal)
                block(canvas, x + 5, y - 41, 5, 5, PixelPalette.MemoryMagenta)
                block(canvas, x - 7, y - 20, 14, 12, PixelPalette.LightIron)
            }
            "cancrab_king" -> {
                block(canvas, x - 29, y - 54, 58, 48, PixelPalette.Ink)
                block(canvas, x - 25, y - 50, 50, 40, PixelPalette.Rust)
                block(canvas, x - 48, y - 45, 25, 28, PixelPalette.Ink)
                block(canvas, x - 45, y - 41, 20, 20, PixelPalette.DarkIron)
                block(canvas, x + 23, y - 45, 25, 28, PixelPalette.Ink)
                block(canvas, x + 25, y - 41, 20, 20, PixelPalette.SparkOrange)
                block(canvas, x - 9, y - 35, 18, 12, PixelPalette.DeepNavy)
                block(canvas, x - 4, y - 31, 8, 5, PixelPalette.WarningAmber)
                block(canvas, x - 21, y - 8, 10, 10, PixelPalette.DarkIron)
                block(canvas, x + 12, y - 8, 10, 10, PixelPalette.DarkIron)
            }
            else -> {
                block(canvas, x - 11, y - 20, 22, 14, PixelPalette.Ink)
                block(canvas, x - 9, y - 18, 18, 10, PixelPalette.MidIron)
                block(canvas, x - 6, y - 16, 12, 3, PixelPalette.Rust)
                block(canvas, x - 13, y - 8, 5, 7, PixelPalette.DarkIron)
                block(canvas, x + 8, y - 8, 5, 7, PixelPalette.DarkIron)
                block(canvas, x + 6, y - 15, 3, 3, PixelPalette.WarningAmber)
            }
        }
    }

    private fun drawHealthBar(canvas: Canvas, state: CombatSnapshot) {
        val enemyName = state.enemyId.replace('_', ' ').uppercase()
        val nameX = (180 - enemyName.length * 3).coerceAtLeast(116)
        text(canvas, enemyName, nameX, 420, 7, PixelPalette.WorkWhite)
        block(canvas, 203, 428, 124, 12, PixelPalette.Ink)
        block(canvas, 207, 432, 116, 4, PixelPalette.DarkIron)
        val fillWidth = 116 * state.enemyHp / maxOf(1, state.enemyMaxHp)
        block(canvas, 207, 432, fillWidth, 4, PixelPalette.RecoveryGreen)
    }

    private fun drawControls(canvas: Canvas, state: CombatSnapshot) {
        panel(canvas, 8, 648, 344, 88)
        panel(canvas, 18, 674, 52, 44)
        block(canvas, 31, 685, 18, 4, PixelPalette.Teal)
        block(canvas, 31, 689, 4, 14, PixelPalette.Teal)
        block(canvas, 35, 699, 16, 4, PixelPalette.WarningAmber)
        text(canvas, "1X", 91, 701, 8, PixelPalette.WarningAmber)
        text(canvas, "2X", 124, 701, 8, PixelPalette.MidIron)
        text(canvas, "3X", 157, 701, 8, PixelPalette.MidIron)

        panel(canvas, 270, 667, 70, 54)
        block(canvas, 282, 707, 46, 4, PixelPalette.WarningAmber)
        block(canvas, 303, 682, 8, 25, PixelPalette.WarningAmber)
        block(canvas, 295, 694, 8, 13, PixelPalette.WarningAmber)
        val meterWidth = 54 * state.overclockTicks / 160
        block(canvas, 278, 715, 54, 3, PixelPalette.DarkIron)
        block(canvas, 278, 715, meterWidth, 3, PixelPalette.WorkWhite)
        text(canvas, "OVERCLOCK", 216, 659, 6, PixelPalette.WorkWhite)
    }

    private fun drawBottomTabs(canvas: Canvas) {
        val labels = listOf("WORK", "BASE", "DRONE", "DATA")
        repeat(4) { index ->
            val x = 8 + index * 88
            val active = index == 0
            block(canvas, x, 744, 80, 48, if (active) PixelPalette.DarkTeal else PixelPalette.DeepNavy)
            block(canvas, x, 744, 80, 3, PixelPalette.Ink)
            when (index) {
                0 -> {
                    block(canvas, x + 29, 762, 22, 5, PixelPalette.LightIron)
                    block(canvas, x + 44, 756, 6, 17, PixelPalette.SparkOrange)
                }
                1 -> {
                    block(canvas, x + 30, 758, 20, 15, PixelPalette.MidIron)
                    block(canvas, x + 34, 754, 12, 5, PixelPalette.Rust)
                }
                2 -> {
                    block(canvas, x + 29, 756, 22, 17, PixelPalette.Rust)
                    block(canvas, x + 34, 763, 12, 3, PixelPalette.WarningAmber)
                }
                else -> {
                    block(canvas, x + 37, 754, 5, 22, PixelPalette.LightIron)
                    block(canvas, x + 29, 763, 21, 5, PixelPalette.Teal)
                }
            }
            text(canvas, labels[index], x + 28, 787, 5, PixelPalette.WorkWhite)
            if (active) block(canvas, x + 18, 789, 44, 2, PixelPalette.WarningAmber)
        }
    }

    private fun panel(canvas: Canvas, x: Int, y: Int, width: Int, height: Int) {
        block(canvas, x, y, width, height, PixelPalette.Ink)
        block(canvas, x + 2, y + 2, width - 4, height - 4, PixelPalette.DarkIron)
        block(canvas, x + 4, y + 4, width - 8, height - 8, PixelPalette.DeepNavy)
        block(canvas, x + 6, y + 6, 3, 3, PixelPalette.WarningAmber)
        block(canvas, x + width - 9, y + 6, 3, 3, PixelPalette.WarningAmber)
    }

    private fun block(canvas: Canvas, x: Int, y: Int, width: Int, height: Int, color: Int) {
        if (width <= 0 || height <= 0) return
        blockPaint.color = color
        canvas.drawRect(x.toFloat(), y.toFloat(), (x + width).toFloat(), (y + height).toFloat(), blockPaint)
    }

    private fun text(canvas: Canvas, value: String, x: Int, baseline: Int, size: Int, color: Int) {
        textPaint.textSize = size.toFloat()
        textPaint.color = color
        canvas.drawText(value, x.toFloat(), baseline.toFloat(), textPaint)
    }

    companion object {
        const val LOGICAL_WIDTH = 360
        const val LOGICAL_HEIGHT = 800
    }
}
