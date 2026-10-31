// The upstream CFI parser is usable without DOM. Exercise durable-anchor handling.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs/promises'
import * as CFI from '../assets/reader/vendor/foliate/epubcfi.js'
// Reader files are browser modules. Explicit module parsing also catches syntax
// errors that Node's automatic .js format detection can miss with --check.
for(const file of ['reader.js','bootstrap.js']){
  const source=await fs.readFile(new URL('../assets/reader/'+file,import.meta.url),'utf8')
  const result=spawnSync(process.execPath,['--check','--input-type=module'],{input:source,encoding:'utf8'})
  assert.equal(result.status,0,`${file}: ${result.stderr}`)
}
const anchors=['epubcfi(/6/2!/4/2/1:6)','epubcfi(/6/4[chapter]!/4/6,/1:0,/1:24)']
for(const anchor of anchors){assert.equal(CFI.compare(CFI.parse(anchor),anchor),0)}
assert(CFI.compare(anchors[0],anchors[1])<0)
const html=await import('node:fs/promises').then(fs=>fs.readFile(new URL('../assets/reader/index.html',import.meta.url),'utf8'))
assert(html.includes("default-src 'none'"));assert(html.includes("connect-src busybooks: https://busybooks.local"))
console.log(JSON.stringify({status:'passed',checks:5,scope:'CFI parser and packaged network policy; no rendering acceptance'}))
const {fitScale,validPage,cssColor}=await import('../assets/reader/reading_geometry.mjs')
// Mixed portrait/landscape and rotated pages use their own geometry, including
// spread allocation and fractional-scale viewports. No page margin is cropped.
for(const [width,height,viewportWidth,viewportHeight,spread] of [[600,800,960,720,false],[800,600,960,720,false],[600,800,1440,900,true],[800,600,640.5,811.25,false]]){
  const widthFit=fitScale(width,height,viewportWidth,viewportHeight,'fit-width',spread)
  assert(Math.abs(width*widthFit-(viewportWidth/(spread?2:1)-32))<.00001)
  const pageFit=fitScale(width,height,viewportWidth,viewportHeight,'fit-page',spread)
  assert(width*pageFit<=viewportWidth/(spread?2:1)-32+.00001)
  assert(height*pageFit<=viewportHeight-32+.00001)
}
assert.equal(fitScale(600,800,960,720,'1.5'),2)
assert.equal(fitScale(600,800,960,720,'1'),96/72)
assert(validPage(0,4));assert(validPage(3,4));assert(!validPage(4,4));assert(!validPage(-1,4));assert(!validPage(1.5,4))
assert.equal(cssColor(0xfffafafa),'#fafafaff');assert.equal(cssColor(0x663584e4),'#3584e466')
console.log(JSON.stringify({status:'passed',scope:'mixed-page fit geometry, explicit zoom, PDF page validation and bridge colors; no rendering acceptance',checks:21}))

const {tabTarget}=await import('../assets/reader/reading_geometry.mjs')
const links=['first','middle','last']
assert.equal(tabTarget(links,'body'),'first');assert.equal(tabTarget(links,'first'),'middle')
assert.equal(tabTarget(links,'last'),null);assert.equal(tabTarget(links,'first',true),null)
assert.equal(tabTarget(links,'middle',true),'first');assert.equal(tabTarget([],'body'),null)
console.log(JSON.stringify({status:'passed',checks:6,scope:'content tab sequence and application boundary; no native focus acceptance'}))

await import('./epub_integration_probe.mjs')
await import('./fixed_layout_probe.mjs')
await import('./reader_startup_probe.mjs')

await import('./reader_defects_probe.mjs')
await import('./reader_review_regressions.mjs')

await import('./reader_sidebar_probe.mjs')

await import('./typography_probe.mjs')
await import('./reader_appearance_probe.mjs')
await import('./reader_focus_probe.mjs')
await import('./pdf_selection_probe.mjs')
await import('./comic_interaction_probe.mjs')

await import('./literal_search_probe.mjs')
