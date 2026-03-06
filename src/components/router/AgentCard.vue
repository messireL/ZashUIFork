<template>
  <div class="card gap-2 p-3">
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <div class="font-semibold">{{ $t('routerAgent') }}</div>
        <span v-if="!agentEnabled" class="badge badge-ghost">{{ $t('disabled') }}</span>
        <span v-else class="badge" :class="status.ok ? 'badge-success' : 'badge-error'">
          {{ status.ok ? $t('online') : $t('offline') }}
        </span>
        <span v-if="agentEnabled && status.ok && status.tc" class="badge badge-success">tc</span>
        <span v-if="agentEnabled && status.ok && !status.tc" class="badge badge-warning">no-tc</span>
      </div>

      <div class="flex items-center gap-2">
        <button type="button" class="btn btn-sm" @click="refresh">{{ $t('test') }}</button>
        <button
          type="button"
          class="btn btn-sm btn-outline"
          @click="runBackup"
          :disabled="!agentEnabled || !status.ok || backupLoading || backup.running"
          :title="$t('agentBackupNow')"
        >
          <span v-if="backupLoading || backup.running" class="loading loading-spinner loading-xs"></span>
          <span v-else>{{ $t('agentBackup') }}</span>
        </button>
      </div>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
      <label class="flex items-center justify-between gap-2">
        <span class="text-sm">{{ $t('enable') }}</span>
        <input type="checkbox" class="toggle" v-model="agentEnabled" />
      </label>

      <label class="flex items-center justify-between gap-2">
        <span class="text-sm">{{ $t('enforceBandwidth') }}</span>
        <input type="checkbox" class="toggle" v-model="agentEnforceBandwidth" :disabled="!agentEnabled" />
      </label>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
      <label class="flex flex-col gap-1">
        <span class="text-sm opacity-70">{{ $t('agentUrl') }}</span>
        <input class="input input-sm" v-model="agentUrl" placeholder="http://192.168.1.1:9099" :disabled="!agentEnabled" />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm opacity-70">{{ $t('agentToken') }}</span>
        <input class="input input-sm" v-model="agentToken" placeholder="(optional)" :disabled="!agentEnabled" />
      </label>
    </div>

        <div class="text-xs opacity-70">
      <div v-if="agentEnabled && status.ok">
        {{ $t('agentDetected') }}: {{ status.lan || 'br0' }} → {{ status.wan || 'eth4' }}
        <div v-if="status.version || status.serverVersion" class="mt-0.5 flex flex-wrap items-center gap-2">
          <span v-if="status.version" class="font-mono">v{{ status.version }}</span>
          <span v-if="status.serverVersion" class="opacity-60">
            latest <span class="font-mono">{{ status.serverVersion }}</span>
          </span>
          <span v-if="needsUpdate" class="badge badge-warning badge-sm">{{ $t('agentUpdate') }}</span>
          <span v-else-if="isAhead" class="badge badge-info badge-sm">{{ $t('agentAhead') }}</span>
        </div>

        <div class="mt-1">
          <div class="flex flex-wrap items-center gap-2">
            <span class="opacity-60">{{ $t('agentBackupLast') }}:</span>
            <span v-if="backup.running" class="badge badge-info badge-sm">{{ $t('agentBackupRunning') }}</span>
            <span v-else-if="backup.success" class="badge badge-success badge-sm">{{ $t('agentBackupOk') }}</span>
            <span v-else-if="backup.finishedAt || backup.startedAt" class="badge badge-warning badge-sm">{{ $t('agentBackupFail') }}</span>
            <span v-if="backup.finishedAt || backup.startedAt" class="font-mono">{{ backup.finishedAt || backup.startedAt }}</span>
            <span v-if="backup.file" class="opacity-60 font-mono">{{ backup.file }}</span>
            <button type="button" class="btn btn-ghost btn-xs" @click="refreshBackup" :disabled="backupLoading">↻</button>
          </div>
          <details class="mt-1" @toggle="onBackupLogToggle">
            <summary class="cursor-pointer text-xs opacity-80">{{ $t('agentBackupViewLog') }}</summary>
            <pre class="mt-1 max-h-40 overflow-auto whitespace-pre-wrap rounded-lg bg-base-200/60 p-2 text-[11px]">{{ backupLog || '…' }}</pre>
          </details>

          <div class="mt-2 rounded-lg bg-base-200/70 p-2 text-xs">
            <div class="flex flex-wrap items-center gap-2">
              <span class="opacity-60">{{ $t('agentBackupCloud') }}:</span>
              <span v-if="cloudStatus.cloudReady" class="badge badge-success badge-sm">{{ $t('agentBackupCloudReady') }}</span>
              <span v-else-if="cloudStatus.rcloneInstalled && cloudStatus.remote && !cloudStatus.remoteExists" class="badge badge-warning badge-sm">{{ $t('agentBackupCloudMissingRemote') }}</span>
              <span v-else-if="!cloudStatus.rcloneInstalled" class="badge badge-warning badge-sm">{{ $t('agentBackupCloudMissingRclone') }}</span>
              <span v-else class="badge badge-ghost badge-sm">{{ $t('agentBackupCloudNotReady') }}</span>
              <button type="button" class="btn btn-ghost btn-xs" @click="refreshCloud" :disabled="cloudLoading">↻</button>
            </div>
            <div class="mt-1 grid grid-cols-1 gap-1 sm:grid-cols-2">
              <div>
                <span class="opacity-60">{{ $t('agentBackupCloudRemote') }}:</span>
                <span class="font-mono">{{ cloudRemoteLabel }}</span>
              </div>
              <div>
                <span class="opacity-60">{{ $t('agentBackupCloudKeep') }}:</span>
                <span class="font-mono">{{ cloudKeepLabel }}</span>
              </div>
              <div class="sm:col-span-2" v-if="cloudStatus.configPath">
                <span class="opacity-60">{{ $t('agentBackupCloudConfig') }}:</span>
                <span class="font-mono break-all">{{ cloudStatus.configPath }}</span>
              </div>
            </div>
          </div>

          <details class="mt-2" @toggle="onBackupHistoryToggle">
            <summary class="cursor-pointer text-xs opacity-80">{{ $t('agentBackupHistory') }}</summary>
            <div class="mt-2 rounded-lg bg-base-200/60 p-2 text-xs">
              <div class="flex flex-wrap items-center gap-2">
                <span class="opacity-60">{{ $t('agentBackupCount') }}:</span>
                <span class="font-mono">{{ backupList.length }}</span>
                <span class="opacity-60">{{ $t('agentBackupFolder') }}:</span>
                <span class="font-mono break-all">{{ backupDir || '—' }}</span>
                <button type="button" class="btn btn-ghost btn-xs" @click="refreshBackupList" :disabled="backupListLoading">↻</button>
              </div>

              <div v-if="backupList.length" class="mt-2 max-h-56 overflow-auto rounded-lg border border-base-300/50 bg-base-100/70">
                <div
                  v-for="item in backupList"
                  :key="item.name"
                  class="flex flex-col gap-1 border-b border-base-300/50 px-3 py-2 last:border-b-0 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="truncate font-mono text-[11px] sm:text-xs">{{ item.name }}</span>
                      <span v-if="isCurrentBackup(item.name)" class="badge badge-info badge-sm">{{ $t('agentBackupCurrent') }}</span>
                      <span v-if="isUploadedBackup(item.name)" class="badge badge-success badge-sm">{{ $t('agentBackupUploaded') }}</span>
                    </div>
                    <div class="mt-1 flex flex-wrap items-center gap-3 opacity-70">
                      <span>{{ formatBackupSize(item.size) }}</span>
                      <span class="font-mono">{{ formatBackupTime(item.mtime) }}</span>
                    </div>
                  </div>

                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs"
                      @click="selectBackupForRestore(item.name)"
                      :disabled="!agentEnabled || !status.ok || backup.running || restore.running || deleteLoadingName === item.name"
                    >
                      {{ $t('agentBackupUseForRestore') }}
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error"
                      @click="deleteBackup(item.name)"
                      :disabled="!agentEnabled || !status.ok || backup.running || restore.running || deleteLoadingName === item.name"
                    >
                      <span v-if="deleteLoadingName === item.name" class="loading loading-spinner loading-xs"></span>
                      <span v-else>{{ $t('delete') }}</span>
                    </button>
                  </div>
                </div>
              </div>

              <div v-else class="mt-2 opacity-70">{{ $t('agentBackupNoItems') }}</div>
            </div>
          </details>

          <details class="mt-2" @toggle="onCronToggle">
            <summary class="cursor-pointer text-xs opacity-80">{{ $t('agentBackupSchedule') }}</summary>
            <div class="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2">
              <label class="flex items-center justify-between gap-2">
                <span class="text-xs opacity-80">{{ $t('agentBackupAuto') }}</span>
                <input type="checkbox" class="toggle toggle-sm" v-model="backupAutoEnabled" :disabled="!agentEnabled || !status.ok" />
              </label>
              <label class="flex items-center justify-between gap-2">
                <span class="text-xs opacity-80">{{ $t('agentBackupTime') }}</span>
                <input type="time" class="input input-sm w-28" v-model="backupAutoTime" :disabled="!agentEnabled || !status.ok" />
              </label>
            </div>

            <div class="mt-2 text-xs">
              <div class="flex flex-wrap items-center gap-2">
                <span class="opacity-60">{{ $t('agentBackupCron') }}:</span>
                <span class="font-mono">{{ cronSchedule }}</span>
                <button type="button" class="btn btn-ghost btn-xs" @click="copyCron" :disabled="!cronLine">{{ $t('copy') }}</button>
              </div>
              <div class="mt-1 font-mono rounded-lg bg-base-200/60 p-2 text-[11px] break-all">{{ cronLine }}</div>

              <div class="mt-2 flex flex-wrap items-center gap-2">
                <button type="button" class="btn btn-xs" @click="applyCron" :disabled="!agentEnabled || !status.ok || cronApplying">
                  <span v-if="cronApplying" class="loading loading-spinner loading-xs"></span>
                  <span v-else>{{ $t('apply') }}</span>
                </button>
                <button type="button" class="btn btn-xs btn-outline" @click="removeCron" :disabled="!agentEnabled || !status.ok || cronApplying">{{ $t('delete') }}</button>
                <button type="button" class="btn btn-ghost btn-xs" @click="refreshCron" :disabled="cronApplying">↻</button>

                <span class="opacity-60">{{ $t('agentBackupCronOnRouter') }}:</span>
                <span v-if="cronStatus.ok && cronStatus.enabled" class="badge badge-success badge-sm">on</span>
                <span v-else-if="cronStatus.ok && cronStatus.enabled === false" class="badge badge-ghost badge-sm">off</span>
                <span v-else class="badge badge-warning badge-sm">?</span>
                <span v-if="cronStatus.ok && cronStatus.schedule" class="font-mono opacity-70">{{ cronStatus.schedule }}</span>
              </div>
            </div>


          </details>

          <details class="mt-2" @toggle="onRestoreToggle">
  <summary class="cursor-pointer text-xs opacity-80">{{ $t('agentRestore') }}</summary>

  <div class="mt-2">
    <div class="flex flex-wrap items-center gap-2 text-xs">
      <span class="opacity-60">{{ $t('agentRestoreLast') }}:</span>
      <span v-if="restore.running" class="badge badge-info badge-sm">{{ $t('agentRestoreRunning') }}</span>
      <span v-else-if="restore.success" class="badge badge-success badge-sm">{{ $t('agentRestoreOk') }}</span>
      <span v-else-if="restore.finishedAt || restore.startedAt" class="badge badge-warning badge-sm">{{ $t('agentRestoreFail') }}</span>
      <span v-if="restore.finishedAt || restore.startedAt" class="font-mono">{{ restore.finishedAt || restore.startedAt }}</span>
      <span v-if="restore.file" class="opacity-60 font-mono">{{ restore.file }}</span>
      <button type="button" class="btn btn-ghost btn-xs" @click="refreshRestore" :disabled="restoreLoading">↻</button>
    </div>

    <div class="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2">
      <label class="flex flex-col gap-1">
        <span class="text-xs opacity-80">{{ $t('agentRestoreFrom') }}</span>
        <select class="select select-sm" v-model="restoreSelected" :disabled="!agentEnabled || !status.ok || restoreLoading || restore.running">
          <option value="latest">{{ $t('agentBackupLatest') }}</option>
          <option v-for="b in backupList" :key="b.name" :value="b.name">{{ b.name }}</option>
        </select>
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs opacity-80">{{ $t('agentRestoreScope') }}</span>
        <select class="select select-sm" v-model="restoreScope" :disabled="!agentEnabled || !status.ok || restoreLoading || restore.running">
          <option value="all">{{ $t('agentRestoreScopeAll') }}</option>
          <option value="mihomo">{{ $t('agentRestoreScopeMihomo') }}</option>
          <option value="agent">{{ $t('agentRestoreScopeAgent') }}</option>
        </select>
      </label>
    </div>

    <div class="mt-2 flex flex-wrap items-center justify-between gap-2">
      <label class="flex items-center gap-2 text-xs">
        <input type="checkbox" class="checkbox checkbox-sm" v-model="restoreIncludeEnv" :disabled="!agentEnabled || !status.ok || restoreLoading || restore.running" />
        <span class="opacity-80">{{ $t('agentRestoreIncludeEnv') }}</span>
      </label>

      <button
        type="button"
        class="btn btn-xs btn-warning"
        @click="runRestore"
        :disabled="!agentEnabled || !status.ok || restoreLoading || restore.running"
        :title="$t('agentRestoreNow')"
      >
        <span v-if="restoreLoading || restore.running" class="loading loading-spinner loading-xs"></span>
        <span v-else>{{ $t('agentRestoreNow') }}</span>
      </button>
    </div>

    <div class="mt-2 text-xs opacity-70">
      {{ $t('agentRestoreTip') }}
    </div>

    <details class="mt-1" @toggle="onRestoreLogToggle">
      <summary class="cursor-pointer text-xs opacity-80">{{ $t('agentRestoreViewLog') }}</summary>
      <pre class="mt-1 max-h-40 overflow-auto whitespace-pre-wrap rounded-lg bg-base-200/60 p-2 text-[11px]">{{ restoreLog || '…' }}</pre>
    </details>
  </div>
