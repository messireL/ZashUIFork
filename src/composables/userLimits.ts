import { disconnectByIdSilentAPI, getConfigsSilentAPI, patchConfigsSilentAPI } from '@/api'
import { agentRemoveShapeAPI, agentSetShapeAPI, agentStatusAPI } from '@/api/agent'
import { getIPLabelFromMap } from '@/helper/sourceip'
import { activeConnections } from '@/store/connections'
import { sourceIPLabelList } from '@/store/settings'
import { agentEnabled, agentEnforceBandwidth, agentShaperStatus, managedAgentShapers } from '@/store/agent'
import {
  autoDisconnectLimitedUsers,
  hardBlockLimitedUsers,
  managedLanDisallowedCidrs,
  type UserLimit,
  type UserLimitPeriod,
  userLimits,
} from '@/store/userLimits'
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
    trafficLimitUnit: (l?.trafficLimitUnit ?? 'GB') as any,
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
  if (!next.trafficLimitBytes) delete (next as any).trafficLimitUnit
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

  // Bandwidth limits are "adult" (shaping) when the router agent is enabled.
  const bwViaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value

  // Manual block works regardless of "enabled".
  const blocked = l.disabled || (l.enabled && (trafficExceeded || (!bwViaAgent && bandwidthExceeded)))

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
let lastAppliedManagedCidrsKey = ''
let lastHardBlockSyncAt = 0

const looksLikeIP = (s: string) => {
  const v = (s || '').trim()
  if (!v) return false
  const v4 = /^\d{1,3}(?:\.\d{1,3}){3}$/.test(v)
  const v6 = v.includes(':')
  return v4 || v6
}

const toCidr = (ipOrCidr: string) => {
  const v = (ipOrCidr || '').trim()
  if (!v) return ''
  if (v.includes('/')) return v
  if (v.includes(':')) return `${v}/128`
  return `${v}/32`
}

const ipsForUserLabel = (userLabel: string) => {
  const out: string[] = []
  for (const it of sourceIPLabelList.value) {
    const label = it.label || it.key
    if (label === userLabel || it.key === userLabel) out.push(it.key)
  }
  if (!out.length && looksLikeIP(userLabel)) out.push(userLabel)
  return Array.from(new Set(out))
}

export const getIpsForUser = (userLabel: string) => {
  return ipsForUserLabel(userLabel)
}

const getCfgList = (cfg: any, key: string): string[] => {
  if (!cfg || typeof cfg !== 'object') return []
  // prefer exact key
  const v = (cfg as any)[key]
  if (Array.isArray(v)) return v.filter((x) => typeof x === 'string')
  // fallback: case-insensitive search
  const k = Object.keys(cfg).find((kk) => kk.toLowerCase() === key.toLowerCase())
  const vv = k ? (cfg as any)[k] : undefined
  if (Array.isArray(vv)) return vv.filter((x) => typeof x === 'string')
  return []
}

