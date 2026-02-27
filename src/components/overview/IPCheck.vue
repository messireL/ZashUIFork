<template>
  <div class="bg-base-200/50 relative flex min-h-28 flex-col gap-1 rounded-lg p-2">
    <div class="grid grid-cols-[auto_auto_1fr] gap-x-2 gap-y-1">
      <div class="text-left text-sm">ipip.net</div>
      <div class="text-right text-sm">:</div>
      <div class="text-sm">
        {{ showPrivacy ? ipForChina.ipWithPrivacy[0] : ipForChina.ip[0] }}
        <span class="text-xs" v-if="ipForChina.ip[1]">
          ({{ showPrivacy ? ipForChina.ipWithPrivacy[1] : ipForChina.ip[1] }})
        </span>
      </div>

      <div class="text-left text-sm">2ip.ru</div>
      <div class="text-right text-sm">:</div>
      <div class="text-sm">
        {{ showPrivacy ? ipFor2ipRu.ipWithPrivacy[0] : ipFor2ipRu.ip[0] }}
        <span class="text-xs" v-if="ipFor2ipRu.ip[1]">
          ({{ showPrivacy ? ipFor2ipRu.ipWithPrivacy[1] : ipFor2ipRu.ip[1] }})
        </span>
      </div>

      <div class="text-left text-sm">2ip.io</div>
      <div class="text-right text-sm">:</div>
      <div class="text-sm">
        {{ showPrivacy ? ipFor2ipIo.ipWithPrivacy[0] : ipFor2ipIo.ip[0] }}
        <span class="text-xs" v-if="ipFor2ipIo.ip[1]">
          ({{ showPrivacy ? ipFor2ipIo.ipWithPrivacy[1] : ipFor2ipIo.ip[1] }})
        </span>
      </div>

      <div class="text-left text-sm">{{ IPInfoAPI }}</div>
      <div class="text-right text-sm">:</div>
      <div class="text-sm">
        {{ showPrivacy ? ipForGlobal.ipWithPrivacy[0] : ipForGlobal.ip[0] }}
        <span class="text-xs" v-if="ipForGlobal.ip[1]">
          ({{ showPrivacy ? ipForGlobal.ipWithPrivacy[1] : ipForGlobal.ip[1] }})
        </span>
      </div>
    </div>

    <div class="absolute right-2 bottom-2 flex items-center gap-2">
      <button
        class="btn btn-circle btn-sm flex items-center justify-center"
        @click="showPrivacy = !showPrivacy"
        @mouseenter="handlerShowPrivacyTip"
      >
        <EyeIcon v-if="showPrivacy" class="h-4 w-4" />
        <EyeSlashIcon v-else class="h-4 w-4" />
      </button>

      <button class="btn btn-circle btn-sm" @click="getIPs(true)">
        <BoltIcon class="h-4 w-4" />
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import {
  getIPFrom2ipIoAPI,
  getIPFrom2ipMeGeoAPI,
  getIPFrom2ipMeProviderAPI,
  getIPFromIpipnetAPI,
  getIPInfo,
} from '@/api/geoip'
import { ipForChina, ipForGlobal } from '@/composables/overview'
import { useTooltip } from '@/helper/tooltip'
import { autoIPCheck, IPInfoAPI, twoIpToken } from '@/store/settings'
import { BoltIcon, EyeIcon, EyeSlashIcon } from '@heroicons/vue/24/outline'
import { onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const showPrivacy = ref(false)
const { showTip } = useTooltip()

const handlerShowPrivacyTip = (e: Event) => {
  showTip(e, t('ipScreenshotTip'))
}

type IPBlock = { ip: string[]; ipWithPrivacy: string[] }

const ipFor2ipRu = ref<IPBlock>({ ip: [], ipWithPrivacy: [] })
const ipFor2ipIo = ref<IPBlock>({ ip: [], ipWithPrivacy: [] })

const QUERYING_IP_INFO: IPBlock = {
  ip: [t('getting'), ''],
  ipWithPrivacy: [t('getting'), ''],
}

const FAILED_IP_INFO: IPBlock = {
  ip: [t('testFailedTip'), ''],
  ipWithPrivacy: [t('testFailedTip'), ''],
}

const maskIP = (ip: string) => (ip ? '***.***.***.***' : '')

// 1h cache, чтобы не упираться в лимиты и не долбить 2ip каждый ререндер
const CACHE_TTL = 60 * 60 * 1000
const cacheRead = (key: string): IPBlock | null => {
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return null
    const parsed = JSON.parse(raw) as { expires: number; value: IPBlock }
    if (!parsed?.expires || Date.now() > parsed.expires) return null
    if (!parsed?.value?.ip?.length) return null
    return parsed.value
  } catch {
    return null
  }
}
const cacheWrite = (key: string, value: IPBlock) => {
  try {
    localStorage.setItem(key, JSON.stringify({ expires: Date.now() + CACHE_TTL, value }))
  } catch {
    // ignore
  }
}

