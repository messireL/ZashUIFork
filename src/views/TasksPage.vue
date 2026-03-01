<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('quickActions') }}</div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" @click="applyEnforcement" :disabled="busy">
          {{ $t('applyEnforcementNow') }}
        </button>
        <button type="button" class="btn btn-sm" @click="refreshSsl" :disabled="busy || !agentEnabled">
          {{ $t('refreshProvidersSsl') }}
        </button>
      </div>

      <div class="text-xs opacity-70">
        <div>• {{ $t('applyEnforcementTip') }}</div>
        <div>• {{ $t('refreshProvidersSslTip') }}</div>
      </div>
    </div>

    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('liveLogs') }}</div>
        <div class="flex items-center gap-2">
          <select class="select select-bordered select-sm" v-model="logSource">
            <option value="mihomo">{{ $t('mihomoLog') }}</option>
            <option value="config">{{ $t('mihomoConfig') }}</option>
            <option value="agent">{{ $t('agentLog') }}</option>
          </select>
          <select class="select select-bordered select-sm" v-model.number="logLines">
            <option :value="50">50</option>
            <option :value="200">200</option>
            <option :value="500">500</option>
            <option :value="1000">1000</option>
          </select>
          <button type="button" class="btn btn-sm" @click="refreshLogs" :disabled="logsBusy || !agentEnabled">
            {{ $t('refresh') }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2 text-xs opacity-70">
        <div>
          <span class="opacity-60">{{ $t('path') }}:</span>
          <span class="font-mono">{{ logPath || '—' }}</span>
        </div>
        <label class="flex items-center gap-2">
          <span>{{ $t('autoRefresh') }}</span>
          <input type="checkbox" class="toggle toggle-sm" v-model="logsAuto" />
        </label>
      </div>

      <div v-if="!agentEnabled" class="text-sm opacity-70">
        {{ $t('agentDisabled') }}
      </div>
      <div v-else class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <pre class="max-h-[48vh] overflow-auto whitespace-pre-wrap break-words font-mono text-[11px] leading-4">{{ logText || '—' }}</pre>
      </div>
    </div>

    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('operationsHistory') }}</div>
        <button type="button" class="btn btn-sm btn-ghost" @click="clearJobs" :disabled="!jobs.length">
          {{ $t('clear') }}
        </button>
      </div>

      <div v-if="!jobs.length" class="text-sm opacity-70">
        {{ $t('noOperationsYet') }}
      </div>

      <div v-else class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th style="width: 140px">{{ $t('time') }}</th>
              <th>{{ $t('operation') }}</th>
              <th style="width: 120px">{{ $t('status') }}</th>
              <th style="width: 110px">{{ $t('duration') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="j in jobs" :key="j.id">
              <td class="font-mono text-xs">{{ fmtTime(j.startedAt) }}</td>
              <td>
                <div class="text-sm">{{ j.title }}</div>
                <div v-if="j.error" class="text-xs text-error">{{ j.error }}</div>
                <div v-else-if="j.meta && Object.keys(j.meta).length" class="text-[11px] opacity-70">
                  <span v-for="(v, k) in j.meta" :key="k" class="mr-2">
                    <span class="opacity-60">{{ k }}:</span>
                    <span class="font-mono">{{ v }}</span>
                  </span>
                </div>
              </td>
              <td>
                <span v-if="j.endedAt && j.ok" class="badge badge-success">{{ $t('done') }}</span>
                <span v-else-if="j.endedAt && j.ok === false" class="badge badge-error">{{ $t('failed') }}</span>
                <span v-else class="badge badge-warning">{{ $t('running') }}</span>
              </td>
              <td class="font-mono text-xs">
                {{ j.endedAt ? fmtMs(j.endedAt - j.startedAt) : '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="flex-1"></div>

    <div class="card items-center justify-center gap-2 p-2 sm:flex-row">
      {{ getLabelFromBackend(activeBackend!) }} :
      <BackendVersion />
    </div>
  </div>
</template>

<script setup lang="ts">
import { agentLogsAPI, agentMihomoProvidersAPI } from '@/api/agent'
import BackendVersion from '@/components/common/BackendVersion.vue'
import { getLabelFromBackend } from '@/helper/utils'
import { showNotification } from '@/helper/notification'
import { decodeB64Utf8 } from '@/helper/b64'
import { activeBackend } from '@/store/setup'
import { agentEnabled } from '@/store/agent'
import { clearJobs, finishJob, jobHistory, startJob } from '@/store/jobs'
import { applyUserEnforcementNow } from '@/composables/userLimits'
import dayjs from 'dayjs'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

const busy = ref(false)
const jobs = computed(() => jobHistory.value || [])

// --- Live logs (router-agent) ---
const logSource = ref<'mihomo' | 'config' | 'agent'>('mihomo')
const logLines = ref<number>(200)
const logsAuto = ref(true)
const logsBusy = ref(false)
const logText = ref('')
const logPath = ref('')

let logTimer: any = null
const refreshLogs = async () => {
  if (!agentEnabled.value) return
  if (logsBusy.value) return
  logsBusy.value = true
  try {
    const r: any = await agentLogsAPI({ type: logSource.value, lines: logLines.value })
    if (!r?.ok) {
      logText.value = r?.error || 'failed'
      return
    }
    logPath.value = r?.path || ''
    logText.value = decodeB64Utf8(r?.contentB64) || ''
  } finally {
    logsBusy.value = false
  }
}

const stopTimer = () => {
  if (logTimer) {
    clearInterval(logTimer)
    logTimer = null
  }
}

const startTimer = () => {
  stopTimer()
  if (!logsAuto.value) return
  if (!agentEnabled.value) return
  logTimer = setInterval(() => {
    refreshLogs()
  }, 2000)
}

onMounted(() => {
  refreshLogs()
  startTimer()
})

onBeforeUnmount(() => {
  stopTimer()
})

watch([logsAuto, logSource, logLines, agentEnabled], () => {
  refreshLogs()
  startTimer()
})

const fmtTime = (ts: number) => dayjs(ts).format('HH:mm:ss')
const fmtMs = (ms: number) => {
  if (!Number.isFinite(ms)) return '—'
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

const applyEnforcement = async () => {
  if (busy.value) return
  busy.value = true
  try {
    const id = startJob('Apply limits & blocks')
    try {
      await applyUserEnforcementNow()
      finishJob(id, { ok: true })
      showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
    } catch (e: any) {
      finishJob(id, { ok: false, error: e?.message || 'failed' })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
    }
  } finally {
    busy.value = false
  }
}

const refreshSsl = async () => {
  if (busy.value) return
  if (!agentEnabled.value) {
    showNotification({ content: 'agentDisabled', type: 'alert-warning', timeout: 2000 })
    return
  }
  busy.value = true
  try {
    const id = startJob('Refresh providers SSL')
    try {
      const r: any = await agentMihomoProvidersAPI(true)
      if (!r?.ok) {
        finishJob(id, { ok: false, error: r?.error || 'failed' })
        showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
        return
      }
      const n = Array.isArray(r?.providers) ? r.providers.length : 0
      finishJob(id, { ok: true, meta: { providers: n } })
      showNotification({ content: 'sslRefreshed', type: 'alert-success', timeout: 1600 })
    } catch (e: any) {
      finishJob(id, { ok: false, error: e?.message || 'failed' })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
    }
  } finally {
    busy.value = false
  }
}
</script>
