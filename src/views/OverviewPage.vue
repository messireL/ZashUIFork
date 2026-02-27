<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
    <ChartsCard />
    <NetworkCard v-if="showIPAndConnectionInfo" />

    <div class="card" v-if="displayProxiesRelationship">
      <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
        <span>{{ $t('proxiesRelationship') }}</span>

        <div class="flex items-center gap-2 text-sm">
          <span class="opacity-70">{{ $t('proxiesRelationshipTree') }}</span>
          <input class="toggle toggle-sm" type="checkbox" v-model="proxiesRelationshipUseSources" />
          <span class="opacity-70">{{ $t('proxiesRelationshipSources') }}</span>
        </div>
      </div>

      <div class="px-4 pb-4">
        <ProxiesCharts v-if="!proxiesRelationshipUseSources" />
        <ProxiesSourcesCharts v-else />
      </div>
    </div>

    <ConnectionHistory />
    <div class="flex-1"></div>

    <div class="card items-center justify-center gap-2 p-2 sm:flex-row">
      {{ getLabelFromBackend(activeBackend!) }} :
      <BackendVersion />
    </div>
  </div>
</template>

<script setup lang="ts">
import BackendVersion from '@/components/common/BackendVersion.vue'
import ChartsCard from '@/components/overview/ChartsCard.vue'
import ConnectionHistory from '@/components/overview/ConnectionHistory.vue'
import NetworkCard from '@/components/overview/NetworkCard.vue'
import ProxiesCharts from '@/components/overview/ProxiesCharts.vue'
import ProxiesSourcesCharts from '@/components/overview/ProxiesSourcesCharts.vue'
import { getLabelFromBackend } from '@/helper/utils'
import { displayProxiesRelationship, proxiesRelationshipUseSources, showIPAndConnectionInfo } from '@/store/settings'
import { activeBackend } from '@/store/setup'
</script>
