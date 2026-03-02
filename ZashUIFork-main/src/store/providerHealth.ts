import { agentMihomoProvidersAPI } from '@/api/agent'
import { useStorage } from '@vueuse/core'
import { computed, ref, watch } from 'vue'
import { agentEnabled } from './agent'

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

// best-effort: refresh when agent toggled
watch(
  agentEnabled,
  (on) => {
    if (on) fetchAgentProviders(false)
  },
  { immediate: true },
)
