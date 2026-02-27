<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
    <ChartsCard />
    <NetworkCard v-if="showIPAndConnectionInfo" />

    <div class="card" v-if="displayProxiesRelationship">
      <div class="card-title px-4 pt-4 flex items-center justify-between gap-2">
        <span>{{ $t('proxiesRelationship') }}</span>

        <div class="flex items-center gap-2">
          <div class="join">
            <button
              class="btn btn-xs join-item"
              :class="proxiesRelationshipView === 'tree' ? 'btn-active' : ''"
              @click="proxiesRelationshipView = 'tree'"
            >
              {{ $t('proxiesRelationshipTree') }}
            </button>

            <button
              class="btn btn-xs join-item"
              :class="proxiesRelationshipView === 'sources' ? 'btn-active' : ''"
              @click="proxiesRelationshipView = 'sources'"
            >
              {{ $t('proxiesRelationshipSources') }}
            </button>

            <button
              class="btn btn-xs join-item"
              :class="proxiesRelationshipView === 'clients' ? 'btn-active' : ''"
              @click="proxiesRelationshipView = 'clients'"
            >
              {{ $t('proxiesRelationshipClients') }}
            </button>
          </div>

          <template v-if="proxiesRelationshipView !== 'tree'">
            <button
              class="btn btn-ghost btn-circle btn-xs"
              :title="proxiesRelationshipPaused ? $t('resume') : $t('pause')"
              @click="proxiesRelationshipPaused = !proxiesRelationshipPaused"
            >
              <component :is="proxiesRelationshipPaused ? PlayIcon : PauseIcon" class="h-4 w-4" />
            </button>

            <button
              class="btn btn-ghost btn-circle btn-xs"
              :title="$t('refresh')"
              @click="proxiesRelationshipRefreshNonce++"
            >
              <ArrowPathIcon class="h-4 w-4" />
            </button>

            <span class="text-xs opacity-60">
              {{ proxiesRelationshipPaused ? $t('paused') : `${proxiesRelationshipRefreshSec}s` }}
            </span>
          </template>
        </div>
      </div>

      <div class="px-4 pb-4">
        <ProxiesCharts v-if="proxiesRelationshipView === 'tree'" />
        <ProxiesSourcesCharts v-else-if="proxiesRelationshipView === 'sources'" />
        <ProxiesClientCharts v-else />
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
import ProxiesClientCharts from '@/components/overview/ProxiesClientCharts.vue'
import ProxiesSourcesCharts from '@/components/overview/ProxiesSourcesCharts.vue'
import { getLabelFromBackend } from '@/helper/utils'
import {
  displayProxiesRelationship,
  proxiesRelationshipPaused,
  proxiesRelationshipRefreshNonce,
  proxiesRelationshipRefreshSec,
  proxiesRelationshipView,
  showIPAndConnectionInfo,
} from '@/store/settings'
import { activeBackend } from '@/store/setup'
import { ArrowPathIcon, PauseIcon, PlayIcon } from '@heroicons/vue/24/outline'
</script>
