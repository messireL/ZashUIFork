export const normalizeProviderIcon = (v: any): string => {
  const s = String(v || '').trim()
  if (!s) return ''
  const low = s.toLowerCase()
  if (low === 'globe' || s === '🌍' || s === '🌎' || s === '🌏' || s === '🌐') return 'globe'
  // ISO 3166-1 alpha-2
  if (/^[a-zA-Z]{2}$/.test(s)) return s.toUpperCase()
  return ''
}

export const countryCodeToFlagEmoji = (code: string): string => {
  const cc = String(code || '').trim().toUpperCase()
  if (!/^[A-Z]{2}$/.test(cc)) return ''
  const A = 0x1f1e6
  const cp1 = A + (cc.charCodeAt(0) - 65)
  const cp2 = A + (cc.charCodeAt(1) - 65)
  try {
    // eslint-disable-next-line no-undef
    return String.fromCodePoint(cp1, cp2)
  } catch {
    return ''
  }
}

export const providerIconLabel = (icon: string): { kind: 'none' | 'globe' | 'flag'; text: string } => {
  const n = normalizeProviderIcon(icon)
  if (!n) return { kind: 'none', text: '' }
  if (n === 'globe') return { kind: 'globe', text: 'globe' }
  const flag = countryCodeToFlagEmoji(n)
  return { kind: flag ? 'flag' : 'none', text: flag || '' }
}
