import { getIPLabelFromMap } from '@/helper/sourceip'
import { activeConnections } from '@/store/connections'
import { prettyBytesHelper } from '@/helper/utils'
import dayjs from 'dayjs'
import { debounce } from 'lodash'
import { computed, ref, watch } from 'vue'

export type UserTrafficBucket = { dl: number; ul: number }
export type UserTrafficStore = Record<string, Record<string, UserTrafficBucket>>

const STORAGE_KEY = 'stats/user-traffic-hourly-v1'
const MAX_DAYS = 35 // keep ~1 month

const store = ref<UserTrafficStore>({})

const safeParse = (raw: string | null): UserTrafficStore => {
  if (!raw) return {}
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

const load = () => {
  store.value = safeParse(localStorage.getItem(STORAGE_KEY))
}

const save = debounce(() => {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store.value))
  } catch {
    // ignore
  }
}, 1500)

const bucketKey = (ts: number) => dayjs(ts).format('YYYY-MM-DDTHH')

const trimOld = () => {
  const cutoff = dayjs().subtract(MAX_DAYS, 'day')
  const next: UserTrafficStore = {}
  for (const [k, v] of Object.entries(store.value)) {
    const t = dayjs(k, 'YYYY-MM-DDTHH')
    if (t.isBefore(cutoff)) continue
    next[k] = v
  }
  store.value = next
}

export const clearUserTrafficHistory = () => {
  store.value = {}
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
}

const add = (user: string, dl: number, ul: number, ts = Date.now()) => {
  if (!user) return
  if (!Number.isFinite(dl)) dl = 0
  if (!Number.isFinite(ul)) ul = 0
  if (dl < 0) dl = 0
  if (ul < 0) ul = 0
  if (dl === 0 && ul === 0) return

  const b = bucketKey(ts)
  const bucket = (store.value[b] ||= {})
  const cur = (bucket[user] ||= { dl: 0, ul: 0 })
  cur.dl += dl
  cur.ul += ul

  trimOld()
  save()
}

let started = false
export const initUserTrafficRecorder = () => {
  if (started) return
  started = true

  load()

  // Every WS tick, connections list updates with *delta* downloadSpeed/uploadSpeed.
  watch(
    activeConnections,
    (list) => {
      const now = Date.now()
      for (const c of list) {
        const ip = c?.metadata?.sourceIP || ''
        const user = getIPLabelFromMap(ip)
        add(user, c.downloadSpeed || 0, c.uploadSpeed || 0, now)
      }
    },
    { deep: false },
  )
}

export const getTrafficRange = (startTs: number, endTs: number) => {
  // inclusive start hour, exclusive end hour
  const out = new Map<string, UserTrafficBucket>()
  const startKey = dayjs(startTs).startOf('hour')
  const endKey = dayjs(endTs).startOf('hour')

  for (let t = startKey; t.isBefore(endKey) || t.isSame(endKey); t = t.add(1, 'hour')) {
    const k = t.format('YYYY-MM-DDTHH')
    const bucket = store.value[k]
    if (!bucket) continue
    for (const [user, v] of Object.entries(bucket)) {
      const cur = out.get(user) || { dl: 0, ul: 0 }
      cur.dl += v.dl || 0
      cur.ul += v.ul || 0
      out.set(user, cur)
    }
  }

  return out
}

export const formatTraffic = (bytes: number) => prettyBytesHelper(bytes)

export const userTrafficStoreSize = computed(() => Object.keys(store.value).length)
