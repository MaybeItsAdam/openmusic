package io.github.maybeitsadam.openmusic.glance.models

import kotlinx.serialization.Serializable

@Serializable
data class Image(
    val height: Int?,
    val width: Int?,
    val path: String,
)