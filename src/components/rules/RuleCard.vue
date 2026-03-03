<template>
  <div
    class="card hover:bg-base-200 gap-2 p-2 text-sm"
    data-nav-kind="rule"
    :data-rule-type="rule.type"
    :data-rule-payload="String(rule.payload || '')"
  >
    <div class="flex items-start justify-between gap-2 min-h-5 leading-5">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="opacity-70">{{ index }}.</span>
          <span class="font-medium">{{ rule.type }}</span>
          <span
            v-if="rule.payload"
            class="text-main min-w-0 truncate"
            :title="String(rule.payload)"
          >
            {{ rule.payload }}
          </span>

          <span
            v-if="typeof size === 'number' && size !== -1"
            class="text-base-content/70 text-xs"
          >
            ({{ size }})
            <QuestionMarkCircleIcon
              v-if="size === 0"
              class="ml-1 inline-block h-4 w-4"
              @mouseenter="showMMDBSizeTip"
            />
          </span>
        </div>
      </div>

      <div class="flex items-center gap-1 shrink-0">
        <span class="badge badge-xs" :title="$t('ruleHitsTip')">
          {{ $t('hits') }}: {{ hits }}
        </span>

        <button
          v-if="isUpdateableRuleSet"
          :class="twMerge('btn btn-circle btn-ghost btn-xs', isUpdating ? 'animate-spin' : '')"
          @click="updateRuleProviderClickHandler"
          :title="$t('update')"
        >
          <ArrowPathIcon class="h-4 w-4" />
        </button>

        <!-- Topology: Only / Exclude this rule (stage: R) -->
        <div class="join">
          <button
            type="button"
            class="btn btn-ghost btn-xs join-item"
            :title="$t('topologyOnlyThis')"
            @click.stop="openTopologyWithRule('only')"
          >
            <FunnelIcon class="h-4 w-4" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs join-item"
            :title="$t('topologyExcludeThis')"
            @click.stop="openTopologyWithRule('exclude')"
          >
            <NoSymbolIcon class="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
    <div class="flex items-center gap-1">
      <ProxyName
        :name="rule.proxy"
        class="badge badge-sm gap-0"
      />
      <template v-if="proxyNode?.now && displayNowNodeInRule">
        <ArrowRightCircleIcon class="h-4 w-4" />
        <ProxyName
          :name="getNowProxyNodeName(rule.proxy)"
          class="badge badge-sm gap-0"
        />
      </template>
      <span
        v-if="latency !== NOT_CONNECTED && displayLatencyInRule"
        :class="latencyColor"
        class="ml-1 text-xs"
      >
        {{ latency }}
      </span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { updateRuleProviderAPI } from '@/api'
import { useBounceOnVisible } from '@/composables/bouncein'
import { NOT_CONNECTED, ROUTE_NAME } from '@/constant'
import { getColorForLatency } from '@/helper'
import { useTooltip } from '@/helper/tooltip'
import router from '@/router'
import { getLatencyByName, getNowProxyNodeName, proxyMap } from '@/store/proxies'
import { fetchRules, getRuleHitCount, ruleProviderList } from '@/store/rules'
import { displayLatencyInRule, displayNowNodeInRule } from '@/store/settings'
import type { Rule } from '@/types'
import {
  ArrowPathIcon,
  ArrowRightCircleIcon,
  FunnelIcon,
  NoSymbolIcon,
  QuestionMarkCircleIcon,
} from '@heroicons/vue/24/outline'
import { twMerge } from 'tailwind-merge'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import ProxyName from '../proxies/ProxyName.vue'

const props = defineProps<{
  rule: Rule
  index: number
}>()

const { t } = useI18n()
const { showTip } = useTooltip()
const proxyNode = computed(() => proxyMap.value[props.rule.proxy])
const latency = computed(() => getLatencyByName(props.rule.proxy, props.rule.proxy))
const latencyColor = computed(() => getColorForLatency(Number(latency.value)))
const hits = computed(() => getRuleHitCount(props.rule.type, props.rule.payload))

const size = computed(() => {
  if (props.rule.type === 'RuleSet') {
    return ruleProviderList.value.find((provider) => provider.name === props.rule.payload)
      ?.ruleCount
  }

  return props.rule.size
})

const isUpdating = ref(false)
const isUpdateableRuleSet = computed(() => {
  if (props.rule.type !== 'RuleSet') {
    return false
  }

  const provider = ruleProviderList.value.find((provider) => provider.name === props.rule.payload)

  if (!provider) {
    return false
  }
  return provider.vehicleType !== 'Inline'
})

const updateRuleProviderClickHandler = async () => {
  if (isUpdating.value) return

  isUpdating.value = true
  await updateRuleProviderAPI(props.rule.payload)
  fetchRules()
  isUpdating.value = false
}

const showMMDBSizeTip = (e: Event) => {
  showTip(e, t('mmdbSizeTip'))
}

const TOPOLOGY_NAV_FILTER_KEY = 'runtime/topology-pending-filter-v1'
const ruleTextForTopology = computed(() => {
  const type = String(props.rule.type || '').trim()
  const payload = String(props.rule.payload || '').trim()
  return payload ? `${type}: ${payload}` : type
})

const openTopologyWithRule = async (mode: 'only' | 'exclude' = 'only') => {
  const value = String(ruleTextForTopology.value || '').trim()
  if (!value) return

  const payload = {
    ts: Date.now(),
    mode,
    focus: { stage: 'R', kind: 'value', value },
  }

  try {
    localStorage.setItem(TOPOLOGY_NAV_FILTER_KEY, JSON.stringify(payload))
  } catch {
    // ignore
  }

  await router.push({ name: ROUTE_NAME.overview })
}

useBounceOnVisible()
</script>
