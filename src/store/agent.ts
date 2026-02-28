import { useStorage } from '@vueuse/core'

/**
 * Router-side helper agent (optional).
 * Used for "adult" bandwidth shaping per client via tc/iptables, because Mihomo API
 * does not provide traffic shaping.
 */

export const agentEnabled = useStorage<boolean>('config/agent-enabled', false)

/**
 * Default tries same host as the UI, on port 9099.
 * Example: http://192.168.1.1:9099
 */
export const agentUrl = useStorage<string>(
  'config/agent-url',
  typeof window !== 'undefined' ? `http://${window.location.hostname}:9099` : '',
)

/** Optional Bearer token for the agent. */
export const agentToken = useStorage<string>('config/agent-token', '')

/**
 * If enabled, bandwidth limits (Mbps) are enforced by the agent (tc/iptables),
 * NOT by disconnecting connections.
 */
export const agentEnforceBandwidth = useStorage<boolean>('config/agent-enforce-bandwidth', false)

/**
 * Remember which IPs were shaped by the UI, so we can clean up removed limits.
 */
export const managedAgentShapers = useStorage<Record<string, { upMbps: number; downMbps: number }>>(
  'config/agent-managed-shapers-v1',
  {},
)

/**
 * Per-IP shaping status from the agent.
 * Useful to show "applied/failed" badges and allow manual re-apply.
 */
export const agentShaperStatus = useStorage<
  Record<string, { ok: boolean; at: number; error?: string }>
>('config/agent-shaper-status-v1', {})

/**
 * MAC blocks managed by the UI (best-effort). Key = mac.
 */
export const managedAgentBlocks = useStorage<Record<string, { ports: string }>>(
  'config/agent-managed-blocks-v1',
  {},
)
