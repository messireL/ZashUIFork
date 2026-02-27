<template>
  <div class="card w-full max-w-none">
    <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
      <span>{{ $t('mihomoConfigEditor') }}</span>
      <div class="flex items-center gap-2">
        <button class="btn btn-sm" :class="isLoading && 'loading'" @click="load">
          {{ $t('load') }}
        </button>
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
        <span class="text-xs opacity-70">{{ $t('configPath') }}</span>
        <input class="input input-sm" v-model="path" readonly />
      </label>

      <textarea
        class="textarea textarea-sm font-mono w-full h-[70vh] min-h-[28rem] resize-y leading-5 overflow-x-auto whitespace-pre [tab-size:2]"
        wrap="off"
        v-model="payload"
        :placeholder="$t('pasteYamlHere')"
      ></textarea>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="text-xs opacity-60">
          {{ $t('mihomoConfigDraftSaved') }}
        </div>
        <button class="btn btn-ghost btn-sm" @click="clearDraft">{{ $t('clearDraft') }}</button>
      </div>

      <div class="text-xs opacity-60">
        {{ $t('mihomoConfigLoadNote') }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { getConfigsAPI, getConfigsRawAPI, reloadConfigsAPI, restartCoreAPI } from '@/api'
import { showNotification } from '@/helper/notification'
import { useStorage } from '@vueuse/core'
import { onMounted, ref } from 'vue'

const path = useStorage('config/mihomo-config-path', '/opt/etc/mihomo/config.yaml')
const payload = useStorage('config/mihomo-config-payload', '')

const isLoading = ref(false)
const isReloading = ref(false)
const isRestarting = ref(false)

const load = async () => {
  if (isLoading.value) return
  isLoading.value = true
  try {
    // На некоторых сборках /configs может вернуть текст (YAML). Если вернёт JSON — покажем его.
    const raw = await getConfigsRawAPI({ path: path.value })
    const data: any = raw?.data

    if (typeof data === 'string' && data.trim().length > 0 && data.includes('\n')) {
      payload.value = data
      showNotification({ content: 'mihomoConfigLoadSuccess', type: 'alert-success' })
      return
    }

    const json = await getConfigsAPI()
    payload.value = `# /configs (JSON)\n# Полный YAML mihomo по API может быть недоступен в вашей сборке.\n\n${JSON.stringify(
      json.data,
      null,
      2,
    )}`
    showNotification({ content: 'mihomoConfigLoadPartial', type: 'alert-info' })
  } catch {
    showNotification({ content: 'mihomoConfigLoadFailed', type: 'alert-error' })
  } finally {
    isLoading.value = false
  }
}

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

onMounted(() => {
  if (!payload.value) load()
})
</script>
