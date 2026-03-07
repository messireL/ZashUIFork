import axios from 'axios'
import { agentToken, agentUrl } from '@/store/agent'

// Normalized agent base URL for plain fetch() calls.
// (Vite does not typecheck by default; keeping this local avoids runtime ReferenceError.)
const getAgentBaseUrl = () => {
  const u = String(agentUrl.value || '').trim()
  if (!u) return ''
  return u.replace(/\/+$/g, '')
}

/**
 * Some router setups return CGI-style headers inside the response body,
 * e.g. "Content-Type: application/json\n...\n\n{...}".
 * Axios will then keep it as a string and JSON parsing downstream breaks.
 */
const parseMaybeCgiJson = (data: any) => {
  if (typeof data !== 'string') return data
  // Fast path: valid JSON.
  try {
    return JSON.parse(data)
  } catch {
    /* noop */
  }
  // Fallback: strip everything before the first '{'.
  const i = data.indexOf('{')
  if (i < 0) return data
  const j = data.lastIndexOf('}')
  const jsonStr = j >= i ? data.slice(i, j + 1) : data.slice(i)
  try {
    return JSON.parse(jsonStr)
  } catch {
    /* noop */
  }
  // Some router CGI scripts accidentally return pseudo-JSON with escaped quotes,
  // e.g. {"ok":true}. Best-effort normalize it for the UI.
  try {
    const normalized = jsonStr.replace(/\"/g, '"')
    return JSON.parse(normalized)
  } catch {
    return data
  }
}

type AgentStatus = {
  ok: boolean
  version?: string
  serverVersion?: string
  wan?: string
  lan?: string
  tc?: boolean
  iptables?: boolean
  hashlimit?: boolean
  // optional system metrics (agent >= 0.4)
  cpuPct?: number
  load1?: string
  uptimeSec?: number
  memTotal?: number
  memUsed?: number
  memUsedPct?: number
  error?: string
}

const agentAxios = () => {
  const instance = axios.create({
    baseURL: agentUrl.value || '',
    timeout: 4000,
    transformResponse: [
      (data) => {
        // Keep default behaviour for already-parsed objects.
        return parseMaybeCgiJson(data)
      },
    ],
  })

  instance.interceptors.request.use((cfg) => {
    const token = (agentToken.value || '').trim()
    if (token) {
      cfg.headers = cfg.headers || {}
      ;(cfg.headers as any).Authorization = `Bearer ${token}`
    }
    return cfg
  })

  return instance
}

export const agentStatusAPI = async (): Promise<AgentStatus> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'status' },
      // NOTE: this axios instance does not use the global interceptors.
      // Adding custom headers (like X-Zash-Silent) triggers CORS preflight
      // from browsers, so keep requests headerless unless a token is set.
    })
    return (data || {}) as AgentStatus
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentSetShapeAPI = async (args: {
  ip: string
  upMbps: number
  downMbps: number
}): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: {
        cmd: 'shape',
        ip: args.ip,
        up: args.upMbps,
        down: args.downMbps,
      },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentRemoveShapeAPI = async (ip: string): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'unshape', ip },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export type AgentNeighbor = { ip: string; mac: string; state?: string }

export const agentNeighborsAPI = async (): Promise<{ ok: boolean; items?: AgentNeighbor[]; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'neighbors' },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


export type AgentLanHost = { ip: string; mac?: string; hostname?: string; source?: string }

export const agentLanHostsAPI = async (): Promise<{ ok: boolean; items?: AgentLanHost[]; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'lan_hosts' },
      timeout: 10000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentIpToMacAPI = async (ip: string): Promise<{ ok: boolean; mac?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'ip2mac', ip },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentBlockMacAPI = async (args: {
  mac: string
  /**
   * 'all' = drop all traffic from the MAC.
   * number[] = legacy mode (block only selected ports).
   */
  ports: number[] | 'all'
}): Promise<{ ok: boolean; error?: string }> => {
  try {
    const portsParam = args.ports === 'all' ? 'all' : args.ports.join(',')
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'blockmac', mac: args.mac, ports: portsParam },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentBlockIpAPI = async (ip: string): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'blockip', ip },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentUnblockIpAPI = async (ip: string): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'unblockip', ip },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentLogsAPI = async (args: {
  type: 'mihomo' | 'agent' | 'config'
  lines?: number
}): Promise<{ ok: boolean; kind?: string; path?: string; contentB64?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'logs', type: args.type, lines: args.lines ?? 200 },
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}

