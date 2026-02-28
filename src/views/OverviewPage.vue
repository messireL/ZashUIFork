<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
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
import ConnectionHistory from '@/components/overview/ConnectionHistory.vue'
import ProxiesRuleCharts from '@/components/overview/ProxiesRuleCharts.vue'
import { getLabelFromBackend } from '@/helper/utils'
import { displayProxiesRelationship, proxiesRelationshipTopN, proxiesRelationshipWeightMode } from '@/store/settings'
import { activeBackend } from '@/store/setup'
</script>
