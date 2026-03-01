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
          <button type="button" class="btn btn-sm" @click="forceRefreshLogs" :disabled="logsBusy || !agentEnabled">
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
        <div class="font-semibold">{{ $t('dataFreshness') }}</div>
        <button type="button" class="btn btn-sm btn-ghost" @click="refreshFreshness" :disabled="freshnessBusy">
          {{ $t('refresh') }}
        </button>
      </div>

      <div class="grid gap-2 md:grid-cols-2">
        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('geoFiles') }}</div>
          <div v-if="!agentEnabled" class="text-sm opacity-70">
            {{ $t('agentDisabled') }}
          </div>
          <div v-else-if="geoBusy" class="text-sm opacity-70">…</div>
          <div v-else>
            <div v-if="geoError" class="text-xs text-error">{{ geoError }}</div>
            <div v-else-if="!geoItems.length" class="text-sm opacity-70">—</div>
            <div v-else class="flex flex-col gap-1">
              <div v-for="g in geoItems" :key="g.kind + ':' + g.path" class="flex items-center justify-between gap-2 text-xs">
                <div class="min-w-0">
                  <span class="opacity-70">{{ geoKindLabel(g.kind) }}:</span>
                  <span class="ml-1 font-mono opacity-70" :title="g.path">{{ shortPath(g.path) }}</span>
                  <span v-if="typeof g.sizeBytes === 'number' && g.sizeBytes >= 0" class="ml-2 opacity-60">({{ prettyBytesHelper(g.sizeBytes) }})</span>
                </div>
                <div class="shrink-0 font-mono opacity-80">{{ fmtMtime(g.mtimeSec) }}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('filterPoliciesFiles') }}</div>
          <div v-if="providersBusy" class="text-sm opacity-70">…</div>
          <div v-else>
            <div v-if="!ruleProviders.length" class="text-sm opacity-70">—</div>
            <div v-else class="flex flex-col gap-1 text-xs">
              <div>
                <span class="opacity-70">{{ $t('ruleProvidersCount') }}:</span>
                <span class="ml-1 font-mono">{{ ruleProviders.length }}</span>
              </div>
              <div>
                <span class="opacity-70">{{ $t('newestUpdate') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(newestProviderAt) }}</span>
              </div>
              <div>
                <span class="opacity-70">{{ $t('oldestUpdate') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(oldestProviderAt) }}</span>
              </div>
              <details class="mt-1">
                <summary class="cursor-pointer opacity-80">{{ $t('showList') }}</summary>
                <div class="mt-2 flex flex-col gap-1">
                  <div v-for="p in sortedProviders" :key="p.name" class="flex items-center justify-between gap-2">
                    <span class="min-w-0 truncate font-mono" :title="p.name">{{ p.name }}</span>
                    <span class="shrink-0 font-mono opacity-70">{{ fmtUpdatedAt(p.updatedAt) }}</span>
                  </div>
                </div>
              </details>
            </div>

            <div v-if="agentEnabled" class="mt-2 border-t border-base-content/10 pt-2">
              <div class="mb-1 text-xs font-semibold opacity-80">{{ $t('localRulesDir') }}</div>
              <div v-if="rulesBusy" class="text-sm opacity-70">…</div>
              <div v-else>
                <div v-if="rulesError" class="text-xs text-error">{{ rulesError }}</div>
                <div v-else-if="!rulesDir" class="text-sm opacity-70">—</div>
                <div v-else class="flex flex-col gap-1 text-xs">
                  <div>
                    <span class="opacity-70">{{ $t('path') }}:</span>
                    <span class="ml-1 font-mono" :title="rulesDir">{{ shortPath(rulesDir) }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('filesCount') }}:</span>
                    <span class="ml-1 font-mono">{{ rulesCount }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('newestUpdate') }}:</span>
                    <span class="ml-1 font-mono">{{ fmtMtime(rulesNewest) }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('oldestUpdate') }}:</span>
                    <span class="ml-1 font-mono">{{ fmtMtime(rulesOldest) }}</span>
                  </div>

                  <details v-if="rulesItems.length" class="mt-1">
                    <summary class="cursor-pointer opacity-80">{{ $t('showList') }}</summary>
                    <div class="mt-2 flex flex-col gap-1">
                      <div v-for="f in rulesItems" :key="f.path" class="flex items-center justify-between gap-2">
                        <span class="min-w-0 truncate font-mono" :title="f.path">{{ f.name || shortPath(f.path) }}</span>
                        <span class="shrink-0 font-mono opacity-70">{{ fmtMtime(f.mtimeSec) }}</span>
                      </div>
                    </div>
                  </details>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="text-[11px] opacity-60">
        {{ $t('dataFreshnessTip') }}
      </div>
    </div>


    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('diagnostics') }}</div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" @click="downloadDiagnostics" :disabled="diagBusy">
          {{ $t('downloadReport') }}
        </button>
        <button type="button" class="btn btn-sm btn-ghost" @click="copyDiagnostics" :disabled="diagBusy">
          {{ $t('copy') }}
        </button>
      </div>

      <div class="text-xs opacity-70">
        {{ $t('diagnosticsTip') }}
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
import { fetchRuleProvidersAPI, zashboardVersion, version as coreVersion } from '@/api'
import { agentGeoInfoAPI, agentLogsAPI, agentLogsFollowAPI, agentMihomoProvidersAPI, agentRulesInfoAPI, agentStatusAPI } from '@/api/agent'
import BackendVersion from '@/components/common/BackendVersion.vue'
import { getLabelFromBackend, prettyBytesHelper } from '@/helper/utils'
import { showNotification } from '@/helper/notification'
import { decodeB64Utf8 } from '@/helper/b64'
import { activeBackend } from '@/store/setup'
import { agentEnabled, agentUrl } from '@/store/agent'
import { userLimitProfiles } from '@/store/userLimitProfiles'
import { userLimitSnapshots } from '@/store/userLimitSnapshots'
import { autoDisconnectLimitedUsers, hardBlockLimitedUsers, managedLanDisallowedCidrs, userLimits } from '@/store/userLimits'
import { activeConnections } from '@/store/connections'
import { clearJobs, finishJob, jobHistory, startJob } from '@/store/jobs'
import { applyUserEnforcementNow, getUserLimitState } from '@/composables/userLimits'
import dayjs from 'dayjs'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { RuleProvider } from '@/types'
import { useI18n } from 'vue-i18n'

