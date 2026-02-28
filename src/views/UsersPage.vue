<template>
  <div class="grid grid-cols-1 gap-2 overflow-x-hidden p-2">
    <div class="card">
      <div class="card-title px-4 pt-4">{{ $t('users') }}</div>
      <div class="card-body gap-3">
        <div class="text-sm opacity-70">
          {{ $t('usersTip') }}
        </div>

        <div class="flex flex-col gap-2">
          <Draggable
            v-if="sourceIPLabelList.length"
            class="flex flex-1 flex-col gap-2"
            v-model="sourceIPLabelList"
            group="list"
            :animation="150"
            :handle="'.drag-handle'"
            :filter="'.no-drag'"
            :prevent-on-filter="false"
            :item-key="'id'"
            @start="disableSwipe = true"
            @end="disableSwipe = false"
          >
            <template #item="{ element: sourceIP }">
              <SourceIPInput
                :model-value="sourceIP"
                @update:model-value="handlerLabelUpdate"
              >
                <template #prefix>
                  <ChevronUpDownIcon class="drag-handle h-4 w-4 shrink-0 cursor-grab" />
                  <LockClosedIcon
                    v-if="isBlockedUser(sourceIP)"
                    class="no-drag h-4 w-4 text-error"
                    :title="$t('userBlockedTip')"
                  />
                </template>
                <template #default>
                  <button
                    type="button"
                    class="no-drag btn btn-circle btn-ghost btn-sm"
                    @click.stop.prevent="handlerLabelRemove(sourceIP.id)"
                    @pointerdown.stop.prevent
                    @mousedown.stop.prevent
                    @touchstart.stop.prevent
                    :title="$t('delete')"
                  >
                    <TrashIcon class="h-4 w-4" />
                  </button>
                </template>
              </SourceIPInput>
            </template>
          </Draggable>

          <div v-else class="text-sm opacity-60">
            {{ $t('usersEmpty') }}
          </div>

          <SourceIPInput
            v-model="newLabelForIP"
            @keydown.enter="handlerLabelAdd"
          >
            <template #prefix>
              <TagIcon class="h-4 w-4 shrink-0" />
            </template>
            <template #default>
              <button
                type="button"
                class="no-drag btn btn-circle btn-sm"
                @click.stop.prevent="handlerLabelAdd"
                @pointerdown.stop.prevent
                @mousedown.stop.prevent
                @touchstart.stop.prevent
                :title="$t('add')"
              >
                <PlusIcon class="h-4 w-4" />
              </button>
            </template>
          </SourceIPInput>
        </div>
      </div>
    </div>

    <UserTrafficStats />
  </div>
</template>


<script setup lang="ts">
import UserTrafficStats from '@/components/users/UserTrafficStats.vue'
import SourceIPInput from '@/components/settings/SourceIPInput.vue'
import { disableSwipe } from '@/composables/swipe'
import { sourceIPLabelList } from '@/store/settings'
import type { SourceIPLabel } from '@/types'
import { ChevronUpDownIcon, LockClosedIcon, PlusIcon, TagIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { v4 as uuid } from 'uuid'
import { ref } from 'vue'
import Draggable from 'vuedraggable'
import { getUserLimitState } from '@/composables/userLimits'

const newLabelForIP = ref<Omit<SourceIPLabel, 'id'>>({
  key: '',
  label: '',
})

const handlerLabelAdd = () => {
  if (!newLabelForIP.value.key || !newLabelForIP.value.label) {
    return
  }
  sourceIPLabelList.value.push({
    ...newLabelForIP.value,
    id: uuid(),
  })
  newLabelForIP.value = {
    key: '',
    label: '',
  }
}

const handlerLabelRemove = (id: string) => {
  const idx = sourceIPLabelList.value.findIndex((item) => item.id === id)
  if (idx >= 0) sourceIPLabelList.value.splice(idx, 1)
}

const handlerLabelUpdate = (sourceIP: Partial<SourceIPLabel>) => {
  const index = sourceIPLabelList.value.findIndex((item) => item.id === sourceIP.id)
  if (index < 0) return
  sourceIPLabelList.value[index] = {
    ...sourceIPLabelList.value[index],
    ...sourceIP,
  }
}

const isBlockedUser = (sourceIP: Partial<SourceIPLabel>) => {
  const user = (sourceIP.label || sourceIP.key || '').toString().trim()
  if (!user) return false
  return getUserLimitState(user).blocked
}
</script>