</details>

        </div>
      </div>
      <div v-else-if="agentEnabled && !status.ok">
        {{ $t('agentOfflineTip') }}
      </div>
      <div v-else>
        {{ $t('agentDisabledTip') }}
      </div>
    </div>

  </div>
</template>

<script setup lang="ts">
import {
  agentBackupCloudStatusAPI,
  agentBackupCronGetAPI,
  agentBackupCronSetAPI,
  agentBackupDeleteAPI,
  agentBackupListAPI,
  agentBackupLogAPI,
  agentBackupStartAPI,
  agentBackupStatusAPI,
  agentRestoreLogAPI,
  agentRestoreStartAPI,
  agentRestoreStatusAPI,
  agentStatusAPI,
} from '@/api/agent'
import {
  agentBackupAutoEnabled,
  agentBackupAutoTime,
  agentEnabled,
  agentEnforceBandwidth,
  agentToken,
  agentUrl,
} from '@/store/agent'
import { prettyBytesHelper } from '@/helper/utils'
import { showNotification } from '@/helper/notification'
import dayjs from 'dayjs'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'

const status = ref<{ ok: boolean; version?: string; serverVersion?: string; tc?: boolean; wan?: string; lan?: string }>({ ok: false })

// Aliases for template readability (these are persisted refs via useStorage).
const backupAutoEnabled = agentBackupAutoEnabled
const backupAutoTime = agentBackupAutoTime

