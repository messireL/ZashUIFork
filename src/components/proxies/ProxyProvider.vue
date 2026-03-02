<template>
  <CollapseCard :name="proxyProvider.name">
    <template v-slot:title="{ open }">
      <div class="flex items-center justify-between gap-2 rounded-xl px-2 py-1" :class="open ? 'bg-base-200 ring-1 ring-base-300' : ''">
        <div class="text-xl font-medium">
          {{ proxyProvider.name }}
          <span
            v-if="providerHealth"
            class="badge badge-sm ml-2 align-middle"
            :class="providerHealth.badgeCls"
            :title="providerHealth.tip"
          >
            {{ $t(providerHealth.labelKey) }}
          </span>
          <span class="text-base-content/60 text-sm font-normal"> ({{ proxiesCount }}) </span>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            :class="twMerge('btn btn-circle btn-sm z-30')"
            @click.stop.prevent="healthCheckClickHandler"
          >
            <span
              v-if="isHealthChecking"
              class="loading loading-spinner loading-xs"
            ></span>
            <BoltIcon
              v-else
              class="h-4 w-4"
            />
          </button>
          <button
            type="button"
            v-if="proxyProvider.vehicleType !== 'Inline'"
            :class="twMerge('btn btn-circle btn-sm z-30', isUpdating ? 'animate-spin' : '')"
            @click.stop.prevent="updateProviderClickHandler"
          >
            <ArrowPathIcon class="h-4 w-4" />
          </button>
        </div>
      </div>
      <div
        class="text-base-content/60 flex items-end justify-between text-sm max-sm:flex-col max-sm:items-start"
      >
        <div class="min-h-10">
          <div v-if="subscriptionInfo">
            {{ subscriptionInfo.expireStr }}
          </div>
          <div v-if="subscriptionInfo" class="flex items-center gap-2">
            <span>{{ subscriptionInfo.usageStr }}</span>
            <button
              v-if="subscriptionInfo.totalLabel === '—'"
              type="button"
              class="btn btn-ghost btn-xs"
              @click.stop="showRawSub = !showRawSub"
              :title="'subscriptionInfo'"
            >
              raw
            </button>
          </div>
          <progress
            v-if="subscriptionInfo.percent !== null"
            class="progress progress-info w-full max-w-72"
            :value="subscriptionInfo.percent"
            max="100"
          ></progress>

          <div v-if="sslExpireInfo" class="mt-1 text-xs" :class="sslExpireInfo.cls">
            {{ $t('sslExpire') }}: {{ sslExpireInfo.label }}
          </div>

          <!-- Shared management panel URL (synced via router-agent users DB) -->
          <div v-if="open" class="mt-2 flex flex-wrap items-center gap-2 text-xs">
            <span class="opacity-70">{{ $t('providerPanelUrl') }}:</span>
            <input
              class="input input-bordered input-xs w-72 max-w-full"
              v-model="panelUrlDraft"
              :placeholder="$t('providerPanelUrlPlaceholder')"
              @keydown.enter.stop.prevent="savePanelUrl"
              @blur="savePanelUrl"
            />
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              :disabled="!panelUrl"
              @click.stop="openPanelUrl"
              :title="$t('openPanel')"
            >
              <ArrowTopRightOnSquareIcon class="h-4 w-4" />
            </button>
          </div>

          <pre
            v-if="subscriptionInfo.totalLabel === '—' && showRawSub"
            class="mt-2 text-xs opacity-70 whitespace-pre-wrap break-all"
          >{{ subscriptionInfo.raw }}</pre>

          <div
            v-if="providerStats.connections > 0 || providerStats.bytes > 0"
            class="mt-1 text-xs opacity-70"
          >
            {{ $t('connections') }}: {{ providerStats.connections }}
            · {{ $t('proxies') }}: {{ proxiesCount }}
            · {{ $t('traffic') }}: {{ prettyBytesHelper(providerStats.bytes, { binary: true }) }}
            <template v-if="providerStats.speed > 0">
              ({{ prettyBytesHelper(providerStats.speed, { binary: true }) }}/s)
            </template>
          </div>
        </div>
        <div class="flex flex-col items-end gap-1 max-sm:items-start">
          <div v-if="open" class="flex flex-wrap items-center gap-1.5 text-xs">
            <span class="opacity-70">{{ activeProxy ? $t('activeProxy') : $t('bestLatencyProxy') }}:</span>
            <span
              class="font-mono truncate max-w-[18rem]"
              :class="activeProxy ? '' : 'opacity-70'"
              :title="displayProxyName || ''"
            >
              {{ displayProxyName || '—' }}
            </span>

            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              @click.stop="copyActiveName"
              :disabled="!displayProxyName"
              :title="$t('copyProxyName')"
            >
              <ClipboardDocumentIcon class="h-4 w-4" />
            </button>

            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              @click.stop="testActiveNode"
              :disabled="isActiveTesting || !displayProxyName"
              :title="$t('testProxyLatency')"
            >
              <span
                v-if="isActiveTesting"
                class="loading loading-spinner loading-xs"
              ></span>
              <BoltIcon v-else class="h-4 w-4" />
            </button>

            <button
              v-if="activeProxyUri"
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              @click.stop="copyActiveUri"
              :title="$t('copyProxyUri')"
            >
              <LinkIcon class="h-4 w-4" />
            </button>

            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              @click.stop="openTopologyWithProvider"
              :title="$t('showInTopology')"
            >
              <PresentationChartLineIcon class="h-4 w-4" />
            </button>

            <button
              v-if="panelUrl"
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              @click.stop="openPanelUrl"
              :title="$t('openPanel')"
            >
              <ArrowTopRightOnSquareIcon class="h-4 w-4" />
            </button>
          </div>
          <div>{{ $t('updated') }} {{ fromNow(proxyProvider.updatedAt) }}</div>
        </div>
      </div>
    </template>
    <template v-slot:preview>
      <div class="flex flex-col gap-2">
        <ProxyPreview
          :nodes="renderProxies"
          :now="displayProxyName"
          :group-name="proxyProvider.name"
          :enable-topology-filter="true"
          @nodefilter="openTopologyWithProxy"
        />

        <div class="flex flex-wrap items-center gap-1.5 text-xs">
          <span class="opacity-70">{{ activeProxy ? $t('activeProxy') : $t('bestLatencyProxy') }}:</span>
          <span
            class="font-mono truncate max-w-[18rem]"
            :class="activeProxy ? '' : 'opacity-70'"
            :title="displayProxyName || ''"
          >
            {{ displayProxyName || '—' }}
          </span>

          <button
            type="button"
            class="btn btn-ghost btn-xs btn-circle"
            @click.stop="copyActiveName"
            :disabled="!displayProxyName"
            :title="$t('copyProxyName')"
          >
            <ClipboardDocumentIcon class="h-4 w-4" />
          </button>

          <button
            type="button"
            class="btn btn-ghost btn-xs btn-circle"
            @click.stop="testActiveNode"
            :disabled="isActiveTesting || !displayProxyName"
            :title="$t('testProxyLatency')"
          >
            <span
              v-if="isActiveTesting"
              class="loading loading-spinner loading-xs"
            ></span>
            <BoltIcon
              v-else
              class="h-4 w-4"
            />
          </button>

          <button
            v-if="activeProxyUri"
            type="button"
            class="btn btn-ghost btn-xs btn-circle"
            @click.stop="copyActiveUri"
            :title="$t('copyProxyUri')"
          >
            <LinkIcon class="h-4 w-4" />
          </button>

          <button
            type="button"
            class="btn btn-ghost btn-xs btn-circle"
            @click.stop="openTopologyWithProvider"
            :title="$t('showInTopology')"
          >
            <PresentationChartLineIcon class="h-4 w-4" />
          </button>

          <button
            v-if="panelUrl"
            type="button"
            class="btn btn-ghost btn-xs btn-circle"
            @click.stop="openPanelUrl"
            :title="$t('openPanel')"
          >
            <ArrowTopRightOnSquareIcon class="h-4 w-4" />
          </button>
        </div>
      </div>
    </template>
    <template v-slot:content="{ showFullContent }">
      <ProxyNodeGrid>
        <ProxyNodeCard
          v-for="node in showFullContent
            ? renderProxies
            : renderProxies.slice(0, twoColumnProxyGroup ? 48 : 96)"
          :key="node"
          :name="node"
          :group-name="name"
        />
      </ProxyNodeGrid>
    </template>
  </CollapseCard>
