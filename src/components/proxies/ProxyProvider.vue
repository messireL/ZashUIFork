<template>
  <CollapseCard :name="proxyProvider.name">
    <template v-slot:title>
      <div class="flex items-center justify-between gap-2">
        <div class="text-xl font-medium">
          {{ proxyProvider.name }}
          <span class="text-base-content/60 text-sm font-normal"> ({{ proxiesCount }}) </span>
        </div>
        <div class="flex gap-2">
          <button
            :class="twMerge('btn btn-circle btn-sm z-30')"
            @click.stop="healthCheckClickHandler"
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
            v-if="proxyProvider.vehicleType !== 'Inline'"
            :class="twMerge('btn btn-circle btn-sm z-30', isUpdating ? 'animate-spin' : '')"
            @click.stop="updateProviderClickHandler"
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
          <div v-if="subscriptionInfo">
            {{ subscriptionInfo.usageStr }}
          </div>
          <progress
            v-if="subscriptionInfo.percent !== null"
            class="progress progress-info w-full max-w-72"
            :value="subscriptionInfo.percent"
            max="100"
          ></progress>

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
        <div>{{ $t('updated') }} {{ fromNow(proxyProvider.updatedAt) }}</div>
      </div>
    </template>
    <template v-slot:preview>
      <ProxyPreview :nodes="renderProxies" />
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
import { useBounceOnVisible } from '@/composables/bouncein'
import { useRenderProxies } from '@/composables/renderProxies'
import { fromNow, prettyBytesHelper } from '@/helper/utils'
import { fetchProxies, proxyProviederList } from '@/store/proxies'
import { activeConnections } from '@/store/connections'
import { twoColumnProxyGroup } from '@/store/settings'
import { ArrowPathIcon, BoltIcon } from '@heroicons/vue/24/outline'
import dayjs from 'dayjs'
import { twMerge } from 'tailwind-merge'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import CollapseCard from '../common/CollapseCard.vue'
import ProxyNodeCard from './ProxyNodeCard.vue'
import ProxyNodeGrid from './ProxyNodeGrid.vue'
import ProxyPreview from './ProxyPreview.vue'

const props = defineProps<{
  name: string
}>()

const proxyProvider = computed(
  () => proxyProviederList.value.find((group) => group.name === props.name)!,
)
const allProxies = computed(() => proxyProvider.value.proxies.map((node) => node.name) ?? [])
const { renderProxies, proxiesCount } = useRenderProxies(allProxies)

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

const subscriptionInfo = computed(() => {
  const info = proxyProvider.value.subscriptionInfo

  if (info) {
    const parseBytes = (v: any): number => {
      if (v === null || v === undefined) return 0
      if (typeof v === 'number') return Number.isFinite(v) ? v : 0
      if (typeof v === 'string') {
        const s = v.trim()
        if (!s) return 0
        // plain number string
        if (/^[0-9]+(\.[0-9]+)?$/.test(s)) return Number(s) || 0
        const m = s.match(/^\s*([0-9]+(?:\.[0-9]+)?)\s*([kmgtpe]?i?b?)\s*$/i)
        if (!m) return Number(s) || 0
        const num = Number(m[1])
        const unit = (m[2] || '').toUpperCase()
        const pow10 = { K: 1, M: 2, G: 3, T: 4, P: 5, E: 6 }
        const base = unit.includes('I') ? 1024 : 1000
        const letter = unit.replace('IB', '').replace('B', '')
        const p = (pow10 as any)[letter] || 0
        return num * Math.pow(base, p)
      }
      return 0
    }

    const getValCI = (obj: any, key: string) => {
      if (!obj) return undefined
      const direct = obj[key]
      if (direct !== undefined && direct !== null) return direct
      const k = Object.keys(obj).find((x) => x.toLowerCase() === key.toLowerCase())
      return k ? obj[k] : undefined
    }

    const Download = parseBytes(getValCI(info, 'Download'))
    const Upload = parseBytes(getValCI(info, 'Upload'))
    const Total = parseBytes(getValCI(info, 'Total'))
    const Expire = Number(getValCI(info, 'Expire')) || 0

    if (Download === 0 && Upload === 0 && Total === 0 && Expire === 0) {
      return null
    }

    const { t } = useI18n()
    const total = Total > 0 ? prettyBytesHelper(Total, { binary: true }) : '—'
    const used = prettyBytesHelper(Download + Upload, { binary: true })
    const percentage = Total > 0 ? (((Download + Upload) / Total) * 100).toFixed(2) : ''
    const expireSec = Expire > 1e12 ? Math.floor(Expire / 1000) : Expire
    const expireStr =
      expireSec === 0
        ? `${t('expire')}: ${t('noExpire')}`
        : `${t('expire')}: ${dayjs(expireSec * 1000).format('YYYY-MM-DD')}`

    const usageStr = percentage ? `${used} / ${total} ( ${percentage}% )` : `${used} / ${total}`

    const percentNumber = Total > 0 ? ((Download + Upload) / Total) * 100 : null

    return {
      expireStr,
      usageStr,
      percent: percentNumber,
    }
  }

  return null
})

const isUpdating = ref(false)
const isHealthChecking = ref(false)

const healthCheckClickHandler = async () => {
  if (isHealthChecking.value) return

  isHealthChecking.value = true
  try {
    await proxyProviderHealthCheckAPI(props.name)
    await fetchProxies()
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
    await fetchProxies()
    isUpdating.value = false
  } catch {
    isUpdating.value = false
  }
}

useBounceOnVisible()
</script>
