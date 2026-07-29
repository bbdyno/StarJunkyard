package com.bbdyno.starjunkyard.combat

import com.bbdyno.starjunkyard.math.Pcg32
import com.bbdyno.starjunkyard.model.VerticalSliceContent

data class CombatSnapshot(
    val stage: Int,
    val enemyId: String,
    val enemyClass: String,
    val enemyHp: Int,
    val enemyMaxHp: Int,
    val credits: Int,
    val parts: Int,
    val tick: Int,
    val overclockTicks: Int,
    val scrapTicks: Int,
)

class CombatEngine(private val content: VerticalSliceContent) {
    private val enemyById = content.enemies.associateBy { it.id }
    private var stageIndex = 0
    private var waveIndex = 0
    private var enemyHp = 1
    private var enemyMaxHp = 1
    private var tick = 0
    private var nextPlayerAttackTick = 1
    private var nextDroneAttackTick = 1
    private var overclockUntilTick = 0
    private var scrapTicks = 0
    private var credits = 0
    private var parts = 0
    private var rng = Pcg32(seed = 42uL, stream = 54uL)

    init {
        require(content.stages.isNotEmpty())
        require(content.enemies.isNotEmpty())
        spawnCurrentEnemy()
    }

    fun tick() {
        tick += 1
        if (scrapTicks > 0) scrapTicks -= 1

        if (tick >= nextPlayerAttackTick) {
            val intervalTicks = if (tick < overclockUntilTick) 15 else 24
            nextPlayerAttackTick = tick + intervalTicks
            dealDamage(content.player.baseDamage * 3)
        }

        val drone = content.drones.firstOrNull()
        if (drone != null && currentStage.number >= drone.unlockStage && tick >= nextDroneAttackTick) {
            nextDroneAttackTick = tick + maxOf(1, drone.attackIntervalMs / TICK_MS)
            dealDamage(drone.baseDamage * 2)
        }
    }

    fun activateOverclock() {
        if (tick >= overclockUntilTick) overclockUntilTick = tick + OVERCLOCK_DURATION_TICKS
    }

    fun snapshot(): CombatSnapshot {
        val enemy = currentEnemy
        return CombatSnapshot(
            stage = currentStage.number,
            enemyId = enemy.id,
            enemyClass = enemy.enemyClass,
            enemyHp = maxOf(0, enemyHp),
            enemyMaxHp = enemyMaxHp,
            credits = credits,
            parts = parts,
            tick = tick,
            overclockTicks = maxOf(0, overclockUntilTick - tick),
            scrapTicks = scrapTicks,
        )
    }

    private val currentStage: VerticalSliceContent.Stage
        get() = content.stages[stageIndex]

    private val currentEnemy: VerticalSliceContent.Enemy
        get() = enemyById.getValue(currentStage.wave[waveIndex])

    private fun dealDamage(baseDamage: Int) {
        if (enemyHp <= 0) return
        val critical = rng.bounded(PPM.toUInt()) < content.player.criticalChancePpm.toUInt()
        val damage = if (critical) {
            baseDamage * content.player.criticalDamagePpm / PPM
        } else {
            baseDamage
        }
        enemyHp -= damage
        if (enemyHp <= 0) dismantleCurrentEnemy()
    }

    private fun dismantleCurrentEnemy() {
        val defeated = currentEnemy
        credits += currentStage.baseReward * currentStage.rewardMultiplierPpm / PPM
        parts += when (defeated.enemyClass) {
            "boss" -> 15
            "elite" -> 6
            else -> 3
        }
        scrapTicks = 8
        waveIndex += 1
        if (waveIndex >= currentStage.wave.size) {
            stageIndex = (stageIndex + 1) % content.stages.size
            waveIndex = 0
            rng = Pcg32(seed = content.stages[stageIndex].number.toULong(), stream = 54uL)
        }
        spawnCurrentEnemy()
    }

    private fun spawnCurrentEnemy() {
        val enemy = currentEnemy
        enemyMaxHp = maxOf(1, currentStage.baseHp * enemy.hpMultiplierPpm / PPM)
        enemyHp = enemyMaxHp
    }

    private companion object {
        const val PPM = 1_000_000
        const val TICK_MS = 50
        const val OVERCLOCK_DURATION_TICKS = 160
    }
}