</template>

<script setup lang="ts">
import { proxyProviderHealthCheckAPI, updateProxyProviderAPI } from '@/api'
import { getProviderHealth } from '@/helper/providerHealth'
import { agentProviderByName, fetchAgentProviders } from '@/store/providerHealth'
import { useBounceOnVisible } from '@/composables/bouncein'
import { useRenderProxies } from '@/composables/renderProxies'
import { fromNow, prettyBytesHelper } from '@/helper/utils'
import { showNotification } from '@/helper/notification'
import { fetchProxyProviderByNameOnly, getTestUrl, proxyLatencyTest, proxyMap, proxyProviederList } from '@/store/proxies'
import { activeConnections } from '@/store/connections'
import { NOT_CONNECTED, ROUTE_NAME } from '@/constant'
import { proxyProviderPanelUrlMap, twoColumnProxyGroup } from '@/store/settings'
import { ArrowPathIcon, ArrowTopRightOnSquareIcon, BoltIcon, ClipboardDocumentIcon, LinkIcon, PresentationChartLineIcon } from '@heroicons/vue/24/outline'
import dayjs from 'dayjs'
import { twMerge } from 'tailwind-merge'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import CollapseCard from '../common/CollapseCard.vue'
import ProxyNodeCard from './ProxyNodeCard.vue'
import ProxyNodeGrid from './ProxyNodeGrid.vue'
import ProxyPreview from './ProxyPreview.vue'

