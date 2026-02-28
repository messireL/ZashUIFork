import { disconnectByIdSilentAPI } from '@/api'
import { getIPLabelFromMap } from '@/helper/sourceip'
import { activeConnections } from '@/store/connections'
import { autoDisconnectLimitedUsers, type UserLimit, type UserLimitPeriod, userLimits } from '@/store/userLimits'
import dayjs from 'dayjs'
import { debounce } from 'lodash'
import { computed, ref, watch } from 'vue'
import { getTrafficRange } from './userTraffic'

export type UserLimitResolved = Required<Pick<UserLimit, 'enabled' | 'disabled' | 'trafficPeriod'>> &
  Omit<UserLimit, 'enabled' | 'disabled' | 'trafficPeriod'>

const resolveLimit = (l?: UserLimit): UserLimitResolved => {
  return {
    // Default: no limits until user explicitly enables them.
    enabled: l?.enabled ?? false,
    disabled: l?.disabled ?? false,
    trafficPeriod: (l?.trafficPeriod ?? '30d') as UserLimitPeriod,
    trafficLimitBytes: l?.trafficLimitBytes ?? 0,
    bandwidthLimitBps: l?.bandwidthLimitBps ?? 0,
    resetAt: l?.resetAt,
  }
}

export const getUserLimit = (user: string) => {
  const raw = userLimits.value[user]
  return resolveLimit(raw)
}

export const setUserLimit = (user: string, patch: Partial<UserLimit>) => {
  const prev = userLimits.value[user] || {}
  const next = { ...prev, ...patch }
  // Normalize empties
  if (!next.trafficLimitBytes) delete (next as any).trafficLimitBytes
  if (!next.bandwidthLimitBps) delete (next as any).bandwidthLimitBps
  userLimits.value = { ...userLimits.value, [user]: next }
}

export const clearUserLimit = (user: string) => {
  const next = { ...userLimits.value }
  delete next[user]
  userLimits.value = next
}

const getWindow = (period: UserLimitPeriod, resetAt?: number) => {
  const now = dayjs()
  let start: dayjs.Dayjs
  if (period === '1d') start = now.subtract(24, 'hour')
  else if (period === 'month') start = now.startOf('month')
  else start = now.subtract(30, 'day')

  let startTs = start.valueOf()
  if (resetAt && Number.isFinite(resetAt) && resetAt > startTs) startTs = resetAt

  return { startTs, endTs: now.valueOf() }
}

export const getUserUsageBytes = (user: string, limit?: UserLimitResolved) => {
  const l = limit || getUserLimit(user)
  const { startTs, endTs } = getWindow(l.trafficPeriod, l.resetAt)
  const agg = getTrafficRange(startTs, endTs)
  const t = agg.get(user) || { dl: 0, ul: 0 }
  return (t.dl || 0) + (t.ul || 0)
}

