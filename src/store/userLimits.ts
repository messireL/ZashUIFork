import { useStorage } from '@vueuse/core'

export type UserLimitPeriod = '1d' | '30d' | 'month'

export type UserLimit = {
  enabled?: boolean
  /** Hard disable for the user (manual block). */
  disabled?: boolean
  /** Traffic limit in bytes for the selected period. 0/undefined = no limit. */
  trafficLimitBytes?: number
  /** Traffic period window. */
  trafficPeriod?: UserLimitPeriod
  /** Optional reset baseline timestamp (ms). */
  resetAt?: number
  /** Bandwidth limit in bytes per second (download+upload). 0/undefined = no limit. */
  bandwidthLimitBps?: number
}

export type UserLimitsStore = Record<string, UserLimit>

export const userLimits = useStorage<UserLimitsStore>('config/user-limits-v1', {})

/**
 * If enabled, the UI will attempt to enforce limits by disconnecting active connections
 * of users that are blocked/over-limit via Mihomo API.
 */
export const autoDisconnectLimitedUsers = useStorage<boolean>(
  'config/user-limits-auto-disconnect',
  true,
)