const props = defineProps<{
  name: string
}>()

const router = useRouter()

const proxyProvider = computed(
  () => proxyProviederList.value.find((group) => group.name === props.name)!,
)
const allProxies = computed(() => proxyProvider.value.proxies.map((node) => node.name) ?? [])
const { renderProxies, proxiesCount } = useRenderProxies(allProxies)

// best-effort: ensure cache is populated when provider cards mount
fetchAgentProviders(false)

const providerHealth = computed(() => {
  const ap = agentProviderByName.value[props.name]
  return getProviderHealth(proxyProvider.value as any, ap)
})

const providerStats = computed(() => {
  const set = new Set(allProxies.value || [])
  let connections = 0
  let bytes = 0
  let speed = 0

  for (const c of activeConnections.value || []) {
    const proxy = (c as any)?.chains?.[0]
    if (!proxy || !set.has(proxy)) continue
    connections++
    bytes += (Number((c as any).download) || 0) + (Number((c as any).upload) || 0)
    speed += (Number((c as any).downloadSpeed) || 0) + (Number((c as any).uploadSpeed) || 0)
  }

  return { connections, bytes, speed }
})

// Highlight the "currently used" proxy inside this provider.
// Best-effort: infer from active connections (leaf hop with max traffic).
const activeProxy = computed(() => {
  const set = new Set(allProxies.value || [])
  let bestName = ''
  let bestTotal = 0

  for (const c of activeConnections.value || []) {
    const chains = (c as any)?.chains
    if (!Array.isArray(chains) || !chains.length) continue
    const leaf = chains[chains.length - 1]
    if (!leaf || !set.has(leaf)) continue

    const total = (Number((c as any)?.download) || 0) + (Number((c as any)?.upload) || 0)
    if (total > bestTotal) {
      bestTotal = total
      bestName = leaf
    }
  }

  return bestName
})

// Fallback: if there are no active connections, show the best (lowest) latency proxy.
const bestLatencyProxy = computed(() => {
  let best = ''
  let bestLatency = Number.POSITIVE_INFINITY

  for (const name of renderProxies.value || []) {
    const l = getLatencyByName(name, proxyProvider.value?.name)
    if (l === NOT_CONNECTED) continue
    if (typeof l !== 'number' || !Number.isFinite(l) || l <= 0) continue
    if (l < bestLatency) {
      bestLatency = l
      best = name
    }
  }

  return best
})

const displayProxyName = computed(() => {
  return activeProxy.value || bestLatencyProxy.value || ''
})

// ---- shared provider management panel URL ----

const panelUrl = computed(() => {
  const m = proxyProviderPanelUrlMap.value || {}
  return String((m as any)[props.name] || '').trim()
})

const panelUrlDraft = ref(panelUrl.value)
watch(panelUrl, (v) => {
  // keep draft in sync when updated by sync engine
  if (panelUrlDraft.value !== v) panelUrlDraft.value = v
})

const savePanelUrl = () => {
  const raw = String(panelUrlDraft.value || '').trim()
  const normalized = raw && !/^https?:\/\//i.test(raw) ? `https://${raw}` : raw

  const cur = { ...(proxyProviderPanelUrlMap.value || {}) }
  if (!normalized) {
    delete (cur as any)[props.name]
  } else {
    ;(cur as any)[props.name] = normalized
  }
  proxyProviderPanelUrlMap.value = cur
}