export const getUserCurrentSpeedBps = (user: string) => {
  let bps = 0
  for (const c of activeConnections.value) {
    const ip = c?.metadata?.sourceIP || ''
    const u = getIPLabelFromMap(ip)
    if (u !== user) continue
    bps += (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  }
  return bps
}

export const getUserLimitState = (user: string) => {
  const l = getUserLimit(user)
  const usage = l.enabled && l.trafficLimitBytes > 0 ? getUserUsageBytes(user, l) : 0
  const speed = l.enabled && l.bandwidthLimitBps > 0 ? getUserCurrentSpeedBps(user) : 0

  const trafficExceeded = l.enabled && l.trafficLimitBytes > 0 && usage >= l.trafficLimitBytes
  const bandwidthExceeded = l.enabled && l.bandwidthLimitBps > 0 && speed >= l.bandwidthLimitBps

  // Manual block works regardless of "enabled".
  const blocked = l.disabled || (l.enabled && (trafficExceeded || bandwidthExceeded))

  return {
    limit: l,
    usageBytes: usage,
    speedBps: speed,
    trafficExceeded,
    bandwidthExceeded,
    blocked,
  }
}

// --- Enforcement (best-effort) ---
let started = false
const lastDisconnectAt = ref<Record<string, number>>({})
const bwExceedCountByUser = ref<Record<string, number>>({})

const cleanupDisconnectCache = () => {
  const now = Date.now()
  const next: Record<string, number> = {}
  for (const [id, ts] of Object.entries(lastDisconnectAt.value)) {
    if (now - ts < 20_000) next[id] = ts
  }
  lastDisconnectAt.value = next
}

const shouldDisconnect = (connId: string) => {
  const ts = lastDisconnectAt.value[connId]
  if (ts && Date.now() - ts < 2500) return false
  lastDisconnectAt.value[connId] = Date.now()
  return true
}

const enforceNow = async () => {
  if (!autoDisconnectLimitedUsers.value) return

  cleanupDisconnectCache()

  // Precompute current speed per user (for bandwidth limits)
  const speedByUser = new Map<string, number>()
  const connsByUser = new Map<string, string[]>()

  for (const c of activeConnections.value) {
    const id = c?.id
    if (!id) continue
    const user = getIPLabelFromMap(c?.metadata?.sourceIP || '')
    const bps = (c.downloadSpeed || 0) + (c.uploadSpeed || 0)

    speedByUser.set(user, (speedByUser.get(user) || 0) + bps)
    const ids = connsByUser.get(user) || []
    ids.push(id)
    connsByUser.set(user, ids)
  }

  // Compute traffic aggregates for the distinct periods present in limits
  const usersWithTrafficLimits: Array<{ user: string; l: UserLimitResolved }> = []
  const periods = new Map<string, { startTs: number; endTs: number }>()
  for (const [user, raw] of Object.entries(userLimits.value)) {
    const l = resolveLimit(raw)
    if (!l.enabled) continue
    if (l.trafficLimitBytes && l.trafficLimitBytes > 0) {
      usersWithTrafficLimits.push({ user, l })
      const w = getWindow(l.trafficPeriod, l.resetAt)
      periods.set(`${l.trafficPeriod}:${w.startTs}`, w)
    }
  }

  const aggByWindow = new Map<string, Map<string, { dl: number; ul: number }>>()
  for (const [k, w] of periods.entries()) {
    aggByWindow.set(k, getTrafficRange(w.startTs, w.endTs))
  }

  const isUserBlocked = (user: string): boolean => {
    const l = resolveLimit(userLimits.value[user])
    if (l.disabled) return true
    if (!l.enabled) return false

    if (l.bandwidthLimitBps && l.bandwidthLimitBps > 0) {
      const sp = speedByUser.get(user) || 0
      if (sp >= l.bandwidthLimitBps) {
        bwExceedCountByUser.value[user] = (bwExceedCountByUser.value[user] || 0) + 1
        if (bwExceedCountByUser.value[user] >= 3) return true
      } else {
        bwExceedCountByUser.value[user] = 0
      }
    }

    if (l.trafficLimitBytes && l.trafficLimitBytes > 0) {
      const w = getWindow(l.trafficPeriod, l.resetAt)
      const key = `${l.trafficPeriod}:${w.startTs}`
      const agg = aggByWindow.get(key)
      if (agg) {
        const t = agg.get(user)
        const used = (t?.dl || 0) + (t?.ul || 0)
        if (used >= l.trafficLimitBytes) return true
      }
    }

    return false
  }

  // Disconnect active connections for blocked users
  const tasks: Promise<any>[] = []
  for (const [user, ids] of connsByUser.entries()) {
    if (!isUserBlocked(user)) continue
    for (const id of ids) {
      if (!shouldDisconnect(id)) continue
      tasks.push(disconnectByIdSilentAPI(id).catch(() => null))
    }
  }

  if (tasks.length) {
    await Promise.allSettled(tasks)
  }
}

const enforceDebounced = debounce(() => {
  enforceNow()
}, 500)

export const initUserLimitsEnforcer = () => {
  if (started) return
  started = true

  // Trigger on every connections WS tick (activeConnections updated)
  watch(
    activeConnections,
    () => {
      enforceDebounced()
    },
    { deep: false },
  )

  // Also trigger when limits toggled
  watch(
    userLimits,
    () => {
      enforceDebounced()
    },
    { deep: true },
  )
}

export const limitedUsersCount = computed(() => Object.keys(userLimits.value || {}).length)
