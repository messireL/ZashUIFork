import { agentUsersDbGetAPI, agentUsersDbPutAPI } from '@/api/agent'
import { decodeB64Utf8 } from '@/helper/b64'
import type { SourceIPLabel } from '@/types'
import { useStorage } from '@vueuse/core'
import { debounce, isEqual } from 'lodash'
import { computed, ref, watch } from 'vue'
import { agentEnabled } from './agent'
import { sourceIPLabelList } from './settings'

/**
 * Shared users database (Source IP labels) stored on the router via router-agent.
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

// When agent is offline/disabled, keep local edits and sync later.
export const usersDbLocalDirty = useStorage<boolean>('runtime/users-db-local-dirty-v1', false)

export const usersDbPhase = ref<UsersDbSyncPhase>('idle')

export const usersDbSyncActive = computed(() => {
  return Boolean(usersDbSyncEnabled.value && agentEnabled.value)
})

const safeParseLabels = (raw: string): SourceIPLabel[] => {
  try {
    const v = JSON.parse(raw)
    if (!Array.isArray(v)) return []
    return v
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
    const prev = byKey.get(k)
    if (!prev) {
      byKey.set(k, v)
      continue
    }
    byKey.set(k, v)
  }
  return Array.from(byKey.values())
}

let started = false
let suppressNextPush = false
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
    const remoteRaw = decodeB64Utf8(r.contentB64) || '[]'
    const remoteList = safeParseLabels(remoteRaw)

    usersDbRemoteRev.value = remoteRev
    usersDbRemoteUpdatedAt.value = remoteUpdatedAt

    const localList = (sourceIPLabelList.value || []) as SourceIPLabel[]

    // If we had offline edits, merge them into the remote and push back.
    if (usersDbLocalDirty.value) {
      const merged = mergeLabels(remoteList, localList)
      suppressNextPush = true
      sourceIPLabelList.value = merged
      const put = await usersDbPushNow(remoteRev, merged)
      usersDbLocalDirty.value = !put.ok
    } else {
      // First-time bootstrap: remote empty and local has data -> seed remote.
      if (remoteRev === 0 && remoteList.length === 0 && localList.length > 0) {
        await usersDbPushNow(remoteRev, localList)
      } else if (!isEqual(remoteList, localList)) {
        suppressNextPush = true
        sourceIPLabelList.value = remoteList
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

export const usersDbPushNow = async (baseRev?: number, overrideList?: SourceIPLabel[]) => {
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
    const list = (overrideList ?? sourceIPLabelList.value ?? []) as SourceIPLabel[]
    const body = JSON.stringify(list)
    const rev = Number(baseRev ?? usersDbRemoteRev.value) || 0

    const r: any = await agentUsersDbPutAPI({ rev, content: body })
    if (r?.ok) {
      usersDbRemoteRev.value = Number(r.rev) || usersDbRemoteRev.value + 1
      usersDbRemoteUpdatedAt.value = String(r.updatedAt || '').trim()
      usersDbLastPushAt.value = Date.now()
      usersDbLocalDirty.value = false
      usersDbPhase.value = 'idle'
      return { ok: true }
    }

    if (r?.error === 'conflict') {
      usersDbPhase.value = 'conflict'
      usersDbConflictAt.value = Date.now()
      usersDbConflictCount.value = (Number(usersDbConflictCount.value) || 0) + 1

      // Merge with current remote and retry once.
      const remoteRev = Number(r.rev) || 0
      const remoteUpdatedAt = String(r.updatedAt || '').trim()
      const remoteRaw = decodeB64Utf8(r.contentB64) || '[]'
      const remoteList = safeParseLabels(remoteRaw)
      const merged = mergeLabels(remoteList, list)

      suppressNextPush = true
      sourceIPLabelList.value = merged

      usersDbRemoteRev.value = remoteRev
      usersDbRemoteUpdatedAt.value = remoteUpdatedAt

      const r2: any = await agentUsersDbPutAPI({ rev: remoteRev, content: JSON.stringify(merged) })
      if (r2?.ok) {
        usersDbRemoteRev.value = Number(r2.rev) || remoteRev + 1
        usersDbRemoteUpdatedAt.value = String(r2.updatedAt || '').trim()
        usersDbLastPushAt.value = Date.now()
        usersDbLocalDirty.value = false
        usersDbPhase.value = 'idle'
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
    sourceIPLabelList,
    () => {
      if (suppressNextPush) {
        suppressNextPush = false
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