const openPanelUrl = () => {
  const url = panelUrl.value
  if (!url) return
  try {
    window.open(url, '_blank', 'noopener,noreferrer')
  } catch {
    // ignore
  }
}

const TOPOLOGY_NAV_FILTER_KEY = 'runtime/topology-pending-filter-v1'

const openTopologyWithProxy = async (p: { name: string; mode: 'only' | 'exclude' }) => {
  const payload = {
    ts: Date.now(),
    mode: p.mode,
    focus: { stage: 'S', kind: 'value', value: p.name },
  }

  try {
    localStorage.setItem(TOPOLOGY_NAV_FILTER_KEY, JSON.stringify(payload))
  } catch {
    // ignore
  }

  await router.push({ name: ROUTE_NAME.overview })
}

const openTopologyWithProvider = async () => {
  const payload = {
    ts: Date.now(),
    mode: 'only',
    focus: { stage: 'P', kind: 'value', value: proxyProvider.value?.name || props.name },
    // Fallback to a concrete proxy name if provider map is not yet ready on the Topology page.
    fallbackProxyName: displayProxyName.value || '',
  }

  try {
    localStorage.setItem(TOPOLOGY_NAV_FILTER_KEY, JSON.stringify(payload))
  } catch {
    // ignore
  }

  await router.push({ name: ROUTE_NAME.overview })
}

const getAnyFromObj = (obj: any, candidates: string[]): any => {
  if (!obj || typeof obj !== 'object') return undefined
  const keys = Object.keys(obj)

  // exact match (case-insensitive)
  for (const c of candidates) {
    const k = keys.find((x) => x.toLowerCase() === c.toLowerCase())
    if (k) {
      const v = (obj as any)[k]
      if (v !== undefined && v !== null && `${v}`.trim() !== '') return v
    }
  }

  // contains match (case-insensitive)
  for (const c of candidates) {
    const lc = c.toLowerCase()
    const k = keys.find((x) => x.toLowerCase().includes(lc))
    if (k) {
      const v = (obj as any)[k]
      if (v !== undefined && v !== null && `${v}`.trim() !== '') return v
    }
  }

  return undefined
}

const parseDateMaybe = (v: any): dayjs.Dayjs | null => {
  if (v === null || v === undefined) return null
  if (typeof v === 'number' && Number.isFinite(v)) {
    const ts = v > 10_000_000_000 ? v : v * 1000
    const d = dayjs(ts)
    return d.isValid() ? d : null
  }
  if (typeof v === 'string') {
    const s = v.trim()
    if (!s) return null
    if (/^[0-9]{10,13}$/.test(s)) {
      const num = Number(s)
      return parseDateMaybe(num)
    }
    const d = dayjs(s)
    return d.isValid() ? d : null
  }
  if (typeof v === 'object') {
    // common shapes: { expire: ... }
    const inner = getAnyFromObj(v, ['expire', 'expiry', 'expiration', 'notAfter', 'not_after'])
    return parseDateMaybe(inner)
  }
  return null
}

const sslExpireInfo = computed(() => {
  const p: any = proxyProvider.value as any
  const info: any = (proxyProvider.value as any).subscriptionInfo

  const raw =
    getAnyFromObj(p, [
      'sslExpire',
      'ssl_expire',
      'sslExpiration',
      'ssl_expiration',
      'certExpire',
      'cert_expire',
      'tlsExpire',
      'tls_expire',
      'certificateExpire',
      'certificate_expire',
      'certNotAfter',
    ]) ||
    getAnyFromObj(info, [
      'sslExpire',
      'ssl_expire',
      'sslExpiration',
      'ssl_expiration',
      'certExpire',
      'cert_expire',
      'tlsExpire',
      'tls_expire',
      'certificateExpire',
      'certificate_expire',
      'certNotAfter',
    ])

  const raw2: any = raw || agentProviderByName.value[props.name]?.sslNotAfter

  const d = parseDateMaybe(raw2)
  if (!d) return null

  const days = d.diff(dayjs(), 'day')
  const dateTime = d.format('DD-MM-YYYY HH:mm:ss')

  const cls = days < 0 ? 'text-error' : days <= 14 ? 'text-warning' : 'text-success'
  const label = days < 0 ? `${dateTime} (expired)` : `${dateTime} (${days}d)`

  return { dateTime, days, cls, label }
})

