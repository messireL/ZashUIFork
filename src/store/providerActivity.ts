import { computed, ref, watch } from 'vue'
import { proxyProviederList } from '@/store/proxies'
import { activeConnections } from '@/store/connections'
import { debounce, throttle } from 'lodash'

export type ProviderActivity = {
  /** Number of active connections currently attributed to this provider. */
  connections: number
  /** Whether the provider is currently active in routing/traffic. */
  active: boolean
  /** Accumulated traffic observed for this provider since manual reset. */
  bytes: number
  speed: number
  activeProxy: string
  activeProxyBytes: number
  /** Sum of currently active connection counters for this provider. */
  currentBytes: number
  /** Since reset totals split by direction. */
  download: number
  upload: number
  /** Since start of current day totals split by direction. */
  todayBytes: number
  todayDownload: number
  todayUpload: number
  updatedAt?: number
}

export type ProviderLiveStatus = {
  connections: number
  active: boolean
}

type ProviderTrafficTotals = {
  dl: number
  ul: number
  updatedAt?: number
}

type DailyTrafficStore = {
  day: string
  totals: Record<string, ProviderTrafficTotals>
}

const STORAGE_KEY = 'stats/provider-traffic-session-v2'
const DAILY_STORAGE_KEY = 'stats/provider-traffic-daily-v1'
const trafficTotals = ref<Record<string, ProviderTrafficTotals>>({})
const dailyTrafficTotals = ref<Record<string, ProviderTrafficTotals>>({})
const connTotals = new Map<string, { provider: string; dl: number; ul: number }>()
const providerActivityCurrent = ref<Record<string, ProviderActivity>>({})

const todayKey = () => new Date().toISOString().slice(0, 10)

const safeParse = <T>(raw: string | null, fallback: T): T => {
  if (!raw) return fallback
  try {
    const parsed = JSON.parse(raw)
    return (parsed && typeof parsed === 'object' ? parsed : fallback) as T
  } catch {
    return fallback
  }
}

const loadTrafficTotals = () => {
  if (typeof localStorage === 'undefined') return
  trafficTotals.value = safeParse<Record<string, ProviderTrafficTotals>>(localStorage.getItem(STORAGE_KEY), {})
}

const loadDailyTrafficTotals = () => {
  if (typeof localStorage === 'undefined') return
  const day = todayKey()
  const parsed = safeParse<DailyTrafficStore>(localStorage.getItem(DAILY_STORAGE_KEY), { day, totals: {} })
  if (parsed.day !== day) {
    dailyTrafficTotals.value = {}
    return
  }
  dailyTrafficTotals.value = parsed.totals || {}
}

const saveTrafficTotals = debounce(() => {
  if (typeof localStorage === 'undefined') return
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(trafficTotals.value || {}))
  } catch {
    // ignore
  }
}, 1500)

const saveDailyTrafficTotals = debounce(() => {
  if (typeof localStorage === 'undefined') return
  try {
    const payload: DailyTrafficStore = { day: todayKey(), totals: dailyTrafficTotals.value || {} }
    localStorage.setItem(DAILY_STORAGE_KEY, JSON.stringify(payload))
  } catch {
    // ignore
  }
}, 1500)

loadTrafficTotals()
loadDailyTrafficTotals()

const emptyActivity = (): ProviderActivity => ({
  connections: 0,
  active: false,
  bytes: 0,
  speed: 0,
  activeProxy: '',
  activeProxyBytes: 0,
  currentBytes: 0,
  download: 0,
  upload: 0,
  todayBytes: 0,
  todayDownload: 0,
  todayUpload: 0,
  updatedAt: undefined,
})

export const providerProxyNames = (provider: any): string[] => {
  const raw = provider?.proxies
  const items = Array.isArray(raw) ? raw : raw && typeof raw === 'object' ? Object.values(raw) : []
  return (items as any[])
    .map((node: any) => (typeof node === 'string' ? node : node?.name))
    .map((name: any) => String(name || '').trim())
    .filter(Boolean)
}

export const connectionProxyCandidates = (conn: any): string[] => {
  const candidates: string[] = []
  const specialProxy = String(conn?.metadata?.specialProxy || '').trim()
  if (specialProxy) candidates.push(specialProxy)
  const chains = Array.isArray(conn?.chains) ? conn.chains : []
  for (let i = chains.length - 1; i >= 0; i--) {
    const name = String(chains[i] || '').trim()
    if (name) candidates.push(name)
  }
  const out: string[] = []
  const seen = new Set<string>()
  for (const name of candidates) {
    if (!name || seen.has(name)) continue
    seen.add(name)
    out.push(name)
  }
  return out
}

