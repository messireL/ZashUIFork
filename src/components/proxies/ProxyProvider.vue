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

const subscriptionInfo = computed(() => {
  const info = proxyProvider.value.subscriptionInfo

  if (info) {
    const getNum = (obj: any, ...keys: string[]) => {
      for (const k of keys) {
        if (obj?.[k] !== undefined && obj?.[k] !== null) return Number(obj[k]) || 0
      }
      return 0
    }

    const Download = getNum(info, 'Download', 'download')
    const Upload = getNum(info, 'Upload', 'upload')
    const Total = getNum(info, 'Total', 'total')
    const Expire = getNum(info, 'Expire', 'expire')

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
