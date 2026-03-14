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
          class="border-b-success/25 border-t-success/60 border-l-info/25 border-r-info/60 text-base-content/10 bg-base-100/80 hidden [--router-wan-down:#2563eb] [--router-wan-up:#14b8a6] [--router-mihomo-down:#7c3aed] [--router-mihomo-up:#ec4899] [--router-other-down:#f59e0b] [--router-other-up:#22c55e]"
        />
      </div>

      <div class="grid gap-2 px-1 text-sm sm:grid-cols-3">
        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('routerTrafficTotal') }}</div>
          <div class="flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-wan-down)]" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentRouterDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-wan-up)]" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentRouterUploadLabel }}</span>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('mihomoVersion') }}</div>
          <div class="flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-mihomo-down)]" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentMihomoDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-mihomo-up)]" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentMihomoUploadLabel }}</span>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2">
          <div class="mb-1 text-xs opacity-60">{{ $t('routerTrafficOutsideMihomo') }}</div>
          <div class="flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-other-down)]" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ currentOtherDownloadLabel }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-other-up)]" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ currentOtherUploadLabel }}</span>
          </div>
        </div>
      </div>

      <div v-if="currentExtraStats.length" class="grid gap-2 px-1 text-sm sm:grid-cols-2 xl:grid-cols-3">
        <div
          v-for="(item, index) in currentExtraStats"
          :key="`extra-card-${item.name}`"
          class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-2"
        >
          <div class="mb-1 flex items-center justify-between gap-2">
            <div class="min-w-0 truncate text-xs opacity-80">{{ ifaceDisplayName(item.name, item.kind) }}</div>
            <span class="badge badge-ghost badge-xs uppercase">{{ item.kind || 'vpn' }}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full" :style="{ backgroundColor: extraColorPair(index).down }" />
            <span class="opacity-80">{{ $t('download') }}:</span>
            <span class="font-mono">{{ speedLabel(item.down) }}</span>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full" :style="{ backgroundColor: extraColorPair(index).up }" />
            <span class="opacity-80">{{ $t('upload') }}:</span>
            <span class="font-mono">{{ speedLabel(item.up) }}</span>
          </div>
        </div>
      </div>

      <div v-if="stableTrafficHosts.length" class="rounded-lg border border-base-content/10 bg-base-200/20 px-3 py-3">
        <div class="mb-2 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <div class="text-sm font-medium">{{ $t('routerTrafficTopHosts') }}</div>
            <div class="text-xs opacity-60">{{ $t('routerTrafficTopHostsTip') }}</div>
          </div>
          <span class="badge badge-ghost badge-sm">Mihomo</span>
        </div>

        <div class="overflow-hidden rounded-lg border border-base-content/10 bg-base-100/30">
          <div class="grid grid-cols-[minmax(0,1.4fr)_96px_96px_72px] items-center gap-3 px-3 py-2 text-[11px] uppercase tracking-wide opacity-60">
            <div>{{ $t('routerTrafficTopHosts') }}</div>
            <div>{{ $t('download') }}</div>
            <div>{{ $t('upload') }}</div>
            <div class="text-right">{{ $t('connections') }}</div>
          </div>

          <div
            v-for="item in stableTrafficHosts"
            :key="`traffic-host-${item.ip}`"
            class="grid grid-cols-[minmax(0,1.4fr)_96px_96px_72px] items-center gap-3 border-t border-base-content/10 px-3 py-2 text-sm"
          >
            <div class="min-w-0">
              <div class="truncate font-medium">{{ item.label }}</div>
              <div class="truncate text-[11px] opacity-60">{{ item.ip }}</div>
              <div v-if="item.targets.length" class="truncate text-[11px] opacity-70">{{ item.targets.join(' · ') }}</div>
            </div>
            <div class="inline-flex items-center gap-2 font-mono text-xs sm:text-sm">
              <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-mihomo-down)]" />
              <span>{{ speedLabel(item.down) }}</span>
            </div>
            <div class="inline-flex items-center gap-2 font-mono text-xs sm:text-sm">
              <span class="inline-block h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--router-mihomo-up)]" />
              <span>{{ speedLabel(item.up) }}</span>
            </div>
            <div class="text-right">
              <span class="badge badge-ghost badge-xs sm:badge-sm">{{ item.connections }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { agentLanHostsAPI, agentTrafficLiveAPI, type AgentTrafficLiveIface } from '@/api/agent'
import { prettyBytesHelper } from '@/helper/utils'
import { agentEnabled } from '@/store/agent'
import { activeConnections } from '@/store/connections'
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
type ToolTipParams = {
  axisValue?: number
  seriesName?: string
  color?: string
  value?: number
}
type ExtraHistoryMap = Record<string, { down: Point[]; up: Point[]; kind?: string }>
type ExtraCounterState = Record<string, { rxBytes: number; txBytes: number; ts: number; kind?: string }>

type ExtraColorPair = { down: string; up: string }
type HostTrafficStat = { label: string; ip: string; down: number; up: number; connections: number; targets: string[] }
type HostTrafficState = HostTrafficStat & { displayDown: number; displayUp: number; lastSeen: number; score: number; missingTicks: number }

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
const extraHistories = ref<ExtraHistoryMap>({})
const extraOrder = ref<string[]>([])

const colorSet = {
  baseContent: '',
  baseContent10: '',
  base70: '',
  success25: '',
  success60: '',
  info30: '',
  info60: '',
}
const extraPalette: ExtraColorPair[] = [
  { down: '#06b6d4', up: '#f97316' },
  { down: '#84cc16', up: '#ef4444' },
  { down: '#a855f7', up: '#14b8a6' },
  { down: '#f43f5e', up: '#0ea5e9' },
  { down: '#facc15', up: '#7c3aed' },
  { down: '#22c55e', up: '#e11d48' },
  { down: '#38bdf8', up: '#d97706' },
  { down: '#10b981', up: '#8b5cf6' },
]
let fontFamily = ''
let pollTimer: number | null = null
let lastRxBytes: number | null = null
let lastTxBytes: number | null = null
let lastSampleTs: number | null = null
const lastExtraCounters = ref<ExtraCounterState>({})
const lanHostNames = ref<Record<string, string>>({})
let hostsTimer: number | null = null

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

const pushHistory = (target: { value: Point[] }, timestamp: number, value: number) => {
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

const ifaceDisplayName = (name: string, kind?: string) => {
  const upperKind = (kind || '').toLowerCase()
  if (upperKind === 'xkeen') return `XKeen · ${name}`
  if (upperKind === 'wireguard') return `WireGuard · ${name}`
  if (upperKind === 'tailscale') return `Tailscale · ${name}`
  if (upperKind === 'openvpn' || upperKind === 'ovpn') return `OpenVPN · ${name}`
  if (upperKind === 'zerotier') return `ZeroTier · ${name}`
  if (upperKind === 'ipsec') return `IPsec · ${name}`
  return name
}

const ifaceDownLabel = (name: string, kind?: string) => `${ifaceDisplayName(name, kind)} ↓`
const ifaceUpLabel = (name: string, kind?: string) => `${ifaceDisplayName(name, kind)} ↑`
const extraColorPair = (index: number) => extraPalette[index % extraPalette.length]

const ensureExtraHistory = (name: string, kind?: string) => {
  if (!extraHistories.value[name]) {
    extraHistories.value[name] = { down: initValue(), up: initValue(), kind }
  }
  if (!extraOrder.value.includes(name)) {
    extraOrder.value = [...extraOrder.value, name]
  }
  if (kind) extraHistories.value[name].kind = kind
}

const extraInterfaceKeys = computed(() => extraOrder.value.filter((name) => !!extraHistories.value[name]))

const currentExtraStats = computed(() => {
  return extraInterfaceKeys.value
    .map((name) => ({
      name,
      kind: extraHistories.value[name]?.kind || 'vpn',
      down: latestValue(extraHistories.value[name]?.down || []),
      up: latestValue(extraHistories.value[name]?.up || []),
    }))
    .filter((item) => item.down > 0 || item.up > 0 || !!item.kind)
    .sort((a, b) => (b.down + b.up) - (a.down + a.up))
})

const hostTrafficState = ref<Record<string, HostTrafficState>>({})
let hostTrafficTimer: number | null = null

const collectHostSnapshot = (): HostTrafficStat[] => {
  const map = new Map<string, { ip: string; label: string; down: number; up: number; connections: number; targets: Set<string> }>()

  for (const conn of activeConnections.value) {
    const ip = String(conn?.metadata?.sourceIP || '').trim()
    if (!ip) continue

    const down = Math.max(0, Number(conn?.downloadSpeed || 0))
    const up = Math.max(0, Number(conn?.uploadSpeed || 0))
    const target = String(conn?.metadata?.host || conn?.metadata?.sniffHost || conn?.metadata?.destinationIP || '').trim()
    const label = lanHostNames.value[ip] || ip

    const current = map.get(ip) || { ip, label, down: 0, up: 0, connections: 0, targets: new Set<string>() }
    current.label = label || current.label || ip
    current.down += down
    current.up += up
    current.connections += 1
    if (target && current.targets.size < 3) current.targets.add(target)
    map.set(ip, current)
  }

  return [...map.values()].map((item) => ({
    ip: item.ip,
    label: item.label,
    down: item.down,
    up: item.up,
    connections: item.connections,
    targets: [...item.targets],
  }))
}

const refreshHostTraffic = () => {
  const now = Date.now()
  const current = collectHostSnapshot()
  const seen = new Set<string>()
  const next: Record<string, HostTrafficState> = { ...hostTrafficState.value }

  for (const item of current) {
    seen.add(item.ip)
    const prev = next[item.ip]
    const alpha = prev ? 0.38 : 1
    const displayDown = prev ? ((prev.displayDown * (1 - alpha)) + (item.down * alpha)) : item.down
    const displayUp = prev ? ((prev.displayUp * (1 - alpha)) + (item.up * alpha)) : item.up
    const scoreBase = item.down + item.up
    next[item.ip] = {
      ...item,
      displayDown,
      displayUp,
      lastSeen: now,
      score: prev ? ((prev.score * 0.7) + (scoreBase * 0.3)) : scoreBase,
      missingTicks: 0,
    }
  }

  for (const [ip, item] of Object.entries(next)) {
    if (seen.has(ip)) continue
    const agedMs = now - Number(item.lastSeen || 0)
    const decay = agedMs > 20000 ? 0.72 : 0.84
    const displayDown = (item.displayDown || 0) * decay
    const displayUp = (item.displayUp || 0) * decay
    const score = (item.score || 0) * decay
    const missingTicks = (item.missingTicks || 0) + 1
    if ((displayDown + displayUp) < 256 && missingTicks > 8) {
      delete next[ip]
      continue
    }
    next[ip] = {
      ...item,
      down: displayDown,
      up: displayUp,
      displayDown,
      displayUp,
      connections: 0,
      score,
      missingTicks,
    }
  }

  hostTrafficState.value = next
}

const scheduleHostTrafficRefresh = () => {
  if (hostTrafficTimer !== null) window.clearTimeout(hostTrafficTimer)
  hostTrafficTimer = window.setTimeout(() => {
    refreshHostTraffic()
    scheduleHostTrafficRefresh()
  }, 1500)
}

const stableTrafficHosts = computed<HostTrafficStat[]>(() => {
  return Object.values(hostTrafficState.value)
    .filter((item) => (item.displayDown + item.displayUp) > 0)
    .sort((a, b) => {
      const scoreDiff = (b.score || 0) - (a.score || 0)
      if (Math.abs(scoreDiff) > 128) return scoreDiff
      return (b.lastSeen || 0) - (a.lastSeen || 0)
    })
    .slice(0, 8)
    .map((item) => ({
      ip: item.ip,
      label: item.label,
      down: item.displayDown,
      up: item.displayUp,
      connections: item.connections,
      targets: item.targets,
    }))
})

const refreshLanHosts = async () => {
  if (!agentEnabled.value) return
  const res = await agentLanHostsAPI()
  if (!res?.ok || !Array.isArray(res.items)) return
  const next: Record<string, string> = {}
  for (const item of res.items) {
    const ip = String(item?.ip || '').trim()
    if (!ip) continue
    const label = String(item?.hostname || item?.mac || '').trim()
    if (label) next[ip] = label
  }
  lanHostNames.value = next
}

const scheduleHostRefresh = () => {
  if (hostsTimer !== null) window.clearTimeout(hostsTimer)
  hostsTimer = window.setTimeout(async () => {
    await refreshLanHosts()
    scheduleHostRefresh()
  }, 60000)
}

const extraSeriesValues = computed(() => {
  return extraInterfaceKeys.value.flatMap((name) => {
    const hist = extraHistories.value[name]
    if (!hist) return [] as number[]
    return [...hist.down, ...hist.up].map((item) => Number(item?.value || 0))
  })
})

const allSeriesValues = computed(() => [
  ...routerDownloadHistory.value,
  ...routerUploadHistory.value,
  ...mihomoDownloadHistory.value,
  ...mihomoUploadHistory.value,
  ...otherDownloadHistory.value,
  ...otherUploadHistory.value,
].map((item) => Number(item?.value || 0)).concat(extraSeriesValues.value))

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

const dynamicLegendItems = computed(() => extraInterfaceKeys.value.flatMap((name) => {
  const kind = extraHistories.value[name]?.kind
  return [ifaceDownLabel(name, kind), ifaceUpLabel(name, kind)]
}))

const dynamicExtraSeries = computed(() => extraInterfaceKeys.value.flatMap((name, index) => {
  const hist = extraHistories.value[name]
  if (!hist) return []
  const colors = extraColorPair(index)
  return [
    {
      name: ifaceDownLabel(name, hist.kind),
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: hist.down.map((item) => item.value),
      color: colors.down,
      lineStyle: { width: 1.8 },
      emphasis: { focus: 'series' },
    },
    {
      name: ifaceUpLabel(name, hist.kind),
      type: 'line',
      smooth: true,
      symbol: 'none',
      data: hist.up.map((item) => item.value),
      color: colors.up,
      lineStyle: { width: 1.8, type: 'dotted' },
      emphasis: { focus: 'series' },
    },
  ]
}))

const options = computed(() => ({
  grid: {
    left: 12,
    top: 52,
    right: 12,
    bottom: 26,
    containLabel: true,
  },
  legend: {
    type: 'scroll',
    top: 8,
    left: 12,
    right: 12,
    itemWidth: 12,
    itemHeight: 8,
    pageIconColor: colorSet.baseContent,
    pageTextStyle: {
      color: colorSet.baseContent,
      fontFamily,
      fontSize: 10,
    },
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
      ...dynamicLegendItems.value,
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
      color: '#ec4899',
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
      color: '#22c55e',
      lineStyle: { width: 2 },
      emphasis: { focus: 'series' },
    },
    ...dynamicExtraSeries.value,
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

const computeExtraSpeeds = (items: AgentTrafficLiveIface[], ts: number) => {
  const speeds: Record<string, { down: number; up: number; kind?: string }> = {}
  const nextState: ExtraCounterState = { ...lastExtraCounters.value }

  for (const item of items) {
    const name = String(item?.name || '').trim()
    if (!name) continue
    const kind = item?.kind || 'vpn'
    const rxBytes = Number(item?.rxBytes || 0)
    const txBytes = Number(item?.txBytes || 0)
    const prev = lastExtraCounters.value[name]
    let down = 0
    let up = 0
    if (prev && ts > prev.ts) {
      const dtSec = Math.max((ts - prev.ts) / 1000, 1)
      down = Math.max(rxBytes - prev.rxBytes, 0) / dtSec
      up = Math.max(txBytes - prev.txBytes, 0) / dtSec
    }
    speeds[name] = { down, up, kind }
    nextState[name] = { rxBytes, txBytes, ts, kind }
    ensureExtraHistory(name, kind)
  }

  lastExtraCounters.value = nextState
  return speeds
}

const pollTraffic = async () => {
  const timestamp = Date.now()
  const mihomoDown = Math.max(0, Number(downloadSpeed.value || 0))
  const mihomoUp = Math.max(0, Number(uploadSpeed.value || 0))

  let routerDown = 0
  let routerUp = 0
  let extraSpeeds: Record<string, { down: number; up: number; kind?: string }> = {}

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
      if (Array.isArray(live.extraIfaces) && live.extraIfaces.length) {
        extraSpeeds = computeExtraSpeeds(live.extraIfaces, ts)
      }
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

  for (const name of extraInterfaceKeys.value) {
    const hist = extraHistories.value[name]
    if (!hist) continue
    const current = extraSpeeds[name]
    pushHistory({ value: hist.down }, timestamp, current?.down || 0)
    hist.down = hist.down.slice(-1 * timeSaved)
    pushHistory({ value: hist.up }, timestamp, current?.up || 0)
    hist.up = hist.up.slice(-1 * timeSaved)
    if (current?.kind) hist.kind = current.kind
  }

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

  refreshLanHosts()
  scheduleHostRefresh()
  refreshHostTraffic()
  scheduleHostTrafficRefresh()
  pollTraffic()

  watch(activeConnections, refreshHostTraffic, { deep: true })
})

onBeforeUnmount(() => {
  stopPolling()
  if (hostsTimer !== null) {
    window.clearTimeout(hostsTimer)
    hostsTimer = null
  }
  if (hostTrafficTimer !== null) {
    window.clearTimeout(hostTrafficTimer)
    hostTrafficTimer = null
  }
})
</script>
