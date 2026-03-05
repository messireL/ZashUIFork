import { agentMihomoProvidersAPI, agentSslProbeBatchAPI } from '@/api/agent'
import { useStorage } from '@vueuse/core'
import { computed, ref, watch } from 'vue'
import { agentEnabled } from './agent'
import { proxyProviderPanelUrlMap } from './settings'

export const autoSortProxyProvidersByHealth = useStorage<boolean>(
  'config/auto-sort-proxy-providers-by-health',
  true,
)

/** Provider list sort mode on the Providers tab. */
export const proxyProvidersSortMode = useStorage<'health' | 'activity' | 'name'>(
  'config/proxy-providers-sort-mode',
  'health',
)

/** Show only providers that currently have active connections (best-effort). */
export const showOnlyActiveProxyProviders = useStorage<boolean>(
  'config/show-only-active-proxy-providers',
  false,
)

/** Optional quick filter for providers tab: expired | nearExpiry | offline | degraded | healthy */
export const providerHealthFilter = useStorage<string>('config/provider-health-filter', '')

export const agentProvidersLoading = ref(false)
export const agentProvidersOk = ref(false)
export const agentProvidersError = ref<string | null>(null)
export const agentProvidersAt = ref<number>(0)
export const agentProviders = ref<any[]>([])

// SSL probe results for provider management panel URLs (name -> notAfter string).
export const panelSslNotAfterByName = ref<Record<string, string>>({})
export const panelSslCheckedAt = ref<number>(0)
export const panelSslProbeError = ref<string | null>(null)
export const panelSslProbeLoading = ref(false)

export const agentProviderByName = computed<Record<string, any>>(() => {
  const map: Record<string, any> = {}
  for (const p of agentProviders.value || []) {
    if (p?.name) map[String(p.name)] = p
  }
  return map
})

export const fetchAgentProviders = async (force = false) => {
  if (!agentEnabled.value) {
    agentProvidersOk.value = false
    agentProvidersError.value = null
    agentProviders.value = []
    agentProvidersAt.value = Date.now()
    return
  }

  if (agentProvidersLoading.value) return

  agentProvidersLoading.value = true
  try {
    const res = await agentMihomoProvidersAPI(force)
    agentProvidersOk.value = !!res?.ok
    agentProvidersError.value = res?.ok ? null : res?.error || 'offline'
    agentProviders.value = (res as any)?.providers || []
    agentProvidersAt.value = Date.now()
  } finally {
    agentProvidersLoading.value = false
  }
}

const buildProbeLines = (): string => {
  const map = proxyProviderPanelUrlMap.value || {}
  const lines: string[] = []
  for (const [name, url] of Object.entries(map)) {
    const n = String(name || '').trim()
    const u = String(url || '').trim()
    if (!n || !u) continue
    // We probe only https/wss. Other schemes will return empty anyway.
    lines.push(`${n}\t${u}`)
  }
  return lines.join('\n') + (lines.length ? '\n' : '')
}

export const probePanelSsl = async (force = false) => {
  if (!agentEnabled.value) {
    panelSslNotAfterByName.value = {}
    panelSslCheckedAt.value = Date.now()
    panelSslProbeError.value = null
    return
  }
  if (panelSslProbeLoading.value) return

  // basic TTL: avoid spamming openssl probes
  const ttlMs = 60_000
  if (!force && panelSslCheckedAt.value && Date.now() - panelSslCheckedAt.value < ttlMs) return

  const payload = buildProbeLines()
  if (!payload) {
    panelSslNotAfterByName.value = {}
    panelSslCheckedAt.value = Date.now()
    panelSslProbeError.value = null
    return
  }

  panelSslProbeLoading.value = true
  panelSslProbeError.value = null
  try {
    const res: any = await agentSslProbeBatchAPI(payload)
    if (!res?.ok) {
      panelSslProbeError.value = res?.error || 'failed'
      return
    }
    const out: Record<string, string> = {}
    for (const it of (res?.items || []) as any[]) {
      const name = String(it?.name || '').trim()
      if (!name) continue
      const na = String(it?.sslNotAfter || '').trim()
      if (na) out[name] = na
    }
    panelSslNotAfterByName.value = out
    panelSslCheckedAt.value = typeof res?.checkedAtSec === 'number' && res.checkedAtSec > 0 ? res.checkedAtSec * 1000 : Date.now()
  } catch (e: any) {
    panelSslProbeError.value = e?.message || 'failed'
  } finally {
    panelSslProbeLoading.value = false
  }
}

// best-effort: refresh when agent toggled
watch(
  agentEnabled,
  (on) => {
    if (on) {
      fetchAgentProviders(false)
      probePanelSsl(false)
    }
  },
  { immediate: true },
)

// Refresh SSL probes when panel URL map changes (debounced).
let probeTimer: any = null
watch(
  proxyProviderPanelUrlMap,
  () => {
    if (!agentEnabled.value) return
    if (probeTimer) clearTimeout(probeTimer)
    probeTimer = setTimeout(() => probePanelSsl(true), 600)
  },
  { deep: true },
)
