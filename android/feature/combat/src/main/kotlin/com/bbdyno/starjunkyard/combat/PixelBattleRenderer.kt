package com.bbdyno.starjunkyard.combat

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import kotlin.math.min

internal class PixelBattleRenderer(resources: Resources) {
    private val blockPaint = Paint().apply {
        isAntiAlias = false
        isDither = false
        isFilterBitmap = false
    }
    private val spritePaint = Paint().apply {
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
    private val koreanPaint = Paint().apply {
        isAntiAlias = true
        isDither = false
        color = PixelPalette.WorkWhite
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val background = resources.pixelBitmap(R.drawable.background_r01_back_alley)
    private val mechanic = resources.pixelBitmap(R.drawable.actor_mo_base)
    private val rivet = resources.pixelBitmap(R.drawable.drone_riv0_base)
    private val enemies = mapOf(
        "can_bug" to resources.pixelBitmap(R.drawable.enemy_can_bug),
        "umbrella_crab" to resources.pixelBitmap(R.drawable.enemy_umbrella_crab),
        "fan_bat" to resources.pixelBitmap(R.drawable.enemy_fan_bat),
        "vending_knight" to resources.pixelBitmap(R.drawable.elite_vending_knight),
        "cancrab_king" to resources.pixelBitmap(R.drawable.boss_cancrab_king),
    )

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
        drawScrapyard(canvas, state.tick)
        drawHeader(canvas, state)
        drawCombatants(canvas, state)
        drawControls(canvas, state)
    }

    private fun drawScrapyard(canvas: Canvas, tick: Int) {
        canvas.drawBitmap(background, 0f, 68f, spritePaint)
        val lampPulse = intArrayOf(0, 1, 2, 1)[(tick / 4) % 4]
        block(canvas, 91 - lampPulse, 112 - lampPulse, 4 + lampPulse * 2, 3 + lampPulse, PixelPalette.WarningAmber)
        block(canvas, 181 - lampPulse, 154 - lampPulse, 4 + lampPulse * 2, 3 + lampPulse, PixelPalette.WarningAmber)
        repeat(15) { index ->
            val x = (index * 29 + tick / 3) % 360
            val y = 88 + (index * 37 + tick * 2) % 500
            block(canvas, x, y, 1, 4 + index % 3, PixelPalette.WorkBlue)
        }
    }

    private fun drawHeader(canvas: Canvas, state: CombatSnapshot) {
        panel(canvas, 8, 7, 344, 56)
        text(canvas, "R1 • %02d".format(state.stage), 18, 39, 12, PixelPalette.WorkWhite)
        korean(canvas, "뒷골목 압착장", 137, 39, 10, PixelPalette.Teal)
        korean(canvas, "고철 ${state.credits}  부품 ${state.parts}", 260, 39, 8, PixelPalette.WarningAmber)
    }

    private fun drawCombatants(canvas: Canvas, state: CombatSnapshot) {
        val frame = (state.tick / 3) % 4
        val idleY = intArrayOf(0, -1, 0, 1)[frame]
        val attackX = when (state.playerAttackTicks) {
            3 -> 3
            2 -> 7
            1 -> 4
            else -> 0
        }
        shadow(canvas, 32 + attackX, 561 + idleY, 84)
        sprite(canvas, mechanic, 24 + attackX, 438 + idleY, 2)

        val hoverY = intArrayOf(0, -3, -1, 2)[frame]
        val droneX = if (state.droneAttackTicks == 2) 4 else 0
        sprite(canvas, rivet, 106 + droneX, 337 + hoverY, 1)
        drawRotorMotion(canvas, 106 + droneX, 337 + hoverY, frame)

        val enemy = enemies.getValue(state.enemyId)
        val geometry = enemyGeometry(state.enemyId, enemy, frame, state.hitTicks)
        shadow(canvas, geometry.x + 5, geometry.y + geometry.height - 8, geometry.width - 10)
        sprite(canvas, enemy, geometry.x, geometry.y, geometry.scale, flash = state.hitTicks > 0)
        drawEnemyStatus(canvas, state)
        drawAttackEffects(canvas, state, geometry)
        drawScrapRecovery(canvas, state, geometry)
    }

    private fun enemyGeometry(
        enemyId: String,
        bitmap: Bitmap,
        frame: Int,
        hitTicks: Int,
    ): SpriteGeometry {
        val scale = if (enemyId == "cancrab_king") 1 else 2
        val width = bitmap.width * scale
        val height = bitmap.height * scale
        val baseX = when (enemyId) {
            "vending_knight" -> 218
            "cancrab_king" -> 210
            else -> 246
        }
        val baseY = when (enemyId) {
            "fan_bat" -> 420
            "vending_knight" -> 432
            "cancrab_king" -> 448
            else -> 466
        }
        val motion = intArrayOf(0, -2, 0, 2)[frame]
        val hit = if (hitTicks > 0) intArrayOf(0, 5, -3, 2)[hitTicks.coerceIn(0, 3)] else 0
        return if (enemyId == "fan_bat") {
            SpriteGeometry(baseX + hit, baseY + motion * 2, scale, width, height)
        } else {
            SpriteGeometry(baseX + motion + hit, baseY, scale, width, height)
        }
    }

    private fun drawEnemyStatus(canvas: Canvas, state: CombatSnapshot) {
        val enemyName = when (state.enemyId) {
            "can_bug" -> "캔벌레"
            "umbrella_crab" -> "우산게"
            "fan_bat" -> "선풍기박쥐"
            "vending_knight" -> "자판기기사"
            else -> "압착왕 캔크랩"
        }
        korean(canvas, enemyName, 224, 405, 11, PixelPalette.WorkWhite)
        block(canvas, 214, 414, 124, 12, PixelPalette.Ink)
        block(canvas, 218, 418, 116, 4, PixelPalette.DarkIron)
        val fillWidth = 116 * state.enemyHp / maxOf(1, state.enemyMaxHp)
        block(canvas, 218, 418, fillWidth, 4, PixelPalette.RecoveryGreen)
    }

    private fun drawAttackEffects(canvas: Canvas, state: CombatSnapshot, enemy: SpriteGeometry) {
        if (state.playerAttackTicks > 0) {
            val progress = 4 - state.playerAttackTicks
            val x = 122 + progress * 38
            val y = 492 - progress * 4
            block(canvas, x, y, 9, 4, PixelPalette.WarningAmber)
            block(canvas, x + 8, y + 1, 5, 2, PixelPalette.WorkWhite)
        }
        if (state.droneAttackTicks > 0) {
            val progress = 3 - state.droneAttackTicks
            block(canvas, 155 + progress * 50, 358 + progress * 22, 6, 3, PixelPalette.LightTeal)
        }
        if (state.hitTicks > 0) {
            repeat(4) { index ->
                block(
                    canvas,
                    enemy.x + 8 + index * 13,
                    enemy.y - 4 - (index % 2) * 5,
                    4,
                    4,
                    if (index.isEven()) PixelPalette.WarningAmber else PixelPalette.WorkWhite,
                )
            }
        }
    }

    private fun drawScrapRecovery(canvas: Canvas, state: CombatSnapshot, enemy: SpriteGeometry) {
        if (state.scrapTicks <= 0) return
        val progress = 8 - state.scrapTicks
        repeat(9) { index ->
            val startX = enemy.x + enemy.width / 2 + (index % 3 - 1) * 12
            val startY = enemy.y + enemy.height / 2 + (index / 3 - 1) * 9
            val x = startX + (130 - startX) * progress / 8
            val y = startY + (357 - startY) * progress / 8 - (4 - kotlin.math.abs(4 - progress)) * 5
            block(
                canvas,
                x,
                y,
                3 + index % 2,
                3,
                if (index.isEven()) PixelPalette.SparkOrange else PixelPalette.LightIron,
            )
        }
        repeat(progress.coerceAtMost(4)) { index ->
            block(canvas, 157 + index * 18, 365 + index * 7, 8, 2, PixelPalette.Teal)
        }
    }

    private fun drawRotorMotion(canvas: Canvas, x: Int, y: Int, frame: Int) {
        val width = if (frame.isEven()) 18 else 10
        block(canvas, x - width / 2 + 11, y - 2, width, 2, PixelPalette.LightIron)
        block(canvas, x - width / 2 + 36, y - 2, width, 2, PixelPalette.LightIron)
    }

    private fun drawControls(canvas: Canvas, state: CombatSnapshot) {
        block(canvas, 0, 640, 360, 160, PixelPalette.Ink)
        panel(canvas, 8, 648, 344, 144)
        korean(canvas, "자동 해체 가동 중", 22, 677, 12, PixelPalette.Teal)
        korean(canvas, "절단기 LV.1  •  리벳 지원  •  자석 회수", 22, 698, 8, PixelPalette.WorkWhite)

        block(canvas, 22, 716, 184, 14, PixelPalette.Ink)
        repeat(8) { index ->
            val offset = (state.tick / 2) % 21
            block(
                canvas,
                25 + ((index * 23 + offset) % 178),
                720,
                14,
                6,
                if (index.isEven()) PixelPalette.MidIron else PixelPalette.DarkIron,
            )
        }
        text(canvas, "1X", 40, 764, 9, PixelPalette.WarningAmber)
        text(canvas, "2X", 91, 764, 9, PixelPalette.MidIron)
        text(canvas, "3X", 142, 764, 9, PixelPalette.MidIron)

        panel(canvas, 226, 665, 112, 112)
        korean(canvas, "과부하", 264, 689, 10, PixelPalette.WorkWhite)
        block(canvas, 276, 710, 12, 34, PixelPalette.WarningAmber)
        block(canvas, 264, 728, 24, 12, PixelPalette.WarningAmber)
        block(canvas, 264, 740, 12, 18, PixelPalette.WarningAmber)
        block(canvas, 251, 763, 62, 5, PixelPalette.DarkIron)
        val meterWidth = if (state.overclockTicks == 0) 62 else 62 * state.overclockTicks / 160
        block(canvas, 251, 763, meterWidth, 5, if (state.overclockTicks == 0) PixelPalette.WarningAmber else PixelPalette.WorkWhite)
    }

    private fun sprite(
        canvas: Canvas,
        bitmap: Bitmap,
        x: Int,
        y: Int,
        scale: Int,
        flash: Boolean = false,
    ) {
        val destination = Rect(x, y, x + bitmap.width * scale, y + bitmap.height * scale)
        spritePaint.alpha = if (flash) 150 else 255
        canvas.drawBitmap(bitmap, null, destination, spritePaint)
        spritePaint.alpha = 255
    }

    private fun shadow(canvas: Canvas, x: Int, y: Int, width: Int) {
        block(canvas, x, y, width, 6, PixelPalette.Ink)
        block(canvas, x + 7, y - 2, (width - 14).coerceAtLeast(1), 2, PixelPalette.DarkIron)
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

    private fun korean(canvas: Canvas, value: String, x: Int, baseline: Int, size: Int, color: Int) {
        koreanPaint.textSize = size.toFloat()
        koreanPaint.color = color
        canvas.drawText(value, x.toFloat(), baseline.toFloat(), koreanPaint)
    }

    private data class SpriteGeometry(
        val x: Int,
        val y: Int,
        val scale: Int,
        val width: Int,
        val height: Int,
    )

    private fun Int.isEven(): Boolean = this % 2 == 0

    private fun Resources.pixelBitmap(identifier: Int): Bitmap {
        val options = BitmapFactory.Options().apply { inScaled = false }
        return requireNotNull(BitmapFactory.decodeResource(this, identifier, options))
    }

    companion object {
        const val LOGICAL_WIDTH = 360
        const val LOGICAL_HEIGHT = 800
    }
}