const subscriptionInfo = computed(() => {
  const info: any = (proxyProvider.value as any).subscriptionInfo
  if (!info) return null

  const parseBytes = (v: any): number => {
    if (v === null || v === undefined) return 0
    if (typeof v === 'number') return Number.isFinite(v) ? v : 0

    if (typeof v === 'string') {
      const s0 = v.trim()
      if (!s0) return 0

      // Some backends may pass userinfo fragments like: "total=123; download=..."
      const kv = s0.match(/\b(?:total|download|upload)\s*=\s*([0-9]+(?:\.[0-9]+)?)(?:\s*([kmgtpe]?i?b?)\b)?/i)
      if (kv) {
        const num = Number(kv[1])
        const unit = (kv[2] || '').toUpperCase()
        const pow10: Record<string, number> = { K: 1, M: 2, G: 3, T: 4, P: 5, E: 6 }
        const base = unit.includes('I') ? 1024 : 1000
        const letter = unit.replace('IB', '').replace('B', '')
        const p = pow10[letter] || 0
        return num * Math.pow(base, p)
      }

      // plain number string
      if (/^[0-9]+(\.[0-9]+)?$/.test(s0)) return Number(s0) || 0

      // "<num><unit>" or "<num> <unit>"
      const m = s0.match(/^\s*([0-9]+(?:\.[0-9]+)?)\s*([kmgtpe]?i?b?)\s*$/i)
      if (m) {
        const num = Number(m[1])
        const unit = (m[2] || '').toUpperCase()
        const pow10: Record<string, number> = { K: 1, M: 2, G: 3, T: 4, P: 5, E: 6 }
        const base = unit.includes('I') ? 1024 : 1000
        const letter = unit.replace('IB', '').replace('B', '')
        const p = pow10[letter] || 0
        return num * Math.pow(base, p)
      }

      // Extract first "number+unit" anywhere
      const m2 = s0.match(/([0-9]+(?:\.[0-9]+)?)\s*([kmgtpe]?i?b?)\b/i)
      if (m2) {
        const num = Number(m2[1])
        const unit = (m2[2] || '').toUpperCase()
        const pow10: Record<string, number> = { K: 1, M: 2, G: 3, T: 4, P: 5, E: 6 }
        const base = unit.includes('I') ? 1024 : 1000
        const letter = unit.replace('IB', '').replace('B', '')
        const p = pow10[letter] || 0
        return num * Math.pow(base, p)
      }

      return Number(s0) || 0
    }

    return 0
  }

  const parseNumber = (v: any): number => {
    if (v === null || v === undefined) return 0
    if (typeof v === 'number') return Number.isFinite(v) ? v : 0
    if (typeof v === 'string') {
      const s = v.trim()
      const m = s.match(/-?[0-9]+/)
      return m ? Number(m[0]) || 0 : 0
    }
    return 0
  }

  const getAny = (obj: any, candidates: string[]): any => {
    if (!obj || typeof obj !== 'object') return undefined
    const keys = Object.keys(obj)

    // exact match (case-insensitive)
    for (const c of candidates) {
      const k = keys.find((x) => x.toLowerCase() === c.toLowerCase())
      if (k) {
        const v = (obj as any)[k]
        if (v !== undefined && v !== null && `${v}`.trim() !== '') return v
      }
    }

    // contains match (case-insensitive)
    for (const c of candidates) {
      const lc = c.toLowerCase()
      const k = keys.find((x) => x.toLowerCase().includes(lc))
      if (k) {
        const v = (obj as any)[k]
        if (v !== undefined && v !== null && `${v}`.trim() !== '') return v
      }
    }

    return undefined
  }

  const parseUserinfoString = (s: string) => {
    const read = (k: string) => {
      const m = s.match(new RegExp(`\\b${k}\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)`, 'i'))
      return m ? Number(m[1]) || 0 : 0
    }
    const download = read('download')
    const upload = read('upload')
    const total = read('total')
    const expire = read('expire')
    return { download, upload, total, expire }
  }

  const providerObj: any = proxyProvider.value as any

  const rawDownload = getAny(info, ['Download', 'download']) ?? getAny(providerObj, ['Download', 'download'])
  const rawUpload = getAny(info, ['Upload', 'upload']) ?? getAny(providerObj, ['Upload', 'upload'])
  const rawTotal = getAny(info, ['Total', 'total', 'quota', 'limit']) ?? getAny(providerObj, ['Total', 'total', 'quota', 'limit'])
  const rawExpire = getAny(info, ['Expire', 'expire', 'expiry', 'expiration']) ?? getAny(providerObj, ['Expire', 'expire', 'expiry', 'expiration'])

  let Download = parseBytes(rawDownload)
  let Upload = parseBytes(rawUpload)
  let Total = parseBytes(rawTotal)
  let Expire = parseNumber(rawExpire)

  // Fallback: scan any string field for "total=..."
  if (Total <= 0) {
    for (const v of Object.values(info)) {
      if (typeof v !== 'string') continue
      if (!/\btotal\s*=\s*/i.test(v)) continue
      const p = parseUserinfoString(v)
      if (p.total > 0) Total = p.total
      if (Download <= 0 && p.download > 0) Download = p.download
      if (Upload <= 0 && p.upload > 0) Upload = p.upload
      if (Expire <= 0 && p.expire > 0) Expire = p.expire
    }
  }

  if (Download === 0 && Upload === 0 && Total === 0 && Expire === 0) return null

  const { t } = useI18n()
  const usedBytes = Download + Upload
  const used = prettyBytesHelper(usedBytes, { binary: true })

  const isUnlimited =
    (rawTotal === 0 || rawTotal === '0' || rawTotal === '0B' || rawTotal === '0b' || rawTotal === -1 || rawTotal === '-1') && usedBytes > 0

  const totalLabel = Total > 0 ? prettyBytesHelper(Total, { binary: true }) : isUnlimited ? '∞' : '—'
  const percentage = Total > 0 ? ((usedBytes / Total) * 100).toFixed(2) : ''
  const usageStr = percentage ? `${used} / ${totalLabel} ( ${percentage}% )` : `${used} / ${totalLabel}`

  const expireSec = Expire > 1e12 ? Math.floor(Expire / 1000) : Expire
  const expireStr =
    expireSec === 0
      ? `${t('expire')}: ${t('noExpire')}`
      : `${t('expire')}: ${dayjs(expireSec * 1000).format('YYYY-MM-DD')}`

  const percentNumber = Total > 0 ? (usedBytes / Total) * 100 : null

  return {
    expireStr,
    usageStr,
    percent: percentNumber,
    totalLabel,
    raw: JSON.stringify(info, null, 2),
  }
})


