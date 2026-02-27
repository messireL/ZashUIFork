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
              :class="proxiesRelationshipWeightMode === 'traffic' ? 'btn-active' : ''"
              @click="proxiesRelationshipWeightMode = 'traffic'"
            >
              {{ $t('traffic') }}
            </button>
            <button
              class="btn btn-xs join-item"
              :class="proxiesRelationshipWeightMode === 'count' ? 'btn-active' : ''"
              @click="proxiesRelationshipWeightMode = 'count'"
            >
              {{ $t('count') }}
            </button>
          </div>

          <select class="select select-xs" v-model.number="proxiesRelationshipTopN">
            <option :value="10">top 10</option>
            <option :value="20">top 20</option>
            <option :value="40">top 40</option>
            <option :value="70">top 70</option>
            <option :value="100">top 100</option>
          </select>

          <select class="select select-xs" v-model.number="proxiesRelationshipTopNChain">
            <option :value="10">chain 10</option>
            <option :value="18">chain 18</option>
            <option :value="30">chain 30</option>
            <option :value="60">chain 60</option>
          </select>
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
        </div>
      </div>

      <div class="px-4 pb-4">
        <ProxiesRuleCharts />
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
import ProxiesRuleCharts from '@/components/overview/ProxiesRuleCharts.vue'
import { getLabelFromBackend } from '@/helper/utils'
import {
  displayProxiesRelationship,
  proxiesRelationshipPaused,
  proxiesRelationshipRefreshNonce,
  proxiesRelationshipRefreshSec,
  proxiesRelationshipTopN,
  proxiesRelationshipTopNChain,
  proxiesRelationshipWeightMode,
  showIPAndConnectionInfo,
} from '@/store/settings'
import { activeBackend } from '@/store/setup'
import { ArrowPathIcon, PauseIcon, PlayIcon } from '@heroicons/vue/24/outline'
</script>
