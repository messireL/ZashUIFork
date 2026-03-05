<script setup lang="ts">
import { getProviderHealth } from '@/helper/providerHealth'
import { normalizeProxyProtoKey, protoLabel } from '@/helper/proxyProto'
import { PROXY_TAB_TYPE } from '@/constant'
import { proxiesTabShow, proxyGroupList, proxyMap, proxyProviederList } from '@/store/proxies'
import { providerActivityByName } from '@/store/providerActivity'
import { hideUnusedProxyProviders, hiddenProxyProviderProtoKeys, proxyProviderSslWarnDaysMap, sslNearExpiryDaysDefault } from '@/store/settings'
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
  proxyProvidersProtoFilter,
} from '@/store/providerHealth'
import dayjs from 'dayjs'
import { computed, watch } from 'vue'

const usedProxyNames = computed(() => {
  const set = new Set<string>()
  for (const g of proxyGroupList.value) {
    for (const n of proxyMap.value[g]?.all || []) set.add(n)
  }
  return set
})

const isUsed = (provider: any) => {
  if (usedProxyNames.value.has(provider.name)) return true
  return (provider.proxies || []).some((p: any) => {
    const name = typeof p === 'string' ? p : p?.name
    return name ? usedProxyNames.value.has(name) : false
  })
}

const allProviders = computed(() => proxyProviederList.value || [])

const providersAfterHideUnused = computed(() => {
  let list = allProviders.value || []
  if (hideUnusedProxyProviders.value) {
    list = list.filter((p) => isUsed(p))
  }
  return list
})

const providers = computed(() => {
  let list = providersAfterHideUnused.value || []

  if (showOnlyActiveProxyProviders.value) {
    list = list.filter((p) => {
      const act = (providerActivityByName.value || {})[p.name]
      const conns = Number((act as any)?.connections ?? 0)
      return conns > 0
    })
  }

  return list
})

const hiddenUnusedCount = computed(() => {
  if (!hideUnusedProxyProviders.value) return 0
  return Math.max(0, (allProviders.value.length || 0) - (providersAfterHideUnused.value.length || 0))
})

const counts = computed(() => {
  const c = { total: 0, expired: 0, nearExpiry: 0, offline: 0, degraded: 0, healthy: 0 }
  for (const p of providers.value) {
    c.total++
    const override = Number((proxyProviderSslWarnDaysMap.value || {})[p.name])
    const base = Number(sslNearExpiryDaysDefault.value)
    const nearDays = Number.isFinite(override) ? override : Number.isFinite(base) ? base : 2
    const h = getProviderHealth(p as any, agentProviderByName.value[p.name], { nearExpiryDays: nearDays })
    ;(c as any)[h.status]++
  }
  return c
})

const protoTabs = computed(() => {
  const m = new Map<string, number>()

  for (const p of providers.value || []) {
    const seen = new Set<string>()
    for (const n of ((p as any)?.proxies || []) as any[]) {
      const t0 = typeof n === 'string' ? (proxyMap.value[n]?.type as any) : (n as any)?.type
      const k = normalizeProxyProtoKey(t0)
      if (k) seen.add(k)
    }
    for (const k of seen) {
      m.set(k, (m.get(k) || 0) + 1)
    }
  }

  const arr = Array.from(m.entries()).map(([key, count]) => ({
    key,
    label: protoLabel(key),
    count,
  }))
  arr.sort((a, b) => (b.count - a.count) || a.key.localeCompare(b.key))

  const out: any[] = [{ key: 'all', label: '', count: providers.value.length }]
  out.push(...arr)
  return out
})


const hiddenProtoSet = computed(() => {
  const raw = hiddenProxyProviderProtoKeys.value || []
  const out = new Set<string>()
  for (const k of raw as any[]) {
    const kk = normalizeProxyProtoKey(String(k || ''))
    if (kk && kk !== 'all') out.add(kk)
  }
  return out
})