const busy = ref(false)
const jobs = computed(() => jobHistory.value || [])

// --- Live logs (router-agent) ---
const logSource = ref<'mihomo' | 'config' | 'agent'>('mihomo')
const logLines = ref<number>(200)
const logsAuto = ref(true)
const logsBusy = ref(false)
const logText = ref('')
const logPath = ref('')
const logOffset = ref(0)
const logMode = ref<'poll' | 'delta' | 'full'>('poll')

let logTimer: any = null
const refreshLogs = async () => {
  if (!agentEnabled.value) return
  if (logsBusy.value) return
  logsBusy.value = true
  try {
    if (logSource.value === 'config') {
      const r: any = await agentLogsAPI({ type: 'config', lines: logLines.value })
      logMode.value = 'full'
      logOffset.value = 0
      if (!r?.ok) {
        logText.value = r?.error || 'failed'
        return
      }
      logPath.value = r?.path || ''
      logText.value = decodeB64Utf8(r?.contentB64) || ''
      return
    }

    // Prefer efficient incremental follow (agent >= 0.5.3). Fallback to full polling on older agents.
    const r: any = await agentLogsFollowAPI({ type: logSource.value as any, lines: logLines.value, offset: logOffset.value })
    if (r?.ok) {
      logPath.value = r?.path || ''
      const chunk = decodeB64Utf8(r?.contentB64) || ''
      const mode = (r?.mode || 'delta') as 'full' | 'delta'
      logMode.value = mode
      const newOffset = typeof r?.offset === 'number' ? r.offset : logOffset.value
      const resetLike = logOffset.value === 0 || mode === 'full' || newOffset < logOffset.value
      if (resetLike) logText.value = chunk
      else logText.value = (logText.value || '') + chunk
      logOffset.value = newOffset

      // Keep last N lines (avoid runaway memory).
      const maxLines = Math.min(2000, Math.max(50, logLines.value || 200))
      const arr = (logText.value || '').split(/\r?\n/)
      if (arr.length > maxLines) logText.value = arr.slice(-maxLines).join('\n')
      return
    }

    // Fallback: full fetch
    const r2: any = await agentLogsAPI({ type: logSource.value, lines: logLines.value })
    logMode.value = 'poll'
    logOffset.value = 0
    if (!r2?.ok) {
      logText.value = r2?.error || 'failed'
      return
    }
    logPath.value = r2?.path || ''
    logText.value = decodeB64Utf8(r2?.contentB64) || ''
  } finally {
    logsBusy.value = false
  }
}

const forceRefreshLogs = () => {
  logOffset.value = 0
  logText.value = ''
  refreshLogs()
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
  refreshFreshness()
})

onBeforeUnmount(() => {
  stopTimer()
})

