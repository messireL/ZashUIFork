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
          <option v-for="n in [10, 20, 30, 50, 100]" :key="n" :value="n">top {{ n }}</option>
        </select>
	      <button type="button" class="btn btn-sm" @click="reportDialogOpen = true">
          {{ $t('reports') }}
        </button>
	      <button type="button" class="btn btn-sm" @click="clearHistory">
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


      <div class="rounded-lg border border-base-content/10 bg-base-200/30 p-2">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <div class="text-sm font-semibold">{{ $t('blockedUsers') }}</div>
            <span v-if="blockedList.length" class="badge badge-error">{{ blockedList.length }}</span>
            <span v-else class="badge">{{ blockedList.length }}</span>
          </div>
          <button
            type="button"
            class="btn btn-xs btn-ghost"
            @click="applyNow"
            :disabled="blockedActionBusy"
            :title="$t('applyEnforcementNow')"
          >
            <ArrowPathIcon class="h-4 w-4" :class="blockedActionBusy ? 'animate-spin' : ''" />
          </button>
        </div>

        <div v-if="!blockedList.length" class="mt-1 text-sm opacity-60">
          {{ $t('noBlockedUsers') }}
        </div>

        <div v-else class="mt-2 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{{ $t('user') }}</th>
                <th class="max-md:hidden">IP</th>
                <th class="text-right">{{ $t('traffic') }}</th>
                <th class="text-right max-lg:hidden">{{ $t('limits') }}</th>
                <th class="text-right">{{ $t('actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="b in blockedList" :key="b.user">
                <td class="font-medium">
                  <div class="flex items-center gap-2">
                    <LockClosedIcon class="h-4 w-4 text-error" />
                    <span class="truncate inline-block max-w-[240px]" :title="b.user">{{ b.user }}</span>
                    <div class="flex items-center gap-1">
                      <span
                        v-if="b.trafficLimitBytes"
                        class="inline-flex pointer-events-auto"
                        :title="trafficIconTitle(b.trafficLimitBytes, b.periodKey, b.limitEnabled)"
                      >
                        <CircleStackIcon
                          class="h-4 w-4"
                          :class="b.limitEnabled ? 'text-info' : 'opacity-40'"
                          @mouseenter="showTip($event, trafficIconTitle(b.trafficLimitBytes, b.periodKey, b.limitEnabled))"
                          @mouseleave="hideTip"
                        />
                      </span>
                      <span
                        v-if="b.bandwidthLimitBps"
                        class="inline-flex pointer-events-auto"
                        :title="bandwidthIconTitle(b.bandwidthLimitBps, b.limitEnabled)"
                      >
                        <BoltIcon
                          class="h-4 w-4"
                          :class="b.limitEnabled ? 'text-warning' : 'opacity-40'"
                          @mouseenter="showTip($event, bandwidthIconTitle(b.bandwidthLimitBps, b.limitEnabled))"
                          @mouseleave="hideTip"
                        />
                      </span>
                    </div>
                    <span v-if="b.reasonManual" class="badge badge-error badge-outline">{{ $t('manualBlock') }}</span>
                    <span v-else-if="b.reasonTraffic" class="badge badge-warning badge-outline">{{ $t('trafficExceeded') }}</span>
                    <span v-else-if="b.reasonBandwidth" class="badge badge-warning badge-outline">{{ $t('bandwidthExceeded') }}</span>
                  </div>
                </td>
                <td class="max-md:hidden">
                  <span class="truncate inline-block max-w-[420px] opacity-70" :title="b.ips">{{ b.ips }}</span>
                </td>
                <td class="text-right font-mono whitespace-nowrap">
                  <span v-if="b.limitEnabled && b.trafficLimitBytes">
                    {{ format(b.usageBytes) }} / {{ format(b.trafficLimitBytes) }}
                  </span>
                  <span v-else class="opacity-60">—</span>
                </td>
                <td class="text-right font-mono max-lg:hidden whitespace-nowrap">
                  <span v-if="b.limitEnabled">
                    {{ b.periodLabel }}
                  </span>
                  <span v-else class="opacity-60">—</span>
                </td>
                <td class="text-right relative z-40 pointer-events-auto">
  <div class="flex justify-end gap-1 pointer-events-auto">
    <button
      type="button"
      class="btn btn-ghost btn-circle btn-xs relative z-20"
      @click.stop.prevent="openLimits(b.user)"
      @pointerdown.stop.prevent
      @mousedown.stop.prevent
      @touchstart.stop.prevent
      :title="$t('limits')"
    >
      <AdjustmentsHorizontalIcon class="h-4 w-4" />
    </button>
    <button
      type="button"
      class="btn btn-ghost btn-xs relative z-20"
      @click.stop.prevent="unblockAndReset(b.user)"
      @pointerdown.stop.prevent
      @mousedown.stop.prevent
      @touchstart.stop.prevent
      :disabled="blockedActionBusy"
      :title="$t('unblockAndReset')"
    >
      {{ $t('unblockAndReset') }}
    </button>
    <button
      type="button"
      class="btn btn-ghost btn-xs relative z-20"
      @click.stop.prevent="disableLimitsQuick(b.user)"
      @pointerdown.stop.prevent
      @mousedown.stop.prevent
      @touchstart.stop.prevent
      :disabled="blockedActionBusy"
      :title="$t('disableLimits')"
    >
      {{ $t('disableLimits') }}
    </button>
  </div>
</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>


      <div v-if="selectedList.length" class="rounded-lg border border-base-content/10 bg-base-200/30 p-2">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="text-sm font-semibold">{{ $t('selected') }}: {{ selectedList.length }}</div>
          <div class="flex flex-wrap items-center gap-2">
            <select class="select select-sm" v-model="bulkProfileId">
              <option value="">{{ $t('applyProfile') }}</option>
              <option v-for="p in limitProfiles" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
            <button type="button" class="btn btn-sm" @click="applyProfileBulk" :disabled="!bulkProfileId || bulkBusy">
              {{ $t('apply') }}
            </button>
            <button type="button" class="btn btn-sm btn-ghost" @click="bulkUnblockReset" :disabled="bulkBusy">
              {{ $t('unblockAndReset') }}
            </button>
            <button type="button" class="btn btn-sm btn-ghost" @click="bulkDisableLimits" :disabled="bulkBusy">
              {{ $t('disableLimits') }}
            </button>
            <button type="button" class="btn btn-sm btn-ghost" @click="goPolicies">
              {{ $t('limitProfiles') }}
            </button>
            <button type="button" class="btn btn-sm btn-ghost" @click="clearSelection">
              {{ $t('clearSelection') }}
            </button>
          </div>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th style="width: 38px">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  :checked="allSelected"
                  @click="toggleSelectAll"
                  :title="$t('selectAll')"
                />
              </th>
              <th class="cursor-pointer select-none" @click="setSort('user')">
                {{ $t('user') }}
                <span class="opacity-60" v-if="sortKey === 'user'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="max-md:hidden cursor-pointer select-none" @click="setSort('keys')">
                {{ $t('keys') }}
                <span class="opacity-60" v-if="sortKey === 'keys'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('dl')">
                {{ $t('download') }}
                <span class="opacity-60" v-if="sortKey === 'dl'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('ul')">
                {{ $t('upload') }}
                <span class="opacity-60" v-if="sortKey === 'ul'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right cursor-pointer select-none" @click="setSort('total')">
                {{ $t('total') }}
                <span class="opacity-60" v-if="sortKey === 'total'">{{ sortDir === 'asc' ? '▲' : '▼' }}</span>
              </th>
              <th class="text-right max-lg:hidden">{{ $t('trafficLimit') }}</th>
              <th class="text-right max-lg:hidden">{{ $t('bandwidthLimit') }}</th>
              <th class="text-right">{{ $t('actions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.user">
              <td>
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  v-model="selectedMap[row.user]"
                  @click.stop
                  :title="$t('selectUser')"
                />
              </td>
              <td class="font-medium">
                <div class="flex items-center gap-2">
                  <LockClosedIcon
                    v-if="limitStates[row.user]?.blocked"
                    class="h-4 w-4 text-error"
                    :title="$t('userBlockedTip')"
                  />
                  <template v-if="editingUser === row.user">
                    <input
                      class="input input-xs w-full max-w-[260px]"
                      v-model="editingName"
                      :placeholder="$t('user')"
                    />
                  </template>
                  <template v-else>
                    <span class="truncate inline-block max-w-[240px]" :title="row.user">{{ row.user }}</span>
                    <div class="flex items-center gap-1">
                      <span
                        v-if="limitStates[row.user]?.trafficLimitBytes"
                        class="inline-flex pointer-events-auto"
                        :title="trafficIconTitle(limitStates[row.user].trafficLimitBytes, getUserLimit(row.user).trafficPeriod, limitStates[row.user].enabled)"
                      >
                        <CircleStackIcon
                          class="h-4 w-4"
                          :class="limitStates[row.user].enabled ? 'text-info' : 'opacity-40'"
                          @mouseenter="showTip($event, trafficIconTitle(limitStates[row.user].trafficLimitBytes, getUserLimit(row.user).trafficPeriod, limitStates[row.user].enabled))"
                          @mouseleave="hideTip"
                        />
                      </span>
                      <span
                        v-if="limitStates[row.user]?.bandwidthLimitBps"
                        class="inline-flex pointer-events-auto"
                        :title="bandwidthIconTitle(limitStates[row.user].bandwidthLimitBps, limitStates[row.user].enabled)"
                      >
                        <BoltIcon
                          class="h-4 w-4"
                          :class="limitStates[row.user].enabled ? 'text-warning' : 'opacity-40'"
                          @mouseenter="showTip($event, bandwidthIconTitle(limitStates[row.user].bandwidthLimitBps, limitStates[row.user].enabled))"
                          @mouseleave="hideTip"
                        />
                      </span>
                    </div>
                  </template>
                </div>
              </td>
              <td class="max-md:hidden">
                <span class="truncate inline-block max-w-[420px] opacity-70" :title="row.keys">{{ row.keys }}</span>
              </td>
              <td class="text-right font-mono">{{ format(row.dl) }}</td>
              <td class="text-right font-mono">{{ format(row.ul) }}</td>
              <td class="text-right font-mono">{{ format(row.dl + row.ul) }}</td>

              <td class="text-right font-mono max-lg:hidden">
                <template v-if="limitStates[row.user]?.trafficLimitBytes">
                  <div
                    class="whitespace-nowrap"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    {{ format(limitStates[row.user].usageBytes) }} /
                    {{ format(limitStates[row.user].trafficLimitBytes) }}
                  </div>
                  <div
                    class="text-xs opacity-60 flex items-center justify-end gap-1"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    <span>{{ limitStates[row.user].periodLabel }} · {{ limitStates[row.user].percent }}%</span>
                    <CircleStackIcon
                      class="h-4 w-4"
                      :class="limitStates[row.user].enabled ? 'text-info' : 'opacity-40'"
                      :title="trafficIconTitle(limitStates[row.user].trafficLimitBytes, getUserLimit(row.user).trafficPeriod, limitStates[row.user].enabled)"
                      @mouseenter="showTip($event, trafficIconTitle(limitStates[row.user].trafficLimitBytes, getUserLimit(row.user).trafficPeriod, limitStates[row.user].enabled))"
                      @mouseleave="hideTip"
                    />
                    <BoltIcon
                      v-if="limitStates[row.user].bandwidthLimitBps"
                      class="h-4 w-4"
                      :class="limitStates[row.user].enabled ? 'text-warning' : 'opacity-40'"
                      :title="bandwidthIconTitle(limitStates[row.user].bandwidthLimitBps, limitStates[row.user].enabled)"
                      @mouseenter="showTip($event, bandwidthIconTitle(limitStates[row.user].bandwidthLimitBps, limitStates[row.user].enabled))"
                      @mouseleave="hideTip"
                    />
                  </div>
                </template>
                <template v-else>
                  <span class="opacity-50">—</span>
                </template>
              </td>

              <td class="text-right font-mono max-lg:hidden">
                <template v-if="limitStates[row.user]?.bandwidthLimitBps">
                  <div
                    class="whitespace-nowrap"
                    :class="limitStates[row.user].enabled ? '' : 'opacity-40'"
                  >
                    {{ speed(limitStates[row.user].speedBps) }} /
                    {{ speed(limitStates[row.user].bandwidthLimitBps) }}
                  </div>
                </template>
                <template v-else>
                  <span class="opacity-50">—</span>
                </template>
              </td>

              <td class="text-right relative z-30 pointer-events-auto">
                <div class="flex justify-end gap-1 pointer-events-auto">
                  <template v-if="editingUser === row.user">
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      :disabled="!editingName.trim()"
                      @click.stop.prevent="saveEdit"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('save')"
                    >
                      <CheckIcon class="h-4 w-4" />
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="cancelEdit"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('cancel')"
                    >
                      <XMarkIcon class="h-4 w-4" />
                    </button>
                  </template>
                  <template v-else>
                    <template v-if="shaperBadge[row.user]">
                      <span
                        class="inline-flex items-center justify-center px-1"
                        :title="shaperBadge[row.user].title"
                      >
                        <component
                          :is="shaperBadge[row.user].icon"
                          class="h-4 w-4"
                          :class="shaperBadge[row.user].cls"
                        />
                      </span>
                      <button
                        v-if="shaperBadge[row.user].showReapply"
                        type="button"
                        class="btn btn-ghost btn-circle btn-xs relative z-20"
                        :disabled="applyingShaperUser === row.user"
                        @click.stop.prevent="reapplyShaper(row.user)"
                        @pointerdown.stop.prevent
                        @mousedown.stop.prevent
                        @touchstart.stop.prevent
                        :title="$t('reapply')"
                      >
                        <span v-if="applyingShaperUser === row.user" class="loading loading-spinner loading-xs"></span>
                        <ArrowPathIcon v-else class="h-4 w-4" />
                      </button>
                    </template>
                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="openLimits(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('limits')"
                    >
                      <AdjustmentsHorizontalIcon class="h-4 w-4" />
                    </button>

                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      @click.stop.prevent="startEdit(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('edit')"
                    >
                      <PencilSquareIcon class="h-4 w-4" />
                    </button>

                    <button
                      type="button"
                      class="btn btn-ghost btn-circle btn-xs relative z-20"
                      :disabled="!hasMapping(row.user)"
                      @click.stop.prevent="removeUser(row.user)"
                      @pointerdown.stop.prevent
                      @mousedown.stop.prevent
                      @touchstart.stop.prevent
                      :title="$t('delete')"
                    >
                      <TrashIcon class="h-4 w-4" />
                    </button>
                  </template>
                </div>
              </td>
            </tr>

            <tr v-if="!rows.length">
              <td colspan="8" class="text-center opacity-60">{{ $t('noContent') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="text-xs opacity-60">
        {{ $t('userTrafficTip') }} ({{ $t('buckets') }}: {{ buckets }})
      </div>

      
      <DialogWrapper v-model="reportDialogOpen">
        <div class="flex items-center justify-between gap-2 mb-2">
          <div class="text-base font-semibold">{{ $t('reports') }}</div>
          <div class="text-xs opacity-70 font-mono">
            {{ reportRangeLabel }}
          </div>
        </div>

        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <label class="flex flex-col gap-1 text-sm">
            <span class="opacity-70">{{ $t('groupBy') }}</span>
            <select class="select select-sm" v-model="reportGroupBy">
              <option value="day">{{ $t('day') }}</option>
              <option value="week">{{ $t('week') }}</option>
              <option value="month">{{ $t('month') }}</option>
            </select>
          </label>

          <label class="flex flex-col gap-1 text-sm">
            <span class="opacity-70">{{ $t('user') }}</span>
            <select class="select select-sm" v-model="reportUser">
              <option value="">{{ $t('allUsers') }}</option>
              <option v-for="u in reportUsers" :key="u" :value="u">
                {{ u }}
              </option>
            </select>
          </label>

          <label class="flex items-center justify-between gap-2 sm:pt-6">
            <span class="text-sm opacity-70">{{ $t('skipEmpty') }}</span>
            <input type="checkbox" class="toggle" v-model="reportSkipEmpty" />
          </label>
        </div>

        <div class="flex flex-wrap items-center justify-end gap-2 mt-2">
          <button type="button" class="btn btn-sm" @click="exportTableCsv">
            {{ $t('exportTableCsv') }}
          </button>
          <button type="button" class="btn btn-sm btn-primary" @click="exportReportCsv">
            {{ $t('exportReportCsv') }}
          </button>
        </div>

        <div class="mt-3 overflow-x-auto max-h-[52vh]">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{{ $t('period') }}</th>
                <th>{{ $t('user') }}</th>
                <th class="text-right">{{ $t('download') }}</th>
                <th class="text-right">{{ $t('upload') }}</th>
                <th class="text-right">{{ $t('total') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in reportPreviewRows" :key="r.period + '|' + r.user">
                <td class="font-mono whitespace-nowrap">{{ r.period }}</td>
                <td class="truncate max-w-[320px]" :title="r.user">{{ r.user }}</td>
                <td class="text-right font-mono">{{ format(r.dl) }}</td>
                <td class="text-right font-mono">{{ format(r.ul) }}</td>
                <td class="text-right font-mono">{{ format(r.dl + r.ul) }}</td>
              </tr>

              <tr v-if="!reportPreviewRows.length">
                <td colspan="5" class="text-center opacity-60">{{ $t('noContent') }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="mt-2 text-xs opacity-60">
          {{ $t('reportRows') }}: {{ reportRowsCount }}
          <span v-if="reportPreviewLimited">
            · {{ $t('previewLimited') }}
          </span>
        </div>
      </DialogWrapper>

      <DialogWrapper v-model="limitsDialogOpen">
        <div class="flex items-center justify-between gap-2 mb-2">
          <div class="text-base font-semibold">{{ $t('limits') }}</div>
          <div class="text-sm opacity-70 truncate max-w-[60%]" :title="limitsUser">{{ limitsUser }}</div>
        </div>

        <div class="grid grid-cols-1 gap-3">
          <label class="flex items-center justify-between gap-2">
            <span class="text-sm">{{ $t('enabled') }}</span>
            <input type="checkbox" class="toggle" v-model="draftEnabled" />
          </label>

          <label class="flex items-center justify-between gap-2">
            <span class="text-sm">{{ $t('blocked') }}</span>
            <input type="checkbox" class="toggle" v-model="draftDisabled" />
          </label>

          <div class="flex flex-col gap-1">
            <div class="flex items-center justify-between gap-2">
              <div class="text-sm">
                MAC
                <span class="text-xs opacity-60">({{ $t('routerAgent') }})</span>
              </div>
              <div class="flex items-center gap-2">
                <code
                  class="text-xs px-2 py-1 rounded bg-base-200"
                  :class="draftMac ? '' : 'opacity-50'"
                  :title="draftMac || ''"
                >
                  {{ draftMac || '—' }}
                </code>

                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  :disabled="!agentEnabled"
                  @click="refreshMac"
                  :title="$t('rebindMac')"
                >
                  <ArrowPathIcon class="h-4 w-4" :class="macLoading ? 'animate-spin' : ''" />
                </button>

                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  :disabled="!agentEnabled"
                  @click="refreshMacAndApply"
                  :title="$t('rebindMacApply')"
                >
                  <div class="flex items-center gap-1">
                    <ArrowPathIcon class="h-4 w-4" :class="macApplyLoading ? 'animate-spin' : ''" />
                    <CheckIcon class="h-4 w-4" />
                  </div>
                </button>

                <button type="button" class="btn btn-ghost btn-xs" :disabled="!draftMac" @click="clearMac">
                  {{ $t('clear') }}
                </button>
              </div>
            </div>

            <div v-if="macCandidates.length > 1" class="flex items-center gap-2">
              <select class="select select-sm" v-model="draftMac">
                <option v-for="m in macCandidates" :key="m" :value="m">{{ m }}</option>
              </select>
              <span class="text-xs opacity-60">{{ $t('multipleMacsFound') }}</span>
            </div>
          </div>

          <div class="divider my-0"></div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <label class="flex flex-col gap-1">
              <span class="text-sm opacity-70">{{ $t('trafficLimit') }}</span>
              <div class="flex items-center gap-2">
                <input
                  class="input input-sm flex-1"
                  type="number"
                  min="0"
                  step="0.1"
                  v-model.number="draftTrafficValue"
                  :disabled="!draftEnabled"
                />
                <select class="select select-sm w-20" v-model="draftTrafficUnit" :disabled="!draftEnabled">
                  <option value="GB">GB</option>
                  <option value="MB">MB</option>
                </select>
              </div>
            </label>

            <label class="flex flex-col gap-1">
              <span class="text-sm opacity-70">{{ $t('period') }}</span>
              <select class="select select-sm" v-model="draftPeriod" :disabled="!draftEnabled">
                <option value="1d">{{ $t('last24h') }}</option>
                <option value="30d">{{ $t('last30d') }}</option>
                <option value="month">{{ $t('thisMonth') }}</option>
              </select>
            </label>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-sm opacity-70">{{ $t('bandwidthLimit') }} (Mbps)</span>
            <input class="input input-sm" type="number" min="0" step="0.1" v-model.number="draftBandwidthMbps" :disabled="!draftEnabled" />
            <span class="text-xs opacity-60">{{ $t('bandwidthLimitTip') }}</span>
          </label>

          <div class="flex items-center justify-between gap-2">
            <div class="text-xs opacity-70">{{ $t('autoDisconnectLimitedUsers') }}</div>
            <input type="checkbox" class="toggle toggle-sm" v-model="autoDisconnectLimitedUsers" />
          </div>

          <div class="flex items-center justify-between gap-2">
            <div class="text-xs opacity-70">{{ $t('hardBlockLimitedUsers') }}</div>
            <input type="checkbox" class="toggle toggle-sm" v-model="hardBlockLimitedUsers" />
          </div>

          <div class="flex flex-wrap items-center justify-between gap-2">
            <button type="button" class="btn btn-sm" @click="resetCounter" :disabled="!draftEnabled">{{ $t('resetUsage') }}</button>
            <div class="flex items-center gap-2">
              <button type="button" class="btn btn-ghost btn-sm" @click="clearLimits">{{ $t('clearLimits') }}</button>
              <button type="button" class="btn btn-primary btn-sm" @click="saveLimits">{{ $t('save') }}</button>
            </div>
          </div>

          <div class="text-xs opacity-60">
            {{ $t('limitsEnforcementNote') }}
          </div>
        </div>
      </DialogWrapper>
    </div>
  </div>
</template>

<script setup lang="ts">
import DialogWrapper from '@/components/common/DialogWrapper.vue'
import { getIPLabelFromMap } from '@/helper/sourceip'
import { prettyBytesHelper } from '@/helper/utils'
import { showNotification } from '@/helper/notification'
import { activeConnections } from '@/store/connections'
import { sourceIPLabelList } from '@/store/settings'
import { autoDisconnectLimitedUsers, hardBlockLimitedUsers, userLimits, type UserLimitPeriod } from '@/store/userLimits'
import { userLimitProfiles } from '@/store/userLimitProfiles'
import { agentEnabled, agentEnforceBandwidth, agentShaperStatus } from '@/store/agent'
import {
  clearUserLimit,
  getIpsForUser,
  getUserLimit,
  getUserLimitState,
  applyUserEnforcementNow,
  reapplyAgentShapingForUser,
  setUserLimit,
} from '@/composables/userLimits'
import { applyProfileToUsers, disableLimitsForUsers, unblockResetUsers } from '@/composables/userLimitProfiles'
import {
  clearUserTrafficHistory,
  formatTraffic,
  getTrafficGrouped,
  getTrafficRange,
  getUserHourBucket,
  type TrafficGroupBy,
  userTrafficStoreSize,
} from '@/composables/userTraffic'
import dayjs from 'dayjs'
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { v4 as uuidv4 } from 'uuid'
import { useTooltip } from '@/helper/tooltip'
import {
  AdjustmentsHorizontalIcon,
  ArrowPathIcon,
  BoltIcon,
  CheckIcon,
  CheckCircleIcon,
  CircleStackIcon,
  LockClosedIcon,
  PencilSquareIcon,
  QuestionMarkCircleIcon,
  TrashIcon,
  XMarkIcon,
} from '@heroicons/vue/24/outline'

type Row = { user: string; keys: string; dl: number; ul: number }

const editingUser = ref<string | null>(null)
const editingName = ref('')

const router = useRouter()
const { t } = useI18n()
const { showTip, hideTip } = useTooltip()

// --- Bulk actions (profiles / mass apply) ---
const selectedMap = ref<Record<string, boolean>>({})
const selectedList = computed(() => Object.keys(selectedMap.value || {}).filter((u) => selectedMap.value[u]))
const clearSelection = () => {
  selectedMap.value = {}
}

const limitProfiles = computed(() => userLimitProfiles.value || [])
const bulkProfileId = ref<string>('')
const bulkBusy = ref(false)

const allSelected = computed(() => {
  const list = rows.value || []
  if (!list.length) return false
  return list.every((r) => !!selectedMap.value[r.user])
})

const toggleSelectAll = () => {
  const list = rows.value || []
  const want = !allSelected.value
  const next: Record<string, boolean> = { ...(selectedMap.value || {}) }
  for (const r of list) next[r.user] = want
  selectedMap.value = next
}

const applyProfileBulk = async () => {
  const id = (bulkProfileId.value || '').trim()
  if (!id) return
  const p = (limitProfiles.value || []).find((x) => x.id === id)
  if (!p) return
  if (bulkBusy.value) return
  bulkBusy.value = true
  try {
    await applyProfileToUsers(selectedList.value, p)
    clearSelection()
  } finally {
    bulkBusy.value = false
  }
}

const bulkUnblockReset = async () => {
  if (bulkBusy.value) return
  bulkBusy.value = true
  try {
    await unblockResetUsers(selectedList.value)
    clearSelection()
    showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    bulkBusy.value = false
  }
}

const bulkDisableLimits = async () => {
  if (bulkBusy.value) return
  bulkBusy.value = true
  try {
    await disableLimitsForUsers(selectedList.value)
    clearSelection()
    showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    bulkBusy.value = false
  }
}

const goPolicies = () => {
  router.push({ name: 'policies' })
}

const looksLikeIP = (s: string) => {
  const v = (s || '').trim()
  if (!v) return false
  const v4 = /^\d{1,3}(?:\.\d{1,3}){3}$/.test(v)
  const v6 = v.includes(':')
  return v4 || v6
}

// Normalize user display strings to prevent duplicates (case/whitespace variations).
const normalizeUserName = (s: string) => {
  return (s || '').toString().trim().replace(/\s+/g, ' ').toLowerCase()
}


const hasMapping = (user: string) => {
  const u = (user || '').trim()
  if (!u) return false
  return sourceIPLabelList.value.some((it) => (it.label || it.key) === u || it.key === u)
}

const startEdit = (user: string) => {
  editingUser.value = user
  const mapped = sourceIPLabelList.value.find((it) => it.key === user) || null
  editingName.value = (mapped?.label || user || '').toString()
}

const cancelEdit = () => {
  editingUser.value = null
  editingName.value = ''
}

const saveEdit = () => {
  const oldUser = editingUser.value
  const next = editingName.value.trim()
  if (!oldUser || !next) return

  let changed = false
  for (const it of sourceIPLabelList.value) {
    const u = it.label || it.key
    if (u === oldUser || it.key === oldUser) {
      it.label = next
      changed = true
    }
  }

  if (!changed && looksLikeIP(oldUser)) {
    sourceIPLabelList.value.push({
      key: oldUser,
      label: next,
      id: uuidv4(),
    })
  }

  cancelEdit()
}

const removeUser = (user: string) => {
  const u = (user || '').trim()
  if (!u) return
  for (let i = sourceIPLabelList.value.length - 1; i >= 0; i--) {
    const it = sourceIPLabelList.value[i]
    const name = it.label || it.key
    if (name === u || it.key === u) sourceIPLabelList.value.splice(i, 1)
  }
}

const preset = ref<'1h' | '24h' | '7d' | '30d' | 'custom'>('24h')
const topN = ref<number>(30)

type SortKey = 'user' | 'keys' | 'dl' | 'ul' | 'total'
const sortKey = ref<SortKey>('total')
const sortDir = ref<'asc' | 'desc'>('desc')

const setSort = (k: SortKey) => {
  if (sortKey.value === k) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortKey.value = k
    sortDir.value = k === 'user' || k === 'keys' ? 'asc' : 'desc'
  }
}

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
  // Map normalized display user -> list of IP keys.
  const map = new Map<string, string[]>()
  for (const item of sourceIPLabelList.value || []) {
    const display = String((item as any)?.label || (item as any)?.key || '').trim()
    const ip = String((item as any)?.key || '').trim()
    if (!display || !ip) continue
    const norm = normalizeUserName(display)
    const keys = map.get(norm) || []
    if (!keys.includes(ip)) keys.push(ip)
    map.set(norm, keys)
  }
  return map
})

const canonicalUserByNorm = computed(() => {
  // Prefer explicit labels over raw IPs for display.
  const map = new Map<string, string>()
  for (const item of sourceIPLabelList.value || []) {
    const ip = String((item as any)?.key || '').trim()
    const label = String((item as any)?.label || '').trim()
    const display = (label || ip).trim()
    if (!display) continue
    const norm = normalizeUserName(display)
    const prev = map.get(norm)
    if (!prev) map.set(norm, display)
    else if (label && looksLikeIP(prev)) map.set(norm, display)
  }
  return map
})

const rows = computed<Row[]>(() => {
  const { start, end } = range.value
  // Traffic history buckets are primarily stored by stable keys (IP).
  const aggByKey = getTrafficRange(start, end)

  const normToIps = new Map<string, Set<string>>()
  for (const [norm, ips] of knownKeysByUser.value.entries()) {
    normToIps.set(norm, new Set(ips))
  }

  // Legacy buckets could still be stored under a label/synthetic key.
  const legacyKeysByNorm = new Map<string, Set<string>>()
  for (const k of aggByKey.keys()) {
    const key = String(k || '').trim()
    if (!key) continue
    if (looksLikeIP(key)) continue
    const norm = normalizeUserName(key)
    const set = legacyKeysByNorm.get(norm) || new Set<string>()
    set.add(key)
    legacyKeysByNorm.set(norm, set)
  }

  const canonicalFor = (s: string) => {
    const raw = String(s || '').trim()
    if (!raw) return ''
    const norm = normalizeUserName(raw)
    return canonicalUserByNorm.value.get(norm) || raw
  }

  const addUser = (map: Map<string, string>, raw: string) => {
    const disp = canonicalFor(raw)
    if (!disp) return
    const norm = normalizeUserName(disp)
    if (!map.has(norm)) map.set(norm, disp)
  }

  const all = new Map<string, string>()

  // From saved mapping.
  for (const [norm, ips] of normToIps.entries()) {
    const disp = canonicalUserByNorm.value.get(norm) || (ips.values().next().value || '')
    if (disp) all.set(norm, disp)
  }

  const displayUserForKey = (k: string) => {
    const key = String(k || '').trim()
    if (!key) return ''
    if (looksLikeIP(key)) return (getIPLabelFromMap(key) || key).toString()
    return key
  }

  // From traffic buckets.
  for (const k of aggByKey.keys()) {
    addUser(all, displayUserForKey(String(k)))
  }

  // Also include users with saved limits (after applying profiles)
  for (const u of Object.keys(userLimits.value || {})) addUser(all, u)

  // Fallback: ensure active users are still visible even if traffic history is empty
  for (const c of activeConnections.value || []) {
    const ip = String((c as any)?.metadata?.sourceIP || '').trim()
    const u = (getIPLabelFromMap(ip) || ip || '').toString()
    addUser(all, u)
  }

  const list: Row[] = Array.from(all.entries()).map(([norm, user]) => {
    const keysSet = new Set<string>()

    // IP keys from mapping.
    for (const ip of normToIps.get(norm) || []) keysSet.add(ip)

    // If the displayed user is an IP itself, include it.
    if (looksLikeIP(user)) keysSet.add(user)

    // Legacy buckets stored under a label/synthetic key.
    for (const lk of legacyKeysByNorm.get(norm) || []) keysSet.add(lk)

    let dl = 0
    let ul = 0
    for (const k of keysSet) {
      const t = aggByKey.get(k)
      dl += t?.dl || 0
      ul += t?.ul || 0
    }

    const ipKeys = Array.from(keysSet).filter((k) => looksLikeIP(k))
    ipKeys.sort((a, b) => a.localeCompare(b))
    const keys = ipKeys.join(', ')

    return { user, keys, dl, ul }
  })

  const sorted = list.sort((a, b) => {
    const dir = sortDir.value === 'asc' ? 1 : -1
    if (sortKey.value === 'user') return dir * a.user.localeCompare(b.user)
    if (sortKey.value === 'keys') return dir * a.keys.localeCompare(b.keys)
    if (sortKey.value === 'dl') return dir * (a.dl - b.dl)
    if (sortKey.value === 'ul') return dir * (a.ul - b.ul)
    const at = a.dl + a.ul
    const bt = b.dl + b.ul
    return dir * (at - bt)
  })

  if (topN.value > 0) return sorted.slice(0, topN.value)
  return sorted
})

const speed = (bps: number) => `${prettyBytesHelper(bps || 0)}/s`
const format = (b: number) => formatTraffic(b)
const buckets = computed(() => userTrafficStoreSize.value)

const bpsToMbps = (bps: number) => {
  const v = ((bps || 0) * 8) / 1_000_000
  if (!Number.isFinite(v) || v <= 0) return '0'
  const r = v >= 100 ? Math.round(v) : Math.round(v * 10) / 10
  return String(r).replace(/\.0$/, '')
}

const trafficIconTitle = (limitBytes: number, period: UserLimitPeriod, enabled: boolean) => {
  const on = enabled ? '' : ' (выкл)'
  return `Лимит трафика: ${format(limitBytes)} / ${periodLabel(period)}${on}`
}

const bandwidthIconTitle = (bps: number, enabled: boolean) => {
  const on = enabled ? '' : ' (выкл)'
  return `Лимит канала: ${bpsToMbps(bps)} Mbps${on}`
}

const clearHistory = () => {
  clearUserTrafficHistory()
}

// --- Limits aggregation for the table ---
const normalizeResetAt = (ts: number) => {
  // legacy fallback (when baseline fields are missing)
  const d = dayjs(ts)
  if (d.minute() === 0 && d.second() === 0 && d.millisecond() === 0) return ts
  return d.add(1, 'hour').startOf('hour').valueOf()
}

const hasResetBaseline = (l: any) => {
  return !!l?.resetHourKey && Number.isFinite(l?.resetHourDl) && Number.isFinite(l?.resetHourUl)
}

const windowForLimit = (l: ReturnType<typeof getUserLimit>) => {
  const now = dayjs()
  let start = now.subtract(30, 'day')
  if (l.trafficPeriod === '1d') start = now.subtract(24, 'hour')
  if (l.trafficPeriod === 'month') start = now.startOf('month')
  let startTs = start.valueOf()

  let useBaseline = false
  if (l.resetAt && l.resetAt > startTs) {
    if (hasResetBaseline(l)) {
      startTs = l.resetAt
      useBaseline = true
    } else {
      startTs = normalizeResetAt(l.resetAt)
      useBaseline = false
    }
  }

  const startHourTs = dayjs(startTs).startOf('hour').valueOf()
  return { startTs, startHourTs, endTs: now.valueOf(), useBaseline }
}

const periodLabel = (p: UserLimitPeriod) => {
  if (p === '1d') return '24h'
  if (p === 'month') return 'month'
  return '30d'
}

const speedByUser = computed(() => {
  const map: Record<string, number> = {}
  for (const c of activeConnections.value) {
    const user = getIPLabelFromMap(c?.metadata?.sourceIP || '')
    map[user] = (map[user] || 0) + (c.downloadSpeed || 0) + (c.uploadSpeed || 0)
  }
  return map
})

const limitStates = computed(() => {
  const out: Record<
    string,
    {
      enabled: boolean
      usageBytes: number
      trafficLimitBytes: number
      bandwidthLimitBps: number
      speedBps: number
      blocked: boolean
      percent: string
      periodLabel: string
    }
  > = {}

  // Build windows per user appearing in the table.
  const windows = new Map<string, { startHourTs: number; endTs: number; users: string[] }>()
  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    const hasTraffic = (l.trafficLimitBytes || 0) > 0
    const hasBw = (l.bandwidthLimitBps || 0) > 0
    if (!hasTraffic && !hasBw && !l.disabled) continue

    const w = windowForLimit(l)
    const key = `${l.trafficPeriod}:${w.startHourTs}`
    const item = windows.get(key) || { startHourTs: w.startHourTs, endTs: w.endTs, users: [] }
    item.users.push(row.user)
    windows.set(key, item)
  }

  const aggByKey = new Map<string, Map<string, { dl: number; ul: number }>>()
  for (const [key, w] of windows.entries()) {
    aggByKey.set(key, getTrafficRange(w.startHourTs, w.endTs))
  }

  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    const w = windowForLimit(l)
    const key = `${l.trafficPeriod}:${w.startHourTs}`
    const agg = aggByKey.get(key)
    const keys = new Set<string>([row.user])
    for (const ip of getIpsForUser(row.user) || []) keys.add(ip)

    let dl = 0
    let ul = 0
    for (const k of keys) {
      const t = agg?.get(k)
      dl += t?.dl || 0
      ul += t?.ul || 0
    }
    if (w.useBaseline) {
      dl = Math.max(0, dl - (l.resetHourDl || 0))
      ul = Math.max(0, ul - (l.resetHourUl || 0))
    }
    const usage = dl + ul
    const tl = l.trafficLimitBytes || 0

    const sp = speedByUser.value[row.user] || 0
    const bl = l.bandwidthLimitBps || 0

    const trafficExceeded = l.enabled && tl > 0 && usage >= tl
    const bandwidthExceeded = l.enabled && bl > 0 && sp >= bl

    const bwViaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value

    // Manual block works regardless of "enabled".
    const blocked = l.disabled || (l.enabled && (trafficExceeded || (!bwViaAgent && bandwidthExceeded)))

    const pct = tl > 0 ? Math.min(999, Math.floor((usage / tl) * 100)) : 0

    out[row.user] = {
      enabled: !!l.enabled,
      usageBytes: usage,
      trafficLimitBytes: tl,
      bandwidthLimitBps: bl,
      speedBps: sp,
      blocked,
      percent: tl > 0 ? String(pct) : '0',
      periodLabel: periodLabel(l.trafficPeriod),
    }
  }

  return out
})

const blockedActionBusy = ref(false)

const setResetBaselineNow = (user: string, extra: Record<string, any> = {}) => {
  const now = Date.now()
  const keys = new Set<string>([user])
  for (const ip of getIpsForUser(user) || []) keys.add(ip)

  let dl = 0
  let ul = 0
  for (const k of keys) {
    const b = getUserHourBucket(k, now)
    dl += b.dl || 0
    ul += b.ul || 0
  }

  setUserLimit(user, {
    ...extra,
    resetAt: now,
    resetHourKey: dayjs(now).format('YYYY-MM-DDTHH'),
    resetHourDl: dl,
    resetHourUl: ul,
  })
}

const applyNow = async () => {
  if (blockedActionBusy.value) return
  blockedActionBusy.value = true
  try {
    await applyUserEnforcementNow()
  } finally {
    blockedActionBusy.value = false
  }
}

const blockedList = computed(() => {
  const out: Array<{
    user: string
    ips: string
    usageBytes: number
    trafficLimitBytes: number
    bandwidthLimitBps: number
    limitEnabled: boolean
    periodLabel: string
    periodKey: UserLimitPeriod
    reasonManual: boolean
    reasonTraffic: boolean
    reasonBandwidth: boolean
  }> = []

  const keys = Object.keys(userLimits.value || {})
  for (const user of keys) {
    const st = getUserLimitState(user)
    if (!st.blocked) continue
    const ips = (getIpsForUser(user) || []).join(', ')
    out.push({
      user,
      ips,
      usageBytes: st.usageBytes || 0,
      trafficLimitBytes: st.limit.trafficLimitBytes || 0,
      bandwidthLimitBps: st.limit.bandwidthLimitBps || 0,
      limitEnabled: !!st.limit.enabled,
      periodLabel: periodLabel(st.limit.trafficPeriod),
      periodKey: st.limit.trafficPeriod,
      reasonManual: !!st.limit.disabled,
      reasonTraffic: !!st.trafficExceeded,
      reasonBandwidth: !!st.bandwidthExceeded,
    })
  }

  // Sort: manual first, then traffic exceed, then bandwidth.
  out.sort((a, b) => {
    const pa = a.reasonManual ? 0 : a.reasonTraffic ? 1 : a.reasonBandwidth ? 2 : 3
    const pb = b.reasonManual ? 0 : b.reasonTraffic ? 1 : b.reasonBandwidth ? 2 : 3
    if (pa !== pb) return pa - pb
    return a.user.localeCompare(b.user)
  })

  return out
})

const unblockAndReset = async (user: string) => {
  if (!user) return
  if (blockedActionBusy.value) return
  blockedActionBusy.value = true
  try {
    const l = getUserLimit(user)
    setResetBaselineNow(user, {
      disabled: false,
      // Keep enabled as-is.
      enabled: l.enabled,
    })
    await applyUserEnforcementNow()
    showNotification({ content: 'blockedUnblockDone', params: { user }, type: 'alert-success', timeout: 2200 })
  } catch (e) {
    console.error(e)
    showNotification({ content: 'blockedActionFailed', params: { user }, type: 'alert-error', timeout: 4500 })
  } finally {
    blockedActionBusy.value = false
  }
}

const disableLimitsQuick = async (user: string) => {
  if (!user) return
  if (blockedActionBusy.value) return
  blockedActionBusy.value = true
  try {
    setResetBaselineNow(user, { enabled: false, disabled: false })
    await applyUserEnforcementNow()
    showNotification({ content: 'blockedDisableDone', params: { user }, type: 'alert-success', timeout: 2200 })
  } catch (e) {
    console.error(e)
    showNotification({ content: 'blockedActionFailed', params: { user }, type: 'alert-error', timeout: 4500 })
  } finally {
    blockedActionBusy.value = false
  }
}


type ShaperBadge = { icon: any; cls: string; title: string; showReapply: boolean }

const shaperBadge = computed<Record<string, ShaperBadge | null>>(() => {
  const out: Record<string, ShaperBadge | null> = {}
  const viaAgent = !!agentEnabled.value && !!agentEnforceBandwidth.value
  if (!viaAgent) return out

  const st = agentShaperStatus.value || {}

  for (const row of rows.value) {
    const l = getUserLimit(row.user)
    if (!l.enabled || !l.bandwidthLimitBps || l.bandwidthLimitBps <= 0) {
      out[row.user] = null
      continue
    }

    const ips = getIpsForUser(row.user)
    if (!ips.length) {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: `${row.user}: no IPs`,
        showReapply: true,
      }
      continue
    }

    const statuses = ips.map((ip) => st[ip]).filter(Boolean)
    const hasFail = ips.some((ip) => st[ip] && st[ip].ok === false)
    const allOk = ips.every((ip) => st[ip] && st[ip].ok === true)

    if (hasFail) {
      const firstErr = ips.map((ip) => st[ip]).find((x) => x && !x.ok)?.error
      out[row.user] = {
        icon: XMarkIcon,
        cls: 'text-error',
        title: `${t('shaperFailed')}${firstErr ? `: ${firstErr}` : ''}`,
        showReapply: true,
      }
    } else if (allOk) {
      out[row.user] = {
        icon: CheckCircleIcon,
        cls: 'text-success',
        title: t('shaperApplied'),
        showReapply: true,
      }
    } else if (!statuses.length) {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: t('shaperUnknown'),
        showReapply: true,
      }
    } else {
      out[row.user] = {
        icon: QuestionMarkCircleIcon,
        cls: 'text-base-content/60',
        title: t('shaperUnknown'),
        showReapply: true,
      }
    }
  }

  return out
})

const applyingShaperUser = ref<string | null>(null)
const reapplyShaper = async (user: string) => {
  if (!user) return
  applyingShaperUser.value = user
  try {
    await reapplyAgentShapingForUser(user)
  } finally {
    applyingShaperUser.value = null
  }
}

// --- Limits dialog ---
const limitsDialogOpen = ref(false)
const limitsUser = ref('')

const draftEnabled = ref(false)
const draftDisabled = ref(false)
const draftMac = ref('')
const macCandidates = ref<string[]>([])
const macLoading = ref(false)
const macApplyLoading = ref(false)
const draftTrafficValue = ref<number>(0)
const draftTrafficUnit = ref<'GB' | 'MB'>('GB')
const draftBandwidthMbps = ref<number>(0)
const draftPeriod = ref<UserLimitPeriod>('30d')

const bytesFromTraffic = (value: number, unit: 'GB' | 'MB') => {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return 0
  const factor = unit === 'GB' ? 1_000_000_000 : 1_000_000
  return Math.round(n * factor)
}

const bpsFromMbps = (mbps: number) => {
  const n = Number(mbps)
  if (!Number.isFinite(n) || n <= 0) return 0
  return Math.round((n * 1_000_000) / 8)
}

const openLimits = (user: string) => {
  limitsUser.value = user
  const l = getUserLimit(user)
  draftEnabled.value = l.enabled
  draftDisabled.value = l.disabled
  draftMac.value = (l.mac || '').toString().trim().toLowerCase()
  macCandidates.value = draftMac.value ? [draftMac.value] : []
  draftPeriod.value = l.trafficPeriod
  draftTrafficUnit.value = (l.trafficLimitUnit as any) || (l.trafficLimitBytes >= 1_000_000_000 ? 'GB' : 'MB')
  const factor = draftTrafficUnit.value === 'GB' ? 1_000_000_000 : 1_000_000
  draftTrafficValue.value = l.trafficLimitBytes ? +(l.trafficLimitBytes / factor).toFixed(2) : 0
  draftBandwidthMbps.value = l.bandwidthLimitBps ? +(((l.bandwidthLimitBps * 8) / 1_000_000)).toFixed(2) : 0
  limitsDialogOpen.value = true
}

const refreshMac = async () => {
  const user = limitsUser.value
  if (!user) return
  if (!agentEnabled.value) return

  const ips = getIpsForUser(user)
  if (!ips.length) return

  macLoading.value = true
  try {
    const macs = new Set<string>()

    const macRe = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i
    const extractMac = (val: any): string => {
      if (!val) return ''
      if (typeof val === 'string') {
        const v = val.trim().toLowerCase()
        return macRe.test(v) ? v : ''
      }
      if (typeof val !== 'object') return ''
      const candidates = [
        (val as any).mac,
        (val as any).MAC,
        (val as any).result,
        (val as any).value,
        (val as any).data?.mac,
        (val as any).data?.value,
      ]
      for (const c of candidates) {
        const m = extractMac(c)
        if (m) return m
      }
      return ''
    }

    // Lazy import to avoid increasing initial bundle work.
    const { agentIpToMacAPI, agentNeighborsAPI } = await import('@/api/agent')

    // Neighbors fallback (single request), used when ip2mac fails or returns unexpected shape.
    let neighbors: any[] | null = null
    const loadNeighbors = async () => {
      if (neighbors !== null) return neighbors
      const n = await agentNeighborsAPI().catch(() => null)
      neighbors = n?.ok && n.items ? (n.items as any[]) : []
      return neighbors
    }

    // Prefer a direct ip->mac lookup (new agent). Fall back to neighbors list.
    for (const ip of ips) {
      const r = await agentIpToMacAPI(ip)
      const mac = extractMac(r)
      if ((r as any)?.ok && mac) {
        macs.add(mac)
        continue
      }

      // Fallback: neighbors table.
      const nitems = await loadNeighbors()
      for (const it of nitems) {
        if ((it?.ip || '').trim() !== ip) continue
        const m = extractMac(it?.mac)
        if (m) macs.add(m)
      }
    }

    const list = Array.from(macs).filter(Boolean)
    macCandidates.value = list
    if (list.length === 1) draftMac.value = list[0]
  } finally {
    macLoading.value = false
  }
}

const refreshMacAndApply = async () => {
  const user = limitsUser.value
  if (!user) return
  if (!agentEnabled.value) return

  macApplyLoading.value = true
  try {
    await refreshMac()
    const mac = (draftMac.value || '').trim().toLowerCase()
    if (!mac) return

    // Persist learned MAC even if the user doesn't press "Save".
    setUserLimit(user, { mac })

    // Apply blocks/shaping right away (helps when DHCP changes IPs).
    await applyUserEnforcementNow()
    // Best-effort: also re-apply shaping for this user.
    await reapplyAgentShapingForUser(user)
  } finally {
    macApplyLoading.value = false
  }
}

const clearMac = () => {
  draftMac.value = ''
  macCandidates.value = []
}

const saveLimits = async () => {
  const user = limitsUser.value
  if (!user) return

  const trafficLimitBytes = bytesFromTraffic(draftTrafficValue.value, draftTrafficUnit.value)
  const bandwidthLimitBps = bpsFromMbps(draftBandwidthMbps.value)

  const enabled = !!draftEnabled.value
  const disabled = !!draftDisabled.value

  // Default: don't persist an entry unless user really sets something.
  if (!enabled && !disabled && !trafficLimitBytes && !bandwidthLimitBps) {
    clearUserLimit(user)
    limitsDialogOpen.value = false
    return
  }

  setUserLimit(user, {
    enabled,
    disabled,
    mac: draftMac.value ? draftMac.value : undefined,
    trafficPeriod: draftPeriod.value,
    trafficLimitBytes: trafficLimitBytes || undefined,
    trafficLimitUnit: trafficLimitBytes ? draftTrafficUnit.value : undefined,
    bandwidthLimitBps: bandwidthLimitBps || undefined,
  })

  limitsDialogOpen.value = false

  // Apply right away so that manual block/limits feel instant.
  try {
    await applyUserEnforcementNow()
  } catch {
    // ignore
  }
}

const clearLimits = async () => {
  const user = limitsUser.value
  if (!user) return
  clearUserLimit(user)
  limitsDialogOpen.value = false
  try {
    await applyUserEnforcementNow()
  } catch {
    // ignore
  }
}

const resetCounter = async () => {
  const user = limitsUser.value
  if (!user) return
  setResetBaselineNow(user)
  try {
    await applyUserEnforcementNow()
  } catch {
    // ignore
  }
}
</script>
