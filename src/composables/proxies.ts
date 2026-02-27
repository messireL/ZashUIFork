import { isSingBox } from '@/api'
import { GLOBAL, PROXY_TAB_TYPE } from '@/constant'
import { isHiddenGroup } from '@/helper'
import { configs } from '@/store/config'
import { proxiesTabShow, proxyGroupList, proxyMap, proxyProviederList } from '@/store/proxies'
import { customGlobalNode, displayGlobalByMode, hideUnusedProxyProviders, manageHiddenGroup } from '@/store/settings'
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
    for (const n of proxyMap.value[GLOBAL]?.all || []) usedProxyNames.add(n)

    const isUsed = (provider: any) => {
      if (usedProxyNames.has(provider.name)) return true
      return (provider.proxies || []).some((p: any) => usedProxyNames.has(p.name))
    }

    return proxyProviederList.value
      .filter((p) => !hideUnusedProxyProviders.value || isUsed(p))
      .map((p) => p.name)
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