watch([logsAuto, logSource, logLines, agentEnabled], () => {
  logOffset.value = 0
  refreshLogs()
  startTimer()
})


// --- Data freshness (GEO files + filter policy files) ---
const { t } = useI18n()

type GeoInfoItem = {
  kind: string
  path: string
  exists: boolean
  mtimeSec?: number
  sizeBytes?: number
}

const geoBusy = ref(false)
const geoError = ref('')
const geoItems = ref<GeoInfoItem[]>([])

const providersBusy = ref(false)
const ruleProviders = ref<RuleProvider[]>([])

const sortedProviders = computed(() => {
  return [...(ruleProviders.value || [])].sort((a, b) => {
    const ta = dayjs(a.updatedAt).valueOf()
    const tb = dayjs(b.updatedAt).valueOf()
    return tb - ta
  })
})

const newestProviderAt = computed(() => sortedProviders.value[0]?.updatedAt || '')
const oldestProviderAt = computed(() => {
  const arr = [...(ruleProviders.value || [])].sort(
    (a, b) => dayjs(a.updatedAt).valueOf() - dayjs(b.updatedAt).valueOf(),
  )
  return arr[0]?.updatedAt || ''
})

const geoKindLabel = (kind: string) => {
  const k = (kind || '').toLowerCase()
  if (k === 'geoip') return t('geoipFile')
  if (k === 'geosite') return t('geositeFile')
  if (k === 'asn') return t('asnMmdbFile')
  if (k === 'mmdb') return t('mmdbFile')
  return kind || '—'
}

const fmtMtime = (mtimeSec?: number) => {
  if (!mtimeSec || !Number.isFinite(mtimeSec)) return '—'
  return dayjs.unix(mtimeSec).format('DD-MM-YYYY HH:mm:ss')
}

const fmtUpdatedAt = (s?: string) => {
  const d = dayjs(s || '')
  if (!d.isValid()) return '—'
  return d.format('DD-MM-YYYY HH:mm:ss')
}

const shortPath = (p?: string) => {
  const s = (p || '').trim()
  if (!s) return '—'
  const parts = s.split('/').filter(Boolean)
  if (parts.length <= 3) return s
  return `…/${parts.slice(-3).join('/')}`
}

const refreshGeoInfo = async () => {
  geoError.value = ''
  geoItems.value = []
  if (!agentEnabled.value) return
  geoBusy.value = true
  try {
    const r: any = await agentGeoInfoAPI()
    if (!r?.ok) {
      geoError.value = r?.error || 'failed'
      return
    }
    const items = Array.isArray(r?.items) ? r.items : []
    geoItems.value = items
      .filter((x: any) => x && x.path)
      .map((x: any) => ({
        kind: String(x.kind || ''),
        path: String(x.path || ''),
        exists: !!x.exists,
        mtimeSec:
          typeof x.mtimeSec === 'number' ? x.mtimeSec : Number(x.mtimeSec || 0) || undefined,
        sizeBytes:
          typeof x.sizeBytes === 'number' ? x.sizeBytes : Number(x.sizeBytes || 0) || undefined,
      }))
      .filter((x) => x.exists)
      .sort((a, b) => (a.kind || '').localeCompare(b.kind || ''))
  } catch (e: any) {
    geoError.value = e?.message || 'failed'
  } finally {
    geoBusy.value = false
  }
}

const refreshRuleProviders = async () => {
  providersBusy.value = true
  try {
    const { data } = await fetchRuleProvidersAPI()
    ruleProviders.value = Object.values((data as any)?.providers || {})
  } catch {
    ruleProviders.value = []
  } finally {
    providersBusy.value = false
  }
}

// Local rules directory (XKeen/mihomo rules folder)
const rulesBusy = ref(false)
const rulesError = ref('')
const rulesDir = ref('')
const rulesCount = ref(0)
const rulesNewest = ref<number | undefined>(undefined)
const rulesOldest = ref<number | undefined>(undefined)
const rulesItems = ref<Array<{ name: string; path: string; mtimeSec?: number; sizeBytes?: number }>>([])

