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

const { width } = useElementSize(chart)
const labelFontSize = computed(() => {
  // адаптив: чуть крупнее на больших экранах + в full-screen
  const w = Number(width.value) || 0
  const base = isFullScreen.value ? 14 : w >= 1100 ? 13 : w >= 800 ? 12 : 11
  return base
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

// ----- snapshot & pause (no constant redraw) -----
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
  const sec = Math.max(1, Number(proxiesRelationshipRefreshSec.value) || 5)
  timer = window.setInterval(() => {
    if (!proxiesRelationshipPaused.value) refreshSnapshot()
  }, sec * 1000)
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
  // manual refresh
  refreshSnapshot()
})

// ----- sankey -----
const normalize = (s: string) => (s || '').trim() || '-'
const rootName = computed(() => (isSingBox.value ? 'SingBox' : 'Mihomo'))

const sankeyData = computed(() => {
  const conns = snapshot.value || []
  const MAX_SOURCES = isFullScreen.value ? 70 : 40
  const MAX_CHAIN0 = isFullScreen.value ? 32 : 18
  const MAX_CHAIN1 = isFullScreen.value ? 32 : 18

  const speed = (c: Connection) => (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  const hasSpeed = conns.some((c) => speed(c) > 0)
  // Compress big traffic gaps: keeps “traffic feel” but prevents giant blocks.
  // If there is no speed info, fallback to count (=1).
  const weight = (c: Connection) =>
    hasSpeed ? Math.min(1 + Math.log1p(speed(c)), 60) : 1

  // totals
  const sourceTotals = new Map<string, number>()
  const chain0Totals = new Map<string, number>()
  const chain1Totals = new Map<string, number>()

  for (const c of conns) {
    const v = weight(c)
    const src = normalize(c.rulePayload || c.metadata.host || c.metadata.destinationIP)
    sourceTotals.set(src, (sourceTotals.get(src) || 0) + v)

    const c0 = normalize(c.chains?.[0] || 'DIRECT')
    chain0Totals.set(c0, (chain0Totals.get(c0) || 0) + v)

    const c1 = c.chains?.[1] ? normalize(c.chains[1]) : ''
    if (c1) chain1Totals.set(c1, (chain1Totals.get(c1) || 0) + v)
  }

  const topSources = new Set(
    Array.from(sourceTotals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_SOURCES)
      .map(([k]) => k),
  )

  const topChain0 = new Set(
    Array.from(chain0Totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_CHAIN0)
      .map(([k]) => k),
  )

  const topChain1 = new Set(
    Array.from(chain1Totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_CHAIN1)
      .map(([k]) => k),
  )

  const OTHER_SRC = 'other'
  const OTHER_C0 = 'other-out'
  const OTHER_C1 = 'other-node'

  const linkAgg = new Map<string, number>()
  const addLink = (source: string, target: string, value: number) => {
    const key = `${source}\u0000${target}`
    linkAgg.set(key, (linkAgg.get(key) || 0) + value)
  }

  for (const c of conns) {
    const v = weight(c)

    const rawSource = normalize(c.rulePayload || c.metadata.host || c.metadata.destinationIP)
    const source = topSources.has(rawSource) ? rawSource : OTHER_SRC

    const rawC0 = normalize(c.chains?.[0] || 'DIRECT')
    const chain0 = topChain0.has(rawC0) ? rawC0 : OTHER_C0

    const rawC1 = c.chains?.[1] ? normalize(c.chains[1]) : ''
    const chain1 = rawC1 ? (topChain1.has(rawC1) ? rawC1 : OTHER_C1) : ''

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

  const nodes = Array.from(nodesSet)
    .sort((a, b) => a.localeCompare(b))
    .map((name) => ({ name }))

  const linksSorted = links.sort((a, b) => {
    const s = a.source.localeCompare(b.source)
    if (s) return s
    return a.target.localeCompare(b.target)
  })

  return { nodes, links: linksSorted }
})

const shortLabel = (name: string) => {
  if (!name) return ''
  const max = isFullScreen.value ? 46 : 32
  return name.length > max ? `${name.slice(0, max - 1)}…` : name
}

const options = computed(() => {
  return {
    animation: true,
    animationDuration: 250,
    animationDurationUpdate: 550,
    animationEasingUpdate: 'cubicOut',
    tooltip: {
      trigger: 'item',
      triggerOn: 'mousemove',
      backgroundColor: colorSet.base70,
      borderColor: colorSet.base70,
      confine: true,
      padding: [6, 8],
      textStyle: {
        color: colorSet.baseContent,
        fontFamily,
        fontSize: Math.max(11, labelFontSize.value),
      },
    },
    series: [
      {
        id: 'sankey-sources',
        type: 'sankey',
        data: sankeyData.value.nodes,
        links: sankeyData.value.links,
        nodeAlign: 'justify',
        nodeWidth: isFullScreen.value ? 14 : 12,
        nodeGap: isFullScreen.value ? 6 : 4,
        emphasis: { focus: 'adjacency' },
        lineStyle: { curveness: 0.5, color: colorSet.baseContent30, opacity: 0.4 },
        label: {
          color: colorSet.baseContent,
          fontFamily,
          fontSize: labelFontSize.value,
          overflow: 'truncate',
          width: isFullScreen.value ? 260 : 180,
          formatter: (p: any) => shortLabel(p?.name || ''),
        },
      },
    ],
  }
})

let myChart: echarts.ECharts | null = null
let fsChart: echarts.ECharts | null = null

const render = (force = false) => {
  if (!myChart) return
  // no clear() => smoother updates
  myChart.setOption(options.value as any, { notMerge: force, lazyUpdate: true })
  if (isFullScreen.value && fsChart) {
    fsChart.setOption(options.value as any, { notMerge: force, lazyUpdate: true })
  }
}

onMounted(() => {
  updateColorSet()
  updateFontFamily()

  refreshSnapshot()
  if (!proxiesRelationshipPaused.value) startTimer()

  watch(theme, updateColorSet)
  watch(font, updateFontFamily)

  myChart = echarts.init(chart.value)
  myChart.setOption(options.value as any)

  watch([activeUuid], () => render(true))
  watch([options], () => render(false))

  watch(isFullScreen, async (v) => {
    if (v) {
      await nextTick()
      if (!fsChart) fsChart = echarts.init(fullScreenChart.value)
      render(true)
    } else {
      fsChart?.dispose()
      fsChart = null
    }
  })

  const resize = debounce(() => {
    myChart?.resize()
    fsChart?.resize()
  }, 100)

  watch(width, resize)
})

onBeforeUnmount(() => {
  stopTimer()
  myChart?.dispose()
  fsChart?.dispose()
  myChart = null
  fsChart = null
})
</script>
