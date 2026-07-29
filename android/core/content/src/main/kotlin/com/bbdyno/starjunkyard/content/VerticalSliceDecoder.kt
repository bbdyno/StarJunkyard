package com.bbdyno.starjunkyard.content

import com.bbdyno.starjunkyard.model.VerticalSliceContent
import kotlinx.serialization.json.Json

object VerticalSliceDecoder {
    private val json = Json {
        ignoreUnknownKeys = false
        explicitNulls = false
    }

    fun decode(text: String): VerticalSliceContent = json.decodeFromString(text)
}
