export type ProxyProtoKey = string

export const normalizeProxyProtoKey = (type: any): ProxyProtoKey => {
  let t = String(type || '').trim().toLowerCase()
  if (!t) return ''

  // common aliases
  if (t === 'shadowsocks' || t.startsWith('shadowsocks')) t = 'ss'
  if (t === 'wireguard') t = 'wg'
  if (t === 'hysteria') t = 'hy'
  if (t === 'hysteria2' || t === 'hy2') t = 'hy2'

  // normalize some known names
  if (t === 'trojan-go') t = 'trojan'

  return t
}

export const protoLabel = (key: string): string => {
  const k = String(key || '').trim()
  if (!k) return ''
  return k.toUpperCase()
}
