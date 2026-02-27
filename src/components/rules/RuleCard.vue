<template>
  <div class="card hover:bg-base-200 gap-2 p-2 text-sm">
    <div class="min-h-5 leading-5">
      <span>{{ index }}.</span>
      <span class="ml-2">{{ rule.type }}</span>
      <span
        class="text-main ml-2"
        v-if="rule.payload"
      >
        {{ rule.payload }}
      </span>
      <span
        v-if="typeof size === 'number' && size !== -1"
        class="text-base-content/80 ml-1 text-xs"
      >
        ({{ size }})
        <QuestionMarkCircleIcon
          v-if="size === 0"
          class="ml-1 h-4 w-4"
          @mouseenter="showMMDBSizeTip"
        />
      </span>
      <span class="badge badge-xs ml-2" :title="$t('ruleHitsTip')">
        {{ $t('hits') }}: {{ hits }}
      </span>
      <button
        v-if="isUpdateableRuleSet"
        :class="
          twMerge('btn btn-circle btn-ghost btn-xs -mb-1 ml-1', isUpdating ? 'animate-spin' : '')
        "
        @click="updateRuleProviderClickHandler"
      >
        <ArrowPathIcon class="h-4 w-4" />
      </button>
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
import { NOT_CONNECTED } from '@/constant'
import { getColorForLatency } from '@/helper'
import { useTooltip } from '@/helper/tooltip'
import { getLatencyByName, getNowProxyNodeName, proxyMap } from '@/store/proxies'
import { fetchRules, getRuleHitCount, ruleProviderList } from '@/store/rules'
import { displayLatencyInRule, displayNowNodeInRule } from '@/store/settings'
import type { Rule } from '@/types'
import {
  ArrowPathIcon,
  ArrowRightCircleIcon,
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

useBounceOnVisible()
</script>
