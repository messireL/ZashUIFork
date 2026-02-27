<template>
  <div :class="twMerge('relative h-[32rem] w-full overflow-hidden')" @mousemove.stop @touchmove.stop>
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
import { prettyBytesHelper } from '@/helper/utils'
import { activeConnections } from '@/store/connections'
import { proxyProviederList } from '@/store/proxies'
import {
  blurIntensity,
  dashboardTransparent,
  font,
  proxiesRelationshipColorMode,
  proxiesRelationshipTopN,
  proxiesRelationshipWeightMode,
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
import { useI18n } from 'vue-i18n'

echarts.use([SankeyChart, TooltipComponent, CanvasRenderer])

const { t } = useI18n()

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

const { width, height } = useElementSize(chart)
const labelFontSize = computed(() => {
  const w = Number(width.value) || 0
  return isFullScreen.value ? 16 : w >= 1100 ? 15 : w >= 800 ? 14 : 13
})

const labelWidth = computed(() => {
  const w = (isFullScreen.value ? window.innerWidth : Number(width.value)) || 0
  const col = w > 0 ? w / 4 : 260
  // не даём label'ам разваливать лейаут, но и не делаем их слишком узкими
  return Math.round(Math.max(160, Math.min(560, col - (isFullScreen.value ? 72 : 56))))
})

const normalize = (s: string) => (s || '').trim() || '-'

const stageOf = (name: string) => {
  const i = name.indexOf(':')
  return i >= 0 ? name.slice(0, i) : ''
}

const labelOf = (name: string) => {
  const i = name.indexOf(':')
  return i >= 0 ? name.slice(i + 1) : name
}

const shortLabel = (name: string) => {
  const v = labelOf(name)
  if (!v) return ''
  const max = isFullScreen.value ? 56 : 40
  return v.length > max ? `${v.slice(0, max - 1)}…` : v
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

const providerMap = computed(() => {
  const m = new Map<string, string>()
  for (const p of proxyProviederList.value) {
    for (const proxy of p.proxies || []) {
      m.set(proxy.name, p.name)
    }
  }
  return m
})

const providerOf = (name: string) => providerMap.value.get(name) || ''

const colorFromKey = (key: string) => {
  const s = key || 'unknown'
  let h = 0
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0
  return `hsl(${h % 360} 70% 55%)`
}

// ----- snapshot (обновляемся каждые 5 секунд, без кнопок паузы/рефреша) -----
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
  timer = window.setInterval(refreshSnapshot, 5000)
}

type LinkAgg = { value: number; bytes: number; count: number; colorVotes: Record<string, number> }

type NodeMeta = { bytes: number; count: number; provider?: string }

const sankeyData = computed(() => {
  const conns = snapshot.value || []

  const topClientsN = Math.max(10, Number(proxiesRelationshipTopN.value) || 40)
  const topRulesN = Math.max(10, Math.floor(topClientsN * 1.5))
  const topGroupsN = Math.max(10, Math.floor(topClientsN * 1.2))
  const topServersN = topGroupsN

  const bytes = (c: Connection) => (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  const hasSpeed = conns.some((c) => bytes(c) > 0)

  const weight = (c: Connection) => {
    if (proxiesRelationshipWeightMode.value === 'count') return 1
    if (!hasSpeed) return 1
    return Math.min(1 + Math.log1p(bytes(c)) / 3, 18)
  }

  const fmtRule = (c: Connection) => {
    const rt = normalize((c as any).rule)
    const rp = String((c as any).rulePayload || '').trim()
    return rp ? `${rt}: ${normalize(rp)}` : rt
  }

  const colorKeyOf = (rawRule: string, group: string, server: string, c: Connection) => {
    const cm = proxiesRelationshipColorMode.value
    if (cm === 'none') return ''
    if (cm === 'rule') return normalize((c as any).rule) || rawRule
    if (cm === 'provider') return providerOf(server) || providerOf(group) || group || server
    // default: by real final hop (proxy) / group
    return server || group || rawRule
  }

  const getGroupServer = (c: Connection) => {
    const arr = (c.chains || []).map(normalize).filter((x) => x && x !== '-')
    const group = arr[0] || 'DIRECT'
    const server = arr[arr.length - 1] || group
    return { group, server }
  }

  const totalsClients = new Map<string, number>()
  const totalsRules = new Map<string, number>()
  const totalsGroups = new Map<string, number>()
  const totalsServers = new Map<string, number>()

  for (const c of conns) {
    const ip = c.metadata?.sourceIP || ''
    if (!ip) continue
    const v = weight(c)

    totalsClients.set(ip, (totalsClients.get(ip) || 0) + v)

    const r = fmtRule(c)
    totalsRules.set(r, (totalsRules.get(r) || 0) + v)

    const { group, server } = getGroupServer(c)
    totalsGroups.set(group, (totalsGroups.get(group) || 0) + v)
    totalsServers.set(server, (totalsServers.get(server) || 0) + v)
  }

  const topClients = new Set(
    Array.from(totalsClients.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topClientsN)
      .map(([k]) => k),
  )

  const topRules = new Set(
    Array.from(totalsRules.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topRulesN)
      .map(([k]) => k),
  )

  const topGroups = new Set(
    Array.from(totalsGroups.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topGroupsN)
      .map(([k]) => k),
  )

  const topServers = new Set(
    Array.from(totalsServers.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topServersN)
      .map(([k]) => k),
  )

  const OTHER = t('other')
  const OTHER_CLIENT = `${OTHER}`
  const OTHER_RULE = `${OTHER} (${t('rule')})`
  const OTHER_GROUP = `${OTHER} (${t('proxyGroup')})`
  const OTHER_SERVER = `${OTHER} (${t('proxies')})`

  const node = (stage: 'C' | 'R' | 'G' | 'S', label: string) => `${stage}:${label}`

  const linkAgg = new Map<string, LinkAgg>()
  const nodeMeta = new Map<string, NodeMeta>()

  const addNodeMeta = (name: string, b: number, cnt: number) => {
    const cur = nodeMeta.get(name) || { bytes: 0, count: 0 }
    cur.bytes += b
    cur.count += cnt

    if (!cur.provider && stageOf(name) === 'S') {
      const p = providerOf(labelOf(name))
      if (p) cur.provider = p
    }

    nodeMeta.set(name, cur)
  }

  const voteColor = (agg: LinkAgg, key: string, v: number) => {
    if (!key) return
    agg.colorVotes[key] = (agg.colorVotes[key] || 0) + v
  }

  const add = (s: string, tname: string, c: Connection, colorKey: string) => {
    const b = bytes(c)
    const v = weight(c)
    const key = `${s}\u0000${tname}`
    const agg = linkAgg.get(key) || { value: 0, bytes: 0, count: 0, colorVotes: {} }

    agg.value += v
    agg.bytes += b
    agg.count += 1

    // Окраска потоков — единая по всему пути, по выбранному ключу (по умолчанию: реальный финальный хоп).
    voteColor(agg, colorKey, v)

    linkAgg.set(key, agg)
    addNodeMeta(s, b, 1)
    addNodeMeta(tname, b, 1)
  }

  for (const c of conns) {
    const ip0 = c.metadata?.sourceIP || ''
    if (!ip0) continue

    const lbl = labelForIp(ip0)
    const clientLabel = topClients.has(ip0) ? (lbl ? `${lbl} (${ip0})` : ip0) : OTHER_CLIENT

    const rawRule = fmtRule(c)
    const ruleLabel = topRules.has(rawRule) ? rawRule : OTHER_RULE

    const { group: rawGroup, server: rawServer } = getGroupServer(c)
    const groupLabel = topGroups.has(rawGroup) ? rawGroup : OTHER_GROUP
    const serverLabel = topServers.has(rawServer) ? rawServer : OTHER_SERVER

    const colorKey = colorKeyOf(rawRule, rawGroup, rawServer, c)

    const C = node('C', clientLabel)
    const R = node('R', ruleLabel)
    const G = node('G', groupLabel)
    const S = node('S', serverLabel)

    add(C, R, c, colorKey)
    add(R, G, c, colorKey)
    add(G, S, c, colorKey)
  }

  const nodesSet = new Set<string>()
  const links = Array.from(linkAgg.entries()).map(([k, a]) => {
    const [source, target] = k.split('\u0000')
    nodesSet.add(source)
    nodesSet.add(target)

    let color = colorSet.baseContent30
    if (proxiesRelationshipColorMode.value !== 'none') {
      const entries = Object.entries(a.colorVotes)
      if (entries.length) {
        entries.sort((x, y) => y[1] - x[1])
        color = colorFromKey(entries[0][0])
      }
    }

    return {
      source,
      target,
      value: a.value,
      bytes: a.bytes,
      count: a.count,
      lineStyle: { color, opacity: 0.55 },
    }
  })

  const stageOrder: Record<string, number> = { C: 0, R: 1, G: 2, S: 3 }
  const nodes = Array.from(nodesSet)
    .sort((a, b) => {
      const sa = stageOrder[stageOf(a)] ?? 9
      const sb = stageOrder[stageOf(b)] ?? 9
      if (sa !== sb) return sa - sb
      return labelOf(a).localeCompare(labelOf(b))
    })
    .map((name) => ({ name }))

  return { nodes, links, nodeMeta }
})

const tooltipFormatter = (p: any) => {
  if (p?.dataType === 'edge') {
    const d = p.data || {}
    const cnt = Number(d.count) || 0
    const b = Number(d.bytes) || 0

    return `
      <div style="max-width: 560px">
        <div style="font-weight:600">${shortLabel(d.source)} → ${shortLabel(d.target)}</div>
        <div>${t('count')}: <b>${cnt}</b></div>
        <div>${t('traffic')}: <b>${prettyBytesHelper(b)}</b></div>
      </div>
    `
  }

  const name = p?.name || ''
  const meta = sankeyData.value.nodeMeta.get(name)
  const provider = meta?.provider ? ` (${t('provider')}: ${meta.provider})` : ''
  const cnt = meta?.count || 0
  const b = meta?.bytes || 0

  return `
    <div style="max-width: 560px">
      <div style="font-weight:600">${shortLabel(name)}${provider}</div>
      <div>${t('count')}: <b>${cnt}</b></div>
      <div>${t('traffic')}: <b>${prettyBytesHelper(b)}</b></div>
    </div>
  `
}

const options = computed(() => ({
  animation: true,
  animationDuration: 250,
  animationDurationUpdate: 550,
  animationEasingUpdate: 'cubicOut',
  tooltip: {
    trigger: 'item',
    triggerOn: 'mousemove',
    formatter: tooltipFormatter,
    backgroundColor: colorSet.base70,
    borderColor: colorSet.base70,
    confine: true,
    padding: [6, 8],
    textStyle: { color: colorSet.baseContent, fontFamily, fontSize: Math.max(12, labelFontSize.value) },
  },
  graphic: (() => {
    // небольшие заголовки колонок, чтобы диаграмма читалась "клиент → правило → группа → сервер"
    const w = (isFullScreen.value ? window.innerWidth : Number(width.value)) || 0
    if (!w) return []
    const top = 6
    const left = 12
    const col = w / 4
    const fontSize = Math.max(12, Math.min(14, labelFontSize.value))
    const mk = (i: number, text: string) => ({
      type: 'text',
      left: Math.round(left + col * i),
      top,
      style: {
        text,
        fill: colorSet.baseContent,
        font: `600 ${fontSize}px ${fontFamily}`,
        opacity: 0.65,
      },
      silent: true,
    })
    return [
      mk(0, t('proxiesRelationshipClients')),
      mk(1, t('rule')),
      mk(2, t('proxyGroup')),
      mk(3, t('proxies')),
    ]
  })(),
  series: [
    {
      id: 'sankey-client-rule-group-server',
      type: 'sankey',
      left: 8,
      right: 8,
      top: 28,
      bottom: 8,
      data: sankeyData.value.nodes,
      links: sankeyData.value.links,
      nodeAlign: 'justify',
      nodeWidth: isFullScreen.value ? 12 : 10,
      nodeGap: isFullScreen.value ? 12 : 10,
      emphasis: { focus: 'adjacency' },
      lineStyle: { curveness: 0.52, opacity: 0.55 },
      label: {
        color: colorSet.baseContent,
        fontFamily,
        fontSize: labelFontSize.value,
        overflow: 'truncate',
        width: labelWidth.value,
        formatter: (pp: any) => shortLabel(pp?.name || ''),
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
  startTimer()

  watch(theme, updateColorSet)
  watch(font, updateFontFamily)

  mainChart = echarts.init(chart.value)
  mainChart.setOption(options.value as any)

  watch(options, () => render(false))

  watch(isFullScreen, async (v) => {
    if (v) {
      await nextTick()
      if (!fsChart) fsChart = echarts.init(fullScreenChart.value)
      fsChart.resize()
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
  watch([width, height], resize)
})

onBeforeUnmount(() => {
  stopTimer()
  mainChart?.dispose()
  fsChart?.dispose()
  mainChart = null
  fsChart = null
})
</script>
