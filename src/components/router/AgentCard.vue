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
  agentBackupCronGetAPI,
  agentBackupCronSetAPI,
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
import { showNotification } from '@/helper/notification'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'

const status = ref<{ ok: boolean; version?: string; serverVersion?: string; tc?: boolean; wan?: string; lan?: string }>({ ok: false })

const backup = ref<any>({ ok: true, running: false })
const backupLog = ref('')
const backupLoading = ref(false)

const backupList = ref<any[]>([])

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


const refreshCron = async () => {
  if (!agentEnabled.value) {
    cronStatus.value = { ok: false, enabled: false }
    return
  }
  if (!status.value?.ok) {
    cronStatus.value = { ok: false, enabled: false }
    return
  }
  cronStatus.value = await agentBackupCronGetAPI()
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
    backupList.value = []
    return
  }
  const res = await agentBackupListAPI()
  if (res?.ok && Array.isArray((res as any).items)) {
    backupList.value = (res as any).items || []
  } else {
    backupList.value = []
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
  await refreshRestore()
}

onMounted(() => {
  refresh()
})
</script>
