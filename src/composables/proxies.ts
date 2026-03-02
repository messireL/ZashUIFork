import { isSingBox } from '@/api'
import { GLOBAL, PROXY_TAB_TYPE } from '@/constant'
import { isHiddenGroup } from '@/helper'
import { getProviderHealth } from '@/helper/providerHealth'
import { configs } from '@/store/config'
import { providerActivityByName, providerActivitySnapshot } from '@/store/providerActivity'
import { proxiesTabShow, proxyGroupList, proxyMap, proxyProviederList } from '@/store/proxies'
import { customGlobalNode, displayGlobalByMode, hideUnusedProxyProviders, manageHiddenGroup } from '@/store/settings'
import {
  agentProviderByName,
  autoSortProxyProvidersByHealth,
  providerHealthFilter,
  proxyProvidersSortMode,
  showOnlyActiveProxyProviders,
} from '@/store/providerHealth'
import { isEmpty } from 'lodash'
import { computed } from 'vue'

const filterGroups = (all: string[]) => {
  if (manageHiddenGroup.value) {
    return all
  }

  return all.filter((name) => !isHiddenGroup(name))
}

export const renderGroups = computed(() => {
  if (isEmpty(proxyMap.value)) {
    return []
  }

  if (proxiesTabShow.value === PROXY_TAB_TYPE.PROVIDER) {
    const usedProxyNames = new Set<string>()

    // Собираем все реальные прокси, которые входят хотя бы в одну группу.
    // Если провайдер не даёт ни одного прокси, попавшего в группы — считаем его неиспользуемым.
    for (const g of proxyGroupList.value) {
      for (const n of proxyMap.value[g]?.all || []) usedProxyNames.add(n)
    }

    const isUsed = (provider: any) => {
      if (usedProxyNames.has(provider.name)) return true
      return (provider.proxies || []).some((p: any) => usedProxyNames.has(p.name))
    }

    let list = proxyProviederList.value.filter((p) => !hideUnusedProxyProviders.value || isUsed(p))

    if (providerHealthFilter.value) {
      const target = providerHealthFilter.value
      list = list.filter((p: any) => {
        const h = getProviderHealth(p as any, agentProviderByName.value[p.name])
        return h.status === target
      })
    }

    // Optionally show only providers with active connections (best-effort).
    if (showOnlyActiveProxyProviders.value) {
      list = list.filter((p: any) => (providerActivityByName.value[p.name]?.connections || 0) > 0)
    }

    const mode = proxyProvidersSortMode.value || 'health'

    if (mode === 'activity') {
      list = [...list].sort((a: any, b: any) => {
        // Use throttled snapshot to avoid constant UI re-ordering.
        const aa = (providerActivitySnapshot.value as any)[a.name] || { bytes: 0, connections: 0 }
        const bb = (providerActivitySnapshot.value as any)[b.name] || { bytes: 0, connections: 0 }
        if (bb.bytes !== aa.bytes) return bb.bytes - aa.bytes
        if (bb.connections !== aa.connections) return bb.connections - aa.connections
        return String(a.name).localeCompare(String(b.name))
      })
    } else if (mode === 'name') {
      list = [...list].sort((a: any, b: any) => String(a.name).localeCompare(String(b.name)))
    } else {
      // mode === 'health'
      if (autoSortProxyProvidersByHealth.value) {
        list = [...list].sort((a: any, b: any) => {
          const ha = getProviderHealth(a as any, agentProviderByName.value[a.name])
          const hb = getProviderHealth(b as any, agentProviderByName.value[b.name])
          if (ha.severity !== hb.severity) return ha.severity - hb.severity
          return String(a.name).localeCompare(String(b.name))
        })
      } else {
        list = [...list].sort((a: any, b: any) => String(a.name).localeCompare(String(b.name)))
      }
    }

    return list.map((p) => p.name)
  }

  if (displayGlobalByMode.value) {
    if (configs.value?.mode.toUpperCase() === GLOBAL) {
      return [
        isSingBox.value && proxyMap.value[customGlobalNode.value] ? customGlobalNode.value : GLOBAL,
      ]
    }

    return filterGroups(proxyGroupList.value)
  }

  return filterGroups([...proxyGroupList.value, GLOBAL])
})
