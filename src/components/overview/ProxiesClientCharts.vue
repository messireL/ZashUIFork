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
import { backgroundImage } from '@/helper/indexeddb'
import { activeConnections } from '@/store/connections'
import {
  blurIntensity,
  dashboardTransparent,
  font,
  proxiesRelationshipPaused,
  proxiesRelationshipRefreshNonce,
  proxiesRelationshipRefreshSec,
  sourceIPLabelList,
  theme,
} from '@/store/settings'
import { activeBackend } from '@/store/setup'
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

const sankeyData = computed(() => {
  const conns = snapshot.value || []
  const MAX_CLIENTS = isFullScreen.value ? 60 : 30

  const speed = (c: Connection) => (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  const hasSpeed = conns.some((c) => speed(c) > 0)
  const weight = (c: Connection) => (hasSpeed ? speed(c) : 1)

  const totals = new Map<string, number>()
  for (const c of conns) {
    const ip = c.metadata?.sourceIP || ''
    if (!ip) continue
    totals.set(ip, (totals.get(ip) || 0) + weight(c))
  }

  const top = new Set(
    Array.from(totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_CLIENTS)
      .map(([k]) => k),
  )

  const linkAgg = new Map<string, number>()
  const addLink = (source: string, target: string, value: number) => {
    const key = `${source}\u0000${target}`
    linkAgg.set(key, (linkAgg.get(key) || 0) + value)
  }

  for (const c of conns) {
    const ip0 = c.metadata?.sourceIP || 'unknown'
    const ip = top.has(ip0) ? ip0 : 'other'
    const label = ip === 'other' ? 'other' : (labelForIp(ip) ? `${labelForIp(ip)} (${ip})` : ip)

    const chain0 = normalize(c.chains?.[0] || 'DIRECT')
    const chain1 = c.chains?.[1] ? normalize(c.chains[1]) : ''
    const v = weight(c)

    addLink(label, chain0, v)
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

  watch([options, isFullScreen], () => {
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
