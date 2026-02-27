<template>
  <div class="card">
    <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
      <span>{{ $t('userTraffic') }}</span>
      <div class="flex items-center gap-2">
        <select class="select select-sm" v-model="preset">
          <option value="1h">{{ $t('last1h') }}</option>
          <option value="24h">{{ $t('last24h') }}</option>
          <option value="7d">{{ $t('last7d') }}</option>
          <option value="30d">{{ $t('last30d') }}</option>
          <option value="custom">{{ $t('custom') }}</option>
        </select>
        <select class="select select-sm" v-model.number="topN">
          <option :value="0">{{ $t('all') }}</option>
          <option v-for="n in [10,20,30,50,100]" :key="n" :value="n">top {{ n }}</option>
        </select>
        <button class="btn btn-sm" @click="clearHistory">
          {{ $t('clearHistory') }}
        </button>
      </div>
    </div>

    <div class="card-body gap-3">
      <div v-if="preset === 'custom'" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-sm">
          <span class="opacity-70">{{ $t('from') }}</span>
          <input class="input input-sm" type="datetime-local" v-model="customFrom" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="opacity-70">{{ $t('to') }}</span>
          <input class="input input-sm" type="datetime-local" v-model="customTo" />
        </label>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>{{ $t('user') }}</th>
              <th class="max-md:hidden">{{ $t('keys') }}</th>
              <th class="text-right">{{ $t('download') }}</th>
              <th class="text-right">{{ $t('upload') }}</th>
              <th class="text-right">{{ $t('total') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.user">
              <td class="font-medium">
                <span class="truncate inline-block max-w-[240px]" :title="row.user">{{ row.user }}</span>
              </td>
              <td class="max-md:hidden">
                <span class="truncate inline-block max-w-[420px] opacity-70" :title="row.keys">{{ row.keys }}</span>
              </td>
              <td class="text-right font-mono">{{ format(row.dl) }}</td>
              <td class="text-right font-mono">{{ format(row.ul) }}</td>
              <td class="text-right font-mono">{{ format(row.dl + row.ul) }}</td>
            </tr>

            <tr v-if="!rows.length">
              <td colspan="5" class="text-center opacity-60">{{ $t('noContent') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="text-xs opacity-60">
        {{ $t('userTrafficTip') }} ({{ $t('buckets') }}: {{ buckets }})
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { clearUserTrafficHistory, formatTraffic, getTrafficRange, userTrafficStoreSize } from '@/composables/userTraffic'
import { sourceIPLabelList } from '@/store/settings'
import dayjs from 'dayjs'
import { computed, ref } from 'vue'

type Row = { user: string; keys: string; dl: number; ul: number }

const preset = ref<'1h' | '24h' | '7d' | '30d' | 'custom'>('24h')
const topN = ref<number>(30)

const customFrom = ref(dayjs().subtract(24, 'hour').format('YYYY-MM-DDTHH:mm'))
const customTo = ref(dayjs().format('YYYY-MM-DDTHH:mm'))

const range = computed(() => {
  const now = dayjs()
  if (preset.value === '1h') return { start: now.subtract(1, 'hour').valueOf(), end: now.valueOf() }
  if (preset.value === '24h') return { start: now.subtract(24, 'hour').valueOf(), end: now.valueOf() }
  if (preset.value === '7d') return { start: now.subtract(7, 'day').valueOf(), end: now.valueOf() }
  if (preset.value === '30d') return { start: now.subtract(30, 'day').valueOf(), end: now.valueOf() }

  const s = dayjs(customFrom.value)
  const e = dayjs(customTo.value)
  return {
    start: (s.isValid() ? s : now.subtract(24, 'hour')).valueOf(),
    end: (e.isValid() ? e : now).valueOf(),
  }
})

const knownKeysByUser = computed(() => {
  const map = new Map<string, string[]>()
  for (const item of sourceIPLabelList.value) {
    const user = item.label || item.key
    const keys = map.get(user) || []
    keys.push(item.key)
    map.set(user, keys)
  }
  return map
})

const rows = computed<Row[]>(() => {
  const { start, end } = range.value
  const agg = getTrafficRange(start, end)

  const allUsers = new Set<string>()
  for (const k of knownKeysByUser.value.keys()) allUsers.add(k)
  for (const k of agg.keys()) allUsers.add(k)

  const list: Row[] = Array.from(allUsers).map((user) => {
    const t = agg.get(user) || { dl: 0, ul: 0 }
    const keys = (knownKeysByUser.value.get(user) || []).join(', ')
    return { user, keys, dl: t.dl, ul: t.ul }
  })

  const sorted = list.sort((a, b) => (b.dl + b.ul) - (a.dl + a.ul))
  if (topN.value > 0) return sorted.slice(0, topN.value)
  return sorted
})

const format = (b: number) => formatTraffic(b)
const buckets = computed(() => userTrafficStoreSize.value)

const clearHistory = () => {
  clearUserTrafficHistory()
}
</script>
