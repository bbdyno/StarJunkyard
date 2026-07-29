package com.bbdyno.starjunkyard.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class VerticalSliceContent(
    val schemaVersion: Int,
    val contentVersion: String,
    val slice: Slice,
    val player: Player,
    val drones: List<Drone>,
    val enemies: List<Enemy>,
    val stages: List<Stage>,
) {
    @Serializable
    data class Slice(
        val id: String,
        val regionId: String,
        val stageStart: Int,
        val stageEnd: Int,
    )

    @Serializable
    data class Player(
        val id: String,
        val baseDamage: Int,
        val attackIntervalMs: Int,
        val criticalChancePpm: Int,
        val criticalDamagePpm: Int,
        val spriteId: String,
    )

    @Serializable
    data class Drone(
        val id: String,
        val nameKo: String,
        val role: String,
        val baseDamage: Int,
        val attackIntervalMs: Int,
        val unlockStage: Int,
        val spriteId: String,
    )

    @Serializable
    data class Enemy(
        val id: String,
        val nameKo: String,
        @SerialName("class") val enemyClass: String,
        val hpMultiplierPpm: Int,
        val weakness: String,
        val spriteId: String,
    )

    @Serializable
    data class Stage(
        val number: Int,
        val baseHp: Int,
        val baseReward: Int,
        val wave: List<String>,
        val bossTier: Int? = null,
        val timeLimitMs: Int? = null,
        val rewardMultiplierPpm: Int,
    )
}
