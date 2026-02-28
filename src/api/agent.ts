import axios from 'axios'
import { agentToken, agentUrl } from '@/store/agent'

type AgentStatus = {
  ok: boolean
  version?: string
  wan?: string
  lan?: string
  tc?: boolean
  iptables?: boolean
  hashlimit?: boolean
  error?: string
}

const agentAxios = () => {
  const instance = axios.create({
    baseURL: agentUrl.value || '',
    timeout: 4000,
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
  ports: number[]
}): Promise<{ ok: boolean; error?: string }> => {
  try {
    const { data } = await agentAxios().get('/cgi-bin/api.sh', {
      params: { cmd: 'blockmac', mac: args.mac, ports: args.ports.join(',') },
    })
    return (data || { ok: true }) as any
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
