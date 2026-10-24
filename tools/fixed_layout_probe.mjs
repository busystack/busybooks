// Exercise the vendored renderer's navigation protocol with a controlled DOM.
// This does not establish native layout, accessibility or selection rendering.
import assert from 'node:assert/strict'

const names = ['HTMLElement', 'ResizeObserver', 'CSSStyleSheet', 'customElements', 'document', 'CustomEvent']
const previous = new Map(names.map(name => [name, Object.getOwnPropertyDescriptor(globalThis, name)]))
const documents = new Map()
class Element extends EventTarget {
  style = {}
  children = []
  scrollLeft = 0
  scrollTop = 0
  constructor(tag = 'host') { super(); this.tag = tag }
  append(child) { child.parentElement = this; this.children.push(child) }
  replaceChildren(...children) { this.children = children }
  setAttribute() {}
  attachShadow() { return this.root = new Element('shadow') }
  querySelectorAll(tag) { return this.children.flatMap(child => [...(child.tag === tag ? [child] : []), ...child.querySelectorAll(tag)]) }
  get clientWidth() { return parseFloat(this.style.width) || 600 }
  get clientHeight() { return parseFloat(this.style.height) || 800 }
  getBoundingClientRect() {
    const scale = parseFloat(this.style.transform?.match(/scale\(([^)]+)/)?.[1] ?? 1)
    return { left: 0, top: 0, right: this.clientWidth * scale, bottom: this.clientHeight * scale, width: this.clientWidth * scale, height: this.clientHeight * scale }
  }
  set src(value) { this.contentDocument = documents.get(value); queueMicrotask(() => this.dispatchEvent(new Event('load'))) }
  scrollBy({left, top}) { this.scrollLeft += left; this.scrollTop += top }
}
try {
  Object.assign(globalThis, {
    HTMLElement: Element,
    ResizeObserver: class { observe() {} unobserve() {} },
    CSSStyleSheet: class { replaceSync() {} },
    customElements: { define() {} },
    document: { createElement: tag => new Element(tag) },
    CustomEvent: class extends Event { constructor(type, options) { super(type); this.detail = options.detail } },
  })
  const { FixedLayout } = await import(process.env.BUSYBOOKS_FIXED_LAYOUT_SOURCE??new URL('../assets/reader/vendor/foliate/fixed-layout.js',import.meta.url))
  let selected = null, focused = null
  for (const id of ['cover', 'left', 'right']) documents.set(id, {
    documentElement: { localName: 'html' },
    querySelector: () => null,
    defaultView: { focus: () => { focused = id } },
    getSelection: () => ({ removeAllRanges() { selected = null }, addRange(range) { selected = range } }),
  })
  const renderer = new FixedLayout(), locations = []
  renderer.addEventListener('relocate', event => locations.push(event.detail))
  renderer.open({ dir: 'ltr', rendition: { viewport: { width: 600, height: 800 } }, sections: [...documents.keys()].map(id => ({ load: async () => id })) })
  renderer.spread = 'none'
  await renderer.goTo({ index: 1 })
  assert.equal(renderer.index, 1)
  await renderer.goTo({ index: 2 })
  assert.equal(renderer.index, 2)
  assert.equal(locations.at(-1).index, 2)
  renderer.attributeChangedCallback('zoom', null, '3')
  const frames = renderer.root.querySelectorAll('iframe')
  assert.equal(frames.find(frame => frame.contentDocument === documents.get('left')).parentElement.style.display, 'none')
  assert.equal(frames.find(frame => frame.contentDocument === documents.get('right')).parentElement.style.display, 'block')
  renderer.focusView()
  assert.equal(focused, 'right')
  const range = { startContainer: {}, getClientRects: () => [{left: 40, right: 80, top: 600, bottom: 620}] }
  await renderer.goTo({ index: 2, anchor: () => range, select: true })
  assert.equal(selected, range)
  assert.equal(locations.at(-1).range, range)
  assert(renderer.scrollTop > 0)
  await renderer.select(Promise.resolve({ index: 1, anchor: () => range }))
  assert.equal(selected, range)
  assert.equal(renderer.index, 1)
  renderer.focusView()
  assert.equal(focused, 'left')
  for (const dir of ['ltr', 'rtl']) for (const spread of ['auto', 'none']) {
    const sections = [...documents.keys()].map(id => ({pageSpread: 'center', load: async () => id}))
    renderer.open({dir, rendition: {viewport: {width: 900, height: 600}}, sections})
    renderer.spread = spread
    for (const [index, section] of sections.entries()) {
      assert.equal(renderer.getSpreadOf(section)?.index, index, 'Every centered page owns a spread')
      await renderer.goTo({index})
      assert.equal(renderer.index, index)
    }
  }
  renderer.destroy()
  console.log(JSON.stringify({status: 'passed', scope: 'actual fixed-layout renderer with controlled DOM: consecutive centered spreads, single/spread presentation, reading direction, same-spread identity, zoom target, anchor selection, scrolling and active-page focus; no native rendering acceptance'}))
} finally {
  for (const [name, descriptor] of previous) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor)
    else delete globalThis[name]
  }
}
