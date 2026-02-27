<template>
  <div
    :class="twMerge('relative h-96 w-full overflow-hidden')"
    @mousemove.stop
    @touchmove.stop
  >
    <div ref="chart" class="h-full w-full" />
    <span
      class="border-base-content/30 text-base-content/10 bg-base-100/70 hidden"
      ref="colorRef"
    />

    <button
      :class="
        twMerge(
          'btn btn-ghost btn-circle btn-sm absolute right-1 bottom-1',
          isFullScreen ? 'fixed right-4 bottom-4 mb-[env(safe-area-inset-bottom)]' : '',
        )
      "
      @click="isFullScreen = !isFullScreen"
    >
      <component
        :is="isFullScreen ? ArrowsPointingInIcon : ArrowsPointingOutIcon"
        class="h-4 w-4"
      />
    </button>
  </div>

  <Teleport to="body">
    <div
      v-if="isFullScreen"
      class="bg-base-100 custom-background fixed inset-0 z-[9999] h-screen w-screen bg-cover bg-center"
      :class="`blur-intensity-${blurIntensity} custom-background-${dashboardTransparent}`"
      :style="backgroundImage"
    >
      <div
        ref="fullScreenChart"
        class="bg-base-100 h-full w-full"
        :style="fullChartStyle"
      />
      <button
        class="btn btn-ghost btn-circle btn-sm fixed right-4 bottom-4 mb-[env(safe-area-inset-bottom)]"
        @click="isFullScreen = false"
      >
        <ArrowsPointingInIcon class="h-4 w-4" />
      </button>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { isSingBox } from '@/api'
import { backgroundImage } from '@/helper/indexeddb'
import { activeConnections } from '@/store/connections'
import {
  blurIntensity,
  dashboardTransparent,
  font,
  proxiesRelationshipPaused,
  proxiesRelationshipRefreshNonce,
  proxiesRelationshipRefreshSec,
  theme,
} from '@/store/settings'
import { activeUuid } from '@/store/setup'
import type { Connection } from '@/types'
import { ArrowsPointingInIcon, ArrowsPointingOutIcon } from '@heroicons/vue/24/outline'
import { useElementSize } from '@vueuse/core'
import { SankeyChart } from 'echarts/charts'
import { TooltipComponent } from 'echarts/components'
import * as echarts from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { debounce } from 'lodash'
import { twMerge } from 'tailwind-merge'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

echarts.use([SankeyChart, TooltipComponent, CanvasRenderer])

const isFullScreen = ref(false)
const colorRef = ref()
const chart = ref()
const fullScreenChart = ref()

const fullChartStyle = computed(() => {
  return `backdrop-filter: blur(${blurIntensity.value}px);`
})

const colorSet = {
  baseContent30: '',
  baseContent: '',
  base70: '',
}

let fontFamily = ''

const updateColorSet = () => {
  const colorStyle = getComputedStyle(colorRef.value)
  colorSet.baseContent = colorStyle.getPropertyValue('--color-base-content').trim()
  colorSet.baseContent30 = colorStyle.borderColor
  colorSet.base70 = colorStyle.backgroundColor
}

const updateFontFamily = () => {
  const baseColorStyle = getComputedStyle(colorRef.value)
  fontFamily = baseColorStyle.fontFamily
}

// ----- snapshot & pause -----
const snapshot = ref<Connection[]>([])
let timer: number | undefined

const refreshSnapshot = () => {
  snapshot.value = activeConnections.value.slice()
}

const stopTimer = () => {
  if (timer) {
    clearInterval(timer)
    timer = undefined
  }
}

const startTimer = () => {
  stopTimer()
  timer = window.setInterval(() => {
    if (!proxiesRelationshipPaused.value) refreshSnapshot()
  }, Math.max(1, Number(proxiesRelationshipRefreshSec.value) || 5) * 1000)
}

watch(proxiesRelationshipPaused, (p) => {
  if (p) stopTimer()
  else {
    refreshSnapshot()
    startTimer()
  }
})

watch(proxiesRelationshipRefreshSec, () => {
  if (!proxiesRelationshipPaused.value) startTimer()
})

