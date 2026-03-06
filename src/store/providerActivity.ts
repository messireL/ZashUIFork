import { computed, ref, watch } from 'vue'
import { proxyProviederList } from '@/store/proxies'
import { activeConnections } from '@/store/connections'
import { debounce, throttle } from 'lodash'

export type ProviderActivity = {
  connections: number
  /** Accumulated traffic observed for this provider during the current UI session. */
  bytes: number
  speed: number
  activeProxy: string
  activeProxyBytes: number
  /** Sum of currently active connection counters for this provider. */
  currentBytes: number
  /** Session totals split by direction. */
  download: number
  upload: number
  updatedAt?: number
}

type ProviderTrafficTotals = {
  dl: number
  ul: number
  updatedAt?: number
}

const STORAGE_KEY = 'stats/provider-traffic-session-v1'
const trafficTotals = ref<Record<string, ProviderTrafficTotals>>({})
const connTotals = new Map<string, { provider: string; dl: number; ul: number }>()
const providerActivityCurrent = ref<Record<string, ProviderActivity>>({})

const safeParse = (raw: string | null): Record<string, ProviderTrafficTotals> => {
  if (!raw) return {}
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

const load = () => {
  if (typeof localStorage === 'undefined') return
  trafficTotals.value = safeParse(localStorage.getItem(STORAGE_KEY))
}

const save = debounce(() => {
  if (typeof localStorage === 'undefined') return
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(trafficTotals.value || {}))
  } catch {
    // ignore
  }
}, 1500)

load()

const emptyActivity = (): ProviderActivity => ({
  connections: 0,
  bytes: 0,
  speed: 0,
  activeProxy: '',
  activeProxyBytes: 0,
  currentBytes: 0,
  download: 0,
  upload: 0,
  updatedAt: undefined,
})

const resolveProviderFromChains = (
  chains: unknown,
  proxyToProvider: Record<string, string>,
): { providerName: string; proxyName: string } => {
  if (!Array.isArray(chains) || chains.length === 0) return { providerName: '', proxyName: '' }

  for (let i = chains.length - 1; i >= 0; i--) {
    const proxyName = String(chains[i] || '').trim()
    if (!proxyName) continue
    const providerName = proxyToProvider[proxyName]
    if (providerName) return { providerName, proxyName }
  }

  return { providerName: '', proxyName: '' }
}

watch(
  [activeConnections, proxyProviederList],
  ([list, providers]) => {
    const now = Date.now()
    const proxyToProvider: Record<string, string> = {}
    const current: Record<string, ProviderActivity> = {}

    for (const p of providers || []) {
      const providerName = String((p as any)?.name || '').trim()
      if (!providerName) continue
      current[providerName] = emptyActivity()
      for (const node of ((p as any)?.proxies || []) as any[]) {
        const proxyName = typeof node === 'string'
          ? String(node || '').trim()
          : String((node as any)?.name || '').trim()
        if (proxyName) proxyToProvider[proxyName] = providerName
      }
    }

    const perProxyBytes: Record<string, number> = {}
    const seen = new Set<string>()

    for (const c of list || []) {
      const id = String((c as any)?.id || '').trim()
      if (!id) continue
      seen.add(id)

      const { providerName, proxyName } = resolveProviderFromChains((c as any)?.chains, proxyToProvider)
      if (!providerName) continue

      const rec = current[providerName] || (current[providerName] = emptyActivity())

      const curDl = Number((c as any)?.download ?? 0) || 0
      const curUl = Number((c as any)?.upload ?? 0) || 0
      const curSpeed = (Number((c as any)?.downloadSpeed ?? 0) || 0) + (Number((c as any)?.uploadSpeed ?? 0) || 0)
      const curBytes = curDl + curUl

      rec.connections += 1
      rec.currentBytes += curBytes
      rec.speed += curSpeed

      if (proxyName) {
        const key = `${providerName}|${proxyName}`
        perProxyBytes[key] = (perProxyBytes[key] || 0) + curBytes
      }

      const prev = connTotals.get(id)
      let dDl = curDl
      let dUl = curUl
      if (prev) {
        dDl = curDl - (prev.dl || 0)
        dUl = curUl - (prev.ul || 0)
      }
      if (!Number.isFinite(dDl) || dDl < 0) dDl = 0
      if (!Number.isFinite(dUl) || dUl < 0) dUl = 0

      if (dDl > 0 || dUl > 0) {
        const totals = trafficTotals.value[providerName] || { dl: 0, ul: 0 }
        totals.dl += dDl
        totals.ul += dUl
        totals.updatedAt = now
        trafficTotals.value[providerName] = totals
      }

      connTotals.set(id, { provider: providerName, dl: curDl, ul: curUl })
    }

    for (const id of Array.from(connTotals.keys())) {
      if (!seen.has(id)) connTotals.delete(id)
    }

    for (const [providerName, totals] of Object.entries(trafficTotals.value || {})) {
      const rec = current[providerName] || (current[providerName] = emptyActivity())
      rec.download = Number(totals?.dl ?? 0) || 0
      rec.upload = Number(totals?.ul ?? 0) || 0
      rec.bytes = rec.download + rec.upload
      rec.updatedAt = Number(totals?.updatedAt ?? 0) || undefined
    }

    for (const [key, value] of Object.entries(perProxyBytes)) {
      const idx = key.indexOf('|')
      if (idx < 0) continue
      const providerName = key.slice(0, idx)
      const proxyName = key.slice(idx + 1)
      const rec = current[providerName]
      if (!rec) continue
      if (value > rec.activeProxyBytes) {
        rec.activeProxyBytes = value
        rec.activeProxy = proxyName
      }
    }

    providerActivityCurrent.value = current
    save()
  },
  { immediate: true, deep: false },
)

/**
 * Best-effort provider activity map inferred from active connections.
 * `bytes` is the accumulated session traffic observed for the provider.
 */
export const providerActivityByName = computed<Record<string, ProviderActivity>>(() => {
  return providerActivityCurrent.value || {}
})

/**
 * Throttled snapshot used for sorting providers by activity.
 * Without this, the Providers tab can constantly re-order on every connections tick.
 */
export const providerActivitySnapshot = ref<Record<string, ProviderActivity>>({})

watch(
  providerActivityByName,
  throttle(
    (v) => {
      providerActivitySnapshot.value = v || {}
    },
    30_000,
    { leading: true, trailing: true },
  ),
  { immediate: true, deep: true },
)

export const clearProviderTrafficSession = () => {
  trafficTotals.value = {}
  connTotals.clear()
  providerActivityCurrent.value = {}
  if (typeof localStorage === 'undefined') return
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
}
