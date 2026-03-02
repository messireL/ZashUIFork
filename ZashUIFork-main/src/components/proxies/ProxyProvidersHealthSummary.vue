<script setup lang="ts">
import { getProviderHealth } from '@/helper/providerHealth'
import { PROXY_TAB_TYPE } from '@/constant'
import { proxiesTabShow, proxyGroupList, proxyMap, proxyProviederList } from '@/store/proxies'
import { providerActivityByName } from '@/store/providerActivity'
import { hideUnusedProxyProviders } from '@/store/settings'
import {
  agentProviderByName,
  agentProvidersAt,
  agentProvidersError,
  agentProvidersLoading,
  agentProvidersOk,
  fetchAgentProviders,
  providerHealthFilter,
  proxyProvidersSortMode,
  showOnlyActiveProxyProviders,
} from '@/store/providerHealth'
import dayjs from 'dayjs'
import { computed } from 'vue'

const usedProxyNames = computed(() => {
  const set = new Set<string>()
  for (const g of proxyGroupList.value) {
    for (const n of proxyMap.value[g]?.all || []) set.add(n)
  }
  return set
})

const isUsed = (provider: any) => {
  if (usedProxyNames.value.has(provider.name)) return true
  return (provider.proxies || []).some((p: any) => usedProxyNames.value.has(p.name))
}

const providers = computed(() => {
  return proxyProviederList.value.filter((p) => !hideUnusedProxyProviders.value || isUsed(p))
})

const counts = computed(() => {
  const c = { total: 0, expired: 0, nearExpiry: 0, offline: 0, degraded: 0, healthy: 0 }
  for (const p of providers.value) {
    c.total++
    const h = getProviderHealth(p as any, agentProviderByName.value[p.name])
    ;(c as any)[h.status]++
  }
  return c
})

const activeProvidersCount = computed(() => {
  let n = 0
  for (const p of providers.value || []) {
    if ((providerActivityByName.value[p.name]?.connections || 0) > 0) n += 1
  }
  return n
})

const lastAgentUpdate = computed(() => {
  if (!agentProvidersAt.value) return ''
  return dayjs(agentProvidersAt.value).format('HH:mm:ss')
})

const setFilter = (v: string) => {
  providerHealthFilter.value = providerHealthFilter.value === v ? '' : v
}

const refresh = async () => {
  await fetchAgentProviders(true)
}

const show = computed(() => proxiesTabShow.value === PROXY_TAB_TYPE.PROVIDER)
</script>

<template>
  <div
    v-if="show"
    class="sticky top-0 z-20 pb-2"
  >
    <div
      class="flex flex-wrap items-center gap-2 rounded-xl bg-base-200/90 px-3 py-2 ring-1 ring-base-300 backdrop-blur"
    >
      <div class="font-medium">
        {{ $t('providerHealth') }}
      </div>

      <div class="flex flex-wrap items-center gap-1">
        <button
          class="badge badge-neutral cursor-pointer"
          :class="providerHealthFilter === '' ? 'badge-outline' : ''"
          @click="setFilter('')"
          :title="$t('providerHealthAll')"
        >
          {{ $t('providerHealthAll') }}: {{ counts.total }}
        </button>
        <button
          class="badge badge-error cursor-pointer"
          :class="providerHealthFilter === 'expired' ? '' : 'badge-outline'"
          @click="setFilter('expired')"
        >
          {{ $t('providerHealthExpired') }}: {{ counts.expired }}
        </button>
        <button
          class="badge badge-warning cursor-pointer"
          :class="providerHealthFilter === 'nearExpiry' ? '' : 'badge-outline'"
          @click="setFilter('nearExpiry')"
        >
          {{ $t('providerHealthNearExpiry') }}: {{ counts.nearExpiry }}
        </button>
        <button
          class="badge badge-error cursor-pointer"
          :class="providerHealthFilter === 'offline' ? '' : 'badge-outline'"
          @click="setFilter('offline')"
        >
          {{ $t('providerHealthOffline') }}: {{ counts.offline }}
        </button>
        <button
          class="badge badge-warning cursor-pointer"
          :class="providerHealthFilter === 'degraded' ? '' : 'badge-outline'"
          @click="setFilter('degraded')"
        >
          {{ $t('providerHealthDegraded') }}: {{ counts.degraded }}
        </button>
        <button
          class="badge badge-success cursor-pointer"
          :class="providerHealthFilter === 'healthy' ? '' : 'badge-outline'"
          @click="setFilter('healthy')"
        >
          {{ $t('providerHealthHealthy') }}: {{ counts.healthy }}
        </button>
      </div>

      <div class="ml-auto flex items-center gap-2">
        <button
          class="badge badge-neutral cursor-pointer"
          :class="showOnlyActiveProxyProviders ? '' : 'badge-outline'"
          @click="showOnlyActiveProxyProviders = !showOnlyActiveProxyProviders"
          :title="$t('providerOnlyActiveTip')"
        >
          {{ $t('providerOnlyActive') }}: {{ activeProvidersCount }}
        </button>

        <select
          class="select select-bordered select-xs"
          v-model="proxyProvidersSortMode"
          :title="$t('sortBy')"
        >
          <option value="health">{{ $t('providerSortHealth') }}</option>
          <option value="activity">{{ $t('providerSortActivity') }}</option>
          <option value="name">{{ $t('providerSortName') }}</option>
        </select>
        <div
          v-if="agentProvidersOk"
          class="text-xs opacity-70"
          :title="$t('lastCheck')"
        >
          {{ $t('updated') }} {{ lastAgentUpdate }}
        </div>
        <div
          v-else-if="agentProvidersError"
          class="text-xs text-warning"
          :title="agentProvidersError"
        >
          {{ $t('providerHealthAgentOffline') }}
        </div>
        <button
          class="btn btn-ghost btn-xs"
          @click="refresh"
          :disabled="agentProvidersLoading"
        >
          <span
            v-if="agentProvidersLoading"
            class="loading loading-spinner loading-xs"
          ></span>
          <span v-else>
            {{ $t('refresh') }}
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
