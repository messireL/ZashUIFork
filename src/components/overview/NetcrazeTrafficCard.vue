<template>
  <div class="card w-full">
    <div class="card-title flex items-center justify-between gap-2 px-4 pt-4">
      <div class="flex min-w-0 flex-col">
        <span>{{ $t('routerTrafficLive') }}</span>
        <span class="text-xs font-normal opacity-60">{{ $t('routerTrafficLiveTip') }}</span>
      </div>
      <div class="rounded-full border border-base-content/10 bg-base-200/60 px-2 py-1 text-[11px] opacity-70">
        {{ maxLabel }}
      </div>
    </div>

    <div class="card-body gap-3 pt-2">
      <div class="relative h-64 w-full overflow-hidden rounded-lg border border-base-content/10 bg-base-200/30">
        <div ref="chartRef" class="h-full w-full" />
        <span
          ref="colorRef"
          class="border-b-success/25 border-t-success/60 border-l-info/25 border-r-info/60 text-base-content/10 bg-base-100/80 hidden"
        />
      </div>

      <div class="grid gap-2 px-1 text-sm sm:grid-cols-3">
        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('routerTrafficTotal') }}</div>
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-blue-600" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentRouterDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-teal-500" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentRouterUploadLabel }}</span>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('mihomoVersion') }}</div>
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-violet-500" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentMihomoDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-pink-500" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentMihomoUploadLabel }}</span>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('routerTrafficOutsideMihomo') }}</div>
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-amber-500" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentOtherDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-rose-500" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentOtherUploadLabel }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { agentTrafficLiveAPI } from '@/api/agent'
import { prettyBytesHelper } from '@/helper/utils'
import { agentEnabled } from '@/store/agent'
import { downloadSpeed, timeSaved, uploadSpeed } from '@/store/overview'
import { font, theme } from '@/store/settings'
import { useElementSize } from '@vueuse/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import * as echarts from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { debounce } from 'lodash'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

echarts.use([LineChart, GridComponent, LegendComponent, TooltipComponent, CanvasRenderer])

type Point = { name: number; value: number }

const { t } = useI18n()
const chartRef = ref<HTMLElement | null>(null)
const colorRef = ref<HTMLElement | null>(null)

const initValue = () => new Array(timeSaved).fill(0).map((v, i) => ({ name: i, value: v }))
const routerDownloadHistory = ref<Point[]>(initValue())
const routerUploadHistory = ref<Point[]>(initValue())
const mihomoDownloadHistory = ref<Point[]>(initValue())
const mihomoUploadHistory = ref<Point[]>(initValue())
const otherDownloadHistory = ref<Point[]>(initValue())
const otherUploadHistory = ref<Point[]>(initValue())

const colorSet = {
  baseContent: '',
  baseContent10: '',
  base70: '',
  success25: '',
  success60: '',
  info30: '',
  info60: '',
}
let fontFamily = ''
let pollTimer: number | null = null
let lastRxBytes: number | null = null
let lastTxBytes: number | null = null
let lastSampleTs: number | null = null

const updateColorSet = () => {
  if (!colorRef.value) return
  const colorStyle = getComputedStyle(colorRef.value)
  colorSet.baseContent = colorStyle.getPropertyValue('--color-base-content').trim()
  colorSet.base70 = colorStyle.backgroundColor
  colorSet.baseContent10 = colorStyle.color
  colorSet.success25 = colorStyle.borderBottomColor
  colorSet.success60 = colorStyle.borderTopColor
  colorSet.info30 = colorStyle.borderLeftColor
  colorSet.info60 = colorStyle.borderRightColor
}

const updateFontFamily = () => {
  if (!colorRef.value) return
  fontFamily = getComputedStyle(colorRef.value).fontFamily
}

const latestValue = (items: Point[]) => {
  for (let i = items.length - 1; i >= 0; i -= 1) {
    const v = Number(items[i]?.value || 0)
    if (Number.isFinite(v)) return v
  }
  return 0
}

const pushHistory = (target: typeof routerDownloadHistory, timestamp: number, value: number) => {
  target.value.push({ name: timestamp, value: Math.max(0, Number(value) || 0) })
  target.value = target.value.slice(-1 * timeSaved)
}

const speedLabel = (value: number) => `${prettyBytesHelper(value, {
  maximumFractionDigits: value >= 1024 * 1024 ? 2 : 0,
  binary: false,
})}/s`