export const agentLogsFollowAPI = async (args: {
  type: 'mihomo' | 'agent'
  lines?: number
  offset?: number
}): Promise<{
  ok: boolean
  kind?: string
  path?: string
  contentB64?: string
  offset?: number
  mode?: 'full' | 'delta'
  truncated?: boolean
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'logs_follow', type: args.type, lines: args.lines ?? 200, offset: args.offset ?? 0 },
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


export const agentGeoInfoAPI = async (): Promise<{
  ok: boolean
  items?: Array<{
    kind?: string
    path?: string
    exists?: boolean
    mtimeSec?: number | string
    sizeBytes?: number | string
  }>
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'geo_info' },
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


export const agentGeoUpdateAPI = async (): Promise<{
  ok: boolean
  items?: Array<{
    kind?: string
    path?: string
    changed?: boolean
    mtimeSec?: number | string
    sizeBytes?: number | string
    method?: string
    source?: string
    error?: string
  }>
  note?: string
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'geo_update' },
      timeout: 30000,
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


export const agentRulesInfoAPI = async (): Promise<{
  ok: boolean
  dir?: string
  count?: number
  newestMtimeSec?: number | string
  oldestMtimeSec?: number | string
  items?: Array<{
    name?: string
    path?: string
    mtimeSec?: number | string
    sizeBytes?: number | string
  }>
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'rules_info' },
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


export const agentUnblockMacAPI = async (mac: string): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'unblockmac', mac },
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'failed' }
  }
}


let _mihomoProvidersCache: { ok: boolean; providers?: any[]; error?: string } | null = null
let _mihomoProvidersAt = 0

export const agentMihomoConfigAPI = async (): Promise<{
  ok: boolean
  contentB64?: string
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'mihomo_config' },
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentMihomoProvidersAPI = async (force = false): Promise<{
  ok: boolean
  providers?: Array<{
    name: string
    url?: string
    host?: string
    port?: string
    sslNotAfter?: string
  }>
  error?: string
}> => {
  const now = Date.now()
  if (!force && _mihomoProvidersCache && now - _mihomoProvidersAt < 60_000) return _mihomoProvidersCache as any

  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'mihomo_providers' },
    })
    _mihomoProvidersCache = (data || {}) as any
    _mihomoProvidersAt = now
    return _mihomoProvidersCache as any
  } catch (e: any) {
    const res = { ok: false, error: e?.message || 'offline' }
    _mihomoProvidersCache = res as any
    _mihomoProvidersAt = now
    return res as any
  }
}

// Batch probe TLS certificate expiry (notAfter) for a list of HTTPS/WSS URLs.
// Input format (text/plain): each line "<name>\t<url>".
// Returns: { ok, checkedAtSec, items: [{ name, url, sslNotAfter, error }] }
export const agentSslProbeBatchAPI = async (lines: string): Promise<any> => {
  const base = getAgentBaseUrl()
  if (!base) return { ok: false, error: 'agent-disabled' }

  const url = `${base}/cgi-bin/api.sh?cmd=ssl_probe_batch`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'text/plain',
    },
    body: lines || '',
  })
  return await res.json()
}

// --- Shared users DB (Source IP mapping) ---

export const agentUsersDbGetAPI = async (): Promise<{
  ok: boolean
  rev?: number
  updatedAt?: string
  contentB64?: string
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'users_db_get' },
      // Router can be slow on flash IO; keep sync stable.
      timeout: 15000,
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentUsersDbPutAPI = async (args: { rev: number; content: string }): Promise<{
  ok: boolean
  rev?: number
  updatedAt?: string
  error?: string
  contentB64?: string
}> => {
  try {
    const { data } = await agentAxios().post(`/cgi-bin/api.sh?cmd=users_db_put&rev=${encodeURIComponent(String(args.rev ?? 0))}`,
      args.content,
      {
        headers: {
          'Content-Type': 'text/plain',
        },
        // Allow slower writes on embedded storage.
        timeout: 20000,
      },
    )
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' } as any
  }
}


// --- Shared users DB history / restore ---

export type UsersDbHistoryItem = {
  rev: number
  updatedAt?: string
  current?: boolean
}

