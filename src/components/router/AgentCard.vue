<template>
  <div class="card gap-2 p-3">
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <div class="font-semibold">{{ $t('routerAgent') }}</div>
        <span
          v-if="!agentEnabled"
          class="badge badge-ghost"
          >{{ $t('disabled') }}</span
        >
        <span v-else class="badge" :class="status.ok ? 'badge-success' : 'badge-error'">
          {{ status.ok ? $t('online') : $t('offline') }}
        </span>
        <span v-if="agentEnabled && status.ok && status.tc" class="badge badge-success">tc</span>
        <span v-if="agentEnabled && status.ok && !status.tc" class="badge badge-warning">no-tc</span>
      </div>

      <button type="button" class="btn btn-sm" @click="refresh">{{ $t('test') }}</button>
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
import { agentStatusAPI } from '@/api/agent'
import { agentEnabled, agentEnforceBandwidth, agentToken, agentUrl } from '@/store/agent'
import { onMounted, ref } from 'vue'

const status = ref<{ ok: boolean; tc?: boolean; wan?: string; lan?: string }>({ ok: false })

const refresh = async () => {
  if (!agentEnabled.value) {
    status.value = { ok: false }
    return
  }
  status.value = await agentStatusAPI()
}

onMounted(() => {
  refresh()
})
</script>