const currentRouterUploadLabel = computed(() => speedLabel(latestValue(routerUploadHistory.value)))
const currentRouterDownloadLabel = computed(() => speedLabel(latestValue(routerDownloadHistory.value)))
const currentMihomoUploadLabel = computed(() => speedLabel(latestValue(mihomoUploadHistory.value)))
const currentMihomoDownloadLabel = computed(() => speedLabel(latestValue(mihomoDownloadHistory.value)))
const currentOtherUploadLabel = computed(() => speedLabel(latestValue(otherUploadHistory.value)))
const currentOtherDownloadLabel = computed(() => speedLabel(latestValue(otherDownloadHistory.value)))

const allSeriesValues = computed(() => [
  ...routerDownloadHistory.value,
  ...routerUploadHistory.value,
  ...mihomoDownloadHistory.value,
  ...mihomoUploadHistory.value,
  ...otherDownloadHistory.value,
  ...otherUploadHistory.value,
].map((item) => Number(item?.value || 0)))

const maxObserved = computed(() => Math.max(0, ...allSeriesValues.value))

const roundedPeak = computed(() => {
  const raw = Math.max(maxObserved.value * 1.15, 1024 * 1024)
  const step = raw < 5 * 1024 * 1024 ? 256 * 1024 : 1024 * 1024
  return Math.ceil(raw / step) * step
})

const maxLabel = computed(() => `${t('peakScale')}: ${speedLabel(roundedPeak.value)}`)

const formatTime = (value: number) => {
  if (!value) return '—'
  const dt = new Date(Number(value))
  const hh = String(dt.getHours()).padStart(2, '0')
  const mm = String(dt.getMinutes()).padStart(2, '0')
  const ss = String(dt.getSeconds()).padStart(2, '0')
  return `${hh}:${mm}:${ss}`
}

const routerDownLabel = computed(() => t('routerTrafficLegendRouterDown'))
const routerUpLabel = computed(() => t('routerTrafficLegendRouterUp'))
const mihomoDownLabel = computed(() => t('routerTrafficLegendMihomoDown'))
const mihomoUpLabel = computed(() => t('routerTrafficLegendMihomoUp'))
const otherDownLabel = computed(() => t('routerTrafficLegendOtherDown'))
const otherUpLabel = computed(() => t('routerTrafficLegendOtherUp'))

const options = computed(() => ({
  grid: {
    left: 12,
    top: 42,
    right: 12,
    bottom: 26,
    containLabel: true,
  },
  legend: {
    top: 8,
    left: 12,
    right: 12,
    itemWidth: 12,
    itemHeight: 8,
    textStyle: {
      color: colorSet.baseContent,
      fontFamily,
      fontSize: 11,
    },
    data: [
      routerDownLabel.value,
      routerUpLabel.value,
      mihomoDownLabel.value,
      mihomoUpLabel.value,
      otherDownLabel.value,
      otherUpLabel.value,
    ],
  },
  tooltip: {
    trigger: 'axis',
    confine: true,
    backgroundColor: colorSet.base70,
    borderColor: colorSet.base70,
    textStyle: {
      color: colorSet.baseContent,
      fontFamily,
    },
    formatter: (params: ToolTipParams[]) => {
      const time = formatTime(Number(params?.[0]?.axisValue || 0))
      const lines = [
        `<div style="padding:6px 8px">`,
        `<div style="font-size:12px;opacity:.75;margin-bottom:4px">${time}</div>`,
      ]
      for (const item of params || []) {
        lines.push(
          `<div style="display:flex;align-items:center;gap:8px;margin:2px 0">` +
            `<span style="display:inline-block;width:8px;height:8px;border-radius:9999px;background:${item.color}"></span>` +
            `<span>${item.seriesName}: ${speedLabel(Number(item.value || 0))}</span>` +
          `</div>`,
        )
      }
      lines.push(`</div>`)
      return lines.join('')
    },
  },
  xAxis: {
    type: 'category',
    boundaryGap: false,
    data: routerDownloadHistory.value.map((item) => item.name),
    axisLine: {
      lineStyle: { color: colorSet.baseContent10 },
    },
    axisTick: { show: false },
    axisLabel: {
      color: colorSet.baseContent,
      fontFamily,
      formatter: (value: number, index: number) => {
        const last = routerDownloadHistory.value.length - 1
        return index === 0 || index === last ? formatTime(Number(value)) : ''
      },
    },
    splitLine: { show: false },
  },
  yAxis: {
    type: 'value',
    min: 0,
    max: roundedPeak.value,
    splitNumber: 4,
    axisLine: { show: false },
    axisTick: { show: false },
    axisLabel: {
      color: colorSet.baseContent,
      fontFamily,
      formatter: (value: number) => (Number(value) === roundedPeak.value ? speedLabel(value) : ''),
    },
    splitLine: {
      show: true,
      lineStyle: {
        type: 'dashed',
        color: colorSet.baseContent10,
      },
    },
  },
  series: [
    {
      name: routerDownLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: routerDownloadHistory.value.map((item) => item.value),
      color: '#2563eb',
      lineStyle: { width: 2.4 },
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(37,99,235,0.30)' },
          { offset: 1, color: 'rgba(37,99,235,0.05)' },
        ]),
      },
      emphasis: { focus: 'series' },
    },
    {
      name: routerUpLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: routerUploadHistory.value.map((item) => item.value),
      color: '#0d9488',
      lineStyle: { width: 2.4 },
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(13,148,136,0.28)' },
          { offset: 1, color: 'rgba(13,148,136,0.05)' },
        ]),
      },
      emphasis: { focus: 'series' },
    },
    {
      name: mihomoDownLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: mihomoDownloadHistory.value.map((item) => item.value),
      color: '#7c3aed',
      lineStyle: { width: 1.8, type: 'dashed' },
      emphasis: { focus: 'series' },
    },
    {
      name: mihomoUpLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: mihomoUploadHistory.value.map((item) => item.value),
      color: '#db2777',
      lineStyle: { width: 1.8, type: 'dashed' },
      emphasis: { focus: 'series' },
    },
    {
      name: otherDownLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: otherDownloadHistory.value.map((item) => item.value),
      color: '#f59e0b',
      lineStyle: { width: 2 },
      emphasis: { focus: 'series' },
    },
    {
      name: otherUpLabel.value,
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: otherUploadHistory.value.map((item) => item.value),
      color: '#e11d48',
      lineStyle: { width: 2 },
      emphasis: { focus: 'series' },
    },
  ],
}))

