// Pure page geometry, shared by the adapter and executable regressions.
export const PDF_TO_CSS_UNITS = 96 / 72
export function fitScale(width, height, viewportWidth, viewportHeight, zoom, spread = false, gap = 32) {
    const availableWidth = Math.max(1, viewportWidth / (spread ? 2 : 1) - gap)
    const availableHeight = Math.max(1, viewportHeight - gap)
    const value = zoom === 'fit-width' ? availableWidth / width
        : zoom === 'fit-page' || !zoom ? Math.min(availableWidth / width, availableHeight / height)
        : Number(zoom) * PDF_TO_CSS_UNITS
    return Math.max(.000001, Math.min(5, Number.isFinite(value) && value > 0 ? value : 1))
}
export function validPage(value, count) {
    return Number.isInteger(value) && value >= 0 && value < count
}
export function cssColor(argb) {
    const value = Number(argb) >>> 0
    return `#${(value & 0xffffff).toString(16).padStart(6, '0')}${(value >>> 24).toString(16).padStart(2, '0')}`
}

// Return null only at the application/content focus boundary.
export function tabTarget(items, active, backwards = false) {
    const index = items.indexOf(active)
    return items[index < 0 ? (backwards ? -1 : 0) : index + (backwards ? -1 : 1)] ?? null
}
