// ARIA PATCH: keep renderables out of AnimatedContent's historical state keys.
// Copyright 2026 Aria contributors
// SPDX-License-Identifier: MPL-2.0
package skip.ui

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.referentialEqualityPolicy
import kotlin.collections.List as KotlinList

/**
 * AnimatedContent caches its target states in transitions and targetSizeMap. A
 * renderable list owns native view peers, state savers and images, so a fresh list
 * must not become a new animation state when only a view's content changed.
 *
 * Use immutable identity lists as animation states, and replace their content in
 * this composition-local store. Outgoing content stays available until Compose
 * disposes it; no image is explicitly released or recycled while being drawn.
 */
internal class AnimatedRenderableContent {
    private var targetIds: KotlinList<Any> = emptyList()
    private val content = mutableMapOf<KotlinList<Any>, MutableState<KotlinList<Renderable>>>()

    fun update(ids: KotlinList<Any>, renderables: KotlinList<Renderable>) {
        targetIds = ids.toList()
        val slot = content.getOrPut(targetIds) {
            mutableStateOf(renderables, referentialEqualityPolicy())
        }
        // Cached AnimatedContent lambdas must also see same-identity updates,
        // including while an incoming/outgoing transition is still running.
        slot.value = renderables
    }

    fun renderables(ids: KotlinList<Any>): KotlinList<Renderable> = content[ids]?.value.orEmpty()

    fun dispose(ids: KotlinList<Any>) {
        // A rapidly revisited identity can already be the current target again.
        if (ids != targetIds) content.remove(ids)
    }
}
