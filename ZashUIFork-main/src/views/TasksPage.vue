<template>
  <div class="flex h-full flex-col gap-2 overflow-x-hidden overflow-y-auto p-2">
    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('quickActions') }}</div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" @click="applyEnforcement" :disabled="busy">
          {{ $t('applyEnforcementNow') }}
        </button>
        <button type="button" class="btn btn-sm" @click="refreshSsl" :disabled="busy || !agentEnabled">
          {{ $t('refreshProvidersSsl') }}
        </button>
      </div>

      <div class="text-xs opacity-70">
        <div>• {{ $t('applyEnforcementTip') }}</div>
        <div>• {{ $t('refreshProvidersSslTip') }}</div>
      </div>

      <div class="mt-2 rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <div class="flex items-center justify-between gap-2">
          <div class="text-xs font-semibold opacity-80">{{ $t('routerUiUrlTitle') }}</div>
          <div class="flex items-center gap-2">
            <button type="button" class="btn btn-xs btn-ghost" @click="copyRouterUiUrl(false)">
              {{ $t('copy') }}
            </button>
            <button type="button" class="btn btn-xs btn-ghost" @click="copyRouterUiUrl(true)">
              {{ $t('copyYamlLine') }}
            </button>
          </div>
        </div>
        <div class="mt-1 text-[11px] opacity-60">{{ $t('routerUiUrlTip') }}</div>
        <div class="mt-1 break-all font-mono text-xs opacity-80">{{ routerUiUrl }}</div>
      </div>
    </div>

    <div class="card gap-2 p-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('providersPanelTitle') }}</div>
        <div class="flex items-center gap-2">
          <button type="button" class="btn btn-sm btn-ghost" @click="loadProvidersPanel(true)" :disabled="providersPanelBusy || !agentEnabled">
            {{ $t('refresh') }}
          </button>
        </div>
      </div>

      <div class="text-xs opacity-70">{{ $t('providersPanelTip') }}</div>

      <div v-if="!agentEnabled" class="text-sm opacity-70">
        {{ $t('agentDisabled') }}
      </div>
      <div v-else-if="providersPanelBusy" class="text-sm opacity-70">…</div>
      <div v-else>
        <div v-if="providersPanelError" class="text-xs text-error">{{ providersPanelError }}</div>
        <div v-else-if="!providersPanelList.length" class="text-sm opacity-70">—</div>
        <div v-else class="flex flex-col gap-2">
          <div
            v-for="p in providersPanelList"
            :key="p.name"
            class="rounded-lg border border-base-content/10 bg-base-200/40 p-2"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <div class="truncate font-mono text-xs" :title="p.name">{{ p.name }}</div>
                <div v-if="p.url" class="mt-0.5 truncate text-[11px] opacity-60" :title="p.url">{{ p.url }}</div>
              </div>
              <div class="shrink-0 text-[11px] font-mono opacity-70" :title="$t('sslExpire')">
                {{ fmtSslPanel(p.sslNotAfter) }}
              </div>
            </div>

            <div class="mt-2 flex flex-wrap items-center gap-2">
              <input
                type="text"
                class="input input-bordered input-sm flex-1 min-w-[260px]"
                :placeholder="$t('providerPanelUrlPlaceholder')"
                :value="proxyProviderPanelUrlMap[p.name] || ''"
                @input="(e) => setProviderPanelUrl(p.name, (e && e.target && e.target.value) || '')"
              />
              <a
                v-if="proxyProviderPanelUrlMap[p.name]"
                class="btn btn-sm"
                :href="proxyProviderPanelUrlMap[p.name]"
                target="_blank"
                rel="noreferrer"
              >
                {{ $t('open') }}
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('liveLogs') }}</div>
        <div class="flex items-center gap-2">
          <select class="select select-bordered select-sm" v-model="logSource">
            <option value="mihomo">{{ $t('mihomoLog') }}</option>
            <option value="config">{{ $t('mihomoConfig') }}</option>
            <option value="agent">{{ $t('agentLog') }}</option>
          </select>
          <select class="select select-bordered select-sm" v-model.number="logLines">
            <option :value="50">50</option>
            <option :value="200">200</option>
            <option :value="500">500</option>
            <option :value="1000">1000</option>
          </select>
          <button type="button" class="btn btn-sm" @click="forceRefreshLogs" :disabled="logsBusy || !agentEnabled">
            {{ $t('refresh') }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2 text-xs opacity-70">
        <div>
          <span class="opacity-60">{{ $t('path') }}:</span>
          <span class="font-mono">{{ logPath || '—' }}</span>
        </div>
        <label class="flex items-center gap-2">
          <span>{{ $t('autoRefresh') }}</span>
          <input type="checkbox" class="toggle toggle-sm" v-model="logsAuto" />
        </label>
      </div>

      <div v-if="!agentEnabled" class="text-sm opacity-70">
        {{ $t('agentDisabled') }}
      </div>
      <div v-else class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <pre class="max-h-[48vh] overflow-auto whitespace-pre-wrap break-words font-mono text-[11px] leading-4">{{ logText || '—' }}</pre>
      </div>
    </div>


    <div class="card gap-2 p-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('dataFreshness') }}</div>
        <div class="flex flex-wrap items-center gap-2">
          <button type="button" class="btn btn-sm" @click="updateGeoNow" :disabled="geoUpdateBusy || !agentEnabled">
            {{ $t('updateGeoNow') }}
          </button>
          <button type="button" class="btn btn-sm" @click="updateRuleProvidersNow" :disabled="providersUpdateBusy">
            {{ $t('updateRuleProvidersNow') }}
          </button>
          <button type="button" class="btn btn-sm btn-ghost" @click="rescanLocalRules" :disabled="rulesRescanBusy || !agentEnabled">
            {{ $t('rescanLocalRules') }}
          </button>
          <button type="button" class="btn btn-sm btn-ghost" @click="refreshFreshness" :disabled="freshnessBusy">
            {{ $t('refresh') }}
          </button>
        </div>
      </div>

      <div class="text-xs opacity-70">
        <span class="opacity-60">{{ $t('lastUiRefresh') }}:</span>
        <span class="ml-1 font-mono">{{ fmtTs(lastFreshnessOkAt) }}</span>
      </div>

      <details v-if="lastGeoUpdate?.at" class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <summary class="cursor-pointer text-xs font-semibold opacity-80">
          {{ $t('lastGeoUpdateResult') }}
          <span class="ml-2 font-mono opacity-70">{{ fmtTs(lastGeoUpdate.at) }}</span>
          <span v-if="lastGeoUpdate.ok" class="ml-2 badge badge-success badge-xs">OK</span>
          <span v-else class="ml-2 badge badge-error badge-xs">ERR</span>
        </summary>

        <div class="mt-2 flex flex-col gap-1 text-xs">
          <div v-for="it in (lastGeoUpdate.items || [])" :key="it.kind + ':' + it.path" class="flex flex-col gap-1 rounded-md border border-base-content/10 bg-base-100/40 p-2">
            <div class="flex items-center justify-between gap-2">
              <div class="min-w-0">
                <span class="font-semibold opacity-80">{{ geoKindLabel(it.kind) }}</span>
                <span class="ml-2 font-mono opacity-70" :title="it.path">{{ shortPath(it.path) }}</span>
                <span v-if="it.changed" class="ml-2 badge badge-info badge-xs">{{ $t('changed') }}</span>
              </div>
              <div class="shrink-0 font-mono opacity-80">{{ fmtMtime(it.mtimeSec) }}</div>
            </div>

            <div class="flex flex-wrap items-center gap-x-3 gap-y-1 opacity-70">
              <div v-if="it.method">
                <span class="opacity-60">{{ $t('method') }}:</span>
                <span class="ml-1 font-mono">{{ it.method }}</span>
              </div>
              <div v-if="typeof it.sizeBytes === 'number' && it.sizeBytes >= 0">
                <span class="opacity-60">{{ $t('size') }}:</span>
                <span class="ml-1 font-mono">{{ prettyBytesHelper(it.sizeBytes) }}</span>
              </div>
              <div v-if="it.source" class="min-w-0">
                <span class="opacity-60">{{ $t('source') }}:</span>
                <span class="ml-1 truncate font-mono" :title="it.source">{{ it.source }}</span>
              </div>
            </div>

            <div v-if="it.ok === false || it.error" class="text-error">
              {{ it.error || 'failed' }}
            </div>
          </div>

          <div v-if="lastGeoUpdate.note" class="mt-1 text-[11px] opacity-60">
            {{ lastGeoUpdate.note }}
          </div>
          <div class="text-[11px] opacity-60">
            {{ $t('geoRestartTip') }}
          </div>
        </div>
      </details>

      <details v-if="lastRuleProvidersUpdate?.at" class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <summary class="cursor-pointer text-xs font-semibold opacity-80">
          {{ $t('lastRuleProvidersUpdateResult') }}
          <span class="ml-2 font-mono opacity-70">{{ fmtTs(lastRuleProvidersUpdate.at) }}</span>
          <span v-if="lastRuleProvidersUpdate.ok" class="ml-2 badge badge-success badge-xs">OK</span>
          <span v-else class="ml-2 badge badge-error badge-xs">ERR</span>
        </summary>

        <div class="mt-2 flex flex-col gap-2 text-xs">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 opacity-70">
            <div>
              <span class="opacity-60">{{ $t('total') }}:</span>
              <span class="ml-1 font-mono">{{ lastRuleProvidersUpdate.total }}</span>
            </div>
            <div>
              <span class="opacity-60">OK:</span>
              <span class="ml-1 font-mono">{{ lastRuleProvidersUpdate.okCount }}</span>
            </div>
            <div>
              <span class="opacity-60">ERR:</span>
              <span class="ml-1 font-mono">{{ lastRuleProvidersUpdate.failCount }}</span>
            </div>
          </div>

          <div v-for="it in (lastRuleProvidersUpdate.items || [])" :key="it.name" class="flex flex-col gap-1 rounded-md border border-base-content/10 bg-base-100/40 p-2">
            <div class="flex items-center justify-between gap-2">
              <div class="min-w-0">
                <span class="min-w-0 truncate font-mono" :title="it.name">{{ it.name }}</span>
                <span v-if="it.changed" class="ml-2 badge badge-info badge-xs">{{ $t('changed') }}</span>
                <span v-if="it.ok" class="ml-2 badge badge-success badge-xs">OK</span>
                <span v-else class="ml-2 badge badge-error badge-xs">ERR</span>
              </div>
              <div class="shrink-0 font-mono opacity-70">{{ it.durationMs != null ? fmtMs(it.durationMs) : '—' }}</div>
            </div>

            <div class="flex flex-wrap items-center gap-x-3 gap-y-1 opacity-70">
              <div>
                <span class="opacity-60">{{ $t('before') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(it.beforeUpdatedAt) }}</span>
              </div>
              <div>
                <span class="opacity-60">{{ $t('after') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(it.afterUpdatedAt) }}</span>
              </div>
            </div>

            <div v-if="it.error" class="text-error">{{ it.error }}</div>
          </div>
        </div>
      </details>

      <div class="grid gap-2 md:grid-cols-2">
        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('geoFiles') }}</div>
          <div v-if="!agentEnabled" class="text-sm opacity-70">
            {{ $t('agentDisabled') }}
          </div>
          <div v-else-if="geoBusy" class="text-sm opacity-70">…</div>
          <div v-else>
            <div v-if="geoError" class="text-xs text-error">{{ geoError }}</div>
            <div v-else-if="!geoItems.length" class="text-sm opacity-70">—</div>
            <div v-else class="flex flex-col gap-1">
              <div v-for="g in geoItems" :key="g.kind + ':' + g.path" class="flex items-center justify-between gap-2 text-xs">
                <div class="min-w-0">
                  <span class="opacity-70">{{ geoKindLabel(g.kind) }}:</span>
                  <span class="ml-1 font-mono opacity-70" :title="g.path">{{ shortPath(g.path) }}</span>
                  <span v-if="typeof g.sizeBytes === 'number' && g.sizeBytes >= 0" class="ml-2 opacity-60">({{ prettyBytesHelper(g.sizeBytes) }})</span>
                </div>
                <div class="shrink-0 font-mono opacity-80">{{ fmtMtime(g.mtimeSec) }}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('filterPoliciesFiles') }}</div>
          <div v-if="providersBusy" class="text-sm opacity-70">…</div>
          <div v-else>
            <div v-if="providersError" class="text-xs text-error">{{ providersError }}</div>
            <div v-else-if="!ruleProviders.length" class="text-sm opacity-70">—</div>
            <div v-else class="flex flex-col gap-1 text-xs">
              <div>
                <span class="opacity-70">{{ $t('ruleProvidersCount') }}:</span>
                <span class="ml-1 font-mono">{{ ruleProviders.length }}</span>
              </div>
              <div>
                <span class="opacity-70">{{ $t('newestUpdate') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(newestProviderAt) }}</span>
              </div>
              <div>
                <span class="opacity-70">{{ $t('oldestUpdate') }}:</span>
                <span class="ml-1 font-mono">{{ fmtUpdatedAt(oldestProviderAt) }}</span>
              </div>
              <details class="mt-1">
                <summary class="cursor-pointer opacity-80">{{ $t('showList') }}</summary>
                <div class="mt-2 flex flex-col gap-1">
                  <div v-for="p in sortedProviders" :key="p.name" class="flex items-center justify-between gap-2">
                    <span class="min-w-0 truncate font-mono" :title="p.name">{{ p.name }}</span>
                    <span class="shrink-0 font-mono opacity-70">{{ fmtUpdatedAt(p.updatedAt) }}</span>
                  </div>
                </div>
              </details>

              <div class="mt-2 border-t border-base-content/10 pt-2">
                <div class="mb-1 text-xs font-semibold opacity-80">{{ $t('topRulesTitle') }}</div>
                <div v-if="!topHitRules.length" class="text-sm opacity-70">—</div>
                <details v-else class="mt-1">
                  <summary class="cursor-pointer opacity-80">{{ $t('showList') }}</summary>
                  <div class="mt-2 flex flex-col gap-1">
                    <div v-for="r in topHitRules" :key="r.key" class="flex items-center justify-between gap-2">
                      <button
                        type="button"
                        class="link min-w-0 truncate text-left font-mono"
                        :title="$t('openInTopology')"
                        @click="openTopologyWithRule(r.ruleText)"
                      >
                        {{ r.ruleText }}
                      </button>
                      <span class="shrink-0 font-mono opacity-70">{{ r.hits }}</span>
                    </div>
                  </div>
                </details>
                <div class="mt-1 text-[11px] opacity-60">{{ $t('topRulesTip') }}</div>
              </div>
            </div>

            <div v-if="agentEnabled" class="mt-2 border-t border-base-content/10 pt-2">
              <div class="mb-1 text-xs font-semibold opacity-80">{{ $t('localRulesDir') }}</div>
              <div v-if="rulesBusy" class="text-sm opacity-70">…</div>
              <div v-else>
                <div v-if="rulesError" class="text-xs text-error">{{ rulesError }}</div>
                <div v-else-if="!rulesDir" class="text-sm opacity-70">—</div>
                <div v-else class="flex flex-col gap-1 text-xs">
                  <div>
                    <span class="opacity-70">{{ $t('path') }}:</span>
                    <span class="ml-1 font-mono" :title="rulesDir">{{ shortPath(rulesDir) }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('filesCount') }}:</span>
                    <span class="ml-1 font-mono">{{ rulesCount }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('newestUpdate') }}:</span>
                    <span class="ml-1 font-mono">{{ fmtMtime(rulesNewest) }}</span>
                  </div>
                  <div>
                    <span class="opacity-70">{{ $t('oldestUpdate') }}:</span>
                    <span class="ml-1 font-mono">{{ fmtMtime(rulesOldest) }}</span>
                  </div>

                  <details v-if="rulesItems.length" class="mt-1">
                    <summary class="cursor-pointer opacity-80">{{ $t('showList') }}</summary>
                    <div class="mt-2 flex flex-col gap-1">
                      <div v-for="f in rulesItems" :key="f.path" class="flex items-center justify-between gap-2">
                        <span class="min-w-0 truncate font-mono" :title="f.path">{{ f.name || shortPath(f.path) }}</span>
                        <span class="shrink-0 font-mono opacity-70">{{ fmtMtime(f.mtimeSec) }}</span>
                      </div>
                    </div>
                  </details>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="text-[11px] opacity-60">
        {{ $t('dataFreshnessTip') }}
      </div>
    </div>


    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('diagnostics') }}</div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" @click="downloadDiagnostics" :disabled="diagBusy">
          {{ $t('downloadReport') }}
        </button>
        <button type="button" class="btn btn-sm btn-ghost" @click="copyDiagnostics" :disabled="diagBusy">
          {{ $t('copy') }}
        </button>
      </div>

      <div class="text-xs opacity-70">
        {{ $t('diagnosticsTip') }}
      </div>
    </div>


    <div class="card gap-2 p-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('upstreamTracking') }}</div>
        <div class="flex flex-wrap items-center gap-2">
          <button type="button" class="btn btn-sm btn-ghost" @click="checkUpstream" :disabled="upstreamBusy">
            {{ $t('refresh') }}
          </button>
          <button type="button" class="btn btn-sm" @click="markUpstreamReviewed" :disabled="!upstreamLatest.releaseTag && !upstreamLatest.commitSha">
            {{ $t('markReviewed') }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2 text-xs opacity-70">
        <div>
          <span class="opacity-60">{{ $t('repo') }}:</span>
          <a class="link ml-1 font-mono" :href="upstreamRepoUrl" target="_blank" rel="noreferrer">{{ upstreamRepo }}</a>
        </div>
        <span v-if="upstreamHasNew" class="badge badge-warning badge-xs">{{ $t('new') }}</span>
        <div class="ml-auto">
          <span class="opacity-60">{{ $t('lastChecked') }}:</span>
          <span class="ml-1 font-mono">{{ fmtTs(upstreamCheckedAt) }}</span>
        </div>
      </div>

      <div v-if="upstreamError" class="text-xs text-error">{{ upstreamError }}</div>

      <div v-else class="grid gap-2 md:grid-cols-2">
        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('latestRelease') }}</div>
          <div class="flex flex-col gap-1 text-xs">
            <div class="flex items-center justify-between gap-2">
              <div class="min-w-0">
                <span class="opacity-70">{{ $t('tag') }}:</span>
                <a
                  v-if="upstreamLatest.releaseUrl"
                  class="link ml-1 font-mono"
                  :href="upstreamLatest.releaseUrl"
                  target="_blank"
                  rel="noreferrer"
                >
                  {{ upstreamLatest.releaseTag || '—' }}
                </a>
                <span v-else class="ml-1 font-mono">{{ upstreamLatest.releaseTag || '—' }}</span>
              </div>
              <div class="shrink-0 font-mono opacity-80">{{ fmtIso(upstreamLatest.releasePublishedAt) }}</div>
            </div>

            <div v-if="upstreamCompareReleaseUrl" class="opacity-70">
              <a class="link" :href="upstreamCompareReleaseUrl" target="_blank" rel="noreferrer">
                {{ $t('compareSinceLastReview') }}
              </a>
            </div>
          </div>
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
          <div class="mb-1 text-sm font-semibold">{{ $t('latestCommit') }}</div>
          <div class="flex flex-col gap-1 text-xs">
            <div class="flex items-center justify-between gap-2">
              <div class="min-w-0">
                <span class="opacity-70">SHA:</span>
                <a
                  v-if="upstreamLatest.commitUrl"
                  class="link ml-1 font-mono"
                  :href="upstreamLatest.commitUrl"
                  target="_blank"
                  rel="noreferrer"
                >
                  {{ shortSha(upstreamLatest.commitSha) || '—' }}
                </a>
                <span v-else class="ml-1 font-mono">{{ shortSha(upstreamLatest.commitSha) || '—' }}</span>
              </div>
              <div class="shrink-0 font-mono opacity-80">{{ fmtIso(upstreamLatest.commitDate) }}</div>
            </div>
            <div v-if="upstreamLatest.commitMessage" class="max-h-[32px] overflow-hidden break-words opacity-80" :title="upstreamLatest.commitMessage">
              {{ upstreamLatest.commitMessage }}
            </div>
            <div v-if="upstreamCompareCommitUrl" class="opacity-70">
              <a class="link" :href="upstreamCompareCommitUrl" target="_blank" rel="noreferrer">
                {{ $t('compareCommits') }}
              </a>
            </div>
          </div>
        </div>
      </div>

      <div class="text-[11px] opacity-60">
        {{ $t('upstreamTrackingTip') }}
      </div>
    </div>


    <div class="card gap-2 p-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('usersDbSyncTitle') }}</div>
        <span class="badge badge-sm" :class="usersDbBadge.cls">{{ usersDbBadge.text }}</span>
      </div>

      <div class="text-sm opacity-80">
        {{ $t('usersDbSyncDesc') }}
      </div>

      <div class="text-xs opacity-70">
        <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
          <div><span class="opacity-60">rev:</span> <span class="font-mono">{{ usersDbRemoteRev }}</span></div>
          <div class="min-w-0"><span class="opacity-60">{{ $t('updated') }}:</span> <span class="font-mono">{{ usersDbRemoteUpdatedAt || '—' }}</span></div>
          <div v-if="agentEnabled && (agentStatusLite.version || agentStatusLite.serverVersion)" class="min-w-0">
            <span class="opacity-60">{{ $t('agentVersion') }}:</span>
            <span class="font-mono ml-1">{{ agentStatusLite.version || '—' }}</span>
            <template v-if="agentStatusLite.serverVersion">
              <span class="opacity-60 ml-2">{{ $t('agentServerVersion') }}:</span>
              <span class="font-mono ml-1">{{ agentStatusLite.serverVersion }}</span>
            </template>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1">
          <div><span class="opacity-60">{{ $t('lastPull') }}:</span> <span class="font-mono">{{ usersDbLastPullAt ? fmtTs(usersDbLastPullAt) : '—' }}</span></div>
          <div><span class="opacity-60">{{ $t('lastPush') }}:</span> <span class="font-mono">{{ usersDbLastPushAt ? fmtTs(usersDbLastPushAt) : '—' }}</span></div>
          <div><span class="opacity-60">{{ $t('conflicts') }}:</span> <span class="font-mono">{{ usersDbConflictCount || 0 }}</span></div>
          <div v-if="usersDbLocalDirty"><span class="badge badge-warning badge-xs">{{ $t('pendingChanges') }}</span></div>
        </div>
      </div>

      <div v-if="usersDbLastError" class="text-xs text-error">{{ usersDbLastError }}</div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" @click="usersDbPullNow" :disabled="!usersDbSyncEnabled || !agentEnabled || usersDbBusy">
          {{ $t('pull') }}
        </button>
        <button type="button" class="btn btn-sm" @click="usersDbPushNow" :disabled="!usersDbSyncEnabled || !agentEnabled || usersDbBusy">
          {{ $t('push') }}
        </button>
      </div>

      <div class="text-[11px] opacity-60">
        {{ $t('usersDbSyncCurrent') }}
      </div>
    </div>

    <div class="card gap-2 p-3">
      <div class="flex items-center justify-between gap-2">
        <div class="font-semibold">{{ $t('operationsHistory') }}</div>
        <button type="button" class="btn btn-sm btn-ghost" @click="clearJobs" :disabled="!jobs.length">
          {{ $t('clear') }}
        </button>
      </div>

      <div v-if="!jobs.length" class="text-sm opacity-70">
        {{ $t('noOperationsYet') }}
      </div>

      <div v-else class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th style="width: 140px">{{ $t('time') }}</th>
              <th>{{ $t('operation') }}</th>
              <th style="width: 120px">{{ $t('status') }}</th>
              <th style="width: 110px">{{ $t('duration') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="j in jobs" :key="j.id">
              <td class="font-mono text-xs">{{ fmtTime(j.startedAt) }}</td>
              <td>
                <div class="text-sm">{{ j.title }}</div>
                <div v-if="j.error" class="text-xs text-error">{{ j.error }}</div>
                <div v-else-if="j.meta && Object.keys(j.meta).length" class="text-[11px] opacity-70">
                  <span v-for="(v, k) in j.meta" :key="k" class="mr-2">
                    <span class="opacity-60">{{ k }}:</span>
                    <span class="font-mono">{{ v }}</span>
                  </span>
                </div>
              </td>
              <td>
                <span v-if="j.endedAt && j.ok" class="badge badge-success">{{ $t('done') }}</span>
                <span v-else-if="j.endedAt && j.ok === false" class="badge badge-error">{{ $t('failed') }}</span>
                <span v-else class="badge badge-warning">{{ $t('running') }}</span>
              </td>
              <td class="font-mono text-xs">
                {{ j.endedAt ? fmtMs(j.endedAt - j.startedAt) : '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="flex-1"></div>

    <div class="card items-center justify-center gap-2 p-2 sm:flex-row">
      {{ getLabelFromBackend(activeBackend!) }} :
      <BackendVersion />
    </div>
  </div>
</template>

<script setup lang="ts">
import { fetchRuleProvidersAPI, updateRuleProviderSilentAPI, zashboardVersion, version as coreVersion } from '@/api'
import { agentGeoInfoAPI, agentGeoUpdateAPI, agentLogsAPI, agentLogsFollowAPI, agentMihomoProvidersAPI, agentRulesInfoAPI, agentStatusAPI } from '@/api/agent'
import BackendVersion from '@/components/common/BackendVersion.vue'
import { useStorage } from '@vueuse/core'
import { getLabelFromBackend, prettyBytesHelper } from '@/helper/utils'
import { parseDateMaybe } from '@/helper/providerHealth'
import { showNotification } from '@/helper/notification'
import { decodeB64Utf8 } from '@/helper/b64'
import { activeBackend } from '@/store/setup'
import { agentEnabled, agentUrl } from '@/store/agent'
import { proxyProviderPanelUrlMap } from '@/store/settings'
import { userLimitProfiles } from '@/store/userLimitProfiles'
import { userLimitSnapshots } from '@/store/userLimitSnapshots'
import { autoDisconnectLimitedUsers, hardBlockLimitedUsers, managedLanDisallowedCidrs, userLimits } from '@/store/userLimits'
import { activeConnections } from '@/store/connections'
import { ruleHitMap } from '@/store/rules'
import { clearJobs, finishJob, jobHistory, startJob } from '@/store/jobs'
import { applyUserEnforcementNow, getUserLimitState } from '@/composables/userLimits'
import dayjs from 'dayjs'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { RuleProvider } from '@/types'
import { useI18n } from 'vue-i18n'
import router from '@/router'
import { ROUTE_NAME } from '@/constant'
import {
  usersDbConflictCount,
  usersDbLastError,
  usersDbLastPullAt,
  usersDbLastPushAt,
  usersDbLocalDirty,
  usersDbPhase,
  usersDbRemoteRev,
  usersDbRemoteUpdatedAt,
  usersDbSyncEnabled,
  usersDbPullNow,
  usersDbPushNow,
} from '@/store/usersDbSync'

const busy = ref(false)
const jobs = computed(() => jobHistory.value || [])
// --- Router-agent status (versions) ---
const agentStatusLite = ref<any>({ ok: false })
const refreshAgentStatusLite = async () => {
  if (!agentEnabled.value) {
    agentStatusLite.value = { ok: false }
    return
  }
  agentStatusLite.value = await agentStatusAPI()
}

watch([agentEnabled, agentUrl], () => {
  refreshAgentStatusLite()
})


// --- Router external-ui-url helper (anti-cache) ---
const routerUiUrl = computed(() => {
  const v = encodeURIComponent(zashboardVersion.value || '')
  return `https://github.com/messireL/ZashUIFork/releases/download/rolling/dist.zip?v=${v}`
})

const copyRouterUiUrl = async (asYaml: boolean) => {
  try {
    const text = asYaml ? `external-ui-url: "${routerUiUrl.value}"` : routerUiUrl.value
    await navigator.clipboard.writeText(text)
    showNotification({ content: 'copySuccess', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  }
}



// --- Proxy providers: shared management panel URLs (synced via users DB) ---
const providersPanelBusy = ref(false)
const providersPanelError = ref('')
const providersPanelList = ref<Array<{ name: string; url?: string; host?: string; port?: string; sslNotAfter?: string }>>([])

const fmtSslPanel = (v: any) => {
  const d = parseDateMaybe(v)
  return d ? d.format('DD-MM-YYYY HH:mm:ss') : '—'
}

const setProviderPanelUrl = (name: string, url: string) => {
  const k = String(name || '').trim()
  if (!k) return
  const v = String(url || '').trim()
  const cur = { ...(proxyProviderPanelUrlMap.value || {}) }
  if (!v) delete cur[k]
  else cur[k] = v
  proxyProviderPanelUrlMap.value = cur
}

const loadProvidersPanel = async (force = false) => {
  if (!agentEnabled.value) {
    providersPanelList.value = []
    providersPanelError.value = ''
    return
  }
  if (providersPanelBusy.value) return
  providersPanelBusy.value = true
  providersPanelError.value = ''
  try {
    const r: any = await agentMihomoProvidersAPI(force)
    if (!r?.ok) {
      providersPanelError.value = r?.error || 'failed'
      providersPanelList.value = []
      return
    }
    providersPanelList.value = Array.isArray(r?.providers) ? r.providers : []
  } catch (e: any) {
    providersPanelError.value = e?.message || 'failed'
    providersPanelList.value = []
  } finally {
    providersPanelBusy.value = false
  }
}

// --- Live logs (router-agent) ---
const logSource = ref<'mihomo' | 'config' | 'agent'>('mihomo')
const logLines = ref<number>(200)
const logsAuto = ref(true)
const logsBusy = ref(false)
const logText = ref('')
const logPath = ref('')
const logOffset = ref(0)
const logMode = ref<'poll' | 'delta' | 'full'>('poll')

let logTimer: any = null
const refreshLogs = async () => {
  if (!agentEnabled.value) return
  if (logsBusy.value) return
  logsBusy.value = true
  try {
    if (logSource.value === 'config') {
      const r: any = await agentLogsAPI({ type: 'config', lines: logLines.value })
      logMode.value = 'full'
      logOffset.value = 0
      if (!r?.ok) {
        logText.value = r?.error || 'failed'
        return
      }
      logPath.value = r?.path || ''
      logText.value = decodeB64Utf8(r?.contentB64) || ''
      return
    }

    // Prefer efficient incremental follow (agent >= 0.5.3). Fallback to full polling on older agents.
    const r: any = await agentLogsFollowAPI({ type: logSource.value as any, lines: logLines.value, offset: logOffset.value })
    if (r?.ok) {
      logPath.value = r?.path || ''
      const chunk = decodeB64Utf8(r?.contentB64) || ''
      const mode = (r?.mode || 'delta') as 'full' | 'delta'
      logMode.value = mode
      const newOffset = typeof r?.offset === 'number' ? r.offset : logOffset.value
      const resetLike = logOffset.value === 0 || mode === 'full' || newOffset < logOffset.value
      if (resetLike) logText.value = chunk
      else logText.value = (logText.value || '') + chunk
      logOffset.value = newOffset

      // Keep last N lines (avoid runaway memory).
      const maxLines = Math.min(2000, Math.max(50, logLines.value || 200))
      const arr = (logText.value || '').split(/\r?\n/)
      if (arr.length > maxLines) logText.value = arr.slice(-maxLines).join('\n')
      return
    }

    // Fallback: full fetch
    const r2: any = await agentLogsAPI({ type: logSource.value, lines: logLines.value })
    logMode.value = 'poll'
    logOffset.value = 0
    if (!r2?.ok) {
      logText.value = r2?.error || 'failed'
      return
    }
    logPath.value = r2?.path || ''
    logText.value = decodeB64Utf8(r2?.contentB64) || ''
  } finally {
    logsBusy.value = false
  }
}

const forceRefreshLogs = () => {
  logOffset.value = 0
  logText.value = ''
  refreshLogs()
}


const stopTimer = () => {
  if (logTimer) {
    clearInterval(logTimer)
    logTimer = null
  }
}

const startTimer = () => {
  stopTimer()
  if (!logsAuto.value) return
  if (!agentEnabled.value) return
  logTimer = setInterval(() => {
    refreshLogs()
  }, 2000)
}

onMounted(() => {
  refreshAgentStatusLite()
  refreshLogs()
  startTimer()
  refreshFreshness()
  loadProvidersPanel(false)
  checkUpstream()
  startUpstreamTimer()
})

onBeforeUnmount(() => {
  stopTimer()
  stopUpstreamTimer()
})

watch([logsAuto, logSource, logLines, agentEnabled], () => {
  logOffset.value = 0
  refreshLogs()
  startTimer()
})


// --- Data freshness (GEO files + filter policy files) ---
const { t } = useI18n()


// --- Shared users DB sync status (Source IP mapping) ---
const usersDbBusy = computed(() => usersDbPhase.value === 'pulling' || usersDbPhase.value === 'pushing')

const usersDbBadge = computed(() => {
  if (!usersDbSyncEnabled.value) return { text: 'OFF', cls: 'badge-ghost' }
  if (!agentEnabled.value) return { text: t('localOnly'), cls: 'badge-ghost' }

  if (usersDbPhase.value === 'idle' && !usersDbLocalDirty.value) return { text: t('synced'), cls: 'badge-success' }
  if (usersDbPhase.value === 'pulling' || usersDbPhase.value === 'pushing') return { text: t('running'), cls: 'badge-warning' }
  if (usersDbPhase.value === 'conflict') return { text: t('conflict'), cls: 'badge-warning' }
  if (usersDbPhase.value === 'offline') return { text: t('offline'), cls: 'badge-warning' }
  return { text: t('pendingChanges'), cls: 'badge-warning' }
})

// --- Top rules -> open Topology with filter (stage R) ---
const TOPOLOGY_NAV_FILTER_KEY = 'runtime/topology-pending-filter-v1'
const normalizeRulePart = (s: string) => (s || '').trim() || '-'

const topHitRules = computed(() => {
  const entries = Array.from(ruleHitMap.value.entries() || [])
    .map(([key, hits]) => {
      const parts = String(key).split('\0')
      const type = normalizeRulePart(parts[0] || '')
      const payloadRaw = String(parts[1] || '').trim()
      const ruleText = payloadRaw ? `${type}: ${normalizeRulePart(payloadRaw)}` : type
      return { key: String(key), ruleText, hits: Number(hits) || 0 }
    })
    .filter((x) => x.ruleText && x.ruleText !== '-')
    .sort((a, b) => b.hits - a.hits)
  return entries.slice(0, 20)
})

const openTopologyWithRule = async (ruleText: string) => {
  const payload = {
    ts: Date.now(),
    mode: 'only',
    focus: { stage: 'R', kind: 'value', value: String(ruleText || '').trim() },
  }
  try {
    localStorage.setItem(TOPOLOGY_NAV_FILTER_KEY, JSON.stringify(payload))
  } catch {
    // ignore
  }
  await router.push({ name: ROUTE_NAME.overview })
}

const lastFreshnessOkAt = useStorage<number>('runtime/tasks-last-freshness-ok-at-v1', 0)

type GeoUpdateResult = {
  at: number
  ok: boolean
  items: Array<{
    kind: string
    path: string
    ok?: boolean
    changed?: boolean
    mtimeSec?: number
    sizeBytes?: number
    method?: string
    source?: string
    error?: string
  }>
  note?: string
}

const lastGeoUpdate = useStorage<GeoUpdateResult>('runtime/tasks-last-geo-update-v1', {
  at: 0,
  ok: true,
  items: [],
  note: '',
})

type RuleProvidersUpdateResult = {
  at: number
  ok: boolean
  total: number
  okCount: number
  failCount: number
  items: Array<{
    name: string
    ok: boolean
    changed: boolean
    beforeUpdatedAt?: string
    afterUpdatedAt?: string
    durationMs?: number
    error?: string
  }>
}

const lastRuleProvidersUpdate = useStorage<RuleProvidersUpdateResult>('runtime/tasks-last-rule-providers-update-v1', {
  at: 0,
  ok: true,
  total: 0,
  okCount: 0,
  failCount: 0,
  items: [],
})
type GeoInfoItem = {
  kind: string
  path: string
  exists: boolean
  mtimeSec?: number
  sizeBytes?: number
}

const geoBusy = ref(false)
const geoError = ref('')
const geoItems = ref<GeoInfoItem[]>([])

const providersBusy = ref(false)
const providersError = ref('')
const ruleProviders = ref<RuleProvider[]>([])

const sortedProviders = computed(() => {
  return [...(ruleProviders.value || [])].sort((a, b) => {
    const ta = dayjs(a.updatedAt).valueOf()
    const tb = dayjs(b.updatedAt).valueOf()
    return tb - ta
  })
})

const newestProviderAt = computed(() => sortedProviders.value[0]?.updatedAt || '')
const oldestProviderAt = computed(() => {
  const arr = [...(ruleProviders.value || [])].sort(
    (a, b) => dayjs(a.updatedAt).valueOf() - dayjs(b.updatedAt).valueOf(),
  )
  return arr[0]?.updatedAt || ''
})

const geoKindLabel = (kind: string) => {
  const k = (kind || '').toLowerCase()
  if (k === 'geoip') return t('geoipFile')
  if (k === 'geosite') return t('geositeFile')
  if (k === 'asn') return t('asnMmdbFile')
  if (k === 'mmdb') return t('mmdbFile')
  return kind || '—'
}

const fmtMtime = (mtimeSec?: number) => {
  if (!mtimeSec || !Number.isFinite(mtimeSec)) return '—'
  return dayjs.unix(mtimeSec).format('DD-MM-YYYY HH:mm:ss')
}

const fmtUpdatedAt = (s?: string) => {
  const d = dayjs(s || '')
  if (!d.isValid()) return '—'
  return d.format('DD-MM-YYYY HH:mm:ss')
}

const fmtTs = (ts?: number) => {
  if (!ts || !Number.isFinite(ts)) return '—'
  return dayjs(ts).format('DD-MM-YYYY HH:mm:ss')
}

const shortPath = (p?: string) => {
  const s = (p || '').trim()
  if (!s) return '—'
  const parts = s.split('/').filter(Boolean)
  if (parts.length <= 3) return s
  return `…/${parts.slice(-3).join('/')}`
}

const refreshGeoInfo = async () => {
  geoError.value = ''
  geoItems.value = []
  if (!agentEnabled.value) return
  geoBusy.value = true
  try {
    const r: any = await agentGeoInfoAPI()
    if (!r?.ok) {
      geoError.value = r?.error || 'failed'
      return
    }
    const items = Array.isArray(r?.items) ? r.items : []
    geoItems.value = items
      .filter((x: any) => x && x.path)
      .map((x: any) => ({
        kind: String(x.kind || ''),
        path: String(x.path || ''),
        exists: !!x.exists,
        mtimeSec:
          typeof x.mtimeSec === 'number' ? x.mtimeSec : Number(x.mtimeSec || 0) || undefined,
        sizeBytes:
          typeof x.sizeBytes === 'number' ? x.sizeBytes : Number(x.sizeBytes || 0) || undefined,
      }))
      .filter((x) => x.exists)
      .sort((a, b) => (a.kind || '').localeCompare(b.kind || ''))
  } catch (e: any) {
    geoError.value = e?.message || 'failed'
  } finally {
    geoBusy.value = false
  }
}

const refreshRuleProviders = async () => {
  providersBusy.value = true
  providersError.value = ''
  try {
    const { data } = await fetchRuleProvidersAPI()
    ruleProviders.value = Object.values((data as any)?.providers || {})
  } catch (e: any) {
    ruleProviders.value = []
    providersError.value = e?.message || 'failed'
  } finally {
    providersBusy.value = false
  }
}

// Local rules directory (XKeen/mihomo rules folder)
const rulesBusy = ref(false)
const rulesError = ref('')
const rulesDir = ref('')
const rulesCount = ref(0)
const rulesNewest = ref<number | undefined>(undefined)
const rulesOldest = ref<number | undefined>(undefined)
const rulesItems = ref<Array<{ name: string; path: string; mtimeSec?: number; sizeBytes?: number }>>([])

const refreshRulesInfo = async () => {
  rulesError.value = ''
  rulesDir.value = ''
  rulesCount.value = 0
  rulesNewest.value = undefined
  rulesOldest.value = undefined
  rulesItems.value = []
  if (!agentEnabled.value) return
  rulesBusy.value = true
  try {
    const r: any = await agentRulesInfoAPI()
    if (!r?.ok) {
      rulesError.value = r?.error || 'failed'
      return
    }
    rulesDir.value = String(r?.dir || '')
    rulesCount.value = Number(r?.count || 0) || 0
    const newest = typeof r?.newestMtimeSec === 'number' ? r.newestMtimeSec : Number(r?.newestMtimeSec || 0) || 0
    const oldest = typeof r?.oldestMtimeSec === 'number' ? r.oldestMtimeSec : Number(r?.oldestMtimeSec || 0) || 0
    rulesNewest.value = newest > 0 ? newest : undefined
    rulesOldest.value = oldest > 0 ? oldest : undefined
    const items = Array.isArray(r?.items) ? r.items : []
    rulesItems.value = items
      .filter((x: any) => x && x.path)
      .map((x: any) => ({
        name: String(x.name || ''),
        path: String(x.path || ''),
        mtimeSec: typeof x.mtimeSec === 'number' ? x.mtimeSec : Number(x.mtimeSec || 0) || undefined,
        sizeBytes: typeof x.sizeBytes === 'number' ? x.sizeBytes : Number(x.sizeBytes || 0) || undefined,
      }))
  } catch (e: any) {
    rulesError.value = e?.message || 'failed'
  } finally {
    rulesBusy.value = false
  }
}

const freshnessBusy = computed(() => geoBusy.value || providersBusy.value || rulesBusy.value)
const refreshFreshness = async () => {
  await Promise.all([refreshGeoInfo(), refreshRuleProviders(), refreshRulesInfo()])

  const okProviders = !providersError.value
  const okGeo = !agentEnabled.value || !geoError.value
  const okRules = !agentEnabled.value || !rulesError.value
  if (okProviders && okGeo && okRules) {
    lastFreshnessOkAt.value = Date.now()
  }
}


// --- Upstream tracking (GitHub: Zephyruso/zashboard) ---
const upstreamRepo = 'Zephyruso/zashboard'
const upstreamRepoUrl = 'https://github.com/Zephyruso/zashboard'
const upstreamApiBase = 'https://api.github.com/repos/Zephyruso/zashboard'

type UpstreamLatest = {
  releaseTag: string
  releasePublishedAt: string
  releaseUrl: string
  commitSha: string
  commitDate: string
  commitMessage: string
  commitUrl: string
}

const upstreamLatest = useStorage<UpstreamLatest>('runtime/tasks-upstream-latest-v1', {
  releaseTag: '',
  releasePublishedAt: '',
  releaseUrl: '',
  commitSha: '',
  commitDate: '',
  commitMessage: '',
  commitUrl: '',
})

const upstreamReviewed = useStorage<{ releaseTag: string; commitSha: string; reviewedAt: number }>(
  'runtime/tasks-upstream-reviewed-v1',
  { releaseTag: '', commitSha: '', reviewedAt: 0 },
)

const upstreamCheckedAt = useStorage<number>('runtime/tasks-upstream-checked-at-v1', 0)
const upstreamLastNotifiedKey = useStorage<string>('runtime/tasks-upstream-last-notified-v1', '')
const upstreamBusy = ref(false)
const upstreamError = ref('')

const upstreamHasNew = computed(() => {
  const newRelease =
    !!upstreamLatest.value.releaseTag &&
    !!upstreamReviewed.value.releaseTag &&
    upstreamLatest.value.releaseTag !== upstreamReviewed.value.releaseTag
  const newCommit =
    !!upstreamLatest.value.commitSha &&
    !!upstreamReviewed.value.commitSha &&
    upstreamLatest.value.commitSha !== upstreamReviewed.value.commitSha
  // If user hasn't marked reviewed yet, still show NEW when we have data.
  const neverReviewed = !upstreamReviewed.value.releaseTag && !upstreamReviewed.value.commitSha
  return neverReviewed ? !!(upstreamLatest.value.releaseTag || upstreamLatest.value.commitSha) : newRelease || newCommit
})

const shortSha = (sha?: string) => (sha || '').trim().slice(0, 7)

const fmtIso = (iso?: string) => {
  const d = dayjs(iso || '')
  if (!d.isValid()) return '—'
  return d.format('DD-MM-YYYY HH:mm:ss')
}

const upstreamCompareReleaseUrl = computed(() => {
  const a = (upstreamReviewed.value.releaseTag || '').trim()
  const b = (upstreamLatest.value.releaseTag || '').trim()
  if (!a || !b || a === b) return ''
  return `https://github.com/Zephyruso/zashboard/compare/${encodeURIComponent(a)}...${encodeURIComponent(b)}`
})

const upstreamCompareCommitUrl = computed(() => {
  const a = (upstreamReviewed.value.commitSha || '').trim()
  const b = (upstreamLatest.value.commitSha || '').trim()
  if (!a || !b || a === b) return ''
  return `https://github.com/Zephyruso/zashboard/compare/${encodeURIComponent(a)}...${encodeURIComponent(b)}`
})

const checkUpstream = async () => {
  if (upstreamBusy.value) return
  upstreamBusy.value = true
  upstreamError.value = ''
  try {
    const ghFetch = async (url: string) => {
      const res = await fetch(url, {
        headers: {
          Accept: 'application/vnd.github+json',
        },
        cache: 'no-store',
      })

      // Rate limit hint
      const remaining = res.headers.get('x-ratelimit-remaining')
      if (res.status === 403 && remaining === '0') {
        throw new Error(t('githubRateLimited'))
      }

      if (!res.ok) {
        throw new Error(`${t('operationFailed')}: ${res.status}`)
      }
      return res.json()
    }

    const [rel, commits] = await Promise.all([
      ghFetch(`${upstreamApiBase}/releases/latest`),
      ghFetch(`${upstreamApiBase}/commits?per_page=1`),
    ])

    const latestReleaseTag = String(rel?.tag_name || '')
    const latestReleaseAt = String(rel?.published_at || rel?.created_at || '')
    const latestReleaseUrl = String(rel?.html_url || '')

    const c0 = Array.isArray(commits) ? commits[0] : commits
    const latestCommitSha = String(c0?.sha || '')
    const latestCommitDate = String(c0?.commit?.committer?.date || c0?.commit?.author?.date || '')
    const latestCommitMessage = String(c0?.commit?.message || '').split('\n')[0]
    const latestCommitUrl = String(c0?.html_url || '')

    upstreamLatest.value = {
      releaseTag: latestReleaseTag,
      releasePublishedAt: latestReleaseAt,
      releaseUrl: latestReleaseUrl,
      commitSha: latestCommitSha,
      commitDate: latestCommitDate,
      commitMessage: latestCommitMessage,
      commitUrl: latestCommitUrl,
    }

    upstreamCheckedAt.value = Date.now()

    // Notify only once per new release tag (or commit if no tag)
    const notifyKey = latestReleaseTag || latestCommitSha
    if (upstreamHasNew.value && notifyKey && upstreamLastNotifiedKey.value !== notifyKey) {
      upstreamLastNotifiedKey.value = notifyKey
      showNotification({ content: 'upstreamUpdateAvailable', type: 'alert-warning', timeout: 2600 })
    }
  } catch (e: any) {
    upstreamError.value = e?.message || 'failed'
  } finally {
    upstreamBusy.value = false
  }
}

const markUpstreamReviewed = () => {
  upstreamReviewed.value = {
    releaseTag: upstreamLatest.value.releaseTag || upstreamReviewed.value.releaseTag || '',
    commitSha: upstreamLatest.value.commitSha || upstreamReviewed.value.commitSha || '',
    reviewedAt: Date.now(),
  }
  showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
}

let upstreamTimer: any = null
const startUpstreamTimer = () => {
  stopUpstreamTimer()
  // While Tasks page is open: check every 6 hours.
  upstreamTimer = setInterval(() => {
    checkUpstream()
  }, 6 * 60 * 60 * 1000)
}

const stopUpstreamTimer = () => {
  if (upstreamTimer) {
    clearInterval(upstreamTimer)
    upstreamTimer = null
  }
}

// --- Diagnostics report ---
const diagBusy = ref(false)

const buildDiagnostics = async () => {
  const ts = new Date().toISOString()
  const agentStatus = await agentStatusAPI()

  const takeLog = async (type: 'mihomo' | 'agent' | 'config') => {
    const r: any = await agentLogsAPI({ type, lines: 200 })
    return {
      ok: !!r?.ok,
      path: r?.path || '',
      content: decodeB64Utf8(r?.contentB64) || (r?.error || ''),
    }
  }

  const logs = {
    mihomo: await takeLog('mihomo'),
    agent: await takeLog('agent'),
    config: await takeLog('config'),
  }

  const blocked = [] as any[]
  const keys = Object.keys(userLimits.value || {})
  for (const u of keys) {
    const st = getUserLimitState(u)
    if (st.blocked) {
      blocked.push({
        user: u,
        reasonManual: !!st.limit.disabled,
        trafficExceeded: !!st.trafficExceeded,
        bandwidthExceeded: !!st.bandwidthExceeded,
        usageBytes: st.usageBytes,
        trafficLimitBytes: st.limit.trafficLimitBytes || 0,
        bandwidthLimitBps: st.limit.bandwidthLimitBps || 0,
        mac: st.limit.mac || '',
      })
    }
  }

  return {
    kind: 'zash-diagnostics',
    generatedAt: ts,
    uiVersion: zashboardVersion.value,
    coreVersion: coreVersion.value,
    backend: activeBackend.value ? {
      label: activeBackend.value.label,
      host: activeBackend.value.host,
      port: activeBackend.value.port,
      protocol: activeBackend.value.protocol,
      secondaryPath: activeBackend.value.secondaryPath,
    } : null,
    agent: {
      enabled: !!agentEnabled.value,
      url: agentUrl.value,
      status: agentStatus,
    },
    limits: {
      autoDisconnectLimitedUsers: !!autoDisconnectLimitedUsers.value,
      hardBlockLimitedUsers: !!hardBlockLimitedUsers.value,
      managedLanDisallowedCidrs: managedLanDisallowedCidrs.value || [],
      profiles: userLimitProfiles.value || [],
      snapshotsCount: (userLimitSnapshots.value || []).length,
      userLimits: userLimits.value || {},
      blockedUsers: blocked,
    },
    connections: {
      activeCount: (activeConnections.value || []).length,
    },
    logs,
    ua: navigator.userAgent,
  }
}

const downloadDiagnostics = async () => {
  if (diagBusy.value) return
  diagBusy.value = true
  try {
    const rep = await buildDiagnostics()
    const blob = new Blob([JSON.stringify(rep, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `zash-diagnostics-${dayjs().format('YYYYMMDD-HHmmss')}.json`
    a.click()
    URL.revokeObjectURL(url)
    showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    diagBusy.value = false
  }
}

const copyDiagnostics = async () => {
  if (diagBusy.value) return
  diagBusy.value = true
  try {
    const rep = await buildDiagnostics()
    const text = JSON.stringify(rep, null, 2)
    await navigator.clipboard.writeText(text)
    showNotification({ content: 'copySuccess', type: 'alert-success', timeout: 1400 })
  } catch {
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    diagBusy.value = false
  }
}

const fmtTime = (ts: number) => dayjs(ts).format('HH:mm:ss')
const fmtMs = (ms: number) => {
  if (!Number.isFinite(ms)) return '—'
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

const applyEnforcement = async () => {
  if (busy.value) return
  busy.value = true
  try {
    const id = startJob('Apply limits & blocks')
    try {
      await applyUserEnforcementNow()
      finishJob(id, { ok: true })
      showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
    } catch (e: any) {
      finishJob(id, { ok: false, error: e?.message || 'failed' })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
    }
  } finally {
    busy.value = false
  }
}

const refreshSsl = async () => {
  if (busy.value) return
  if (!agentEnabled.value) {
    showNotification({ content: 'agentDisabled', type: 'alert-warning', timeout: 2000 })
    return
  }
  busy.value = true
  try {
    const id = startJob('Refresh providers SSL')
    try {
      const r: any = await agentMihomoProvidersAPI(true)
      await loadProvidersPanel(true)
      if (!r?.ok) {
        finishJob(id, { ok: false, error: r?.error || 'failed' })
        showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
        return
      }
      const n = Array.isArray(r?.providers) ? r.providers.length : 0
      finishJob(id, { ok: true, meta: { providers: n } })
      showNotification({ content: 'sslRefreshed', type: 'alert-success', timeout: 1600 })
    } catch (e: any) {
      finishJob(id, { ok: false, error: e?.message || 'failed' })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
    }
  } finally {
    busy.value = false
  }
}


// --- Data refresh operations (panel) ---
const geoUpdateBusy = ref(false)
const providersUpdateBusy = ref(false)
const rulesRescanBusy = ref(false)

const updateGeoNow = async () => {
  if (!agentEnabled.value) {
    showNotification({ content: 'agentDisabled', type: 'alert-warning', timeout: 2000 })
    return
  }
  if (geoUpdateBusy.value) return
  geoUpdateBusy.value = true
  const id = startJob(t('updateGeoNow'))
  try {
    const r: any = await agentGeoUpdateAPI()
    const itemsRaw = Array.isArray(r?.items) ? r.items : []
    const items = itemsRaw
      .filter((x: any) => x && x.path)
      .map((x: any) => ({
        kind: String(x.kind || ''),
        path: String(x.path || ''),
        ok: typeof x.ok === 'boolean' ? x.ok : (x.ok ?? true),
        changed: !!x.changed,
        mtimeSec: typeof x.mtimeSec === 'number' ? x.mtimeSec : Number(x.mtimeSec || 0) || undefined,
        sizeBytes: typeof x.sizeBytes === 'number' ? x.sizeBytes : Number(x.sizeBytes || 0) || undefined,
        method: String(x.method || ''),
        source: String(x.source || ''),
        error: String(x.error || ''),
      }))

    const failItems = items.filter((x: any) => x.ok === false || !!x.error)
    const okAll = !!r?.ok && failItems.length === 0
    const changedKinds = items.filter((x: any) => x.changed).map((x: any) => x.kind).join(', ')

    lastGeoUpdate.value = {
      at: Date.now(),
      ok: okAll,
      items,
      note: String(r?.note || ''),
    }

    if (!r?.ok) {
      finishJob(id, { ok: false, error: r?.error || 'failed', meta: { changed: changedKinds || '—' } })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
      return
    }

    finishJob(id, { ok: okAll, meta: { changed: changedKinds || '—', fail: failItems.length } })
    showNotification({ content: okAll ? 'updateGeoSuccess' : 'operationFailed', type: okAll ? 'alert-success' : 'alert-warning', timeout: 2200 })
    await refreshFreshness()
  } catch (e: any) {
    finishJob(id, { ok: false, error: e?.message || 'failed' })
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    geoUpdateBusy.value = false
  }
}

const updateRuleProvidersNow = async () => {
  if (providersUpdateBusy.value) return
  providersUpdateBusy.value = true
  const id = startJob(t('updateRuleProvidersNow'))
  try {
    await refreshRuleProviders()
    const beforeMap = new Map<string, string>()
    for (const p of ruleProviders.value || []) {
      if (p?.name) beforeMap.set(p.name, p.updatedAt || '')
    }

    const names = (ruleProviders.value || []).map((p) => p.name).filter(Boolean) as string[]
    const items: any[] = []
    let ok = 0
    let fail = 0

    for (const name of names) {
      const started = Date.now()
      try {
        await updateRuleProviderSilentAPI(name)
        ok += 1
        items.push({
          name,
          ok: true,
          changed: false,
          beforeUpdatedAt: beforeMap.get(name) || '',
          durationMs: Date.now() - started,
          error: '',
        })
      } catch (e: any) {
        fail += 1
        const d = e?.response?.data
        const msg = (() => {
          if (typeof d === 'string') return d
          if (d && typeof d === 'object') return JSON.stringify(d)
          return String(e?.message || 'failed')
        })()
        items.push({
          name,
          ok: false,
          changed: false,
          beforeUpdatedAt: beforeMap.get(name) || '',
          durationMs: Date.now() - started,
          error: msg,
        })
      }
    }

    await refreshRuleProviders()
    const afterMap = new Map<string, string>()
    for (const p of ruleProviders.value || []) {
      if (p?.name) afterMap.set(p.name, p.updatedAt || '')
    }

    let changed = 0
    for (const it of items) {
      const after = afterMap.get(it.name) || ''
      it.afterUpdatedAt = after
      const before = it.beforeUpdatedAt || ''
      const ch = !!after && !!before && after !== before
      it.changed = ch
      if (ch) changed += 1
    }

    const okAll = fail === 0
    lastRuleProvidersUpdate.value = {
      at: Date.now(),
      ok: okAll,
      total: names.length,
      okCount: ok,
      failCount: fail,
      items,
    }

    finishJob(id, { ok: okAll, meta: { total: names.length, ok, fail, changed } })
    showNotification({ content: okAll ? 'operationDone' : 'operationFailed', type: okAll ? 'alert-success' : 'alert-warning', timeout: 2200 })
    await refreshFreshness()
  } catch (e: any) {
    finishJob(id, { ok: false, error: e?.message || 'failed' })
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    providersUpdateBusy.value = false
  }
}

const rescanLocalRules = async () => {
  if (!agentEnabled.value) {
    showNotification({ content: 'agentDisabled', type: 'alert-warning', timeout: 2000 })
    return
  }
  if (rulesRescanBusy.value) return
  rulesRescanBusy.value = true
  const id = startJob(t('rescanLocalRules'))
  try {
    await refreshRulesInfo()
    if (rulesError.value) {
      finishJob(id, { ok: false, error: rulesError.value })
      showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
      return
    }
    finishJob(id, { ok: true, meta: { files: rulesCount.value } })
    showNotification({ content: 'operationDone', type: 'alert-success', timeout: 1600 })
    await refreshFreshness()
  } catch (e: any) {
    finishJob(id, { ok: false, error: e?.message || 'failed' })
    showNotification({ content: 'operationFailed', type: 'alert-error', timeout: 2200 })
  } finally {
    rulesRescanBusy.value = false
  }
}
</script>