export const connectionMatchesProviderProxyNames = (conn: any, proxyNames: Iterable<string>): string => {
  const set = proxyNames instanceof Set ? proxyNames : new Set(Array.from(proxyNames || []))
  for (const proxyName of connectionProxyCandidates(conn)) {
    if (set.has(proxyName)) return proxyName
  }
  return ''
}

const resolveProviderFromConnection = (
  conn: any,
  proxyToProvider: Record<string, string>,
): { providerName: string; proxyName: string } => {
  for (const proxyName of connectionProxyCandidates(conn)) {
    const providerName = proxyToProvider[proxyName]
    if (providerName) return { providerName, proxyName }
  }
  return { providerName: '', proxyName: '' }
}

watch(
  [activeConnections, proxyProviederList],
  ([list, providers]) => {
    if (todayKey() !== safeParse<DailyTrafficStore>(typeof localStorage === 'undefined' ? null : localStorage.getItem(DAILY_STORAGE_KEY), { day: todayKey(), totals: {} }).day) {
      dailyTrafficTotals.value = {}
      saveDailyTrafficTotals()
    }

    const now = Date.now()
    const proxyToProvider: Record<string, string> = {}
    const current: Record<string, ProviderActivity> = {}

    for (const p of providers || []) {
      const providerName = String((p as any)?.name || '').trim()
      if (!providerName) continue
      current[providerName] = emptyActivity()
      for (const proxyName of providerProxyNames(p as any)) {
        if (!proxyName) continue
        if (!(proxyName in proxyToProvider)) proxyToProvider[proxyName] = providerName
      }
    }

    const perProxyBytes: Record<string, number> = {}
    const seen = new Set<string>()

    for (const c of list || []) {
      const id = String((c as any)?.id || '').trim()
      if (!id) continue
      seen.add(id)

      const { providerName, proxyName } = resolveProviderFromConnection(c as any, proxyToProvider)
      if (!providerName) continue

      const rec = current[providerName] || (current[providerName] = emptyActivity())
      const curDl = Number((c as any)?.download ?? 0) || 0
      const curUl = Number((c as any)?.upload ?? 0) || 0
      const curSpeed = (Number((c as any)?.downloadSpeed ?? 0) || 0) + (Number((c as any)?.uploadSpeed ?? 0) || 0)
      const curBytes = curDl + curUl

      rec.connections += 1
      rec.currentBytes += curBytes
      rec.speed += curSpeed
      rec.active = true

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

        const daily = dailyTrafficTotals.value[providerName] || { dl: 0, ul: 0 }
        daily.dl += dDl
        daily.ul += dUl
        daily.updatedAt = now
        dailyTrafficTotals.value[providerName] = daily
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

    for (const [providerName, totals] of Object.entries(dailyTrafficTotals.value || {})) {
      const rec = current[providerName] || (current[providerName] = emptyActivity())
      rec.todayDownload = Number(totals?.dl ?? 0) || 0
      rec.todayUpload = Number(totals?.ul ?? 0) || 0
      rec.todayBytes = rec.todayDownload + rec.todayUpload
      rec.updatedAt = Math.max(Number(rec.updatedAt || 0), Number(totals?.updatedAt ?? 0) || 0) || undefined
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
    saveTrafficTotals()
    saveDailyTrafficTotals()
  },
  { immediate: true, deep: false },
)

export const providerActivityByName = computed<Record<string, ProviderActivity>>(() => providerActivityCurrent.value || {})

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

export const providerLiveStatusByName = computed<Record<string, ProviderLiveStatus>>(() => {
  const out: Record<string, ProviderLiveStatus> = {}
  const list = activeConnections.value || []
  for (const provider of proxyProviederList.value || []) {
    const providerName = String((provider as any)?.name || '').trim()
    if (!providerName) continue
    const names = new Set(providerProxyNames(provider as any))
    if (!names.size) {
      out[providerName] = { connections: 0, active: false }
      continue
    }
    let connections = 0
    for (const c of list) {
      if (connectionMatchesProviderProxyNames(c as any, names)) connections += 1
    }
    out[providerName] = { connections, active: connections > 0 }
  }
  return out
})

export const clearProviderTrafficSession = () => {
  trafficTotals.value = {}
  connTotals.clear()
  providerActivityCurrent.value = {}
  if (typeof localStorage !== 'undefined') {
    try {
      localStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }
}
