import { agentUsersDbGetAPI, agentUsersDbPutAPI } from '@/api/agent'
import { decodeB64Utf8 } from '@/helper/b64'
import type { SourceIPLabel } from '@/types'
import { useStorage } from '@vueuse/core'
import { debounce, isEqual } from 'lodash'
import { computed, ref, watch } from 'vue'
import { agentEnabled } from './agent'
import { proxyProviderPanelUrlMap, sourceIPLabelList } from './settings'

/**
 * Shared users database stored on the router via router-agent.
 *
 * We keep Source IP labels + a couple of shared UI settings in a single payload.
 *
 * Goals:
 * - Sync enabled by default.
 * - Auto pull on start / when agent becomes available.
 * - Debounced auto push on local changes.
 * - Offline fallback to localStorage and catch-up when the agent is back.
 * - Conflict-safe revision (agent side).
 */

export type UsersDbSyncPhase = 'disabled' | 'idle' | 'pulling' | 'pushing' | 'offline' | 'conflict' | 'error'

export const usersDbSyncEnabled = useStorage<boolean>('config/users-db-sync-enabled', true)

export const usersDbRemoteRev = useStorage<number>('runtime/users-db-remote-rev-v1', 0)
export const usersDbRemoteUpdatedAt = useStorage<string>('runtime/users-db-remote-updated-at-v1', '')

export const usersDbLastPullAt = useStorage<number>('runtime/users-db-last-pull-at-v1', 0)
export const usersDbLastPushAt = useStorage<number>('runtime/users-db-last-push-at-v1', 0)
export const usersDbLastError = useStorage<string>('runtime/users-db-last-error-v1', '')

export const usersDbConflictAt = useStorage<number>('runtime/users-db-conflict-at-v1', 0)
export const usersDbConflictCount = useStorage<number>('runtime/users-db-conflict-count-v1', 0)

// Snapshot of the last successfully synced payload (used for per-item synced markers).
export const usersDbLastSyncedLabels = useStorage<SourceIPLabel[]>('runtime/users-db-last-synced-labels-v1', [])
export const usersDbLastSyncedProviderPanelUrls = useStorage<Record<string, string>>(
  'runtime/users-db-last-synced-provider-panel-urls-v1',
  {},
)

// When agent is offline/disabled, keep local edits and sync later.
export const usersDbLocalDirty = useStorage<boolean>('runtime/users-db-local-dirty-v1', false)

export const usersDbPhase = ref<UsersDbSyncPhase>('idle')

export const usersDbSyncActive = computed(() => {
  return Boolean(usersDbSyncEnabled.value && agentEnabled.value)
})

// ---- payload helpers ----

type UsersDbPayload = {
  labels: SourceIPLabel[]
  providerPanelUrls: Record<string, string>
}

const sanitizeLabels = (raw: any): SourceIPLabel[] => {
  try {
    if (!Array.isArray(raw)) return []
    return raw
      .map((x) => {
        if (!x || typeof x !== 'object') return null
        const key = String((x as any).key || '').trim()
        const label = String((x as any).label || '').trim()
        const id = String((x as any).id || '').trim()
        const scope = Array.isArray((x as any).scope) ? ((x as any).scope as any[]).map(String) : undefined
        if (!key || !label || !id) return null
        const o: SourceIPLabel = { key, label, id }
        if (scope && scope.length) o.scope = scope
        return o
      })
      .filter(Boolean) as SourceIPLabel[]
  } catch {
    return []
  }
}

const sanitizeUrlMap = (raw: any): Record<string, string> => {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {}
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(raw)) {
    const kk = String(k || '').trim()
    if (!kk) continue
    const vv = String(v || '').trim()
    if (!vv) continue
    out[kk] = vv
  }
  return out
}

const safeParsePayload = (raw: string): UsersDbPayload => {
  try {
    const v: any = JSON.parse(raw || '')

    // Backward compatibility: array means labels only.
    if (Array.isArray(v)) return { labels: sanitizeLabels(v), providerPanelUrls: {} }

    if (v && typeof v === 'object') {
      const labels = Array.isArray(v.labels)
        ? sanitizeLabels(v.labels)
        : Array.isArray(v.sourceIPLabelList)
          ? sanitizeLabels(v.sourceIPLabelList)
          : Array.isArray(v.users)
            ? sanitizeLabels(v.users)
            : []

      const urls =
        v.providerPanelUrls && typeof v.providerPanelUrls === 'object'
          ? sanitizeUrlMap(v.providerPanelUrls)
          : v.proxyProviderPanelUrls && typeof v.proxyProviderPanelUrls === 'object'
            ? sanitizeUrlMap(v.proxyProviderPanelUrls)
            : v.proxyProviderPanelUrlMap && typeof v.proxyProviderPanelUrlMap === 'object'
              ? sanitizeUrlMap(v.proxyProviderPanelUrlMap)
              : {}

      return { labels, providerPanelUrls: urls }
    }
  } catch {
    // ignore
  }
  return { labels: [], providerPanelUrls: {} }
}

const buildPayloadForWrite = (p: UsersDbPayload) => {
  return {
    version: 1,
    labels: p.labels || [],
    providerPanelUrls: p.providerPanelUrls || {},
  }
}

