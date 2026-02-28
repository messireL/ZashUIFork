<template>
  <div class="card">
    <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
      <span>{{ $t('userTraffic') }}</span>
      <div class="flex items-center gap-2">
        <select class="select select-sm" v-model="preset">
          <option value="1h">{{ $t('last1h') }}</option>
          <option value="24h">{{ $t('last24h') }}</option>
          <option value="7d">{{ $t('last7d') }}</option>
          <option value="30d">{{ $t('last30d') }}</option>
          <option value="custom">{{ $t('custom') }}</option>
        </select>
        <select class="select select-sm" v-model.number="topN">
          <option :value="0">{{ $t('all') }}</option>
          <option v-for="n in [10, 20, 30, 50, 100]" :key="n" :value="n">top {{ n }}</option>
        </select>
        <button type="button" class="btn btn-sm" @click="clearHistory">
          {{ $t('clearHistory') }}
        </button>
      </div>
    </div>

    <div class="card-body gap-3">
      <div v-if="preset === 'custom'" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-sm">
          <span class="opacity-70">{{ $t('from') }}</span>
          <input class="input input-sm" type="datetime-local" v-model="customFrom" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="opacity-70">{{ $t('to') }}</span>
          <input class="input input-sm" type="datetime-local" v-model="customTo" />
        </label>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="cursor-pointer select-none" @click="setSort('user')">
                {{ $t('user') }}
                <span class="opacity-60" v-if="sortKey === 'user'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="max-md:hidden cursor-pointer select-none" @click="setSort('keys')">
                {{ $t('keys') }}
                <span class="opacity-60" v-if="sortKey === 'keys'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('dl')">
                {{ $t('download') }}
                <span class="opacity-60" v-if="sortKey === 'dl'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('ul')">
                {{ $t('upload') }}
                <span class="opacity-60" v-if="sortKey === 'ul'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('total')">
                {{ $t('total') }}
                <span class="opacity-60" v-if="sortKey === 'total'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right max-lg:hidden">{{ $t('trafficLimit') }}</th>
              <th class="text-right max-lg:hidden">{{ $t('bandwidthLimit') }}</th>
              <th class="text-right">{{ $t('actions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.user">
              <td class="font-medium">
                <div class="flex items-center gap-2">
                  <LockClosedIcon
                    v-if="limitStates[row.user]?.blocked"
                    class="h-4 w-4 text-error"
                    :title="$t('userBlockedTip')"
                  />
                  <template v-if="editingUser === row.user">
                    <input
                      class="input input-xs w-full max-w-[260px]"
                      v-model="editingName"
                      :placeholder="$t('user')"
                    />
                  </template>
                  <template v-else>
                    <span class="truncate inline-block max-w-[240px]" :title="row.user">{{ row.user }}</span>
                  </template>
                </div>
              </td>
              <td class="max-md:hidden">
                <span class="truncate inline-block max-w-[420px] opacity-70" :title="row.keys">{{ row.keys }}</span>
              </td>
              <td class="text-right font-mono">{{ format(row.dl) }}</td>
              <td class="text-right font-mono">{{ format(row.ul) }}</td>
              <td class="text-right font-mono">{{ format(row.dl + row.ul) }}</td>

              <td class="text-right font-mono max-lg:hidden">
                <template v-if="limitStates[row.user]?.trafficLimitBytes">
                  <div
                    class="whitespace-nowrap"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    {{ format(limitStates[row.user].usageBytes) }} /
                    {{ format(limitStates[row.user].trafficLimitBytes) }}
                  </div>
                  <div
                    class="text-xs opacity-60"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    {{ limitStates[row.user].periodLabel }} · {{ limitStates[row.user].percent }}%
                  </div>
                </template>
                <template v-else>
                  <span class="opacity-50">—</span>
                </template>
              </td>

              <td class="text-right font-mono max-lg:hidden">
                <template v-if="limitStates[row.user]?.bandwidthLimitBps">
                  <div
                    class="whitespace-nowrap"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    {{ speed(limitStates[row.user].speedBps) }} /
                    {{ speed(limitStates[row.user].bandwidthLimitBps) }}
                  </div>
                </template>
                <template v-else>
                  <span class="opacity-50">—</span>
                </template>
              </td>

              <td class="text-right relative z-30 pointer-events-auto">
                <div class="flex justify-end gap-1 pointer-events-auto">
                  <template v-if="editingUser === row.user">
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      :disabled="!editingName.trim()"
                      @click.stop.prevent="saveEdit"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('save')"
                    >
                      <CheckIcon class="h-4 w-4" />
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="cancelEdit"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('cancel')"
                    >
                      <XMarkIcon class="h-4 w-4" />
                    </button>
                  </template>
                  <template v-else>
                    <template v-if="shaperBadge[row.user]">
                      <span
                        class="inline-flex items-center justify-center px-1"
                        :title="shaperBadge[row.user].title"
                      >
                        <component
                          :is="shaperBadge[row.user].icon"
                          class="h-4 w-4"
                          :class="shaperBadge[row.user].cls"
                        />
                      </span>
                      <button
                        v-if="shaperBadge[row.user].showReapply"
                        type="button"
                        class="btn btn-ghost btn-circle btn-xs relative z-20"
                        :disabled="applyingShaperUser === row.user"
                        @click.stop.prevent="reapplyShaper(row.user)"
                        @pointerdown.stop.prevent
                        @mousedown.stop.prevent
                        @touchstart.stop.prevent
                        :title="$t('reapply')"
                      >
                        <span v-if="applyingShaperUser === row.user" class="loading loading-spinner loading-xs"></span>
                        <ArrowPathIcon v-else class="h-4 w-4" />
                      </button>
                    </template>
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="openLimits(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('limits')"
                    >
                      <AdjustmentsHorizontalIcon class="h-4 w-4" />
                    </button>

                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="startEdit(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('edit')"
                    >
                      <PencilSquareIcon class="h-4 w-4" />
                    </button>

                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      :disabled="!hasMapping(row.user)"
                      @click.stop.prevent="removeUser(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('delete')"
                    >
                      <TrashIcon class="h-4 w-4" />
                    </button>
                  </template>
                </div>
              </td>
            </tr>

            <tr v-if="!rows.length">
              <td colspan="8" class="text-center opacity-60">{{ $t('noContent') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="text-xs opacity-60">
        {{ $t('userTrafficTip') }} ({{ $t('buckets') }}: {{ buckets }})
      </div>

      <DialogWrapper v-model="limitsDialogOpen">
        <div class="flex items-center justify-between gap-2 mb-2">
          <div class="text-base font-semibold">{{ $t('limits') }}</div>
          <div class="text-sm opacity-70 truncate max-w-[60%]" :title="limitsUser">{{ limitsUser }}</div>
        </div>

        <div class="grid grid-cols-1 gap-3">
          <label class="flex items-center justify-between gap-2">
            <span class="text-sm">{{ $t('enabled') }}</span>
            <input type="checkbox" class="toggle" v-model="draftEnabled" />
          </label>

          <label class="flex items-center justify-between gap-2">
            <span class="text-sm">{{ $t('blocked') }}</span>
            <input type="checkbox" class="toggle" v-model="draftDisabled" />
          </label>

          <div class="flex flex-col gap-1">
            <div class="flex items-center justify-between gap-2">
              <div class="text-sm">
                MAC
                <span class="text-xs opacity-60">({{ $t('routerAgent') }})</span>
              </div>
              <div class="flex items-center gap-2">
                <code
                  class="text-xs px-2 py-1 rounded bg-base-200"
                  :class="draftMac ? '' : 'opacity-50'"
                  :title="draftMac || ''"
                >
                  {{ draftMac || '—' }}
                </code>

                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  :disabled="!agentEnabled"
                  @click="refreshMac"
                  :title="$t('rebindMac')"
                >
                  <ArrowPathIcon class="h-4 w-4" :class="macLoading ? 'animate-spin' : ''" />
                </button>

                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  :disabled="!agentEnabled"
                  @click="refreshMacAndApply"
                  :title="$t('rebindMacApply')"
                >
                  <div class="flex items-center gap-1">
                    <ArrowPathIcon class="h-4 w-4" :class="macApplyLoading ? 'animate-spin' : ''" />
                    <CheckIcon class="h-4 w-4" />
                  </div>
                </button>

                <button type="button" class="btn btn-ghost btn-xs" :disabled="!draftMac" @click="clearMac">
                  {{ $t('clear') }}
                </button>
              </div>
            </div>

            <div v-if="macCandidates.length > 1" class="flex items-center gap-2">
              <select class="select select-sm" v-model="draftMac">
                <option v-for="m in macCandidates" :key="m" :value="m">{{ m }}</option>
              </select>
              <span class="text-xs opacity-60">{{ $t('multipleMacsFound') }}</span>
            </div>
          </div>

          <div class="divider my-0"></div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <label class="flex flex-col gap-1">
              <span class="text-sm opacity-70">{{ $t('trafficLimit') }}</span>
              <div class="flex items-center gap-2">
                <input
                  class="input input-sm flex-1"
                  type="number"
                  min="0"
                  step="0.1"
                  v-model.number="draftTrafficValue"
                  :disabled="!draftEnabled"
                />
                <select class="select select-sm w-20" v-model="draftTrafficUnit" :disabled="!draftEnabled">
                  <option value="GB">GB</option>
                  <option value="MB">MB</option>
                </select>
              </div>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-sm opacity-70">{{ $t('period') }}</span>
              <select class="select select-sm" v-model="draftPeriod" :disabled="!draftEnabled">
                <option value="1d">{{ $t('last24h') }}</option>
                <option value="30d">{{ $t('last30d') }}</option>
                <option value="month">{{ $t('thisMonth') }}</option>
              </select>
            </label>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-sm opacity-70">{{ $t('bandwidthLimit') }} (Mbps)</span>
            <input class="input input-sm" type="number" min="0" step="0.1" v-model.number="draftBandwidthMbps" :disabled="!draftEnabled" />
            <span class="text-xs opacity-60">{{ $t('bandwidthLimitTip') }}</span>
          </label>

          <div class="flex items-center justify-between gap-2">
            <div class="text-xs opacity-70">{{ $t('autoDisconnectLimitedUsers') }}</div>
            <input type="checkbox" class="toggle toggle-sm" v-model="autoDisconnectLimitedUsers" />
          </div>

          <div class="flex items-center justify-between gap-2">
            <div class="text-xs opacity-70">{{ $t('hardBlockLimitedUsers') }}</div>
            <input type="checkbox" class="toggle toggle-sm" v-model="hardBlockLimitedUsers" />
          </div>

          <div class="flex flex-wrap items-center justify-between gap-2">
            <button type="button" class="btn btn-sm" @click="resetCounter" :disabled="!draftEnabled">{{ $t('resetUsage') }}</button>
            <div class="flex items-center gap-2">
              <button type="button" class="btn btn-ghost btn-sm" @click="clearLimits">{{ $t('clearLimits') }}</button>
              <button type="button" class="btn btn-primary btn-sm" @click="saveLimits">{{ $t('save') }}</button>
            </div>
          </div>

          <div class="text-xs opacity-60">
            {{ $t('limitsEnforcementNote') }}
          </div>
        </div>
      </DialogWrapper>
    </div>
  </div>
</template>

<script setup lang="ts">
import DialogWrapper from '@/components/common/DialogWrapper.vue'
import { getIPLabelFromMap } from '@/helper/sourceip'
import { prettyBytesHelper } from '@/helper/utils'
import { activeConnections } from '@/store/connections'
import { sourceIPLabelList } from '@/store/settings'
import { autoDisconnectLimitedUsers, hardBlockLimitedUsers, type UserLimitPeriod } from '@/store/userLimits'
import { agentEnabled, agentEnforceBandwidth, agentShaperStatus } from '@/store/agent'
import {
  clearUserLimit,
  getIpsForUser,
  getUserLimit,
  applyUserEnforcementNow,
  reapplyAgentShapingForUser,
  setUserLimit,
} from '@/composables/userLimits'
import { clearUserTrafficHistory, formatTraffic, getTrafficRange, userTrafficStoreSize } from '@/composables/userTraffic'
import dayjs from 'dayjs'
import { computed, ref } from 'vue'
import { v4 as uuidv4 } from 'uuid'
import {
  AdjustmentsHorizontalIcon,
  ArrowPathIcon,
  CheckIcon,
  CheckCircleIcon,
  LockClosedIcon,
  PencilSquareIcon,
  QuestionMarkCircleIcon,
  TrashIcon,
  XMarkIcon,
} from '@heroicons/vue/24/outline'

type Row = { user: string; keys: string; dl: number; ul: number }

const editingUser = ref<string | null>(null)
const editingName = ref('')

const looksLikeIP = (s: string) => {
  const v = (s || '').trim()
  if (!v) return false
  const v4 = /^\d{1,3}(?:\.\d{1,3}){3}$/.test(v)
  const v6 = v.includes(':')
  return v4 || v6
}

const hasMapping = (user: string) => {
  const u = (user || '').trim()
  if (!u) return false
  return sourceIPLabelList.value.some((it) => (it.label || it.key) === u || it.key === u)
}

const startEdit = (user: string) => {
  editingUser.value = user
  const mapped = sourceIPLabelList.value.find((it) => it.key === user) || null
  editingName.value = (mapped?.label || user || '').toString()
}

const cancelEdit = () => {
  editingUser.value = null
  editingName.value = ''
}

const saveEdit = () => {
  const oldUser = editingUser.value
  const next = editingName.value.trim()
  if (!oldUser || !next) return

  let changed = false
  for (const it of sourceIPLabelList.value) {
    const u = it.label || it.key
    if (u === oldUser || it.key === oldUser) {
      it.label = next
      changed = true
    }
  }

  if (!changed && looksLikeIP(oldUser)) {
    sourceIPLabelList.value.push({
      key: oldUser,
      label: next,
      id: uuidv4(),
    })
  }

  cancelEdit()
}

const removeUser = (user: string) => {
  const u = (user || '').trim()
  if (!u) return
  for (let i = sourceIPLabelList.value.length - 1; i >= 0; i--) {
    const it = sourceIPLabelList.value[i]
    const name = it.label || it.key
    if (name === u || it.key === u) sourceIPLabelList.value.splice(i, 1)
  }
}

const preset = ref<'1h' | '24h' | '7d' | '30d' | 'custom'>('24h')
const topN = ref<number>(30)

type SortKey = 'user' | 'keys' | 'dl' | 'ul' | 'total'
const sortKey = ref<SortKey>('total')
const sortDir = ref<'asc' | 'desc'>('desc')

const setSort = (k: SortKey) => {
  if (sortKey.value === k) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortKey.value = k
    sortDir.value = k === 'user' || k === 'keys' ? 'asc' : 'desc'
  }
}

const customFrom = ref(dayjs().subtract(24, 'hour').format('YYYY-MM-DDTHH:mm'))
const customTo = ref(dayjs().format('YYYY-MM-DDTHH:mm'))

const range = computed(() => {
  const now = dayjs()
  if (preset.value === '1h') return { start: now.subtract(1, 'hour').valueOf(), end: now.valueOf() }
  if (preset.value === '24h') return { start: now.subtract(24, 'hour').valueOf(), end: now.valueOf() }
  if (preset.value === '7d') return { start: now.subtract(7, 'day').valueOf(), end: now.valueOf() }
  if (preset.value === '30d') return { start: now.subtract(30, 'day').valueOf(), end: now.valueOf() }

  const s = dayjs(customFrom.value)
  const e = dayjs(customTo.value)
  return {
    start: (s.isValid() ? s : now.subtract(24, 'hour')).valueOf(),
    end: (e.isValid() ? e : now).valueOf(),
  }
})

const knownKeysByUser = computed(() => {
  const map = new Map<string, string[]>()
  for (const item of sourceIPLabelList.value) {
    const user = item.label || item.key
    const keys = map.get(user) || []
    keys.push(item.key)
    map.set(user, keys)
  }
  return map
})

const rows = computed<Row[]>(() => {
  const { start, end } = range.value
  const agg = getTrafficRange(start, end)

  const allUsers = new Set<string>()
  for (const k of knownKeysByUser.value.keys()) allUsers.add(k)
  for (const k of agg.keys()) allUsers.add(k)

  const list: Row[] = Array.from(allUsers).map((user) => {
    const t = agg.get(user) || { dl: 0, ul: 0 }
    const keys = (knownKeysByUser.value.get(user) || []).join(', ')
    return { user, keys, dl: t.dl, ul: t.ul }
  })

  const sorted = list.sort((a, b) => {
    const dir = sortDir.value === 'asc' ? 1 : -1
    if (sortKey.value === 'user') return dir * a.user.localeCompare(b.user)
    if (sortKey.value === 'keys') return dir * a.keys.localeCompare(b.keys)
    if (sortKey.value === 'dl') return dir * (a.dl - b.dl)
    if (sortKey.value === 'ul') return dir * (a.ul - b.ul)
    const at = a.dl + a.ul
    const bt = b.dl + b.ul
    return dir * (at - bt)
  })

  if (topN.value > 0) return sorted.slice(0, topN.value)
  return sorted
})

const speed = (bps: number) => `${prettyBytesHelper(bps || 0)}/s`
const format = (b: number) => formatTraffic(b)
const buckets = computed(() => userTrafficStoreSize.value)

const clearHistory = () => {
  clearUserTrafficHistory()
}

// --- Limits aggregation for the table ---
const windowForLimit = (period: UserLimitPeriod, resetAt?: number) => {
  const now = dayjs()
  let start = now.subtract(30, 'day')
  if (period === '1d') start = now.subtract(24, 'hour')
  if (period === 'month') start = now.startOf('month')
  let startTs = start.valueOf()
  if (resetAt && resetAt > startTs) startTs = resetAt
  return { startTs, endTs: now.valueOf() }
}

const periodLabel = (p: UserLimitPeriod) => {
  if (p === '1d') return '24h'
  if (p === 'month') return 'month'
  return '30d'
}

const speedByUser = computed(() => {
  const map: Record<string, number> = {}
  for (const c of activeConnections.value) {
    const user = getIPLabelFromMap(c?.metadata?.sourceIP || '')
    map[user] = (map[user] || 0) + (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  }
  return map
})

const limitStates = computed(() => {
  const out: Record<
    string,
    {
      enabled: boolean
      usageBytes: number
      trafficLimitBytes: number
      bandwidthLimitBps: number
      speedBps: number
      blocked: boolean
      percent: string
      periodLabel: string
    }
  > = {}

  // Build windows per user appearing in the table.
  const windows = new Map<string, { startTs: number; endTs: number; users: string[] }>()
  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    const hasTraffic = (l.trafficLimitBytes || 0) > 0
    const hasBw = (l.bandwidthLimitBps || 0) > 0
    if (!hasTraffic && !hasBw && !l.disabled) continue

    const w = windowForLimit(l.trafficPeriod, l.resetAt)
    const key = `${l.trafficPeriod}:${w.startTs}`
    const item = windows.get(key) || { ...w, users: [] }
    item.users.push(row.user)
    windows.set(key, item)
  }

  const aggByKey = new Map<string, Map<string, { dl: number; ul: number }>>()
  for (const [key, w] of windows.entries()) {
    aggByKey.set(key, getTrafficRange(w.startTs, w.endTs))
  }

  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    const w = windowForLimit(l.trafficPeriod, l.resetAt)
    const key = `${l.trafficPeriod}:${w.startTs}`
    const agg = aggByKey.get(key)
    const t = agg?.get(row.user) || { dl: 0, ul: 0 }
    const usage = (t.dl || 0) + (t.ul || 0)
    const tl = l.trafficLimitBytes || 0

    const sp = speedByUser.value[row.user] || 0
    const bl = l.bandwidthLimitBps || 0

    const trafficExceeded = l.enabled && tl > 0 && usage >= tl
    const bandwidthExceeded = l.enabled && bl > 0 && sp >= bl

    const bwViaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value

    // Manual block works regardless of "enabled".
    const blocked = l.disabled || (l.enabled && (trafficExceeded || (!bwViaAgent && bandwidthExceeded)))

    const pct = tl > 0 ? Math.min(999, Math.floor((usage / tl) * 100)) : 0

    out[row.user] = {
      enabled: !!l.enabled,
      usageBytes: usage,
      trafficLimitBytes: tl,
      bandwidthLimitBps: bl,
      speedBps: sp,
      blocked,
      percent: tl > 0 ? String(pct) : '0',
      periodLabel: periodLabel(l.trafficPeriod),
    }
  }

  return out
})

type ShaperBadge = { icon: any; cls: string; title: string; showReapply: boolean }

const shaperBadge = computed<Record<string, ShaperBadge | null>>(() => {
  const out: Record<string, ShaperBadge | null> = {}
  const viaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value
  if (!viaAgent) return out

  const st = agentShaperStatus.value || {}

  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    if (!l.enabled || !l.bandwidthLimitBps || l.bandwidthLimitBps <= 0) {
      out[row.user] = null
      continue
    }

    const ips = getIpsForUser(row.user)
    if (!ips.length) {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: `${row.user}: no IPs`,
        showReapply: true,
      }
      continue
    }

    const statuses = ips.map((ip) => st[ip]).filter(Boolean)
    const hasFail = ips.some((ip) => st[ip] && st[ip].ok === false)
    const allOk = ips.every((ip) => st[ip] && st[ip].ok === true)

    if (hasFail) {
      const firstErr = ips.map((ip) => st[ip]).find((x) => x && !x.ok)?.error
      out[row.user] = {
        icon: XMarkIcon,
        cls: 'text-error',
        title: `${t('shaperFailed')}${firstErr ? `: ${firstErr}` : ''}`,
        showReapply: true,
      }
    } else if (allOk) {
      out[row.user] = {
        icon: CheckCircleIcon,
        cls: 'text-success',
        title: t('shaperApplied'),
        showReapply: true,
      }
    } else if (!statuses.length) {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: t('shaperUnknown'),
        showReapply: true,
      }
    } else {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: t('shaperUnknown'),
        showReapply: true,
      }
    }
  }

  return out
})