// Cron state from router.
const cronStatus = ref<any>({ ok: false, enabled: false })
const cronApplying = ref(false)

// Convert HH:MM -> "M H * * *". Fallback to 04:00.
const cronSchedule = computed(() => {
  const raw = String(backupAutoTime.value || '04:00').trim()
  const m = raw.match(/^(\d{1,2}):(\d{2})$/)
  const hh = m ? Number(m[1]) : 4
  const mm = m ? Number(m[2]) : 0

  const H = Number.isFinite(hh) ? Math.min(23, Math.max(0, Math.floor(hh))) : 4
  const M = Number.isFinite(mm) ? Math.min(59, Math.max(0, Math.floor(mm))) : 0
  return `${M} ${H} * * *`
})

// Human-copyable cron line.
const cronLine = computed(() => {
  const s = cronSchedule.value
  if (!s) return ''
  return `${s} /opt/zash-agent/backup.sh >/opt/zash-agent/var/backup.cron.log 2>&1 # zash-backup`
})

const backup = ref<any>({ ok: true, running: false })
const backupLog = ref('')
const backupLoading = ref(false)
const cloudStatus = ref<any>({ ok: true, rcloneInstalled: false, remote: '', path: '' })
const cloudLoading = ref(false)

const backupList = ref<any[]>([])
const backupDir = ref('')
const backupListLoading = ref(false)
const deleteLoadingName = ref('')