const mergeLabels = (remote: SourceIPLabel[], local: SourceIPLabel[]) => {
  // Union with local preference.
  const byId = new Map<string, SourceIPLabel>()
  for (const r of remote || []) {
    if (!r?.id) continue
    byId.set(r.id, r)
  }
  for (const l of local || []) {
    if (!l?.id) continue
    byId.set(l.id, l)
  }

  // Deduplicate by key (prefer local).
  const byKey = new Map<string, SourceIPLabel>()
  for (const v of byId.values()) {
    const k = (v.key || '').trim()
    if (!k) continue
    byKey.set(k, v)
  }
  return Array.from(byKey.values())
}

const mergePayload = (remote: UsersDbPayload, local: UsersDbPayload): UsersDbPayload => {
  const labels = mergeLabels(remote.labels || [], local.labels || [])
  const urls = { ...(remote.providerPanelUrls || {}) }
  for (const [k, v] of Object.entries(local.providerPanelUrls || {})) {
    const kk = String(k || '').trim()
    if (!kk) continue
    const vv = String(v || '').trim()
    if (!vv) continue
    urls[kk] = vv
  }
  return { labels, providerPanelUrls: urls }
}

const payloadEqual = (a: UsersDbPayload, b: UsersDbPayload) => {
  return isEqual(a.labels || [], b.labels || []) && isEqual(a.providerPanelUrls || {}, b.providerPanelUrls || {})
}

const setLocalFromPayload = (p: UsersDbPayload) => {
  sourceIPLabelList.value = (p.labels || []) as any
  proxyProviderPanelUrlMap.value = (p.providerPanelUrls || {}) as any
}

const getLocalPayload = (): UsersDbPayload => {
  return {
    labels: (sourceIPLabelList.value || []) as any,
    providerPanelUrls: (proxyProviderPanelUrlMap.value || {}) as any,
  }
}

const markSynced = (p: UsersDbPayload) => {
  usersDbLastSyncedLabels.value = (p.labels || []) as any
  usersDbLastSyncedProviderPanelUrls.value = (p.providerPanelUrls || {}) as any
}

export const usersDbSyncedIdSet = computed(() => {
  // Per-item marker: item is considered synced if it matches the last synced snapshot by id + fields.
  const snapById = new Map<string, string>()
  const sig = (x: any) => {
    const scope = Array.isArray(x?.scope) ? (x.scope as any[]).map(String).sort().join(',') : ''
    return `${String(x?.id || '')}|${String(x?.key || '')}|${String(x?.label || '')}|${scope}`
  }

  for (const it of (usersDbLastSyncedLabels.value || []) as any[]) {
    const id = String(it?.id || '').trim()
    if (!id) continue
    snapById.set(id, sig(it))
  }

  const out = new Set<string>()
  for (const it of (sourceIPLabelList.value || []) as any[]) {
    const id = String(it?.id || '').trim()
    if (!id) continue
    if (snapById.get(id) == sig(it)) out.add(id)
  }
  return out
})

// ---- sync engine ----

let started = false
let suppressPushCount = 0
let pullInFlight = false
let pushInFlight = false

export const usersDbPullNow = async () => {
  if (!usersDbSyncActive.value) {
    usersDbPhase.value = usersDbSyncEnabled.value ? 'offline' : 'disabled'
    return { ok: false, error: 'agent-disabled' }
  }
  if (pullInFlight) return { ok: false, error: 'busy' }
  pullInFlight = true
  usersDbPhase.value = 'pulling'
  usersDbLastError.value = ''
  try {
    const r: any = await agentUsersDbGetAPI()
    if (!r?.ok) {
      usersDbPhase.value = 'offline'
      usersDbLastError.value = r?.error || 'offline'
      return { ok: false, error: usersDbLastError.value }
    }

    const remoteRev = Number(r.rev) || 0
    const remoteUpdatedAt = String(r.updatedAt || '').trim()
    const remoteRaw = decodeB64Utf8(r.contentB64) || '{}' // may be array or object
    const remotePayload = safeParsePayload(remoteRaw)

    usersDbRemoteRev.value = remoteRev
    usersDbRemoteUpdatedAt.value = remoteUpdatedAt

    const localPayload = getLocalPayload()

    // If we had offline edits, merge them into the remote and push back.
    if (usersDbLocalDirty.value) {
      const merged = mergePayload(remotePayload, localPayload)
      suppressPushCount = 2
      setLocalFromPayload(merged)
      const put = await usersDbPushNow(remoteRev, merged)
      usersDbLocalDirty.value = !put.ok
      if (put.ok) markSynced(merged)
    } else {
      // First-time bootstrap: remote empty and local has data -> seed remote.
      const remoteEmpty = remotePayload.labels.length === 0 && Object.keys(remotePayload.providerPanelUrls || {}).length === 0
      const localHasData = localPayload.labels.length > 0 || Object.keys(localPayload.providerPanelUrls || {}).length > 0

      if (remoteRev == 0 && remoteEmpty && localHasData) {
        const put = await usersDbPushNow(remoteRev, localPayload)
        if (put.ok) markSynced(localPayload)
      } else if (!payloadEqual(remotePayload, localPayload)) {
        suppressPushCount = 2
        setLocalFromPayload(remotePayload)
        markSynced(remotePayload)
      } else {
        markSynced(localPayload)
      }
    }

    usersDbLastPullAt.value = Date.now()
    usersDbPhase.value = 'idle'
    return { ok: true }
  } catch (e: any) {
    usersDbPhase.value = 'offline'
    usersDbLastError.value = e?.message || 'offline'
    return { ok: false, error: usersDbLastError.value }
  } finally {
    pullInFlight = false
  }
}

