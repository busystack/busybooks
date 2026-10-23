import assert from 'node:assert/strict'
import vm from 'node:vm'
import fs from 'node:fs/promises'
import * as typography from '../assets/reader/typography.mjs'
import {webcrypto} from 'node:crypto'
globalThis.crypto??=webcrypto
for(const name of ['Noto Serif','A "quote", \\ family','字体 العربية','📖 Reading','A; } body { color: red']){
  assert(typography.validFamily(name));const quoted=typography.cssString(name)
  assert(quoted.startsWith('"')&&quoted.endsWith('"'))
  assert.equal(typography.fontChoice({family:name}).family,name)
}
for(const name of ['', ' x', 'x\n', 'x\u0085', '\ud800', 'a'.repeat(257)])assert(!typography.validFamily(name))
assert.deepEqual(typography.fontChoice('serif'),{generic:'serif'})
assert.deepEqual(typography.fontChoice({family:'serif'}),{family:'serif'})
const resolution={family:'Face "名", \\!',faces:[{sources:['Face "名", \\!'],weight:400,italic:false},{sources:['Face "名", \\!'],weight:400,italic:false},{sources:['Face "名", \\!'],weight:400,italic:false},{sources:['Face "名", \\!'],weight:400,italic:false}]}
const chosen=typography.createLocalFont(resolution)
assert.equal(chosen.faces.length,1,'a missing emphasis face is not mislabeled as a real bold/italic face')
assert(chosen.faces[0].source.includes('local("Face \\"名\\", \\\\!")'))
assert.notEqual(typography.createLocalFont(resolution).family,chosen.family,'aliases are publication-independent')
{
 const weighted=typography.createLocalFont({family:'Weights',faces:[300,380,400,500,600,700,900].map(weight=>({sources:['Face'+weight],weight,italic:false}))})
 assert.deepEqual(weighted.faces.map(f=>f.descriptors.weight),['300','380','400','500','600','700','900'])
 for(const weight of [0,1001,400.5])assert.throws(()=>typography.localSources({sources:['Face'],weight,italic:false}))
 const original=globalThis.FontFace,gate=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}},pending=gate()
 globalThis.FontFace=class{constructor(name,source){this.family=name;this.source=source}load(){return this.source.includes('Later')?pending.promise:Promise.resolve(this)}}
 try{
  const doc={fonts:new Set()},make=name=>typography.createLocalFont({family:name,faces:[{sources:[name],weight:400,italic:false}]}),a=make('Current'),b=make('Later')
  await typography.installLocalFont(doc,a)
  const before=[...doc.fonts];let current=true
  const loading=typography.installLocalFont(doc,b,()=>current)
  await Promise.resolve();assert.deepEqual([...doc.fonts],before,'preparing a candidate keeps the visible faces')
  current=false;pending.resolve();assert.equal(await loading,false);assert.deepEqual([...doc.fonts],before,'late cancelled loads cannot replace active faces')
 }finally{globalThis.FontFace=original}
}
assert.equal(typography.typographyCSS({publisher:true},chosen.family),'')
const css=typography.typographyCSS({publisher:false,size:20},chosen.family)
assert(!css.includes('*{'));assert(css.includes('code'));assert(css.includes('h1'));assert(!css.includes('h1{font-size'))
for(const capabilities of [{fontFamily:true,textMetrics:false},{fontFamily:false,textMetrics:true},typography.noTypography]){
  const styles=typography.typographyCSS({publisher:false,size:20},chosen.family,'',capabilities)
  assert.equal(styles.includes('font-family:'),capabilities.fontFamily)
  assert.equal(styles.includes('font-size:'),capabilities.textMetrics)
  if(!capabilities.fontFamily)assert.throws(()=>typography.validateTypographyUpdate({font:{family:'X'}},capabilities))
  if(!capabilities.textMetrics)assert.throws(()=>typography.validateTypographyUpdate({size:24},capabilities))
}
{
  const work=new typography.TypographyWork(),a=work.begin({cfi:'passage'}),b=work.begin({cfi:'transient'})
  assert(!work.current(a));assert.equal(b.anchor.cfi,'passage');work.navigate();assert(!work.canRestore(b));work.finish(a);assert(work.current(b));work.finish(b);assert.equal(work.active,null)
}
const source=(await fs.readFile(new URL('../assets/reader/reader.js',import.meta.url),'utf8')).replace(/^import .*\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
function adapter(){
 const events=[],content={addEventListener(){},style:{setProperty(){}},clientWidth:900}
 const context=vm.createContext({...typography,URL,Uint8Array,console,setTimeout,clearTimeout,requestAnimationFrame:f=>f(),
  pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},
  document:{querySelector:()=>content,querySelectorAll:()=>[],addEventListener(){},body:{style:{setProperty(){}}}},
  window:{location:{href:'https://busybooks.local/?session=typography'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}}})
 vm.runInContext(source,context);return {context,events}
}
{
 const {context,events}=adapter()
 await vm.runInContext("dispatch({action:'appearance',request:1,value:{font:{family:'X'},publisher:false}})",context)
 assert(events.some(e=>e.type==='appearanceResult'&&e.message),'an unavailable renderer rejects replacement')
}
{
 const {context,events}=adapter()
 vm.runInContext("location={anchor:{cfi:'saved'},progress:.4};pinnedTypographyLocation={view,anchor:location.anchor,progress:.4};reportEpubLocation({anchor:{cfi:'transient'},progress:1});userNavigation();reportEpubLocation({anchor:{cfi:'user-next'},progress:.6})",context)
 const positions=events.filter(e=>e.type==='location')
 assert.equal(positions[0].anchor.cfi,'saved');assert.equal(positions[0].progress,.4);assert.equal(positions[1].anchor.cfi,'user-next')
}
console.log(JSON.stringify({status:'passed',scope:'Typography data/CSS escaping, generic identity, missing faces, request ownership, unsupported readers and durable locations; native glyph rendering verified separately'}))