const applyingShaperUser = ref<string | null>(null)
const reapplyShaper = async (user: string) => {
  if (!user) return
  applyingShaperUser.value = user
  try {
    await reapplyAgentShapingForUser(user)
  } finally {
    applyingShaperUser.value = null
  }
}

// --- Limits dialog ---
const limitsDialogOpen = ref(false)
const limitsUser = ref('')

const draftEnabled = ref(false)
const draftDisabled = ref(false)
const draftMac = ref('')
const macCandidates = ref<string[]>([])
const macLoading = ref(false)
const macApplyLoading = ref(false)
const draftTrafficValue = ref<number>(0)
const draftTrafficUnit = ref<'GB' | 'MB'>('GB')
const draftBandwidthMbps = ref<number>(0)
const draftPeriod = ref<UserLimitPeriod>('30d')

const bytesFromTraffic = (value: number, unit: 'GB' | 'MB') => {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return 0
  const factor = unit === 'GB' ? 1_000_000_000 : 1_000_000
  return Math.round(n * factor)
}

const bpsFromMbps = (mbps: number) => {
  const n = Number(mbps)
  if (!Number.isFinite(n) || n <= 0) return 0
  return Math.round((n * 1_000_000) / 8)
}

const openLimits = (user: string) => {
  limitsUser.value = user
  const l = getUserLimit(user)
  draftEnabled.value = l.enabled
  draftDisabled.value = l.disabled
  draftMac.value = (l.mac || '').toString().trim().toLowerCase()
  macCandidates.value = draftMac.value ? [draftMac.value] : []
  draftPeriod.value = l.trafficPeriod
  draftTrafficUnit.value = (l.trafficLimitUnit as any) || (l.trafficLimitBytes >= 1_000_000_000 ? 'GB' : 'MB')
  const factor = draftTrafficUnit.value === 'GB' ? 1_000_000_000 : 1_000_000
  draftTrafficValue.value = l.trafficLimitBytes ? +(l.trafficLimitBytes / factor).toFixed(2) : 0
  draftBandwidthMbps.value = l.bandwidthLimitBps ? +(((l.bandwidthLimitBps * 8) / 1_000_000)).toFixed(2) : 0
  limitsDialogOpen.value = true
}