export const usersDbPushNow = async (baseRev?: number, overridePayload?: UsersDbPayload) => {
  if (!usersDbSyncActive.value) {
    usersDbPhase.value = usersDbSyncEnabled.value ? 'offline' : 'disabled'
    usersDbLocalDirty.value = true
    return { ok: false, error: 'agent-disabled' }
  }
  if (pushInFlight) return { ok: false, error: 'busy' }
  pushInFlight = true
  usersDbPhase.value = 'pushing'
  usersDbLastError.value = ''
  try {
    const payload = overridePayload ? overridePayload : getLocalPayload()
    const body = JSON.stringify(buildPayloadForWrite(payload))
    const rev = Number(baseRev ?? usersDbRemoteRev.value) || 0

    const r: any = await agentUsersDbPutAPI({ rev, content: body })
    if (r?.ok) {
      usersDbRemoteRev.value = Number(r.rev) || usersDbRemoteRev.value + 1
      usersDbRemoteUpdatedAt.value = String(r.updatedAt || '').trim()
      usersDbLastPushAt.value = Date.now()
      usersDbLocalDirty.value = false
      usersDbPhase.value = 'idle'
      markSynced(payload)
      return { ok: true }
    }

    if (r?.error === 'conflict') {
      usersDbPhase.value = 'conflict'
      usersDbConflictAt.value = Date.now()
      usersDbConflictCount.value = (Number(usersDbConflictCount.value) || 0) + 1

      // Merge with current remote and retry once.
      const remoteRev = Number(r.rev) || 0
      const remoteUpdatedAt = String(r.updatedAt || '').trim()
      const remoteRaw = decodeB64Utf8(r.contentB64) || '{}'
      const remotePayload = safeParsePayload(remoteRaw)
      const merged = mergePayload(remotePayload, payload)

      suppressPushCount = 2
      setLocalFromPayload(merged)

      usersDbRemoteRev.value = remoteRev
      usersDbRemoteUpdatedAt.value = remoteUpdatedAt

      const r2: any = await agentUsersDbPutAPI({ rev: remoteRev, content: JSON.stringify(buildPayloadForWrite(merged)) })
      if (r2?.ok) {
        usersDbRemoteRev.value = Number(r2.rev) || remoteRev + 1
        usersDbRemoteUpdatedAt.value = String(r2.updatedAt || '').trim()
        usersDbLastPushAt.value = Date.now()
        usersDbLocalDirty.value = false
        usersDbPhase.value = 'idle'
        markSynced(merged)
        return { ok: true }
      }

      usersDbLastError.value = r2?.error || 'conflict'
      usersDbLocalDirty.value = true
      usersDbPhase.value = 'error'
      return { ok: false, error: usersDbLastError.value }
    }

    usersDbLastError.value = r?.error || 'failed'
    usersDbLocalDirty.value = true
    usersDbPhase.value = 'error'
    return { ok: false, error: usersDbLastError.value }
  } catch (e: any) {
    usersDbLastError.value = e?.message || 'failed'
    usersDbLocalDirty.value = true
    usersDbPhase.value = 'offline'
    return { ok: false, error: usersDbLastError.value }
  } finally {
    pushInFlight = false
  }
}

const debouncedPush = debounce(() => {
  usersDbPushNow()
}, 800)

export const initUsersDbSync = () => {
  if (started) return
  started = true

  watch(
    [usersDbSyncEnabled, agentEnabled],
    async () => {
      if (!usersDbSyncEnabled.value) {
        usersDbPhase.value = 'disabled'
        return
      }
      if (!agentEnabled.value) {
        usersDbPhase.value = 'offline'
        return
      }
      await usersDbPullNow()
    },
    { immediate: true },
  )

  watch(
    [sourceIPLabelList, proxyProviderPanelUrlMap],
    () => {
      if (suppressPushCount > 0) {
        suppressPushCount -= 1
        return
      }
      if (!usersDbSyncEnabled.value) return
      if (!agentEnabled.value) {
        usersDbLocalDirty.value = true
        return
      }
      usersDbLocalDirty.value = true
      debouncedPush()
    },
    { deep: true },
  )

  // Periodic catch-up when dirty.
  window.setInterval(() => {
    if (!usersDbSyncEnabled.value) return
    if (!agentEnabled.value) return
    if (!usersDbLocalDirty.value) return
    if (usersDbPhase.value === 'pulling' || usersDbPhase.value === 'pushing') return
    usersDbPullNow()
  }, 45_000)
}