const syncLanDisallowedIps = async (desiredManagedCidrs: string[]) => {
  const desired = Array.from(new Set(desiredManagedCidrs.filter(Boolean))).sort()
  const desiredKey = desired.join('|')
  const now = Date.now()
  // Avoid hammering /configs: if desired hasn't changed, sync at most every 15s.
  if (desiredKey === lastAppliedManagedCidrsKey && now - lastHardBlockSyncAt < 15_000) return

  const prevManaged = Array.from(new Set((managedLanDisallowedCidrs.value || []).filter(Boolean))).sort()

  const cfgResp = await getConfigsSilentAPI().catch(() => null)
  const cfg: any = cfgResp?.data
  const current = getCfgList(cfg, 'lan-disallowed-ips')

  // Keep entries not managed by UI, update only managed ones.
  const nonManaged = current.filter((x) => !prevManaged.includes(x))
  const next = Array.from(new Set([...nonManaged, ...desired]))

  // Patch only if changed
  const curKey = Array.from(new Set(current)).sort().join('|')
  const nextKey = Array.from(new Set(next)).sort().join('|')
  if (curKey !== nextKey) {
    await patchConfigsSilentAPI({ 'lan-disallowed-ips': next }).catch(() => null)
  }

  managedLanDisallowedCidrs.value = desired
  lastAppliedManagedCidrsKey = desiredKey
  lastHardBlockSyncAt = now
}

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
  const useDisconnect = !!autoDisconnectLimitedUsers.value
  const useHardBlock = !!hardBlockLimitedUsers.value
  if (!useDisconnect && !useHardBlock) return

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

    const bwViaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value

    if (l.bandwidthLimitBps && l.bandwidthLimitBps > 0) {
      const sp = speedByUser.get(user) || 0
      if (sp >= l.bandwidthLimitBps) {
        bwExceedCountByUser.value[user] = (bwExceedCountByUser.value[user] || 0) + 1
        // If bandwidth is enforced by the router agent, do not "block" the user.
        if (!bwViaAgent && bwExceedCountByUser.value[user] >= 3) return true
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

  // --- Hard block via Mihomo `lan-disallowed-ips` ---
  if (useHardBlock) {
    const blockedUsers: string[] = []
    for (const [user] of Object.entries(userLimits.value)) {
      if (isUserBlocked(user)) blockedUsers.push(user)
    }

    const cidrs: string[] = []
    for (const u of blockedUsers) {
      for (const ip of ipsForUserLabel(u)) {
        const cidr = toCidr(ip)
        if (cidr) cidrs.push(cidr)
      }
    }

    if (cidrs.length || (managedLanDisallowedCidrs.value || []).length) {
      await syncLanDisallowedIps(cidrs)
    }
  } else {
    // If hard-block disabled, clean up only entries we previously managed.
    if ((managedLanDisallowedCidrs.value || []).length) {
      await syncLanDisallowedIps([])
    }
  }

  // Disconnect active connections for blocked users
  const tasks: Promise<any>[] = []
  // If hard-block is enabled we still disconnect to make the block immediate.
  if (useDisconnect || useHardBlock) {
    for (const [user, ids] of connsByUser.entries()) {
      if (!isUserBlocked(user)) continue
      for (const id of ids) {
        if (!shouldDisconnect(id)) continue
        tasks.push(disconnectByIdSilentAPI(id).catch(() => null))
      }
    }
  }

  if (tasks.length) {
    await Promise.allSettled(tasks)
  }
}

// --- Bandwidth shaping via router agent (tc/iptables) ---
const syncAgentShapingNow = async () => {
  const enabled = !!agentEnabled.value && !!agentEnforceBandwidth.value
  const prev = managedAgentShapers.value || {}

  // When disabled: best-effort remove everything we previously managed.
  if (!enabled) {
    const ips = Object.keys(prev)
    if (!ips.length) return
    await Promise.allSettled(ips.map((ip) => agentRemoveShapeAPI(ip)))
    managedAgentShapers.value = {}
    return
  }

  // Desired: from enabled users with bandwidthLimit.
  const desired: Record<string, { upMbps: number; downMbps: number }> = {}
  for (const [user, raw] of Object.entries(userLimits.value || {})) {
    const l = resolveLimit(raw)
    if (!l.enabled) continue
    if (!l.bandwidthLimitBps || l.bandwidthLimitBps <= 0) continue

    // Stored as bytes/sec; convert to Mbps (bits/sec).
    const mbps = +(((l.bandwidthLimitBps * 8) / 1_000_000)).toFixed(2)
    if (!mbps || mbps <= 0) continue

    for (const ip of ipsForUserLabel(user)) {
      // Single field applies to both directions.
      desired[ip] = { upMbps: mbps, downMbps: mbps }
    }
  }

  // If agent is offline, don't destroy the previous state; we'll retry later.
  const st = await agentStatusAPI()
  if (!st?.ok) return

  const now = Date.now()
  const tasks: Array<Promise<void>> = []

  // Apply/Update
  for (const [ip, v] of Object.entries(desired)) {
    const p = prev[ip]
    const changed = !p || p.upMbps !== v.upMbps || p.downMbps !== v.downMbps
    if (!changed) continue
    tasks.push(
      agentSetShapeAPI({ ip, upMbps: v.upMbps, downMbps: v.downMbps }).then((res) => {
        agentShaperStatus.value = {
          ...agentShaperStatus.value,
          [ip]: { ok: !!res.ok, error: res.ok ? undefined : res.error, at: now },
        }
      }),
    )
  }
  // Remove
  for (const ip of Object.keys(prev)) {
    if (desired[ip]) continue
    tasks.push(
      agentRemoveShapeAPI(ip).then((res) => {
        const next = { ...(agentShaperStatus.value || {}) }
        // keep last error if failed
        if (!res.ok) {
          next[ip] = { ok: false, error: res.error, at: now }
        } else {
          delete next[ip]
        }
        agentShaperStatus.value = next
      }),
    )
  }

  if (tasks.length) await Promise.allSettled(tasks)
  managedAgentShapers.value = desired
}

const syncAgentShapingDebounced = debounce(() => {
  syncAgentShapingNow()
}, 600)


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

  // Sync shaping rules whenever limits or agent settings change.
  watch(
    [userLimits, agentEnabled, agentEnforceBandwidth],
    () => {
      syncAgentShapingDebounced()
    },
    { deep: true },
  )
}

export const reapplyAgentShapingForUser = async (userLabel: string) => {
  const enabled = !!agentEnabled.value && !!agentEnforceBandwidth.value
  if (!enabled) return { ok: false as const, error: 'agent disabled' }

  const l = resolveLimit(userLimits.value[userLabel])
  if (!l.enabled || !l.bandwidthLimitBps || l.bandwidthLimitBps <= 0) {
    return { ok: false as const, error: 'no bandwidth limit' }
  }

  const mbps = +(((l.bandwidthLimitBps * 8) / 1_000_000)).toFixed(2)
  if (!mbps || mbps <= 0) return { ok: false as const, error: 'invalid limit' }

  const st = await agentStatusAPI()
  if (!st?.ok) return { ok: false as const, error: st?.error || 'offline' }

  const ips = ipsForUserLabel(userLabel)
  if (!ips.length) return { ok: false as const, error: 'no ips' }

  const now = Date.now()
  const nextManaged = { ...(managedAgentShapers.value || {}) }
  const nextStatus = { ...(agentShaperStatus.value || {}) }

  const results = await Promise.allSettled(
    ips.map((ip) =>
      agentSetShapeAPI({ ip, upMbps: mbps, downMbps: mbps }).then((res) => {
        nextStatus[ip] = { ok: !!res.ok, error: res.ok ? undefined : res.error, at: now }
        if (res.ok) nextManaged[ip] = { upMbps: mbps, downMbps: mbps }
        return res
      }),
    ),
  )

  agentShaperStatus.value = nextStatus
  managedAgentShapers.value = nextManaged

  const anyFail = results.some((r) => r.status === 'fulfilled' && !(r.value as any)?.ok)
  return anyFail ? { ok: false as const, error: 'failed' } : { ok: true as const }
}

export const limitedUsersCount = computed(() => Object.keys(userLimits.value || {}).length)
