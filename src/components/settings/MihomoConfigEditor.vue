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

const dumpYaml = (value: any): string => {
  const isScalar = (v: any) =>
    v === null || ['string', 'number', 'boolean'].includes(typeof v)

  const scalarInline = (v: any) => {
    if (v === null) return 'null'
    if (typeof v === 'string') return JSON.stringify(v)
    if (typeof v === 'number' || typeof v === 'boolean') return String(v)
    return JSON.stringify(String(v))
  }

  const emit = (v: any, indent = 0): string[] => {
    const sp = ' '.repeat(indent)

    if (isScalar(v)) {
      if (typeof v === 'string' && v.includes('\n')) {
        const lines = v.split(/\r?\n/)
        return [sp + '|-', ...lines.map((l) => sp + '  ' + l)]
      }
      return [sp + scalarInline(v)]
    }

    if (Array.isArray(v)) {
      if (!v.length) return [sp + '[]']
      const out: string[] = []
      for (const item of v) {
        if (isScalar(item)) {
          if (typeof item === 'string' && item.includes('\n')) {
            const lines = item.split(/\r?\n/)
            out.push(sp + '- |-')
            out.push(...lines.map((l) => sp + '  ' + l))
          } else {
            out.push(sp + '- ' + scalarInline(item))
          }
        } else {
          out.push(sp + '-')
          out.push(...emit(item, indent + 2))
        }
      }
      return out
    }

    if (typeof v === 'object') {
      const keys = Object.keys(v || {})
      if (!keys.length) return [sp + '{}']

      const out: string[] = []
      for (const k of keys) {
        const key = /^[A-Za-z0-9_.-]+$/.test(k) ? k : JSON.stringify(k)
        const val = (v as any)[k]

        if (isScalar(val)) {
          if (typeof val === 'string' && val.includes('\n')) {
            const lines = val.split(/\r?\n/)
            out.push(sp + key + ': |-')
            out.push(...lines.map((l) => sp + '  ' + l))
          } else {
            out.push(sp + key + ': ' + scalarInline(val))
          }
        } else {
          if (Array.isArray(val) && !val.length) {
            out.push(sp + key + ': []')
          } else {
            out.push(sp + key + ':')
            out.push(...emit(val, indent + 2))
          }
        }
      }
      return out
    }

    return [sp + JSON.stringify(String(v))]
  }

  return emit(value, 0).join('\n') + '\n'
}

const load = async () => {
  if (isLoading.value) return
  isLoading.value = true
  try {
    // На некоторых сборках /configs может вернуть текст (YAML). Если вернёт JSON — покажем его.
    const raw = await getConfigsRawAPI({ path: path.value })
    const data: any = raw?.data

    if (typeof data === 'string' && data.trim().length > 0) {
      payload.value = data
      showNotification({ content: 'mihomoConfigLoadSuccess', type: 'alert-success' })
      return
    }

    const json = await getConfigsAPI()
    payload.value = `# Converted from /configs (JSON)\n# Comments/ordering may differ from the original mihomo YAML.\n\n${dumpYaml(json.data)}`
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
