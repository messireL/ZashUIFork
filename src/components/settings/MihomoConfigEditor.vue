<template>
  <div class="card">
    <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
      <span>{{ $t('mihomoConfigEditor') }}</span>
      <div class="flex items-center gap-2">
        <button class="btn btn-sm" :class="isReloading && 'loading'" @click="apply">
          {{ $t('applyAndReload') }}
        </button>
        <button class="btn btn-sm" :class="isRestarting && 'loading'" @click="restart">
          {{ $t('restartCore') }}
        </button>
      </div>
    </div>

    <div class="card-body gap-2">
      <div class="text-xs opacity-70">
        {{ $t('mihomoConfigEditorTip') }}
      </div>

      <label class="flex flex-col gap-1">
        <span class="text-xs opacity-70">{{ $t('configPath') }} ({{ $t('optional') }})</span>
        <input class="input input-sm" v-model="path" placeholder="/etc/mihomo/config.yaml" />
      </label>

      <textarea
        class="textarea textarea-sm font-mono h-64"
        v-model="payload"
        :placeholder="$t('pasteYamlHere')"
      ></textarea>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="text-xs opacity-60">
          {{ $t('mihomoConfigDraftSaved') }}
        </div>
        <button class="btn btn-ghost btn-sm" @click="clearDraft">{{ $t('clearDraft') }}</button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reloadConfigsAPI, restartCoreAPI } from '@/api'
import { showNotification } from '@/helper/notification'
import { useStorage } from '@vueuse/core'
import { ref } from 'vue'

const path = useStorage('config/mihomo-config-path', '')
const payload = useStorage('config/mihomo-config-payload', '')

const isReloading = ref(false)
const isRestarting = ref(false)

const apply = async () => {
  if (isReloading.value) return
  isReloading.value = true
  try {
    await reloadConfigsAPI({ path: path.value || '', payload: payload.value || '' })
    showNotification({ content: 'reloadConfigsSuccess', type: 'alert-success' })
  } catch {
    // handled by interceptor
  } finally {
    isReloading.value = false
  }
}

const restart = async () => {
  if (isRestarting.value) return
  isRestarting.value = true
  try {
    await restartCoreAPI()
    showNotification({ content: 'restartCoreSuccess', type: 'alert-success' })
  } catch {
    // handled by interceptor
  } finally {
    isRestarting.value = false
  }
}

const clearDraft = () => {
  payload.value = ''
}
</script>
