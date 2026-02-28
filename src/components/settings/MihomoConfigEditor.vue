<template>
  <div class="card w-full max-w-none">
    <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="btn btn-ghost btn-circle btn-sm"
          @click="expanded = !expanded"
          :title="expanded ? $t('collapse') : $t('expand')"
        >
          <ChevronUpIcon v-if="expanded" class="h-4 w-4" />
          <ChevronDownIcon v-else class="h-4 w-4" />
        </button>
        <span>{{ $t('mihomoConfigEditor') }}</span>
      </div>

      <div class="flex items-center gap-2">
        <div class="text-xs opacity-70 hidden md:block">
          <span v-if="isFullYaml">{{ $t('configFullYaml') }}</span>
          <span v-else>{{ $t('configRuntime') }}</span>
        </div>
        <button class="btn btn-sm" :class="isLoading && 'loading'" @click="load">
          {{ $t('load') }}
        </button>
        <button class="btn btn-sm" :class="isReloading && 'loading'" @click="apply" :disabled="!expanded">
          {{ $t('applyAndReload') }}
        </button>
        <button class="btn btn-sm" :class="isRestarting && 'loading'" @click="restart">
          {{ $t('restartCore') }}
        </button>
      </div>
    </div>

    <div class="card-body gap-2">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="text-xs opacity-70">
          <span class="opacity-70">{{ $t('configPath') }}:</span>
          <span class="font-mono">{{ path }}</span>
        </div>
        <div class="text-xs opacity-60">
          <span v-if="isFullYaml">{{ $t('configFullYaml') }}</span>
          <span v-else>{{ $t('mihomoConfigLoadPartial') }}</span>
        </div>
      </div>

      <div
        class="transparent-collapse collapse rounded-none shadow-none"
        :class="expanded ? 'collapse-open' : ''"
      >
        <div class="collapse-content p-0">
          <div v-if="expanded" class="grid grid-cols-1 gap-2">
            <div class="text-xs opacity-70">
              {{ $t('mihomoConfigEditorTip') }}
            </div>

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
      </div>

      <div class="text-xs opacity-60" v-if="!expanded">
        {{ $t('configCollapsedTip') }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { getConfigsAPI, getConfigsRawAPI, reloadConfigsAPI, restartCoreAPI } from '@/api'
import { agentMihomoConfigAPI } from '@/api/agent'
import { agentEnabled } from '@/store/agent'
import axios from 'axios'
import { showNotification } from '@/helper/notification'
import { useStorage } from '@vueuse/core'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import { computed, onMounted, ref } from 'vue'

const path = useStorage('config/mihomo-config-path', '/opt/etc/mihomo/config.yaml')
const payload = useStorage('config/mihomo-config-payload', '')
const expanded = useStorage('config/mihomo-config-expanded', false)

const isLoading = ref(false)
const isReloading = ref(false)
const isRestarting = ref(false)

const dumpYaml = (value: any): string => {
  const isScalar = (v: any) => v === null || ['string', 'number', 'boolean'].includes(typeof v)

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

const looksLikeFullConfig = (s: string) => {
  const t = (s || '').trim()
  if (!t) return false
  return (
    /(^|\n)\s*proxies\s*:/m.test(t) ||
    /(^|\n)\s*proxy-groups\s*:/m.test(t) ||
    /(^|\n)\s*proxy-providers\s*:/m.test(t) ||
    /(^|\n)\s*rule-providers\s*:/m.test(t) ||
    /(^|\n)\s*rules\s*:/m.test(t)
  )
}

const looksLikeRuntimeConfigs = (obj: any) => {
  if (!obj || typeof obj !== 'object') return false
  const keys = Object.keys(obj)
  const hasPorts = keys.some((k) =>
    ['port', 'socks-port', 'redir-port', 'tproxy-port', 'mixed-port'].includes(k),
  )
  const hasGroups = keys.some((k) =>
    ['proxy-groups', 'proxies', 'rules', 'proxy-providers', 'rule-providers'].includes(k),
  )
  return hasPorts && !hasGroups
}

const tryLoadFromFileLikeEndpoints = async (pathValue: string): Promise<string | null> => {
  const candidates: Array<{ url: string; params?: Record<string, any> }> = [
    { url: '/configs', params: { path: pathValue, format: 'raw' } },
    { url: '/configs', params: { path: pathValue, raw: true } },
    { url: '/configs', params: { path: pathValue, file: true } },
    { url: '/configs', params: { path: pathValue, download: true } },
    { url: '/configs/raw', params: { path: pathValue } },
    { url: '/configs/file', params: { path: pathValue } },
  ]

  for (const c of candidates) {
    try {
      const r = await axios.get(c.url, {
        params: c.params,
        responseType: 'text',
        silent: true as any,
        headers: {
          Accept: 'text/plain, application/x-yaml, application/yaml, */*',
          'X-Zash-Silent': '1',
        } as any,
      })

      const data: any = (r as any)?.data
      if (typeof data === 'string') {
        const s = data.trim()
        if (looksLikeFullConfig(s)) return data
        if ((s.startsWith('{') || s.startsWith('[')) && (s.endsWith('}') || s.endsWith(']'))) {
          try {
            const parsed = JSON.parse(s)
            const payload = (parsed && (parsed.payload || parsed.data?.payload || parsed.config || parsed.yaml)) as any
            if (typeof payload === 'string' && looksLikeFullConfig(payload)) return payload
          } catch {
            // ignore
          }
        }
      } else if (data && typeof data === 'object') {
        const payload = (data.payload || data.data?.payload || data.config || data.yaml) as any
        if (typeof payload === 'string' && looksLikeFullConfig(payload)) return payload
      }
    } catch {
      // try next
    }
  }

  return null
}

const isFullYaml = computed(() => looksLikeFullConfig(payload.value || ''))

const load = async () => {
  if (isLoading.value) return
  isLoading.value = true
  try {
if (agentEnabled.value) {
  const res = await agentMihomoConfigAPI()
  if (res?.ok && res?.contentB64) {
    try {
      payload.value = atob(res.contentB64)
      showNotification({ content: 'mihomoConfigLoadSuccess', type: 'alert-success' })
      return
    } catch {
      // ignore decode errors and fallback
    }
  }
}

    const fileText = await tryLoadFromFileLikeEndpoints(path.value)
    if (fileText) {
      payload.value = fileText
      showNotification({ content: 'mihomoConfigLoadSuccess', type: 'alert-success' })
      return
    }

    const raw = await getConfigsRawAPI({ path: path.value })
    const data: any = raw?.data

    if (typeof data === 'string' && data.trim().length > 0) {
      const s = data.trim()

      if (looksLikeFullConfig(s)) {
        payload.value = data
        showNotification({ content: 'mihomoConfigLoadSuccess', type: 'alert-success' })
        return
      }

      if (s.startsWith('{') || s.startsWith('[')) {
        try {
          const parsed = JSON.parse(s)
          if (looksLikeRuntimeConfigs(parsed)) {
            payload.value =
              `# Mihomo API /configs does not expose the full YAML file on this build.\n` +
              `# Showing runtime config (ports/tun/etc). If your backend supports reading the file,\n` +
              `# enable it to load: ${path.value}\n\n` +
              dumpYaml(parsed)
            showNotification({ content: 'mihomoConfigLoadPartial', type: 'alert-info' })
            return
          }

          payload.value =
            `# Converted from /configs (JSON)\n# Comments/ordering may differ from the original mihomo YAML.\n\n${dumpYaml(parsed)}`
          showNotification({ content: 'mihomoConfigLoadPartial', type: 'alert-info' })
          return
        } catch {
          // fall through
        }
      }

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