const protoTabsVisible = computed(() => {
  const hidden = hiddenProtoSet.value
  const tabs = protoTabs.value || []
  return (tabs as any[]).filter((t) => String((t as any)?.key) === 'all' || !hidden.has(String((t as any)?.key)))
})

const manageableProtoTabs = computed(() => {
  return (protoTabs.value || []).filter((t: any) => String(t?.key) !== 'all')
})

const toggleProtoHidden = (k0: string) => {
  const k = normalizeProxyProtoKey(String(k0 || ''))
  if (!k || k === 'all') return

  const cur = Array.isArray(hiddenProxyProviderProtoKeys.value) ? [...hiddenProxyProviderProtoKeys.value] : []
  const set = new Set<string>()
  for (const x of cur as any[]) {
    const kk = normalizeProxyProtoKey(String(x || ''))
    if (kk && kk !== 'all') set.add(kk)
  }

  if (set.has(k)) set.delete(k)
  else set.add(k)

  hiddenProxyProviderProtoKeys.value = Array.from(set).sort((a, b) => a.localeCompare(b))
}

const setProto = (k: string) => {
  proxyProvidersProtoFilter.value = k || 'all'
}

watch(
  protoTabsVisible,
  (tabs) => {
    const keys = new Set((tabs || []).map((t: any) => String(t.key)))
    const cur = String(proxyProvidersProtoFilter.value || 'all')
    if (!keys.has(cur)) proxyProvidersProtoFilter.value = 'all'
  },
  { immediate: true },
)
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
      <div v-if="protoTabs.length > 1" class="flex w-full flex-wrap items-center gap-2" data-proto-tabs>
        <div class="tabs tabs-boxed tabs-sm">
          <a
            v-for="t2 in protoTabsVisible"
            :key="t2.key"
            class="tab"
            :class="proxyProvidersProtoFilter === t2.key ? 'tab-active' : ''"
            @click="setProto(t2.key)"
            :title="t2.key === 'all' ? $t('all') : (t2.label + ': ' + t2.count)"
          >
            <template v-if="t2.key === 'all'">{{ $t('all') }}</template>
            <template v-else>{{ t2.label }} ({{ t2.count }})</template>
          </a>
        </div>

        <div class="text-[11px] opacity-60">{{ $t('providerProtoTip') }}</div>

        <div v-if="manageableProtoTabs.length" class="ml-auto">
          <details class="dropdown dropdown-end">
            <summary
              class="btn btn-ghost btn-xs"
              @click.stop
              :title="$t('providerProtoManage')"
            >
              ⚙
            </summary>
            <div class="dropdown-content z-[999] mt-2 w-64 rounded-box bg-base-200 p-2 shadow ring-1 ring-base-300">
              <div class="text-xs font-medium mb-1">{{ $t('providerProtoManage') }}</div>
              <div class="text-[11px] opacity-70 mb-2">{{ $t('providerProtoTip') }}</div>
              <div class="max-h-64 overflow-auto">
                <div
                  v-for="t2 in manageableProtoTabs"
                  :key="t2.key"
                  class="flex items-center gap-2 rounded-lg px-2 py-1 hover:bg-base-300/40"
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    :checked="!hiddenProtoSet.has(String(t2.key))"
                    @change="toggleProtoHidden(String(t2.key))"
                  />
                  <div class="text-sm">{{ t2.label }}</div>
                  <div class="ml-auto text-[11px] opacity-70">{{ t2.count }}</div>
                </div>
                <div v-if="!manageableProtoTabs.length" class="text-xs opacity-60 px-2 py-1">{{ $t('noData') }}</div>
              </div>
            </div>
          </details>
        </div>
      </div>

      <div class="w-full"></div>
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
          :class="hideUnusedProxyProviders ? '' : 'badge-outline'"
          @click="hideUnusedProxyProviders = !hideUnusedProxyProviders"
          :title="$t('providerHideUnusedTip')"
        >
          {{ $t('providerHideUnused') }}
          <template v-if="hiddenUnusedCount > 0">
            • {{ $t('providerHiddenCount', { n: hiddenUnusedCount }) }}
          </template>
        </button>

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
