<template>
  <div
    class="sidebar bg-base-200 text-base-content scrollbar-hidden h-full overflow-x-hidden p-2 transition-all"
    :class="isSidebarCollapsed ? 'w-18 px-0' : 'w-64'"
  >
    <div :class="twMerge('flex h-full flex-col gap-2', isSidebarCollapsed ? 'w-18 px-0' : 'w-60')">
      <ul class="menu w-full flex-1">
        <li @mouseenter="(e) => mouseenterHandler(e, 'globalSearch')">
          <button
            type="button"
            :class="[
              globalSearchOpen ? 'menu-active' : '',
              isSidebarCollapsed && 'justify-center',
              'w-full py-2',
            ]"
            @click="openGlobalSearch"
          >
            <MagnifyingGlassIcon class="h-5 w-5" />
            <template v-if="!isSidebarCollapsed">
              {{ $t('globalSearch') }}
              <span class="ml-auto text-[10px] opacity-60">Ctrl+K</span>
            </template>
          </button>
        </li>

        <li
          v-for="r in renderRoutes"
          :key="r"
          @mouseenter="(e) => mouseenterHandler(e, r)"
        >
          <a
            :class="[
              r === route.name ? 'menu-active' : '',
              isSidebarCollapsed && 'justify-center',
              'py-2',
            ]"
            @click.passive="() => router.push({ name: r })"
          >
            <component
              :is="ROUTE_ICON_MAP[r]"
              class="h-5 w-5"
            />
            <template v-if="!isSidebarCollapsed">
              {{ $t(r) }}
            </template>
          </a>
        </li>
      </ul>
      <template v-if="isSidebarCollapsed">
        <VerticalInfos v-if="showStatisticsWhenSidebarCollapsed" />
        <div
          v-else
          class="flex w-full items-center justify-center"
        >
          <button
            class="btn btn-circle btn-sm bg-base-300"
            @click="isSidebarCollapsed = false"
          >
            <ArrowRightCircleIcon class="h-5 w-5" />
          </button>
        </div>
      </template>
      <template v-else>
        <OverviewCarousel v-if="route.name !== ROUTE_NAME.overview" />
        <div class="card">
          <CommonSidebar />
        </div>
        <div class="flex w-full items-center justify-center">
          <button
            class="btn btn-ghost btn-sm w-full justify-start bg-base-100/40"
            @click="isSidebarCollapsed = true"
          >
            <ArrowLeftCircleIcon class="h-5 w-5" />
            <span class="ml-1">{{ $t('collapseMenu') }}</span>
          </button>
        </div>
      </template>
      <div class="px-3 pb-1 text-[10px] opacity-60" :class="isSidebarCollapsed ? 'text-center' : ''">
        UI {{ zashboardVersion }} (Netcraze Ultra/Mihomo)
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import CommonSidebar from '@/components/sidebar/CommonCtrl.vue'
import { zashboardVersion } from '@/api'
import { ROUTE_ICON_MAP, ROUTE_NAME } from '@/constant'
import { renderRoutes } from '@/helper'
import { useTooltip } from '@/helper/tooltip'
import router from '@/router'
import { isSidebarCollapsed, showStatisticsWhenSidebarCollapsed } from '@/store/settings'
import { globalSearchOpen } from '@/store/globalSearch'
import { ArrowLeftCircleIcon, ArrowRightCircleIcon, MagnifyingGlassIcon } from '@heroicons/vue/24/outline'
import { twMerge } from 'tailwind-merge'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import OverviewCarousel from './OverviewCarousel.vue'
import VerticalInfos from './VerticalInfos.vue'

const { showTip } = useTooltip()
const { t } = useI18n()

const mouseenterHandler = (e: MouseEvent, r: string) => {
  if (!isSidebarCollapsed.value) return
  const label = r === 'globalSearch' ? t('globalSearch') : t(r)
  showTip(e, label, {
    placement: 'right',
  })
}

const route = useRoute()

const openGlobalSearch = () => {
  globalSearchOpen.value = true
}

</script>