const restore = ref<any>({ ok: true, running: false })
const restoreLog = ref('')
const restoreLoading = ref(false)
const restoreSelected = ref<string>('latest')
const restoreScope = ref<string>('all')
const restoreIncludeEnv = ref<boolean>(false)

const { t } = useI18n()

const versionCmp = (a?: string, b?: string) => {
  const as = (a || '').match(/\d+/g)?.map((x) => parseInt(x, 10)) || []
  const bs = (b || '').match(/\d+/g)?.map((x) => parseInt(x, 10)) || []
  const n = Math.max(as.length, bs.length)
  for (let i = 0; i < n; i++) {
    const av = as[i] ?? 0
    const bv = bs[i] ?? 0
    if (av < bv) return -1
    if (av > bv) return 1
  }
  return 0
}

const needsUpdate = computed(() => {
  if (!status.value?.ok || !status.value?.version || !status.value?.serverVersion) return false
  return versionCmp(status.value.version, status.value.serverVersion) < 0
})

const isAhead = computed(() => {
  if (!status.value?.ok || !status.value?.version || !status.value?.serverVersion) return false
  return versionCmp(status.value.version, status.value.serverVersion) > 0
})

const cloudRemoteLabel = computed(() => {
  const remote = String(cloudStatus.value?.remote || '').trim()
  const path = String(cloudStatus.value?.path || '').trim()
  if (!remote) return '—'
  return path ? `${remote}:${path}` : `${remote}:`
})

