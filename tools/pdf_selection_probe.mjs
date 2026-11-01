// Fresh application-owned DOM interfaces exercise logical source coordinates;
// real WebKitGTK/WebView2 selection rendering is qualified separately.
import assert from 'node:assert/strict'
import { PdfSelectionMemory } from '../assets/reader/pdf_selection.mjs'

class Node {
    constructor(value, ...children) {
        this.nodeType = typeof value === 'string' ? 3 : 1
        this.value = this.nodeType === 3 ? value : ''
        this.childNodes = children
        for (const child of children) child.parentNode = this
    }
    get textContent() { return this.nodeType === 3 ? this.value : this.childNodes.map(child => child.textContent).join('') }
    get isConnected() { let node = this; while (node.parentNode) node = node.parentNode; return node === this.document?.root }
}
const text = value => new Node(value), element = (...children) => new Node(null, ...children)
function fixture() {
    const content = {scrollLeft: 18, scrollTop: 42}, state = {owner: {publication: {}, session: 'first'}, pages: [], restored: []}
    const document = {activeElement: {name: 'Notebook editor'}, root: element()}
    function positions() {
        const points = new Map(), raw = new Map(); let order = 0, offset = 0
        function walk(node) {
            const entries = [], offsets = []
            if (node.nodeType === 3) {
                for (let i = 0; i <= node.value.length; i++) { entries.push(order++); offsets.push(offset + i) }
                offset += node.value.length
            } else {
                entries.push(order++); offsets.push(offset)
                for (const child of node.childNodes) { walk(child); entries.push(order++); offsets.push(offset) }
            }
            points.set(node, entries); raw.set(node, offsets)
        }
        walk(document.root)
        return {point: (node, offset) => points.get(node)?.[offset], raw: (node, offset) => raw.get(node)?.[offset]}
    }
    class Range {
        constructor() { this.startContainer = this.endContainer = document.root; this.startOffset = this.endOffset = 0 }
        setStart(node, offset) {
            this.startContainer = node; this.startOffset = offset
            if (this._compare(this.startContainer, this.startOffset, this.endContainer, this.endOffset) > 0) { this.endContainer = node; this.endOffset = offset }
        }
        setEnd(node, offset) {
            this.endContainer = node; this.endOffset = offset
            if (this._compare(this.startContainer, this.startOffset, this.endContainer, this.endOffset) > 0) { this.startContainer = node; this.startOffset = offset }
        }
        _compare(a, x, b, y) { const map = positions(); return Math.sign(map.point(a, x) - map.point(b, y)) }
        selectNodeContents(node) { this.startContainer = this.endContainer = node; this.startOffset = 0; this.endOffset = node.nodeType === 3 ? node.value.length : node.childNodes.length }
        cloneRange() { return Object.assign(new Range(), this) }
        compareBoundaryPoints(how, other) { return how === 0 ? this._compare(this.startContainer, this.startOffset, other.startContainer, other.startOffset) : this._compare(this.endContainer, this.endOffset, other.endContainer, other.endOffset) }
        intersectsNode(node) { return this._compare(this.endContainer, this.endOffset, node, 0) >= 0 && this._compare(this.startContainer, this.startOffset, node, node.nodeType === 3 ? node.value.length : node.childNodes.length) <= 0 }
        collapse(start) { if (start) { this.endContainer = this.startContainer; this.endOffset = this.startOffset } else { this.startContainer = this.endContainer; this.startOffset = this.endOffset } }
        get collapsed() { return this.startContainer === this.endContainer && this.startOffset === this.endOffset }
        toString() { const map = positions(); return document.root.textContent.slice(map.raw(this.startContainer, this.startOffset), map.raw(this.endContainer, this.endOffset)) }
    }
    const selected = {
        range: null, get rangeCount() { return this.range ? 1 : 0 }, get isCollapsed() { return !this.range || this.range.collapsed },
        getRangeAt() { return this.range }, toString() { return this.range?.toString() ?? '' },
        removeAllRanges() { this.range = null }, addRange(range) { this.range = range },
        setBaseAndExtent(anchor, anchorOffset, focus, focusOffset) {
            Object.assign(this, {anchorNode: anchor, anchorOffset, focusNode: focus, focusOffset})
            const map = positions(), backwards = map.point(anchor, anchorOffset) > map.point(focus, focusOffset), range = new Range()
            range.setStart(backwards ? focus : anchor, backwards ? focusOffset : anchorOffset)
            range.setEnd(backwards ? anchor : focus, backwards ? anchorOffset : focusOffset)
            this.range = range
            // Browser scrolling is an unwanted side effect that the helper must undo.
            content.scrollLeft = 999; content.scrollTop = 999
        },
        extend(focus, offset) { this._set(this.anchorNode, this.anchorOffset, focus, offset) },
    }
    selected._set = selected.setBaseAndExtent.bind(selected)
    const addRange = selected.addRange
    selected.addRange = function (range) { addRange.call(this, range); this.anchorNode = range.startContainer; this.anchorOffset = range.startOffset; this.focusNode = range.endContainer; this.focusOffset = range.endOffset }
    document.createRange = () => new Range()
    document.getSelection = () => selected
    const layout = (texts = ['A😀e\u0301 BC終D', 'line spaced終😀']) => {
        state.pages = texts.map((value, index) => {
            const first = text(value.slice(0, 3)), rest = text(value.slice(3)), nested = element(rest), br = element(), layer = element(element(first), br, nested), page = element(layer)
            page.querySelector = name => name === '.textLayer' ? layer : null
            return {ref: {num: index + 10, gen: 0}, element: page, layer, first, rest}
        })
        document.root.childNodes = state.pages.map(page => page.element)
        const connect = (node, parent) => { node.parentNode = parent; node.document = document; for (const child of node.childNodes) connect(child, node) }
        for (const node of document.root.childNodes) connect(node, document.root)
        selected.removeAllRanges()
    }
    layout()
    const memory = new PdfSelectionMemory({document, content, getOwner: () => state.owner, getPages: () => state.pages,
        onRestore: (data, range) => state.restored.push({data, range, active: document.activeElement})})
    function capture({backwards = false, first = 0, last = 1, start = 1, end = 5} = {}) {
        const a = state.pages[first].first, b = state.pages[last].rest
        selected._set(...(backwards ? [b, end, a, start] : [a, start, b, end]))
        const data = {text: selected.toString(), reference: 'Original source', anchor: {page: first,
            segments: [first, last].filter((value, index, all) => all.indexOf(value) === index).map(page => ({page, start: page === first ? start : 0, boxes: [[1, 2, 3, 4]]}))}}
        assert(memory.capture(data)); assert(memory.expectedSelection())
        return data
    }
    return {state, document, content, selected, memory, layout, capture}
}

