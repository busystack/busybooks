// length for context in excerpts
const CONTEXT_LENGTH = 50

const normalizeWhitespace = str => str.replace(/\s+/g, ' ')

const textPosition = strs => {
    const boundaries = [0]
    for (const str of strs) boundaries.push(boundaries.at(-1) + str.length)
    return (offset, end = false) => {
        let low = 0, high = strs.length - 1
        while (low < high) {
            const mid = (low + high) >>> 1
            if (end ? boundaries[mid + 1] < offset : boundaries[mid + 1] <= offset) low = mid + 1
            else high = mid
        }
        return [low, offset - boundaries[low]]
    }
}

const lowercasePosition = (text, lowered, locales) => {
    if (text.length === lowered.length) return offset => offset
    // Keep only length changes, rather than a pair of arrays for every code
    // unit of a potentially large chapter. Graphemes preserve locale mappings
    // involving combining marks, such as Turkish I + dot above.
    const units = Intl?.Segmenter
        ? new Intl.Segmenter(locales, { granularity: 'grapheme' }).segment(text)
        : Array.from(text, segment => ({ segment }))
    const changes = []
    let original = 0, folded = 0
    for (const { segment } of units) {
        const length = segment.toLocaleLowerCase(locales).length
        if (length !== segment.length)
            changes.push({ start: folded, end: folded + length, original, next: original + segment.length })
        original += segment.length
        folded += length
    }
    return (offset, end = false) => {
        let low = 0, high = changes.length
        while (low < high) {
            const mid = (low + high) >>> 1
            if (end ? changes[mid].start < offset : changes[mid].start <= offset) low = mid + 1
            else high = mid
        }
        const change = changes[low - 1]
        if (!change) return offset
        return offset < change.end ? end ? change.next : change.original
            : offset + change.next - change.end
    }
}

const makeExcerpt = (strs, { startIndex, startOffset, endIndex, endOffset }) => {
    const start = strs[startIndex]
    const end = strs[endIndex]
    const match = startIndex === endIndex
        ? start.slice(startOffset, endOffset)
        : start.slice(startOffset)
            + strs.slice(startIndex + 1, endIndex).join('')
            + end.slice(0, endOffset)
    const trimmedStart = normalizeWhitespace(start.slice(0, startOffset)).trimStart()
    const trimmedEnd = normalizeWhitespace(end.slice(endOffset)).trimEnd()
    const ellipsisPre = trimmedStart.length < CONTEXT_LENGTH ? '' : '…'
    const ellipsisPost = trimmedEnd.length < CONTEXT_LENGTH ? '' : '…'
    const pre = `${ellipsisPre}${trimmedStart.slice(-CONTEXT_LENGTH)}`
    const post = `${trimmedEnd.slice(0, CONTEXT_LENGTH)}${ellipsisPost}`
    return { pre, match, post }
}

const simpleSearch = function* (strs, query, options = {}) {
    const { locales = 'en', sensitivity } = options
    const matchCase = sensitivity === 'variant'
    const haystack = strs.join('')
    const lowerHaystack = matchCase ? haystack : haystack.toLocaleLowerCase(locales)
    const needle = matchCase ? query : query.toLocaleLowerCase(locales)
    const needleLength = needle.length
    const original = lowercasePosition(haystack, lowerHaystack, locales)
    const position = textPosition(strs)
    let index = -1
    do {
        index = lowerHaystack.indexOf(needle, index + 1)
        if (index > -1) {
            const [startIndex, startOffset] = position(original(index))
            const [endIndex, endOffset] = position(original(index + needleLength, true), true)
            const range = { startIndex, startOffset, endIndex, endOffset }
            yield { range, excerpt: makeExcerpt(strs, range) }
        }
    } while (index > -1)
}

const segmenterSearch = function* (strs, query, options = {}) {
    const { locales = 'en', granularity = 'word', sensitivity = 'base' } = options
    let segmenter, collator
    try {
        segmenter = new Intl.Segmenter(locales, { usage: 'search', granularity })
        collator = new Intl.Collator(locales, { sensitivity })
    } catch (e) {
        console.warn(e)
        segmenter = new Intl.Segmenter('en', { usage: 'search', granularity })
        collator = new Intl.Collator('en', { sensitivity })
    }
    const queryLength = Array.from(segmenter.segment(query)).length

    const substrArr = []
    // Segment the logical text, so inline markup cannot introduce word or
    // grapheme boundaries. Map the resulting offsets back into the DOM nodes.
    const position = textPosition(strs)
    const segments = segmenter.segment(strs.join(''))[Symbol.iterator]()
    main: while (true) {
        while (substrArr.length < queryLength) {
            const { done, value } = segments.next()
            if (done) {
                break main
            }
            const { index, segment } = value
            // ignore formatting characters
            if (!/[^\p{Format}]/u.test(segment)) continue
            // normalize whitespace
            if (/\s/u.test(segment)) {
                if (!/\s/u.test(substrArr[substrArr.length - 1]?.segment))
                    substrArr.push({ index, segment: ' ', end: index + segment.length })
                continue
            }
            value.end = index + segment.length
            substrArr.push(value)
        }
        const substr = substrArr.map(x => x.segment).join('')
        if (collator.compare(query, substr) === 0) {
            const lastSeg = substrArr[substrArr.length - 1]
            const [endIndex, endOffset] = position(lastSeg.end, true)
            const [startIndex, startOffset] = position(substrArr[0].index)
            const range = { startIndex, startOffset, endIndex, endOffset }
            yield { range, excerpt: makeExcerpt(strs, range) }
        }
        substrArr.shift()
    }
}

export const search = (strs, query, options = {}) => {
    if (!strs.length || !query) return []
    const { granularity = 'grapheme', sensitivity = 'base' } = options
    if (!Intl?.Segmenter || granularity === 'grapheme'
    && (sensitivity === 'variant' || sensitivity === 'accent'))
        return simpleSearch(strs, query, options)
    return segmenterSearch(strs, query, { ...options, granularity, sensitivity })
}

export const searchMatcher = (textWalker, opts) => {
    const { defaultLocale, matchCase, matchDiacritics, matchWholeWords, acceptNode } = opts
    return function* (doc, query) {
        const iter = textWalker(doc, function* (strs, makeRange) {
            for (const result of search(strs, query, {
                locales: doc.body.lang || doc.documentElement.lang || defaultLocale || 'en',
                granularity: matchWholeWords ? 'word' : 'grapheme',
                sensitivity: matchDiacritics && matchCase ? 'variant'
                : matchDiacritics && !matchCase ? 'accent'
                : !matchDiacritics && matchCase ? 'case'
                : 'base',
            })) {
                const { startIndex, startOffset, endIndex, endOffset } = result.range
                result.range = makeRange(startIndex, startOffset, endIndex, endOffset)
                yield result
            }
        }, acceptNode)
        for (const result of iter) yield result
    }
}

