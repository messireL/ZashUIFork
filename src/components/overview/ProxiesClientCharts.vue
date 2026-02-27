<template>
  <div
    :class="twMerge('relative h-96 w-full overflow-hidden')"
    @mousemove.stop
    @touchmove.stop
  >
    <div ref="chart" class="h-full w-full" />
    <span class="border-base-content/30 text-base-content/10 bg-base-100/70 hidden" ref="colorRef" />

    <button
      :class="
        twMerge(
          'btn btn-ghost btn-circle btn-sm absolute right-1 bottom-1',
          isFullScreen ? 'fixed right-4 bottom-4 mb-[env(safe-area-inset-bottom)]' : '',
        )
      "
      @click="isFullScreen = !isFullScreen"
    >
      <component :is="isFullScreen ? ArrowsPointingInIcon : ArrowsPointingOutIcon" class="h-4 w-4" />
    </button>
  </div>

  <Teleport to="body">
    <div
      v-if="isFullScreen"
      class="bg-base-100 custom-background fixed inset-0 z-[9999] h-screen w-screen bg-cover bg-center"
      :class="`blur-intensity-${blurIntensity} custom-background-${dashboardTransparent}`"
      :style="backgroundImage"
    >
      <div ref="fullScreenChart" class="bg-base-100 h-full w-full" :style="fullChartStyle" />
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
import { backgroundImage } from '@/helper/indexeddb'
import type { Connection } from '@/types'
import { activeConnections } from '@/store/connections'
import {
  blurIntensity,
  dashboardTransparent,
  font,
  theme,
  sourceIPLabelList,
  proxiesRelationshipPaused,
  proxiesRelationshipRefreshNonce,
  proxiesRelationshipRefreshSec,
} from '@/store/settings'
import { activeBackend } from '@/store/setup'
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
const chart = ref()
const fullScreenChart = ref()
const colorRef = ref()

const fullChartStyle = computed(() => `backdrop-filter: blur(${blurIntensity.value}px);`)

const colorSet = { baseContent30: '', baseContent: '', base70: '' }
let fontFamily = ''

const updateColorSet = () => {
  const cs = getComputedStyle(colorRef.value)
  colorSet.baseContent = cs.getPropertyValue('--color-base-content').trim()
  colorSet.baseContent30 = cs.borderColor
  colorSet.base70 = cs.backgroundColor
}
const updateFontFamily = () => {
  fontFamily = getComputedStyle(colorRef.value).fontFamily
}

const { width } = useElementSize(chart)
const labelFontSize = computed(() => {
  const w = Number(width.value) || 0
  const base = isFullScreen.value ? 14 : w >= 1100 ? 13 : w >= 800 ? 12 : 11
  return base
})

const labelForIp = (ip: string) => {
  const backendId = activeBackend.value?.uuid
  const item = sourceIPLabelList.value.find((x) => {
    if (x.key !== ip) return false
    if (!x.scope?.length) return true
    return backendId ? x.scope.includes(backendId) : false
  })
  return item?.label || ''
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
  refreshSnapshot()
})

const shortLabel = (name: string) => {
  if (!name) return ''
  const max = isFullScreen.value ? 46 : 32
  return name.length > max ? `${name.slice(0, max - 1)}…` : name
}

const sankeyData = computed(() => {
  const conns = snapshot.value || []
  const MAX_CLIENTS = isFullScreen.value ? 70 : 40

  const speed = (c: Connection) => (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  const hasSpeed = conns.some((c) => speed(c) > 0)
  const weight = (c: Connection) => (hasSpeed ? speed(c) : 1)

  const totals = new Map<string, number>()
  for (const c of conns) {
    const ip = c.metadata?.sourceIP || ''
    if (!ip) continue
    const v = weight(c)
    totals.set(ip, (totals.get(ip) || 0) + v)
  }

  const top = new Set(
    Array.from(totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_CLIENTS)
      .map(([k]) => k),
  )

  const linkAgg = new Map<string, number>()
  const add = (s: string, t: string, v: number) => {
    const key = `${s}\u0000${t}`
    linkAgg.set(key, (linkAgg.get(key) || 0) + v)
  }

  for (const c of conns) {
    const ip0 = c.metadata?.sourceIP || 'unknown'
    const ip = top.has(ip0) ? ip0 : 'other'
    const label = ip === 'other' ? 'other' : labelForIp(ip) ? `${labelForIp(ip)} (${ip})` : ip

    const chain0 = (c.chains?.[0] || 'DIRECT').trim() || 'DIRECT'
    const chain1 = c.chains?.[1]?.trim() || ''

    const v = weight(c)
    add(label, chain0, v)
    if (chain1) add(chain0, chain1, v)
  }

  const nodesSet = new Set<string>()
  const links = Array.from(linkAgg.entries()).map(([k, value]) => {
    const [source, target] = k.split('\u0000')
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

const options = computed(() => ({
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
    textStyle: { color: colorSet.baseContent, fontFamily, fontSize: Math.max(11, labelFontSize.value) },
  },
  series: [
    {
      id: 'sankey-clients',
      type: 'sankey',
      data: sankeyData.value.nodes,
      links: sankeyData.value.links,
      nodeAlign: 'left',
      nodeWidth: isFullScreen.value ? 16 : 14,
      nodeGap: isFullScreen.value ? 10 : 8,
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
}))

let mainChart: echarts.ECharts | null = null
let fsChart: echarts.ECharts | null = null

const render = (force = false) => {
  if (!mainChart) return
  mainChart.setOption(options.value as any, { notMerge: force, lazyUpdate: true })
  if (isFullScreen.value && fsChart) fsChart.setOption(options.value as any, { notMerge: force, lazyUpdate: true })
}

onMounted(() => {
  updateColorSet()
  updateFontFamily()

  refreshSnapshot()
  if (!proxiesRelationshipPaused.value) startTimer()

  watch(theme, updateColorSet)
  watch(font, updateFontFamily)

  mainChart = echarts.init(chart.value)
  mainChart.setOption(options.value as any)

  watch(options, () => render(false))

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
    mainChart?.resize()
    fsChart?.resize()
  }, 100)
  watch(width, resize)
})

onBeforeUnmount(() => {
  stopTimer()
  mainChart?.dispose()
  fsChart?.dispose()
  mainChart = null
  fsChart = null
})
</script>
