import assert from 'node:assert/strict'
import vm from 'node:vm'
import fs from 'node:fs/promises'
import * as typography from '../assets/reader/typography.mjs'
import {webcrypto} from 'node:crypto'
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
const typographySource=(await fs.readFile(new URL('../assets/reader/typography.mjs',import.meta.url),'utf8')).replace(/^export /gm,'')
const source=(await fs.readFile(new URL('../assets/reader/reader.js',import.meta.url),'utf8')).replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
function adapter(options={}){
 const events=[],content={addEventListener(){},style:{setProperty(){}},clientWidth:900}
 const context=vm.createContext({URL,Uint8Array,Uint32Array,crypto:webcrypto,console,setTimeout,clearTimeout,requestAnimationFrame:f=>f(),
  cssColor:()=>"#123456",readerContents:publication=>publication?.renderer.getContents()??[],
  pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},
  document:{querySelector:()=>content,querySelectorAll:()=>[],addEventListener(){},body:{style:{setProperty(){}}}},
  window:{location:{href:'https://busybooks.local/?session=typography'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}},...options})
 vm.runInContext(typographySource,context);vm.runInContext(source,context);return {context,events}
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
// These are newly constructed application-owned interface fixtures in a fresh
// VM. No native FontFace constructor, prototype, or FontFaceSet is replaced.
function deferred(){
 let resolve,reject
 const promise=new Promise((a,b)=>{resolve=a;reject=b})
 return {promise,resolve,reject,entered:Promise.withResolvers()}
}
async function entered(gate){
 let timer
 try{await Promise.race([gate.entered.promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Controlled font stage was not reached')),3000)})])}
 finally{clearTimeout(timer)}
}
function controlledAdapter(){
 const loads=new Map(),ready=[],restorations=[]
 class FixtureFontFace{
  constructor(family,source){this.family=family;this.source=source}
  async load(){
   const gate=[...loads].find(([name])=>this.source.includes(name))?.[1]
   if(gate){gate.entered.resolve();await gate.promise}
   return this
  }
 }
 class FixtureFontSet extends Set{
  get ready(){
   const gate=ready.find(item=>item.accepts())
   if(gate){gate.entered.resolve();return gate.promise}
   return Promise.resolve(this)
  }
 }
 const element=()=>{
  const values=new Map()
  return {style:{setProperty:(key,value,priority='')=>values.set(key,{value,priority}),getPropertyValue:key=>values.get(key)?.value??'',getPropertyPriority:key=>values.get(key)?.priority??'',removeProperty:key=>values.delete(key)},closest:()=>null,getBoundingClientRect:()=>({left:0,right:800,width:800}),querySelectorAll:()=>[]}
 }
 const makeDoc=()=>({body:element(),documentElement:element(),fonts:new FixtureFontSet(),head:{append(){}},getSelection:()=>({rangeCount:0,isCollapsed:true}),querySelectorAll:()=>[],createElement:()=>({disabled:false})})
 const publication=makeDoc(),application=makeDoc(),view={book:{sections:[{},{}]},history:{canGoBack:false,canGoForward:false},style:{setProperty(){}},index:0,
  resolveNavigation:()=>({index:view.index}),goTo(index){view.index=index;return Promise.resolve({index})},
  renderer:{getContents:()=>[{doc:publication,index:view.index}],setAttribute(){},setStyles(){},render(){},goTo:async target=>{restorations.push(target.index);view.index=target.index}}
 }
 const {context,events}=adapter({FontFace:FixtureFontFace,document:{...application,querySelector:()=>({addEventListener(){},style:{setProperty(){}},clientWidth:900}),addEventListener(){}},fakeView:view,CFI:{parse:()=>[[],[]]}})
 vm.runInContext("view=fakeView;typography=reflowableTypography;location={anchor:{cfi:'saved',index:0},progress:.4}",context)
 const run=code=>vm.runInContext(code,context)
 const appearance=(name,request)=>run(`dispatch({action:'appearance',request:${request},value:{publisher:false,font:{family:${JSON.stringify(name)}},resolvedFont:{family:${JSON.stringify(name)},faces:[{sources:[${JSON.stringify(name)}],weight:400,italic:false}]},size:20}})`)
 const family=()=>publication.body.style.getPropertyValue('font-family')
 const holdLoad=name=>{const gate=deferred();loads.set(name,gate);return gate}
 const holdReady=accepts=>{const gate={...deferred(),accepts};ready.push(gate);return gate}
 const releaseReady=gate=>{ready.splice(ready.indexOf(gate),1);gate.resolve()}
 return {context,events,publication,view,restorations,run,appearance,family,holdLoad,holdReady,releaseReady,loads}
}
{
 const f=controlledAdapter();await f.appearance('Current',80)
 const family=f.family(),faces=[...f.publication.fonts],gate=f.holdLoad('Later')
 const change=f.appearance('Later',81);await entered(gate)
 assert.equal(f.family(),family,'loading a candidate leaves the committed family displayed')
 assert.deepEqual([...f.publication.fonts],faces,'preparing a candidate keeps the visible faces')
 await f.run("dispatch({action:'cancelAppearance'})")
 gate.resolve();await change
 assert.equal(f.family(),family,'late cancelled loads cannot replace the committed family')
 assert.deepEqual([...f.publication.fonts],faces,'late cancelled loads cannot replace active faces')
 assert(f.events.some(event=>event.type==='appearanceResult'&&event.request===81&&event.cancelled),'cancelled loads must not report success')
 assert.equal(f.run('prefs.font.family'),'Current','cancelled writes must not replace committed adapter preferences')
 assert.equal(f.run('location.anchor.cfi'),'saved','cancellation retains the logical passage')
 assert.deepEqual([f.view.history.canGoBack,f.view.history.canGoForward],[false,false],'cancellation does not add history')
}
{
 const f=controlledAdapter();await f.appearance('Current',80)
 const family=f.family(),gate=f.holdReady(()=>f.family()!==family)
 const change=f.appearance('Later',84);await entered(gate)
 assert.notEqual(f.family(),family,'the controlled case reaches publication of candidate styles')
 await f.run("dispatch({action:'cancelAppearance'})")
 assert.equal(f.family(),family,'post-style cancellation immediately restores the committed family')
 f.releaseReady(gate);await change
 assert(f.events.some(event=>event.type==='appearanceResult'&&event.request===84&&event.cancelled),'layout-stage cancellation cannot report success')
 assert.equal(f.family(),family,'late layout readiness cannot repaint cancelled styles')
}
{
 const f=controlledAdapter();await f.appearance('Current',80)
 const family=f.family(),gate=f.holdLoad('Later'),change=f.appearance('Later',85)
 await entered(gate)
 f.run("userNavigation();fakeView.goTo(1);reportEpubLocation({anchor:{cfi:'user-next',index:1},progress:.6})")
 f.restorations.length=0
 await f.run("dispatch({action:'cancelAppearance'})")
 gate.resolve();await change
 assert.equal(f.view.index,1,'cancellation cannot undo later user navigation')
 assert.equal(f.run('location.anchor.cfi'),'user-next','rollback belongs to the current logical passage')
 assert(!f.restorations.includes(0),'no cancelled work restores the abandoned source')
 assert.equal(f.family(),family,'the navigated chapter retains the committed family')
}
{
 const f=controlledAdapter();await f.appearance('Current',80)
 const family=f.family(),loading=f.holdLoad('Later'),old=f.appearance('Later',86)
 await entered(loading)
 const rollback=f.holdReady(()=>f.family()===family),cancel=f.run("dispatch({action:'cancelAppearance'})")
 await entered(rollback)
 f.loads.delete('Later')
 await f.appearance('Later',87)
 const newest=f.family()
 assert.notEqual(newest,family,'the accepted newer choice publishes a different family')
 f.releaseReady(rollback);loading.resolve();await Promise.all([old,cancel])
 assert.equal(f.family(),newest,'reverse-order late load and rollback cannot repaint a newer choice')
 assert.equal(f.run('prefs.font.family'),'Later','late rollback cannot replace newer committed preferences')
 assert(f.events.some(event=>event.type==='appearanceResult'&&event.request===86&&event.cancelled),'the superseded old request cannot report success')
 assert(f.events.some(event=>event.type==='appearanceResult'&&event.request===87&&!event.message),'the current request succeeds')
}
console.log(JSON.stringify({status:'passed',scope:'Typography data/CSS, fresh VM owned FontFace/FontFaceSet fixtures for delayed-load, post-style cancellation, navigation and reverse-order rollback ownership; native glyph rendering and observed overlaps verified separately'}))
