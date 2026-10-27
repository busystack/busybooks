// The application search contract is Unicode, case-insensitive literal
// substring matching. ECMAScript Unicode simple case folding agrees with
// Dart's RegExp(unicode: true, caseSensitive: false). Do not lowercase or
// normalize publication text: these offsets always refer to the original.
export function* literalRanges(text, query) {
    if (!query) return
    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const expression = new RegExp(escaped, 'giu')
    for (const match of text.matchAll(expression))
        yield { start: match.index, end: match.index + match[0].length }
}

export function excerptParts(text, { start, end }, context = 60) {
    // Avoid bisecting a supplementary character when clipping the context.
    const safe = offset => offset > 0 && offset < text.length
        && /[\uD800-\uDBFF]/.test(text[offset - 1])
        && /[\uDC00-\uDFFF]/.test(text[offset]) ? offset - 1 : offset
    const before = safe(Math.max(0, start - context)), after = safe(Math.min(text.length, end + context))
    return { pre: (before ? '…' : '') + text.slice(before, start),
        match: text.slice(start, end), post: text.slice(end, after) + (after < text.length ? '…' : '') }
}

// Foliate's text walker supplies text nodes and a range factory. Joining the
// logical text lets literal phrases span inline markup without searching XML.
export function* literalTextMatches(strings, query, makeRange) {
    if (!strings.length || !query) return
    const text = strings.join(''), boundaries = [0]
    for (const string of strings) boundaries.push(boundaries.at(-1) + string.length)
    function position(offset, end) {
        let lo = 0, hi = strings.length - 1
        while (lo < hi) {
            const mid = (lo + hi) >>> 1
            if (end ? boundaries[mid + 1] < offset : boundaries[mid + 1] <= offset) lo = mid + 1
            else hi = mid
        }
        return [lo, offset - boundaries[lo]]
    }
    for (const match of literalRanges(text, query)) {
        const [startIndex, startOffset] = position(match.start, false)
        const [endIndex, endOffset] = position(match.end, true)
        yield { range: makeRange(startIndex, startOffset, endIndex, endOffset),
            excerptParts: excerptParts(text, match) }
    }
}