for (const backwards of [false, true]) {
    const f = fixture(), data = f.capture({backwards}), anchor = data.anchor, original = JSON.stringify(data)
    const work = f.memory.beginRelayout()
    assert.deepEqual([...f.memory.pinnedPages], [0, 1]); assert(f.memory.ownsPending)
    f.layout()
    f.content.scrollLeft = 66
    const active = f.document.activeElement = {name: 'Newly focused Notebook editor'}, ensured = []
    assert(await f.memory.restore(work, {ensurePage: async index => { ensured.push(index); assert(f.memory.pinnedPages.has(index)); f.content.scrollTop = 77 }}))
    assert.deepEqual(ensured, [0, 1]); assert.equal(f.selected.toString(), data.text)
    assert.equal(f.selected.anchorNode, backwards ? f.state.pages[1].rest : f.state.pages[0].first)
    assert.equal(f.selected.focusNode, backwards ? f.state.pages[0].first : f.state.pages[1].rest)
    assert.equal(f.memory.expectedSelection(), true); assert.equal(f.memory.hasSelection, true)
    assert.equal(f.state.restored[0].data, data); assert.equal(f.state.restored[0].data.anchor, anchor); assert.equal(JSON.stringify(data), original)
    assert.equal(f.document.activeElement, active); assert.equal(f.content.scrollTop, 77); assert.equal(f.content.scrollLeft, 66)
    assert.equal(f.memory.ownsPending, false); assert.equal(f.memory.pinnedPages.size, 0)
}
// Element endpoints on either side of an EOL BR have the same raw text offset,
// but are distinct source boundaries and must survive without a guessed clamp.
for (const boundary of [1, 2]) {
    const f = fixture(), layer = f.state.pages[0].layer
    f.selected._set(layer, boundary, f.state.pages[0].rest, 4)
    const data = {text: f.selected.toString(), anchor: {segments: [{page: 0}]}}
    assert(f.memory.capture(data)); const work = f.memory.beginRelayout(); f.layout()
    assert(await f.memory.restore(work, {ensurePage: async () => true}))
    assert.equal(f.selected.anchorNode, f.state.pages[0].layer); assert.equal(f.selected.anchorOffset, boundary)
}
{
    const f = fixture(); f.capture({backwards: true}); const work = f.memory.beginRelayout(); f.layout()
    f.selected.setBaseAndExtent = undefined
    assert(await f.memory.restore(work, {ensurePage: async () => true})); assert.equal(f.selected.anchorNode, f.state.pages[1].rest)
}
for (const stale of ['owner', 'session', 'intent', 'caller', 'clear', 'text', 'reference']) {
    const f = fixture(); f.capture(); const work = f.memory.beginRelayout(); f.layout()
    const restored = await f.memory.restore(work, {ensurePage: async () => {
        if (stale === 'owner') f.state.owner = {publication: {}, session: 'first'}
        if (stale === 'session') f.state.owner = {...f.state.owner, session: 'second'}
        if (stale === 'intent') f.memory.invalidate()
        if (stale === 'clear') { f.selected.removeAllRanges(); f.memory.capture(null) }
        if (stale === 'text') f.state.pages[0].first.value = 'wrong text'
        if (stale === 'reference') f.state.pages[0].ref = {num: 99, gen: 0}
    }, isCurrent: () => stale !== 'caller'})
    assert.equal(restored, false, stale); assert.equal(f.state.restored.length, 0, stale); assert.equal(f.memory.pinnedPages.size, 0, stale)
}
{
    const f = fixture(); f.capture(); const old = f.memory.beginRelayout(); f.layout()
    const data = f.capture({first: 1, last: 1, start: 0, end: 3}), latest = f.memory.beginRelayout()
    assert.equal(await f.memory.restore(old, {ensurePage: async () => true}), false)
    assert(f.memory.hasSelection); assert(f.memory.ownsPending)
    assert(await f.memory.restore(latest, {ensurePage: async () => true})); assert.equal(f.state.restored[0].data, data)
}
{
    const f = fixture(); f.capture(); const old = f.memory.beginRelayout(), latest = f.memory.beginRelayout(); f.layout()
    assert.equal(await f.memory.restore(old, {ensurePage: async () => true}), false)
    assert(f.memory.ownsPending); assert(await f.memory.restore(latest, {ensurePage: async () => true}))
}
for (const change of ['replacement', 'new geometry', 'clear']) {
    const f = fixture(); f.capture(); const old = f.memory.beginRelayout(); f.layout()
    let release
    const render = new Promise(resolve => { release = resolve })
    const restoring = f.memory.restore(old, {ensurePage: () => render})
    let latest, data
    if (change === 'replacement') { data = f.capture({first: 1, last: 1, start: 0, end: 3}); latest = f.memory.beginRelayout() }
    if (change === 'new geometry') latest = f.memory.beginRelayout()
    if (change === 'clear') f.memory.capture(null)
    release(true)
    assert.equal(await restoring, false, change)
    assert.equal(f.state.restored.length, 0)
    assert.equal(f.memory.abandon(old), false, 'old cleanup cannot discard a newer selection or layout')
    if (latest) {
        assert(f.memory.ownsPending)
        assert(await f.memory.restore(latest, {ensurePage: async () => true}))
        if (data) assert.equal(f.state.restored[0].data, data)
    } else assert.equal(f.memory.hasSelection, false)
}
{
    const f = fixture(); f.capture(); const work = f.memory.beginRelayout(); f.layout()
    assert.equal(f.memory.abandon(null), false)
    assert(f.memory.abandon(work), 'an early layout failure can release its exact work')
    assert.equal(f.memory.hasSelection, false); assert.equal(f.memory.ownsPending, false); assert.equal(f.memory.pinnedPages.size, 0)
    assert.equal(await f.memory.restore(work, {ensurePage: async () => true}), false)
}
{
    const f = fixture(); f.layout(['first page', '', 'last page']); f.capture({first: 0, last: 2, end: 3})
    const work = f.memory.beginRelayout(), ensured = []; f.layout(['first page', 'new unloaded gap text', 'last page'])
    assert.equal(await f.memory.restore(work, {ensurePage: async index => ensured.push(index)}), false)
    assert.deepEqual(ensured, [0, 2], 'restoration never loads unrepresented intermediate pages')
    assert.equal(f.state.restored.length, 0)
}
{
    const f = fixture(); f.capture(); const work = f.memory.beginRelayout(); f.layout()
    await assert.rejects(f.memory.restore(work, {ensurePage: async () => { throw Error('original render failure') }}), /original render failure/)
    assert.equal(f.memory.hasSelection, false); assert.equal(f.memory.pinnedPages.size, 0)
}
console.log(JSON.stringify({status: 'passed', scope: 'Owned PDF logical selection: exact UTF-16/BR/nested endpoints, multipage direction, owner/intent/source validation, pinned represented pages, no gap expansion, unchanged anchors/scroll/focus and no popup callbacks; controlled DOM only'}))