const refreshMac = async () => {
  const user = limitsUser.value
  if (!user) return
  if (!agentEnabled.value) return

  const ips = getIpsForUser(user)
  if (!ips.length) return

  macLoading.value = true
  try {
    const macs = new Set<string>()

    // Lazy import to avoid increasing initial bundle work.
    const { agentIpToMacAPI, agentNeighborsAPI } = await import('@/api/agent')

    // Prefer a direct ip->mac lookup (new agent). Fall back to neighbors list.
    for (const ip of ips) {
      const r = await agentIpToMacAPI(ip)
      const mac = (r?.mac || '').trim().toLowerCase()
      if (r?.ok && mac) macs.add(mac)
      // If command is unsupported, fall back to neighbors.
      if (!r?.ok && (r?.error || '').includes('unknown-cmd')) {
        const n = await agentNeighborsAPI()
        if (n?.ok && n.items) {
          for (const it of n.items) {
            if ((it.ip || '').trim() !== ip) continue
            const m = (it.mac || '').trim().toLowerCase()
            if (m) macs.add(m)
          }
        }
      }
    }

    const list = Array.from(macs).filter(Boolean)
    macCandidates.value = list
    if (list.length === 1) draftMac.value = list[0]
  } finally {
    macLoading.value = false
  }
}

