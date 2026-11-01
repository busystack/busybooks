// BusyBooks logical PDF selection memory. Uses only public DOM interfaces and
// the application page records; PDF.js implementation and saved anchors stay intact.
export class PdfSelectionMemory {
    constructor({document, content, getOwner, getPages, onRestore}) {
        Object.assign(this, {document, content, getOwner, getPages, onRestore})
        this.revision = 0
        this.snapshot = null
        this.pending = null
        this.expected = null
    }
    get hasSelection() { return !!this.snapshot && this.snapshot.owner === this.getOwner() }
    get ownsPending() { return !!this.pending && this._current(this.pending) }
    get pinnedPages() { return new Set(this.ownsPending ? this.pending.snapshot.pages.map(page => page.index) : []) }
    invalidate() {
        this.revision++
        this.snapshot = this.pending = this.expected = null
    }
    capture(data) {
        this.invalidate()
        const selected = this.document.getSelection(), owner = this.getOwner()
        if (!owner || !data?.anchor?.segments?.length || selected?.rangeCount !== 1 || selected.isCollapsed) return null
        const range = selected.getRangeAt(0), pages = this.getPages(), captured = []
        const indices = [...new Set(data.anchor.segments.map(segment => segment.page))].sort((a, b) => a - b)
        try {
            for (const index of indices) {
                const page = pages[index], layer = page?.element.querySelector('.textLayer')
                if (!Number.isSafeInteger(index) || !layer?.isConnected || !range.intersectsNode(layer)) return null
                const all = this.document.createRange(); all.selectNodeContents(layer)
                const piece = range.cloneRange()
                if (piece.compareBoundaryPoints(0, all) < 0) piece.setStart(all.startContainer, all.startOffset)
                if (piece.compareBoundaryPoints(2, all) > 0) piece.setEnd(all.endContainer, all.endOffset)
                if (piece.collapsed) continue
                captured.push({index, ref: this._ref(page), text: layer.textContent,
                    start: this._endpoint(layer, piece.startContainer, piece.startOffset),
                    end: this._endpoint(layer, piece.endContainer, piece.endOffset), selected: piece.toString()})
            }
            if (!captured.length || captured.map(page => page.selected).join('') !== range.toString()) return null
            this.snapshot = {owner, revision: this.revision, data, pages: captured, text: range.toString(),
                backwards: selected.anchorNode === range.endContainer && selected.anchorOffset === range.endOffset}
            this.expected = this._selection(range, this.snapshot.backwards)
            return this.snapshot
        } catch (_) { return null }
    }
    beginRelayout() {
        if (!this.hasSelection) return null
        const work = {snapshot: this.snapshot, revision: this.revision}
        this.pending = work
        return work
    }
    abandon(work) {
        if (!work || this.pending !== work) return false
        this.pending = null
        if (this.snapshot === work.snapshot) this.snapshot = this.expected = null
        return true
    }
    expectedSelection(selected = this.document.getSelection()) {
        if (!this.hasSelection || !this.expected || selected?.rangeCount !== 1 || selected.isCollapsed) return false
        const range = selected.getRangeAt(0), expected = this.expected
        return range.startContainer.isConnected && range.endContainer.isConnected &&
            range.startContainer === expected.start && range.startOffset === expected.startOffset &&
            range.endContainer === expected.end && range.endOffset === expected.endOffset &&
            selected.anchorNode === expected.anchor && selected.anchorOffset === expected.anchorOffset &&
            selected.focusNode === expected.focus && selected.focusOffset === expected.focusOffset &&
            range.toString() === this.snapshot.text
    }
    async restore(work, {ensurePage, isCurrent = () => true}) {
        if (!work) return false
        const current = () => this._current(work) && isCurrent()
        let restored = false
        try {
            if (!current()) return false
            for (const page of work.snapshot.pages) {
                if (await ensurePage(page.index) === false || !current()) return false
            }
            const mapped = []
            for (const saved of work.snapshot.pages) {
                const page = this.getPages()[saved.index], layer = page?.element.querySelector('.textLayer')
                if (!layer?.isConnected || this._ref(page) !== saved.ref || layer.textContent !== saved.text) return false
                const start = this._resolve(layer, saved.start), end = this._resolve(layer, saved.end)
                if (!start || !end) return false
                const range = this.document.createRange(); range.setStart(...start); range.setEnd(...end)
                if (range.toString() !== saved.selected) return false
                mapped.push({start, end})
            }
            const range = this.document.createRange()
            range.setStart(...mapped[0].start); range.setEnd(...mapped.at(-1).end)
            // Do not expand a selection to text that was absent in unloaded gaps.
            if (range.toString() !== work.snapshot.text || !current()) return false
            const selected = this.document.getSelection(), backwards = work.snapshot.backwards
            if (!selected) return false
            const anchor = backwards ? mapped.at(-1).end : mapped[0].start
            const focus = backwards ? mapped[0].start : mapped.at(-1).end
            const left = this.content.scrollLeft, top = this.content.scrollTop
            this.expected = this._selection(range, backwards)
            try {
                if (typeof selected.setBaseAndExtent === 'function') selected.setBaseAndExtent(...anchor, ...focus)
                else if (typeof selected.extend === 'function') {
                    const caret = range.cloneRange(); caret.setStart(...anchor); caret.collapse(true)
                    selected.removeAllRanges(); selected.addRange(caret); selected.extend(...focus)
                } else if (!backwards) { selected.removeAllRanges(); selected.addRange(range) }
                else return false
            } finally {
                this.content.scrollLeft = left; this.content.scrollTop = top
            }
            if (!current() || !this.expectedSelection(selected)) return false
            restored = true
            this.onRestore(work.snapshot.data, selected.getRangeAt(0))
            return true
        } finally {
            if (this.pending === work) {
                this.pending = null
                if (!restored && this.snapshot === work.snapshot) this.snapshot = this.expected = null
            }
        }
    }
    _current(work) {
        return this.pending === work && work.revision === this.revision &&
            this.snapshot === work.snapshot && work.snapshot.owner === this.getOwner()
    }
    _ref(page) { return JSON.stringify(page.ref ?? null) }
    _endpoint(layer, node, offset) {
        const path = [], source = node
        for (; node !== layer; node = node.parentNode) {
            if (!node?.parentNode) throw Error('Selection endpoint is outside its PDF text layer')
            path.unshift([...node.parentNode.childNodes].indexOf(node))
        }
        const prefix = this.document.createRange(); prefix.selectNodeContents(layer); prefix.setEnd(source, offset)
        return {path, offset, raw: prefix.toString().length}
    }
    _resolve(layer, endpoint) {
        let node = layer
        for (const index of endpoint.path) { node = node.childNodes[index]; if (!node) return null }
        const maximum = node.nodeType === 3 ? node.textContent.length : node.childNodes.length
        if (endpoint.offset < 0 || endpoint.offset > maximum) return null
        const prefix = this.document.createRange(); prefix.selectNodeContents(layer); prefix.setEnd(node, endpoint.offset)
        return prefix.toString().length === endpoint.raw ? [node, endpoint.offset] : null
    }
    _selection(range, backwards) {
        return {start: range.startContainer, startOffset: range.startOffset, end: range.endContainer, endOffset: range.endOffset,
            anchor: backwards ? range.endContainer : range.startContainer, anchorOffset: backwards ? range.endOffset : range.startOffset,
            focus: backwards ? range.startContainer : range.endContainer, focusOffset: backwards ? range.startOffset : range.endOffset}
    }
}
