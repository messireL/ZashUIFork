import { computed, ref, watch } from 'vue'
import { proxyProviederList } from '@/store/proxies'
import { activeConnections } from '@/store/connections'
import { throttle } from 'lodash'

export type ProviderActivity = {
  connections: number
  bytes: number
  speed: number
  activeProxy: string
  activeProxyBytes: number
}

/**
 * Best-effort provider activity map inferred from active connections.
 * Uses the leaf hop (chains[-1]) as the real proxy.
 */
export const providerActivityByName = computed<Record<string, ProviderActivity>>(() => {
  const out: Record<string, ProviderActivity> = {}

  // proxyName -> providerName
  const proxyToProvider: Record<string, string> = {}

  for (const p of proxyProviederList.value || []) {
    const name = String((p as any)?.name || '')
    if (!name) continue
    if (!out[name]) {
      out[name] = { connections: 0, bytes: 0, speed: 0, activeProxy: '', activeProxyBytes: 0 }
    }
    for (const n of (p as any)?.proxies || []) {
      const proxyName = String(n?.name || '')
      if (proxyName) proxyToProvider[proxyName] = name
    }
  }

  // Aggregate bytes per proxy to find the most-used proxy per provider.
  const perProxyBytes: Record<string, number> = {}

  for (const c of activeConnections.value || []) {
    const chains = (c as any)?.chains
    if (!Array.isArray(chains) || chains.length === 0) continue
    const leaf = String(chains[chains.length - 1] || '')
    if (!leaf) continue

    const providerName = proxyToProvider[leaf]
    if (!providerName) continue

    const rec = out[providerName] || (out[providerName] = { connections: 0, bytes: 0, speed: 0, activeProxy: '', activeProxyBytes: 0 })
    rec.connections += 1

    const dl = Number((c as any)?.download) || 0
    const ul = Number((c as any)?.upload) || 0
    const dls = Number((c as any)?.downloadSpeed) || 0
    const uls = Number((c as any)?.uploadSpeed) || 0

    const total = dl + ul
    rec.bytes += total
    rec.speed += dls + uls

    const key = `${providerName}|${leaf}`
    perProxyBytes[key] = (perProxyBytes[key] || 0) + total
  }

  for (const k of Object.keys(perProxyBytes)) {
    const i = k.indexOf('|')
    if (i < 0) continue
    const providerName = k.slice(0, i)
    const proxyName = k.slice(i + 1)
    const b = perProxyBytes[k] || 0

    const rec = out[providerName]
    if (!rec) continue
    if (b > rec.activeProxyBytes) {
      rec.activeProxyBytes = b
      rec.activeProxy = proxyName
    }
  }

  return out
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