const cloudKeepLabel = computed(() => {
  const local = String(cloudStatus.value?.localKeepDays || '').trim() || '—'
  const cloud = String(cloudStatus.value?.keepDays || '').trim() || '—'
  return `${local} / ${cloud} d`
})

const currentBackupName = computed(() => {
  const f = String(backup.value?.file || '').trim()
  if (!f) return ''
  const parts = f.split('/')
  return parts[parts.length - 1] || ''
})

const isCurrentBackup = (name: string) => String(name || '') === currentBackupName.value
const isUploadedBackup = (name: string) => isCurrentBackup(name) && !!backup.value?.uploaded

const formatBackupSize = (size?: number) => {
  const n = Number(size)
  if (!Number.isFinite(n) || n <= 0) return '0 B'
  return prettyBytesHelper(n, { binary: true })
}

const formatBackupTime = (mtime?: number) => {
  const n = Number(mtime)
  if (!Number.isFinite(n) || n <= 0) return '—'
  return dayjs(n * 1000).format('YYYY-MM-DD HH:mm:ss')
}

const selectBackupForRestore = (name: string) => {
  restoreSelected.value = name
  showNotification({ content: 'agentBackupUseForRestoreDone', type: 'alert-success', timeout: 1400 })
}

const deleteBackup = async (name: string) => {
  const file = String(name || '').trim()
  if (!file || !agentEnabled.value || !status.value?.ok) return

  const ok = window.confirm(String(t('agentBackupDeleteConfirm', { name: file })))
  if (!ok) return

  deleteLoadingName.value = file
  const res = await agentBackupDeleteAPI(file)
  if (res?.ok && res?.deleted) {
    if (restoreSelected.value === file) restoreSelected.value = 'latest'
    showNotification({ content: 'agentBackupDeleteDone', type: 'alert-success', timeout: 1600 })
    await refreshBackupList()
    await refreshBackup()
  } else {
    showNotification({ content: 'agentBackupDeleteFail', type: 'alert-error', timeout: 2400 })
  }
  deleteLoadingName.value = ''
}

const refreshCloud = async () => {
  if (!agentEnabled.value || !status.value?.ok) {
    cloudStatus.value = { ok: true, rcloneInstalled: false, remote: '', path: '' }
    return
  }
  cloudLoading.value = true
  cloudStatus.value = await agentBackupCloudStatusAPI()
  cloudLoading.value = false
}

const refreshCron = async () => {
  if (!agentEnabled.value) {
    cronStatus.value = { ok: false, enabled: false }
    return
  }
  if (!status.value?.ok) {
    cronStatus.value = { ok: false, enabled: false }
    return
  }
  const res: any = await agentBackupCronGetAPI()
  cronStatus.value = res

  // Best-effort sync from router schedule -> UI fields.
  if (res?.ok) {
    if (typeof res.enabled === 'boolean') backupAutoEnabled.value = res.enabled
    if (typeof res.schedule === 'string' && res.schedule.trim()) {
      const parts = res.schedule.trim().split(/\s+/)
      if (parts.length >= 2) {
        const mm = Number(parts[0])
        const hh = Number(parts[1])
        if (Number.isFinite(mm) && Number.isFinite(hh)) {
          const H = Math.min(23, Math.max(0, Math.floor(hh)))
          const M = Math.min(59, Math.max(0, Math.floor(mm)))
          backupAutoTime.value = `${String(H).padStart(2, '0')}:${String(M).padStart(2, '0')}`
        }
      }
    }
  }
}