const showRawSub = ref(false)

const isUpdating = ref(false)
const isHealthChecking = ref(false)

const healthCheckClickHandler = async () => {
  if (isHealthChecking.value) return

  isHealthChecking.value = true
  try {
    await proxyProviderHealthCheckAPI(props.name)
    await fetchProxyProviderByNameOnly(props.name)
    isHealthChecking.value = false
  } catch {
    isHealthChecking.value = false
  }
}

const updateProviderClickHandler = async () => {
  if (isUpdating.value) return

  isUpdating.value = true
  try {
    await updateProxyProviderAPI(props.name)
    await fetchProxyProviderByNameOnly(props.name)
    isUpdating.value = false
  } catch {
    isUpdating.value = false
  }
}



// --- Quick actions for the currently used proxy inside this provider ---
const isActiveTesting = ref(false)

const activeProxyNode = computed(() => {
  const name = displayProxyName.value
  return name ? (proxyMap.value as any)?.[name] : null
})

const activeProxyUri = computed(() => {
  const node: any = activeProxyNode.value
  if (!node) return ''

  const candidates = ['uri', 'url', 'link', 'share', 'subscription', 'subscribe', 'proxyUrl']
  const v1 = getAnyFromObj(node, candidates)
  if (typeof v1 === 'string' && v1.includes('://')) return v1.trim()

  const v2 = getAnyFromObj(node?.extra, candidates)
  if (typeof v2 === 'string' && v2.includes('://')) return v2.trim()

  return ''
})

const copyText = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text)
    showNotification({ content: 'copySuccess', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  }
}

const copyActiveName = async () => {
  if (!displayProxyName.value) return
  await copyText(displayProxyName.value)
}

const copyActiveUri = async () => {
  if (!activeProxyUri.value) return
  await copyText(activeProxyUri.value)
}

const testActiveNode = async () => {
  if (!displayProxyName.value) return
  if (isActiveTesting.value) return

  isActiveTesting.value = true
  try {
    await proxyLatencyTest(displayProxyName.value, getTestUrl(proxyProvider.value?.name))
  } finally {
    isActiveTesting.value = false
  }
}

useBounceOnVisible()
</script>