const CACHE_KEY_2IP_RU = 'cache/ipcheck-2ip-ru'
const CACHE_KEY_2IP_IO = 'cache/ipcheck-2ip-io'

const safeText = (s: any) => (typeof s === 'string' ? s.trim() : '')
const pick = (obj: any, path: string[]) => {
  let cur = obj
  for (const k of path) {
    if (!cur || typeof cur !== 'object') return undefined
    cur = cur[k]
  }
  return cur
}

const format2ipIo = (data: any): { text: string; ip: string } => {
  const ip =
    safeText(data?.ip) ||
    safeText(data?.query) ||
    safeText(data?.address) ||
    safeText(pick(data, ['data', 'ip']))

  const country =
    safeText(data?.country) ||
    safeText(pick(data, ['geo', 'country'])) ||
    safeText(pick(data, ['location', 'country']))

  const city =
    safeText(data?.city) ||
    safeText(pick(data, ['geo', 'city'])) ||
    safeText(pick(data, ['location', 'city']))

  const org =
    safeText(data?.organization) ||
    safeText(data?.org) ||
    safeText(pick(data, ['asn', 'org'])) ||
    safeText(pick(data, ['asn', 'name'])) ||
    safeText(pick(data, ['connection', 'org'])) ||
    safeText(pick(data, ['connection', 'isp']))

  const text = [country, city, org].filter(Boolean).join(' ')
  return { text: text || t('noContent'), ip }
}

const getIPs = (force = false) => {
  ipForChina.value = { ...QUERYING_IP_INFO }
  ipForGlobal.value = { ...QUERYING_IP_INFO }
  ipFor2ipRu.value = { ...QUERYING_IP_INFO }
  ipFor2ipIo.value = { ...QUERYING_IP_INFO }

  // global provider (ip.sb / ipwho.is / ipapi.is)
  getIPInfo()
    .then((res) => {
      const label = `${res.country} ${res.organization}`.trim()
      ipForGlobal.value = {
        ipWithPrivacy: [label, res.ip],
        ip: [label, maskIP(res.ip)],
      }
    })
    .catch(() => (ipForGlobal.value = { ...FAILED_IP_INFO }))

  // china (ipip.net)
  getIPFromIpipnetAPI()
    .then((res) => {
      ipForChina.value = {
        ipWithPrivacy: [res.data.location.join(' '), res.data.ip],
        ip: [`${res.data.location[0]} ** ** **`, maskIP(res.data.ip)],
      }
    })
    .catch(() => (ipForChina.value = { ...FAILED_IP_INFO }))

  // 2ip.ru (через публичный 2ip.me API)
  const cachedRu = !force ? cacheRead(CACHE_KEY_2IP_RU) : null
  if (cachedRu) {
    ipFor2ipRu.value = cachedRu
  } else {
    Promise.all([getIPFrom2ipMeGeoAPI(), getIPFrom2ipMeProviderAPI()])
      .then(([geo, provider]) => {
        const country = geo.country_rus || geo.country
        const city = geo.city_rus || geo.city
        const org = provider.name_rus || provider.name_ripe || ''
        const ip = geo.ip || provider.ip
        const text = [country, city, org].filter(Boolean).join(' ') || t('noContent')

        const value: IPBlock = {
          ipWithPrivacy: [text, ip],
          ip: [text, maskIP(ip)],
        }
        ipFor2ipRu.value = value
        cacheWrite(CACHE_KEY_2IP_RU, value)
      })
      .catch(() => (ipFor2ipRu.value = { ...FAILED_IP_INFO }))
  }

  // 2ip.io (token API)
  const token = (twoIpToken.value || '').trim()
  if (!token) {
    ipFor2ipIo.value = {
      ipWithPrivacy: [t('twoIpTokenMissing'), ''],
      ip: [t('twoIpTokenMissing'), ''],
    }
  } else {
    const cachedIo = !force ? cacheRead(CACHE_KEY_2IP_IO) : null
    if (cachedIo) {
      ipFor2ipIo.value = cachedIo
    } else {
      getIPFrom2ipIoAPI(token)
        .then((data) => {
          if (data && data.success === false) throw new Error('2ip.io failed')
          const { text, ip } = format2ipIo(data)

          const value: IPBlock = {
            ipWithPrivacy: [text, ip],
            ip: [text, maskIP(ip)],
          }
          ipFor2ipIo.value = value
          cacheWrite(CACHE_KEY_2IP_IO, value)
        })
        .catch(() => (ipFor2ipIo.value = { ...FAILED_IP_INFO }))
    }
  }
}

watch(IPInfoAPI, () => {
  const hasAny = [ipForChina, ipForGlobal].some((item) => item.value.ip.length !== 0)
  if (hasAny) getIPs(true)
})

onMounted(() => {
  const hasAny =
    [ipForChina, ipForGlobal].some((item) => item.value.ip.length !== 0) ||
    ipFor2ipRu.value.ip.length !== 0 ||
    ipFor2ipIo.value.ip.length !== 0

  if (autoIPCheck.value && !hasAny) getIPs(false)
})
</script>
