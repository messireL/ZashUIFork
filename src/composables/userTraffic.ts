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

export const getUserHourBucket = (user: string, ts = Date.now()): UserTrafficBucket => {
  const u = (user || '').toString()
  if (!u) return { dl: 0, ul: 0 }
  const k = bucketKey(ts)
  const b = store.value?.[k]?.[u]
  return { dl: b?.dl || 0, ul: b?.ul || 0 }
}

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

const connTotals = new Map<string, { dl: number; ul: number }>()

let started = false
export const initUserTrafficRecorder = () => {
  if (started) return
  started = true

  load()

  // Every WS tick, connections list updates with per-connection counters (download/upload).
  // We compute deltas ourselves so that short-lived connections are still counted on their first appearance.
  watch(
    activeConnections,
    (list) => {
      const now = Date.now()
      const seen = new Set<string>()
      for (const c of list) {
        const id = (c as any)?.id || ''
        if (!id) continue
        seen.add(id)

        const ip = c?.metadata?.sourceIP || ''
        // Some configs can have empty labels; never drop traffic because of that.
        const mapped = getIPLabelFromMap(ip)
        const user = (mapped || ip || '').toString()

        const curDl = Number((c as any)?.download ?? 0) || 0
        const curUl = Number((c as any)?.upload ?? 0) || 0

        const prev = connTotals.get(id)
        let d = curDl
        let u = curUl
        if (prev) {
          d = curDl - (prev.dl || 0)
          u = curUl - (prev.ul || 0)
        }
        if (!Number.isFinite(d) || d < 0) d = 0
        if (!Number.isFinite(u) || u < 0) u = 0

        // Fallback: if totals are not available for some builds but per-tick deltas exist.
        if (d === 0 && u === 0) {
          const sd = Number((c as any)?.downloadSpeed ?? 0) || 0
          const su = Number((c as any)?.uploadSpeed ?? 0) || 0
          if (sd > 0 || su > 0) {
            d = sd
            u = su
          }
        }

        add(user, d, u, now)

        connTotals.set(id, { dl: curDl, ul: curUl })
      }

      // prune ended connections
      for (const id of Array.from(connTotals.keys())) {
        if (!seen.has(id)) connTotals.delete(id)
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


export type TrafficGroupBy = 'day' | 'week' | 'month'

const isoWeekStart = (d: dayjs.Dayjs) => {
  // Monday as start of week
  const dow = d.day() // 0..6 (Sun..Sat)
  const diff = (dow + 6) % 7
  return d.subtract(diff, 'day').startOf('day')
}

const groupKeyForHour = (hourKey: string, groupBy: TrafficGroupBy) => {
  const t = dayjs(hourKey, 'YYYY-MM-DDTHH')
  if (groupBy === 'day') return t.startOf('day').format('YYYY-MM-DD')
  if (groupBy === 'month') return t.startOf('month').format('YYYY-MM')
  // week
  return isoWeekStart(t).format('YYYY-MM-DD')
}

export const getTrafficGrouped = (startTs: number, endTs: number, groupBy: TrafficGroupBy) => {
  // Returns: Map<periodKey, Map<user, {dl, ul}>>
  const out = new Map<string, Map<string, UserTrafficBucket>>()

  const startKey = dayjs(startTs).startOf('hour')
  const endKey = dayjs(endTs).startOf('hour')

  for (let t = startKey; t.isBefore(endKey) || t.isSame(endKey); t = t.add(1, 'hour')) {
    const k = t.format('YYYY-MM-DDTHH')
    const bucket = store.value[k]
    if (!bucket) continue

    const gk = groupKeyForHour(k, groupBy)
    const g = out.get(gk) || new Map<string, UserTrafficBucket>()

    for (const [user, v] of Object.entries(bucket)) {
      const cur = g.get(user) || { dl: 0, ul: 0 }
      cur.dl += v.dl || 0
      cur.ul += v.ul || 0
      g.set(user, cur)
    }

    out.set(gk, g)
  }

  return out
}

export const formatTraffic = (bytes: number) => prettyBytesHelper(bytes)

export const userTrafficStoreSize = computed(() => Object.keys(store.value).length)