watch(proxiesRelationshipRefreshNonce, () => {
  refreshSnapshot()
})

// ----- sankey -----
const normalize = (s: string) => (s || '').trim() || '-'
const rootName = computed(() => (isSingBox.value ? 'SingBox' : 'Mihomo'))

const sankeyData = computed(() => {
  const conns = snapshot.value || []
  const MAX_SOURCES = isFullScreen.value ? 60 : 30

  const speed = (c: Connection) => (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  const hasSpeed = conns.some((c) => speed(c) > 0)
  const weight = (c: Connection) => (hasSpeed ? speed(c) : 1)

  // top sources
  const sourceTotals = new Map<string, number>()
  for (const c of conns) {
    const src = normalize(c.rulePayload || c.metadata.host || c.metadata.destinationIP)
    sourceTotals.set(src, (sourceTotals.get(src) || 0) + weight(c))
  }

  const topSources = new Set(
    Array.from(sourceTotals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_SOURCES)
      .map(([k]) => k),
  )

  const linkAgg = new Map<string, number>()
  const addLink = (source: string, target: string, value: number) => {
    const key = `${source}\u0000${target}`
    linkAgg.set(key, (linkAgg.get(key) || 0) + value)
  }

  for (const c of conns) {
    const rawSource = normalize(c.rulePayload || c.metadata.host || c.metadata.destinationIP)
    const source = topSources.has(rawSource) ? rawSource : 'other'
    const chain0 = normalize(c.chains?.[0] || 'DIRECT')
    const chain1 = c.chains?.[1] ? normalize(c.chains[1]) : ''
    const v = weight(c)

    addLink(rootName.value, source, v)
    addLink(source, chain0, v)
    if (chain1) addLink(chain0, chain1, v)
  }

  const nodesSet = new Set<string>()
  const links = Array.from(linkAgg.entries()).map(([key, value]) => {
    const [source, target] = key.split('\u0000')
    nodesSet.add(source)
    nodesSet.add(target)
    return { source, target, value }
  })

  const nodes = Array.from(nodesSet).map((name) => ({ name }))
  return { nodes, links }
})

const options = computed(() => {
  return {
    tooltip: {
      trigger: 'item',
      triggerOn: 'mousemove',
      backgroundColor: colorSet.base70,
      borderColor: colorSet.base70,
      confine: true,
      padding: [0, 6],
      textStyle: {
        color: colorSet.baseContent,
        fontFamily,
      },
    },
    series: [
      {
        type: 'sankey',
        data: sankeyData.value.nodes,
        links: sankeyData.value.links,
        emphasis: { focus: 'adjacency' },
        lineStyle: { curveness: 0.5, color: colorSet.baseContent30, opacity: 0.35 },
        label: {
          color: colorSet.baseContent,
          fontFamily,
          fontSize: 9,
        },
      },
    ],
  }
})

onMounted(() => {
  updateColorSet()
  updateFontFamily()

  refreshSnapshot()
  if (!proxiesRelationshipPaused.value) startTimer()

  watch(theme, updateColorSet)
  watch(font, updateFontFamily)

  const myChart = echarts.init(chart.value)
  const fullScreenMyChart = ref<echarts.ECharts>()

  myChart.setOption(options.value)

  watch([activeUuid, options, isFullScreen], () => {
    myChart?.clear()
    myChart?.setOption(options.value)

    if (isFullScreen.value) {
      nextTick(() => {
        if (!fullScreenMyChart.value) {
          fullScreenMyChart.value = echarts.init(fullScreenChart.value)
        }
        fullScreenMyChart.value?.clear()
        fullScreenMyChart.value?.setOption(options.value)
      })
    } else {
      fullScreenMyChart.value?.dispose()
      fullScreenMyChart.value = undefined
    }
  })

  const { width } = useElementSize(chart)
  const resize = debounce(() => {
    myChart.resize()
    fullScreenMyChart.value?.resize()
  }, 100)

  watch(width, resize)
})

onBeforeUnmount(() => {
  stopTimer()
})
</script>