const stopPolling = () => {
  if (pollTimer !== null) {
    window.clearTimeout(pollTimer)
    pollTimer = null
  }
}

const scheduleNextPoll = () => {
  stopPolling()
  pollTimer = window.setTimeout(pollTraffic, 2000)
}

const pollTraffic = async () => {
  const timestamp = Date.now()
  const mihomoDown = Math.max(0, Number(downloadSpeed.value || 0))
  const mihomoUp = Math.max(0, Number(uploadSpeed.value || 0))

  let routerDown = 0
  let routerUp = 0

  if (agentEnabled.value) {
    const live = await agentTrafficLiveAPI()
    const rxBytes = Number(live?.rxBytes || 0)
    const txBytes = Number(live?.txBytes || 0)
    const ts = Number(live?.ts || timestamp)

    if (live.ok && Number.isFinite(rxBytes) && Number.isFinite(txBytes)) {
      if (lastRxBytes !== null && lastTxBytes !== null && lastSampleTs !== null && ts > lastSampleTs) {
        const dtSec = Math.max((ts - lastSampleTs) / 1000, 1)
        const rxDelta = Math.max(rxBytes - lastRxBytes, 0)
        const txDelta = Math.max(txBytes - lastTxBytes, 0)
        routerDown = rxDelta / dtSec
        routerUp = txDelta / dtSec
      }
      lastRxBytes = rxBytes
      lastTxBytes = txBytes
      lastSampleTs = ts
    }
  }

  const otherDown = Math.max(routerDown - mihomoDown, 0)
  const otherUp = Math.max(routerUp - mihomoUp, 0)

  pushHistory(routerDownloadHistory, timestamp, routerDown)
  pushHistory(routerUploadHistory, timestamp, routerUp)
  pushHistory(mihomoDownloadHistory, timestamp, mihomoDown)
  pushHistory(mihomoUploadHistory, timestamp, mihomoUp)
  pushHistory(otherDownloadHistory, timestamp, otherDown)
  pushHistory(otherUploadHistory, timestamp, otherUp)

  scheduleNextPoll()
}

onMounted(() => {
  updateColorSet()
  updateFontFamily()
  watch(theme, updateColorSet)
  watch(font, updateFontFamily)

  const chart = echarts.init(chartRef.value!)
  chart.setOption(options.value)

  watch(options, () => {
    chart.setOption(options.value)
  })

  const { width } = useElementSize(chartRef)
  const resize = debounce(() => chart.resize(), 100)
  watch(width, resize)

  pollTraffic()
})

onBeforeUnmount(() => {
  stopPolling()
})
</script>