const refreshRulesInfo = async () => {
  rulesError.value = ''
  rulesDir.value = ''
  rulesCount.value = 0
  rulesNewest.value = undefined
  rulesOldest.value = undefined
  rulesItems.value = []
  if (!agentEnabled.value) return
  rulesBusy.value = true
  try {
    const r: any = await agentRulesInfoAPI()
    if (!r?.ok) {
      rulesError.value = r?.error || 'failed'
      return
    }
    rulesDir.value = String(r?.dir || '')
    rulesCount.value = Number(r?.count || 0) || 0
    const newest = typeof r?.newestMtimeSec === 'number' ? r.newestMtimeSec : Number(r?.newestMtimeSec || 0) || 0
    const oldest = typeof r?.oldestMtimeSec === 'number' ? r.oldestMtimeSec : Number(r?.oldestMtimeSec || 0) || 0
    rulesNewest.value = newest > 0 ? newest : undefined
    rulesOldest.value = oldest > 0 ? oldest : undefined
    const items = Array.isArray(r?.items) ? r.items : []
    rulesItems.value = items
      .filter((x: any) => x && x.path)
      .map((x: any) => ({
        name: String(x.name || ''),
        path: String(x.path || ''),
        mtimeSec: typeof x.mtimeSec === 'number' ? x.mtimeSec : Number(x.mtimeSec || 0) || undefined,
        sizeBytes: typeof x.sizeBytes === 'number' ? x.sizeBytes : Number(x.sizeBytes || 0) || undefined,
      }))
  } catch (e: any) {
    rulesError.value = e?.message || 'failed'
  } finally {
    rulesBusy.value = false
  }
}

const freshnessBusy = computed(() => geoBusy.value || providersBusy.value || rulesBusy.value)
const refreshFreshness = async () => {
  await Promise.all([refreshGeoInfo(), refreshRuleProviders(), refreshRulesInfo()])
}

// --- Diagnostics report ---
const diagBusy = ref(false)

const buildDiagnostics = async () => {
  const ts = new Date().toISOString()
  const agentStatus = await agentStatusAPI()

  const takeLog = async (type: 'mihomo' | 'agent' | 'config') => {
    const r: any = await agentLogsAPI({ type, lines: 200 })
    return {
      ok: !!r?.ok,
      path: r?.path || '',
      content: decodeB64Utf8(r?.contentB64) || (r?.error || ''),
    }
  }

  const logs = {
    mihomo: await takeLog('mihomo'),
    agent: await takeLog('agent'),
    config: await takeLog('config'),
  }

  const blocked = [] as any[]
  const keys = Object.keys(userLimits.value || {})
  for (const u of keys) {
    const st = getUserLimitState(u)
    if (st.blocked) {
      blocked.push({
        user: u,
        reasonManual: !!st.limit.disabled,
        trafficExceeded: !!st.trafficExceeded,
        bandwidthExceeded: !!st.bandwidthExceeded,
        usageBytes: st.usageBytes,
        trafficLimitBytes: st.limit.trafficLimitBytes || 0,
        bandwidthLimitBps: st.limit.bandwidthLimitBps || 0,
        mac: st.limit.mac || '',
      })
    }
  }

  return {
    kind: 'zash-diagnostics',
    generatedAt: ts,
    uiVersion: zashboardVersion.value,
    coreVersion: coreVersion.value,
    backend: activeBackend.value ? {
      label: activeBackend.value.label,
      host: activeBackend.value.host,
      port: activeBackend.value.port,
      protocol: activeBackend.value.protocol,
      secondaryPath: activeBackend.value.secondaryPath,
    } : null,
    agent: {
      enabled: !!agentEnabled.value,
      url: agentUrl.value,
      status: agentStatus,
    },
    limits: {
      autoDisconnectLimitedUsers: !!autoDisconnectLimitedUsers.value,
      hardBlockLimitedUsers: !!hardBlockLimitedUsers.value,
      managedLanDisallowedCidrs: managedLanDisallowedCidrs.value || [],
      profiles: userLimitProfiles.value || [],
      snapshotsCount: (userLimitSnapshots.value || []).length,
      userLimits: userLimits.value || {},
      blockedUsers: blocked,
    },
    connections: {
      activeCount: (activeConnections.value || []).length,
    },
    logs,
    ua: navigator.userAgent,
  }
}

const downloadDiagnostics = async () => {
  if (diagBusy.value) return
  diagBusy.value = true
  try {
    const rep = await buildDiagnostics()
    const blob = new Blob([JSON.stringify(rep, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `zash-diagnostics-${dayjs().format('YYYYMMDD-HHmmss')}.json`
    a.click()
    URL.revokeObjectURL(url)
    showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    diagBusy.value = false
  }
}

const copyDiagnostics = async () => {
  if (diagBusy.value) return
  diagBusy.value = true
  try {
    const rep = await buildDiagnostics()
    const text = JSON.stringify(rep, null, 2)
    await navigator.clipboard.writeText(text)
    showNotification({ content: 'copySuccess', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    diagBusy.value = false
  }
}

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
