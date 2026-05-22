export function parsePointEwkbHex(value: string | null | undefined) {
  if (!value || value.length < 42) return null

  try {
    const buffer = Uint8Array.from(value.match(/.{1,2}/g)!.map((pair) => parseInt(pair, 16)))
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength)

    const littleEndian = view.getUint8(0) === 1
    const type = view.getUint32(1, littleEndian)
    const hasSrid = (type & 0x20000000) !== 0
    const baseType = type & 0x0fffffff
    if (baseType !== 1) return null

    const offset = hasSrid ? 9 : 5
    const lng = view.getFloat64(offset, littleEndian)
    const lat = view.getFloat64(offset + 8, littleEndian)

    return { lat, lng }
  } catch {
    return null
  }
}