const applyCron = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  cronApplying.value = true
  await agentBackupCronSetAPI(!!backupAutoEnabled.value, cronSchedule.value)
  await refreshCron()
  cronApplying.value = false
}

const removeCron = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  cronApplying.value = true
  backupAutoEnabled.value = false
  await agentBackupCronSetAPI(false, cronSchedule.value)
  await refreshCron()
  cronApplying.value = false
}

const copyCron = async () => {
  try {
    await navigator.clipboard.writeText(cronLine.value)
    showNotification({ content: 'copySuccess', type: 'alert-success', timeout: 1400 })
  } catch {
    // ignore
  }
}

const onCronToggle = async (e: any) => {
  if (e?.target?.open) {
    await refreshCron()
  }
}

const refreshBackupList = async () => {
  if (!agentEnabled.value || !status.value?.ok) {
    backupDir.value = ''
    backupList.value = []
    return
  }
  backupListLoading.value = true
  const res = await agentBackupListAPI()
  if (res?.ok && Array.isArray((res as any).items)) {
    backupDir.value = String((res as any).dir || '')
    backupList.value = (res as any).items || []
  } else {
    backupDir.value = String((res as any)?.dir || '')
    backupList.value = []
  }
  backupListLoading.value = false
}

const onBackupHistoryToggle = async (e: any) => {
  if (e?.target?.open) {
    await refreshBackupList()
  }
}

const refreshRestore = async () => {
  if (!agentEnabled.value) {
    restore.value = { ok: false }
    return
  }
  if (!status.value?.ok) {
    restore.value = { ok: true, running: false }
    return
  }
  restoreLoading.value = true
  restore.value = await agentRestoreStatusAPI()
  restoreLoading.value = false
}

const loadRestoreLog = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  const res = await agentRestoreLogAPI(200)
  if (res?.ok && res?.contentB64) {
    try {
      restoreLog.value = atob(res.contentB64)
    } catch {
      restoreLog.value = ''
    }
  } else {
    restoreLog.value = res?.error ? String(res.error) : ''
  }
}

const onRestoreLogToggle = async (e: any) => {
  if (e?.target?.open) {
    await loadRestoreLog()
  }
}

const onRestoreToggle = async (e: any) => {
  if (e?.target?.open) {
    await refreshBackupList()
    await refreshRestore()
  }
}

const runRestore = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  const file = restoreSelected.value || 'latest'
  const scope = restoreScope.value || 'all'
  const includeEnv = !!restoreIncludeEnv.value

  const ok = window.confirm(String(t('agentRestoreConfirm')))
  if (!ok) return

  restoreLoading.value = true
  const res = await agentRestoreStartAPI(file, scope, includeEnv)
  if (!res?.ok) {
    showNotification({ content: 'agentRestoreFail', type: 'alert-error', timeout: 2200 })
  }
  await refreshRestore()
  restoreLoading.value = false
}

const refreshBackup = async () => {
  if (!agentEnabled.value) {
    backup.value = { ok: false }
    return
  }
  if (!status.value?.ok) {
    backup.value = { ok: true, running: false }
    return
  }
  backupLoading.value = true
  backup.value = await agentBackupStatusAPI()
  backupLoading.value = false
}

const runBackup = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  backupLoading.value = true
  await agentBackupStartAPI()
  await refreshBackup()
  await refreshBackupList()
  backupLoading.value = false
}

const loadBackupLog = async () => {
  if (!agentEnabled.value || !status.value?.ok) return
  const res = await agentBackupLogAPI(200)
  if (res?.ok && res?.contentB64) {
    try {
      backupLog.value = atob(res.contentB64)
    } catch {
      backupLog.value = ''
    }
  } else {
    backupLog.value = res?.error ? String(res.error) : ''
  }
}

const onBackupLogToggle = async (e: any) => {
  if (e?.target?.open) {
    await loadBackupLog()
  }
}

const refresh = async () => {
  if (!agentEnabled.value) {
    status.value = { ok: false }
    return
  }
  status.value = await agentStatusAPI()
  await refreshBackup()
  await refreshCloud()
  await refreshBackupList()
  await refreshRestore()
}

onMounted(() => {
  refresh()
})
</script>
