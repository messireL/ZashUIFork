<template>
  <div class="grid grid-cols-1 gap-2 overflow-x-hidden p-2">
    <div class="card">
      <div class="card-title px-4 pt-4">{{ $t('users') }}</div>
      <div class="card-body gap-3">
        <div class="text-sm opacity-70">
          {{ $t('usersTip') }}
        </div>
        <SourceIPLabels />
      </div>
    </div>

    <UserTrafficStats />
  </div>
</template>

<script setup lang="ts">
import UserTrafficStats from '@/components/users/UserTrafficStats.vue'
import SourceIPLabels from '@/components/settings/SourceIPLabels.vue'
</script>
