import { fetchRuleProvidersAPI, fetchRulesAPI } from '@/api'
import { RULE_TAB_TYPE } from '@/constant'
import type { Rule, RuleProvider } from '@/types'
import { computed, ref } from 'vue'
import { activeConnections, closedConnections } from '@/store/connections'

export const rulesFilter = ref('')
export const rulesTabShow = ref(RULE_TAB_TYPE.RULES)

export const rules = ref<Rule[]>([])
export const ruleProviderList = ref<RuleProvider[]>([])

export const renderRules = computed(() => {
  const rulesFilterValue = rulesFilter.value.split(' ').map((f) => f.toLowerCase().trim())

  if (rulesFilter.value === '') {
    return rules.value
  }

  return rules.value.filter((rule) => {
    return rulesFilterValue.every((f) =>
      [rule.type.toLowerCase(), rule.payload.toLowerCase(), rule.proxy.toLowerCase()].some((i) =>
        i.includes(f),
      ),
    )
  })
})

export const renderRulesProvider = computed(() => {
  const rulesFilterValue = rulesFilter.value.split(' ').map((f) => f.toLowerCase().trim())

  if (rulesFilter.value === '') {
    return ruleProviderList.value
  }

  return ruleProviderList.value.filter((ruleProvider) => {
    return rulesFilterValue.every((f) =>
      [
        ruleProvider.name.toLowerCase(),
        ruleProvider.behavior.toLowerCase(),
        ruleProvider.vehicleType.toLowerCase(),
      ].some((i) => i.includes(f)),
    )
  })
})


export const ruleHitMap = computed(() => {
  const map = new Map<string, number>()
  const all = [...activeConnections.value, ...closedConnections.value]

  for (const c of all) {
    const type = (c.rule || '').trim()
    const payload = (c.rulePayload || '').trim()
    if (!type) continue
    const key = `${type}\u0000${payload}`
    map.set(key, (map.get(key) || 0) + 1)
  }
  return map
})

export const getRuleHitCount = (type: string, payload: string) => {
  const key = `${(type || '').trim()}\u0000${(payload || '').trim()}`
  return ruleHitMap.value.get(key) || 0
}

export const ruleMissCount = computed(() => {
  // In Clash/Mihomo, "MATCH" is the final catch-all rule.
  // We treat it as a "miss" from explicit filter rules.
  const all = [...activeConnections.value, ...closedConnections.value]
  return all.filter((c) => (c.rule || '').toUpperCase() === 'MATCH').length
})

export const fetchRules = async () => {
  const { data: ruleData } = await fetchRulesAPI()
  const { data: providerData } = await fetchRuleProvidersAPI()

  rules.value = ruleData.rules.map((rule) => {
    const proxy = rule.proxy
    const proxyName = proxy.startsWith('route(') ? proxy.substring(6, proxy.length - 1) : proxy

    return {
      ...rule,
      proxy: proxyName,
    }
  })
  ruleProviderList.value = Object.values(providerData.providers)
}
