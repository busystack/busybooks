// Actual adapter/bootstrap orchestration with controlled platform APIs. This
// proves failure propagation and first-page ordering, not native PDF rendering.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import * as typographyUtilities from '../assets/reader/typography.mjs'
import { cssColor } from '../assets/reader/reading_geometry.mjs'

const bootstrap = await fs.readFile(new URL('../assets/reader/bootstrap.js', import.meta.url), 'utf8')
for (const name of ['index.html', 'index_linux.html']) {
  const html = await fs.readFile(new URL('../assets/reader/' + name, import.meta.url), 'utf8')
  assert(html.includes('<script defer src="bootstrap.js"></script>'))
}
assert.equal(bootstrap.split("import('./reader.js')").length, 2)
function boot(platform, loadReader) {
  const events = [], listeners = {}, attributes = {}
  const content = {setAttribute: (key, value) => attributes[key] = value}
  const window = {location: {href: 'https://busybooks.local/index.html?session=123&loading=Loading+book'}, addEventListener: (name, callback) => listeners[name] = callback}
  const postMessage = json => events.push(JSON.parse(json))
  if (platform === 'linux') window.webkit = {messageHandlers: {busybooks: {postMessage}}}
  else window.chrome = {webview: {postMessage}}
  vm.runInNewContext(bootstrap.replace("import('./reader.js')", 'loadReader()'), {window, document: {querySelector: () => content}, URL, loadReader})
  return {events, listeners, content, attributes}
}
const broken = boot('linux', () => Promise.reject(new SyntaxError('Renderer dependency failed')))
await new Promise(setImmediate)
assert.equal(broken.events.length, 1)
assert.deepEqual(broken.events[0], {type: 'error', session: '123', message: 'Renderer dependency failed'})
assert.equal(broken.content.textContent, 'Loading book')
assert.equal(broken.attributes['aria-busy'], 'true')
broken.listeners.error({message: 'duplicate'})
assert.equal(broken.events.length, 1)
const windows = boot('windows', () => Promise.resolve())
windows.listeners.unhandledrejection({reason: new Error('Worker stopped')})
assert.equal(windows.events[0].message, 'Worker stopped')
assert.equal(windows.events[0].session, '123')

const events = [], frames = [], timers = [], firstPages = []
let resolveMetadata, rejectOutline
const metadata = new Promise(resolve => resolveMetadata = resolve)
const outline = new Promise((_, reject) => rejectOutline = reject)
// Attach the test's rejection consumer before scheduling the optional work.
outline.catch(() => {})
const publication = {
  numPages: 322,
  getPageLabels: async () => { throw new Error('Damaged optional labels') },
  getMetadata: () => metadata,
  getOutline: () => outline,
  getPage: async () => { throw Error('Optional cover cannot render') },
}
const content = {addEventListener() {}, setAttribute() {}, removeAttribute() {}, style: {}}
const sandbox = {
  ...typographyUtilities, URL, Uint8Array, console, cssColor,
  pdfjs: {GlobalWorkerOptions: {}, getDocument: () => ({promise: Promise.resolve(publication)})},
  document: {querySelector: () => content, addEventListener() {}, body: {style: {setProperty() {}}}},
  window: {location: {href: 'https://busybooks.local/index.html?session=123'}, chrome: {webview: {postMessage: json => events.push(JSON.parse(json))}}},
  ResizeObserver: class { observe() {} },
  fetch: async () => ({arrayBuffer: async () => new ArrayBuffer(8)}),
  requestAnimationFrame: callback => frames.push(callback),
  setTimeout: callback => timers.push(callback),
  testFirstPage: anchor => firstPages.push(anchor),
}
const context = vm.createContext(sandbox)
const source = (await fs.readFile(new URL('../assets/reader/reader.js', import.meta.url), 'utf8'))
  .replace(/^import .*\n/gm, '').replaceAll('import.meta.url', "'https://busybooks.local/reader.js'")
vm.runInContext(source, context)
await vm.runInContext("relayoutPdf = async anchor => {testFirstPage(anchor);return true}; openPdf({anchor: {page: 12, y: .25}, generateCover: false})", context)
assert.equal(firstPages.length, 1)
assert.equal(firstPages[0].page, 12)
assert.equal(firstPages[0].y, .25)
assert.equal(events.find(event => event.type === 'metadata').pages, 322)
assert.equal(content.className, 'pdf')
assert.equal(events.some(event => event.type === 'error'), false)
assert.equal(frames.length, 1)
frames.shift()()
const enrich = timers.shift()()
resolveMetadata({info: {Title: 'Deterministic PDF fixture'}})
rejectOutline(new Error('Damaged optional outline'))
await enrich
assert.equal(events.some(event => event.type === 'metadata' && event.title === 'Deterministic PDF fixture'), true)
assert.equal(events.some(event => event.type === 'diagnostic' && event.stage === 'outline'), true)
assert.equal(events.some(event => event.type === 'diagnostic' && event.stage === 'labels'), true)
assert.equal(events.find(event=>event.type==='metadata').labels[0],'1')
assert.equal(events.some(event => event.type === 'error'), false)
await vm.runInContext('enrichPdf({pages: 322, labels: [], fixed: true}, true)', context)
assert.equal(events.some(event => event.type === 'diagnostic' && event.stage === 'cover'), true)
assert.equal(events.some(event => event.type === 'error'), false)
assert.equal(firstPages.length, 1, 'optional metadata must not navigate away from the saved passage')
console.log(JSON.stringify({status: 'passed', scope: 'reader dependency failure, Linux/Windows bridge reporting, localized startup text, first page before optional PDF metadata, optional outline/cover failures; controlled APIs, no native rendering assertion'}))
