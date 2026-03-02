<template>
  <div class="card gap-2 p-3">
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <div class="font-semibold">{{ $t('routerResources') }}</div>
        <span v-if="agentEnabled && status.ok" class="badge badge-success">{{ $t('online') }}</span>
        <span v-else-if="agentEnabled && !status.ok" class="badge badge-error">{{ $t('offline') }}</span>
        <span v-else class="badge badge-ghost">{{ $t('disabled') }}</span>
      </div>

      <button type="button" class="btn btn-sm" @click="refresh" :disabled="!agentEnabled">
        {{ $t('refresh') }}
      </button>
    </div>

    <div v-if="!agentEnabled" class="text-sm opacity-70">
      {{ $t('agentDisabledTip') }}
    </div>
    <div v-else-if="agentEnabled && !status.ok" class="text-sm opacity-70">
      {{ $t('agentOfflineTip') }}
    </div>

    <div v-else class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div class="flex flex-col gap-1">
        <div class="flex items-center justify-between">
          <div class="text-xs opacity-70">CPU</div>
          <div class="text-sm font-mono">{{ cpuPctText }}</div>
        </div>
        <progress class="progress w-full" :value="status.cpuPct || 0" max="100" />
        <div class="text-[11px] opacity-70">
          {{ $t('loadAvg1m') }}: <span class="font-mono">{{ status.load1 ?? '—' }}</span>
          <span class="opacity-50">·</span>
          {{ $t('uptime') }}: <span class="font-mono">{{ uptimeText }}</span>
        </div>
      </div>

      <div class="flex flex-col gap-1">
        <div class="flex items-center justify-between">
          <div class="text-xs opacity-70">{{ $t('memoryUsage') }}</div>
          <div class="text-sm font-mono">{{ memPctText }}</div>
        </div>
        <progress class="progress w-full" :value="status.memUsedPct || 0" max="100" />
        <div class="text-[11px] opacity-70">
          <span class="font-mono">{{ prettyBytes(status.memUsed) }}</span>
          <span class="opacity-50">/</span>
          <span class="font-mono">{{ prettyBytes(status.memTotal) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { agentStatusAPI } from '@/api/agent'
import { prettyBytesHelper } from '@/helper/utils'
import { agentEnabled } from '@/store/agent'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

type AgentStatusExt = {
  ok: boolean
  cpuPct?: number
  load1?: string
  uptimeSec?: number
  memTotal?: number
  memUsed?: number
  memUsedPct?: number
  error?: string
}

const status = ref<AgentStatusExt>({ ok: false })

const prettyBytes = (v: any) => {
  const n = Number(v || 0)
  return prettyBytesHelper(Number.isFinite(n) ? n : 0)
}

const cpuPctText = computed(() => {
  const v = Number(status.value.cpuPct)
  if (!Number.isFinite(v)) return '—'
  return `${Math.round(v)}%`
})

const memPctText = computed(() => {
  const v = Number(status.value.memUsedPct)
  if (!Number.isFinite(v)) return '—'
  return `${Math.round(v)}%`
})

const uptimeText = computed(() => {
  const s = Number(status.value.uptimeSec)
  if (!Number.isFinite(s) || s <= 0) return '—'
  const sec = Math.floor(s)
  const d = Math.floor(sec / 86400)
  const h = Math.floor((sec % 86400) / 3600)
  const m = Math.floor((sec % 3600) / 60)
  if (d > 0) return `${d}d ${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
})

const refresh = async () => {
  if (!agentEnabled.value) {
    status.value = { ok: false }
    return
  }
  status.value = (await agentStatusAPI()) as any
}

let timer: any = null

onMounted(() => {
  refresh()
  // Light polling for readable "router load".
  timer = setInterval(() => {
    if (agentEnabled.value) refresh()
  }, 10_000)
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
})
</script>