export const agentUsersDbHistoryAPI = async (): Promise<{
  ok: boolean
  items?: UsersDbHistoryItem[]
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'users_db_history' },
      timeout: 15000,
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentUsersDbGetRevAPI = async (rev: number): Promise<{
  ok: boolean
  rev?: number
  updatedAt?: string
  contentB64?: string
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'users_db_get_rev', rev: String(rev ?? 0) },
      timeout: 15000,
    })
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentUsersDbRestoreAPI = async (rev: number): Promise<{
  ok: boolean
  rev?: number
  updatedAt?: string
  restoredFromRev?: number
  error?: string
}> => {
  try {
    const { data } = await agentAxios().post(
      `/cgi-bin/api.sh?cmd=users_db_restore&rev=${encodeURIComponent(String(rev ?? 0))}`,
      '',
      {
        headers: { 'Content-Type': 'text/plain' },
        timeout: 20000,
      },
    )
    return (data || {}) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' } as any
  }
}


export type AgentBackupStatus = {
  ok: boolean
  running?: boolean
  startedAt?: string
  finishedAt?: string
  success?: boolean
  file?: string
  uploaded?: boolean
  error?: string
}

export const agentBackupStatusAPI = async (): Promise<AgentBackupStatus> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_status' },
      timeout: 8000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export type AgentBackupCloudStatus = {
  ok: boolean
  rcloneInstalled?: boolean
  configPath?: string
  remote?: string
  remoteExists?: boolean
  path?: string
  cloudReady?: boolean
  keepDays?: string
  localKeepDays?: string
  uiZipEnabled?: boolean
  error?: string
}

export const agentBackupCloudStatusAPI = async (): Promise<AgentBackupCloudStatus> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_cloud_status' },
      timeout: 8000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupStartAPI = async (): Promise<{ ok: boolean; running?: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_start' },
      timeout: 8000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupLogAPI = async (lines: number = 200): Promise<{ ok: boolean; path?: string; contentB64?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_log', lines: String(lines ?? 200) },
      timeout: 8000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}


export type AgentBackupListItem = { name: string; size?: number; mtime?: number }


export type AgentBackupCloudListItem = {
  Name?: string
  Path?: string
  Size?: number
  ModTime?: string
}

export const agentBackupCloudListAPI = async (): Promise<{
  ok: boolean
  remote?: string
  path?: string
  dir?: string
  items?: AgentBackupCloudListItem[]
  error?: string
}> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_cloud_list' },
      timeout: 12000,
    })
    return (data || { ok: true, items: [] }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupListAPI = async (): Promise<{ ok: boolean; dir?: string; items?: AgentBackupListItem[]; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_list' },
      timeout: 8000,
    })
    return (data || { ok: true, items: [] }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupDeleteAPI = async (file: string): Promise<{ ok: boolean; deleted?: boolean; name?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_delete', file },
      timeout: 10000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupCloudDeleteAPI = async (file: string): Promise<{ ok: boolean; deleted?: boolean; name?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_cloud_delete', file },
      timeout: 12000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export type AgentRestoreStatus = {
  ok: boolean
  running?: boolean
  startedAt?: string
  finishedAt?: string
  success?: boolean
  file?: string
  scope?: string
  includeEnv?: boolean
  source?: string
  stage?: string
  progressPct?: number
  bytesDone?: number
  bytesTotal?: number
  detail?: string
  error?: string
}

export const agentRestoreStatusAPI = async (): Promise<AgentRestoreStatus> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'restore_status' },
      timeout: 8000,
    })
    return (data || { ok: true, running: false }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentRestoreStartAPI = async (
  file: string,
  scope: string,
  includeEnv: boolean,
  source: 'local' | 'cloud' = 'local',
): Promise<{ ok: boolean; running?: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: {
        cmd: 'restore_start',
        file: file || 'latest',
        scope: scope || 'all',
        env: includeEnv ? '1' : '0',
        source: source || 'local',
      },
      timeout: 12000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentRestoreLogAPI = async (lines: number = 200): Promise<{ ok: boolean; path?: string; contentB64?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'restore_log', lines: String(lines ?? 200) },
      timeout: 8000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export type AgentBackupCronStatus = {
  ok: boolean
  enabled?: boolean
  schedule?: string
  line?: string
  path?: string
  error?: string
}

export const agentBackupCronGetAPI = async (): Promise<AgentBackupCronStatus> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_cron_get' },
      timeout: 8000,
    })
    return (data || { ok: true, enabled: false }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}

export const agentBackupCronSetAPI = async (enabled: boolean, schedule: string): Promise<{ ok: boolean; enabled?: boolean; schedule?: string; path?: string; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'backup_cron_set', enabled: enabled ? '1' : '0', schedule },
      timeout: 10000,
    })
    return (data || { ok: true }) as any
  } catch (e: any) {
    return { ok: false, error: e?.message || 'offline' }
  }
}