const refreshMacAndApply = async () => {
  const user = limitsUser.value
  if (!user) return
  if (!agentEnabled.value) return

  macApplyLoading.value = true
  try {
    await refreshMac()
    const mac = (draftMac.value || '').trim().toLowerCase()
    if (!mac) return

    // Persist learned MAC even if the user doesn't press "Save".
    setUserLimit(user, { mac })

    // Apply blocks/shaping right away (helps when DHCP changes IPs).
    await applyUserEnforcementNow()
    // Best-effort: also re-apply shaping for this user.
    await reapplyAgentShapingForUser(user)
  } finally {
    macApplyLoading.value = false
  }
}

const clearMac = () => {
  draftMac.value = ''
  macCandidates.value = []
}

const saveLimits = () => {
  const user = limitsUser.value
  if (!user) return

  const trafficLimitBytes = bytesFromTraffic(draftTrafficValue.value, draftTrafficUnit.value)
  const bandwidthLimitBps = bpsFromMbps(draftBandwidthMbps.value)

  const enabled = !!draftEnabled.value
  const disabled = !!draftDisabled.value

  // Default: don't persist an entry unless user really sets something.
  if (!enabled && !disabled && !trafficLimitBytes && !bandwidthLimitBps) {
    clearUserLimit(user)
    limitsDialogOpen.value = false
    return
  }

  setUserLimit(user, {
    enabled,
    disabled,
    mac: draftMac.value ? draftMac.value : undefined,
    trafficPeriod: draftPeriod.value,
    trafficLimitBytes: trafficLimitBytes || undefined,
    trafficLimitUnit: trafficLimitBytes ? draftTrafficUnit.value : undefined,
    bandwidthLimitBps: bandwidthLimitBps || undefined,
  })

  limitsDialogOpen.value = false
}

const clearLimits = () => {
  const user = limitsUser.value
  if (!user) return
  clearUserLimit(user)
  limitsDialogOpen.value = false
}

const resetCounter = () => {
  const user = limitsUser.value
  if (!user) return
  setUserLimit(user, {
    resetAt: Date.now(),
  })
}
</script>
