<template>
  <div
    ref="previewRef"
    class="flex flex-wrap"
    :class="[(showDots || showSquares) ? 'gap-1 pt-3' : 'gap-2 pt-4 pb-1']"
  >
    <template v-if="showDots || showSquares">
      <div
        v-for="node in nodesLatency"
        :key="node.name"
        class="flex h-5 w-5 items-center justify-center transition hover:scale-110"
        :class="[
          showSquares ? 'rounded-md' : 'rounded-full',
          getBgColor(node.latency),
          now === node.name ? 'ring-2 ring-base-100 ring-offset-2 ring-offset-base-content/20' : '',
        ]"
        ref="dotsRef"
        @mouseenter="(e) => makeTippy(e, node)"
        @click.stop="$emit('nodeclick', node.name)"
      >
        <component :is="iconForLatency(node.latency)" class="h-3.5 w-3.5 text-white/90" />
      </div>
    </template>
    <div
      v-else
      class="flex flex-1 items-center justify-center overflow-hidden rounded-2xl *:h-2"
    >
      <div
        :class="getBgColor(lowLatency - 1)"
        :style="{
          width: `${(goodsCounts * 100) / nodes.length}%`, // cant use tw class, otherwise dynamic classname won't be generated
        }"
      />
      <div
        :class="getBgColor(mediumLatency - 1)"
        :style="{
          width: `${(mediumCounts * 100) / nodes.length}%`,
        }"
      />
      <div
        :class="getBgColor(mediumLatency + 1)"
        :style="{
          width: `${(badCounts * 100) / nodes.length}%`,
        }"
      />
      <div
        :class="getBgColor(NOT_CONNECTED)"
        :style="{
          width: `${(notConnectedCounts * 100) / nodes.length}%`,
        }"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { NOT_CONNECTED, PROXY_PREVIEW_TYPE } from '@/constant'
import { getColorForLatency } from '@/helper'
import { useTooltip } from '@/helper/tooltip'
import { getLatencyByName } from '@/store/proxies'
import { lowLatency, mediumLatency, proxyPreviewType } from '@/store/settings'
import { useElementSize } from '@vueuse/core'
import { BoltIcon, PauseCircleIcon, PlayCircleIcon, XMarkIcon } from '@heroicons/vue/24/outline'
import { computed, ref } from 'vue'

const props = defineProps<{
  nodes: string[]
  now?: string
  groupName?: string
}>()

const { showTip } = useTooltip()
const previewRef = ref<HTMLElement | null>(null)
const { width } = useElementSize(previewRef)

const widthEnough = computed(() => {
  return width.value > 20 * props.nodes.length
})

const makeTippy = (e: Event, node: { name: string; latency: number }) => {
  const tag = document.createElement('div')
  const name = document.createElement('div')

  name.textContent = node.name
  tag.append(name)

  if (node.latency !== NOT_CONNECTED) {
    const latency = document.createElement('div')

    latency.textContent = `${node.latency}ms`
    latency.classList.add(getColorForLatency(node.latency))
    tag.append(latency)
  }

  tag.classList.add('flex', 'items-center', 'gap-2')
  showTip(e, tag)
}

const showSquares = computed(() => {
  return proxyPreviewType.value === PROXY_PREVIEW_TYPE.SQUARES
})

const showDots = computed(() => {
  return (
    proxyPreviewType.value === PROXY_PREVIEW_TYPE.DOTS ||
    (proxyPreviewType.value === PROXY_PREVIEW_TYPE.AUTO && widthEnough.value)
  )
})

const nodesLatency = computed(() =>
  props.nodes.map((name) => {
    return {
      latency: getLatencyByName(name, props.groupName),
      name: name,
    }
  }),
)
const getBgColor = (latency: number) => {
  if (latency === NOT_CONNECTED) {
    return 'bg-base-content/60'
  } else if (latency < lowLatency.value) {
    return 'bg-low-latency'
  } else if (latency < mediumLatency.value) {
    return 'bg-medium-latency'
  } else {
    return 'bg-high-latency'
  }
}

const iconForLatency = (latency: number) => {
  if (latency === NOT_CONNECTED) return XMarkIcon
  if (latency < lowLatency.value) return BoltIcon
  if (latency < mediumLatency.value) return PlayCircleIcon
  return PauseCircleIcon
}

const goodsCounts = computed(() => {
  return nodesLatency.value.filter(
    (node) => node.latency < lowLatency.value && node.latency > NOT_CONNECTED,
  ).length
})
const mediumCounts = computed(() => {
  return nodesLatency.value.filter(
    (node) => node.latency >= lowLatency.value && node.latency < mediumLatency.value,
  ).length
})
const badCounts = computed(() => {
  return nodesLatency.value.filter((node) => node.latency >= mediumLatency.value).length
})
const notConnectedCounts = computed(() => {
  return nodesLatency.value.filter((node) => node.latency === NOT_CONNECTED).length
})
</script>

<style scoped>
.tooltip:before {
  left: 0;
  transform: translateX(-10px);
}
</style>
