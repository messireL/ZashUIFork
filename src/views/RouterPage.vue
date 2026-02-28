<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
    <AgentCard />
    <ChartsCard title-key="router" />
    <NetworkCard v-if="showIPAndConnectionInfo" />

    <div class="flex-1"></div>

    <div class="card items-center justify-center gap-2 p-2 sm:flex-row">
      {{ getLabelFromBackend(activeBackend!) }} :
      <BackendVersion />
    </div>
  </div>
</template>

<script setup lang="ts">
import AgentCard from '@/components/router/AgentCard.vue'
import BackendVersion from '@/components/common/BackendVersion.vue'
import ChartsCard from '@/components/overview/ChartsCard.vue'
import NetworkCard from '@/components/overview/NetworkCard.vue'
import { getLabelFromBackend } from '@/helper/utils'
import { showIPAndConnectionInfo } from '@/store/settings'
import { activeBackend } from '@/store/setup'
</script>
