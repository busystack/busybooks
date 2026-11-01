// Execute the actual publication adapter. Controlled APIs establish hierarchy,
// destination/transport and preview scheduling contracts, not native rendering.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import { readerContents } from '../assets/reader/fixed_layout_integration.mjs'
import * as typographyUtilities from '../assets/reader/typography.mjs'
import { TOCProgress } from '../assets/reader/vendor/foliate/progress.js'
import { validPage } from '../assets/reader/reading_geometry.mjs'
const source=(await fs.readFile(process.env.BUSYBOOKS_READER_SOURCE??new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
  .replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
const normalize=value=>JSON.parse(JSON.stringify(value))
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}
function adapter(extra={}) {
  const events=[],content={addEventListener(){},setAttribute(){},removeAttribute(){},style:{}}
  const context=vm.createContext({readerContents,...typographyUtilities,AbortController,URL,Uint8Array,console,validPage,setTimeout,clearTimeout,requestAnimationFrame:f=>f(),
    pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},
    document:{querySelector:()=>content,querySelectorAll:()=>[],addEventListener(){},getSelection:()=>null,body:{style:{setProperty(){}}}},
    window:{location:{href:'https://busybooks.local/?session=sidebar'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}},...extra})
  vm.runInContext(source,context);return {events,context}
}
function records(events){let rows=[];for(const e of events){if(e.type!=='metadata')continue
  if(e.tocOffset===0)rows=[]
  if(e.toc)rows.push(...e.toc)
  for(const patch of e.tocUpdates??[]){const i=rows.findIndex(r=>r.id===patch.id);assert(i>=0);rows[i]={...rows[i],...patch}}
}return rows}
{
  const {context}=adapter()
  context.items=[{label:'Contents',subitems:[{label:'Repeated',href:'a.xhtml#one'},{label:'Repeated',subitems:[{label:'Deep',href:'a.xhtml#two'}]}]},{label:'End',href:'b.xhtml'}]
  const nodes=normalize(vm.runInContext('flatten(items)',context))
  assert.deepEqual(nodes.map(n=>[n.id,n.label,n.depth]),[['outline:0','Contents',0],['outline:1','Repeated',1],['outline:2','Repeated',1],['outline:3','Deep',2],['outline:4','End',0]])
  assert.equal(nodes[0].href,'');assert.equal(nodes[3].href,'a.xhtml#two')
  assert.equal(new Set(nodes.map(n=>n.id)).size,nodes.length)
}
{
  const {context,events}=adapter()
  context.entries=Array.from({length:10000},(_,i)=>({id:`outline:${i}`,label:'章\u0001'.repeat(200),href:`text.xhtml#${i}`,depth:0}))
  vm.runInContext('publishOutline(entries,7)',context)
  const chunks=events.filter(e=>e.toc)
  assert(chunks.length>10);assert.equal(chunks.at(-1).tocComplete,true)
  for(const chunk of chunks)assert(Buffer.byteLength(JSON.stringify(chunk),'utf8')<1048576)
  assert.deepEqual(records(events).map(n=>n.id),context.entries.map(n=>n.id))
}
{
  const gate=deferred(),{context,events}=adapter();let active=0,maximum=0
  const page={view:[0,0,600,800],getViewport:()=>({height:800,convertToViewportPoint:(x,y)=>[x,800-y]})}
  context.publication={numPages:3,getPageLabels:async()=>['i','67','68'],getMetadata:async()=>({info:{}}),getPage:async()=>page,
    getOutline:async()=>[{title:'Front matter',items:[{title:'Repeated',dest:'first'},{title:'Broken',dest:'bad'},{title:'Repeated',dest:'second'}]}],
    getDestination:async name=>{maximum=Math.max(maximum,++active);try{if(name==='first')await gate.promise
      return name==='bad'?null:[{num:4},{name:'XYZ'},20,name==='first'?700:300]
    }finally{active--}},getPageIndex:async()=>1}
  const opening=vm.runInContext('pdf=publication;pages=[{},{},{}];enrichPdf({pages:3,labels:[],fixed:true},false)',context)
  // Wait on a deterministic destination gate, not an elapsed render assumption.
  for(let i=0;i<30&&!events.some(e=>e.tocComplete);i++)await Promise.resolve()
  assert(events.some(e=>e.tocComplete),'hierarchy is published before a slow named destination')
  assert.equal(records(events)[0].anchor,undefined)
  gate.resolve();await opening
  const rows=records(events)
  assert.equal(rows.length,4);assert.equal(rows[0].href,'');assert.equal(rows[2].anchor,undefined)
  assert.deepEqual(rows[1].anchor,{page:1,point:[20,700]});assert.deepEqual(rows[3].anchor,{page:1,point:[20,300]})
  assert(maximum<=2);assert.equal(events.some(e=>e.type==='error'),false)
  context.viewport=page.getViewport()
  vm.runInContext('pages[1].viewport=viewport',context)
  assert.equal(vm.runInContext('pdfTocId({page:1,point:[0,600]})',context),'outline:1')
  assert.equal(vm.runInContext('pdfTocId({page:1,point:[0,250]})',context),'outline:3')
  vm.runInContext('pdfToc=[pdfToc[0],pdfToc[3],pdfToc[2],pdfToc[1]];pages[2].viewport={height:800,convertToViewportPoint:(x,y)=>[y,x]}',context)
  assert.equal(vm.runInContext('pdfTocId({page:2,y:0})',context),'outline:3','a different current-page rotation must not reorder prior-page destinations')
  assert.deepEqual(normalize(await vm.runInContext("destinationAnchor([1,{name:'FitV'},42])",context)),{page:1,point:[42,800]})
  assert.deepEqual(normalize(await vm.runInContext("destinationAnchor([1,{name:'FitR'},10,20,200,500])",context)),{page:1,rect:[10,20,200,500]})
}
{
  let doc
  class Range {
    selectNodeContents(node){this.start=node.start;this.end=node.end;this.startContainer={getRootNode:()=>doc}}
    collapse(start){if(start)this.end=this.start;else this.start=this.end}
    comparePoint(node){return node.start<this.start?-1:node.start>this.end?1:0}
  }
  const nodes={section:{start:10,end:90},page1:{start:0,end:0},page2:{start:50,end:50}}
  doc={createRange:()=>new Range()}
  const progress=new TOCProgress(),pageList=[{label:'iv',href:'a#page1'},{label:'v',href:'a#page2'}]
  await progress.init({toc:pageList,ids:['a'],splitHref:href=>href.split('#'),getFragment:(_,id)=>nodes[id]})
  const {context,events}=adapter({Range})
  context.book={toc:[{label:'Long section',href:'a#section'}],pageList,sections:[{createDocument:async()=>doc}]}
  context.publication={book:context.book,resolveNavigation:async()=>({index:0,anchor:()=>nodes.section}),getProgressOf:(i,range)=>({pageItem:progress.getProgress(i,range)})}
  await vm.runInContext("view=publication;enrichEpubOutline(book,'sidebar')",context)
  assert.equal(records(events)[0].pageLabel,'iv','the destination begins on iv even when its section contains v')
}
for(const pageList of [[],[{label:'iv',href:'a.xhtml#page'}]]) {
  class Range {selectNodeContents(node){this.node=node}collapse(start){assert.equal(start,true);this.collapsed=true}}
  const {context,events}=adapter({Range});let loaded=0
  context.book={toc:[{label:'Contents',href:'a.xhtml#one',subitems:[{label:'Repeated',href:'a.xhtml#two'}]}],pageList,
    sections:[{createDocument:async()=>{loaded++;return {createRange:()=>new Range()}}}]}
  context.publication={book:context.book,resolveNavigation:async href=>({index:0,anchor:()=>({href})}),
    getProgressOf:(_,range)=>{assert(range.collapsed);return {pageItem:{label:'iv'}}}}
  await vm.runInContext("view=publication;enrichEpubOutline(book,'sidebar')",context)
  const rows=records(events)
  assert.equal(rows[0].label,'Contents');assert.equal(rows[1].href,'a.xhtml#two')
  assert.equal(rows[1].pageLabel,pageList.length?'iv':undefined)
  assert.equal(loaded,pageList.length?1:0,'no fabricated spine pagination or unnecessary documents')
}
{
  const jobs=[],canvases=[],{context,events}=adapter()
  context.document.createElement=()=>{const canvas={width:0,height:0,getContext:()=>({}),toDataURL:()=> 'data:image/png;base64,AA=='};canvases.push(canvas);return canvas}
  context.publication={numPages:200,getTextContent(){throw Error('Scanned PDF has no text layer')},getPage:async page=>({
    getViewport:({scale})=>({width:(page%2?600:800)*scale,height:(page%2?800:600)*scale}),
    render:({viewport})=>{const pending=deferred(),job={page,viewport,pending};jobs.push(job)
      return {promise:pending.promise,cancel:()=>pending.reject(Object.assign(Error('cancelled'),{name:'RenderingCancelledException'}))}}
  })}
  await vm.runInContext("pdf=publication;dispatch({action:'thumbnailWindow',session:'sidebar',pages:[0,1,2,3,4],request:1})",context)
  await Promise.resolve();assert.equal(jobs.length,2,'at most two preview render tasks')
  await vm.runInContext("dispatch({action:'thumbnailWindow',session:'sidebar',pages:[50,51,52],request:2})",context)
  for(let i=0;i<20&&jobs.length<4;i++)await Promise.resolve()
  assert.equal(jobs.length,4);assert.equal(jobs[2].viewport.width/jobs[2].viewport.height,.75);assert.equal(jobs[3].viewport.width/jobs[3].viewport.height,4/3);assert.equal(events.some(e=>e.type==='thumbnail'),false)
  jobs[2].pending.resolve();jobs[3].pending.reject(Error('injected page render failure'))
  for(let i=0;i<20&&jobs.length<5;i++)await Promise.resolve()
  jobs[4].pending.resolve()
  for(let i=0;i<20;i++)await Promise.resolve()
  assert.deepEqual(events.filter(e=>e.type==='thumbnail').map(e=>e.page),[50,52])
  assert.equal(events.find(e=>e.type==='thumbnailError').page,51)
  assert(events.filter(e=>e.type==='thumbnail').every(e=>e.request===2&&e.width<=240&&e.height<=320))
  const before=jobs.length
  await vm.runInContext("dispatch({action:'thumbnail',session:'sidebar',page:51,request:2});dispatch({action:'thumbnail',session:'sidebar',page:51,request:2})",context)
  for(let i=0;i<10&&jobs.length===before;i++)await Promise.resolve()
  assert.equal(jobs.length,before+1,'retry is explicit and deduplicated')
  vm.runInContext('pdf={numPages:1}',context)
  jobs.at(-1).pending.resolve();for(let i=0;i<10;i++)await Promise.resolve()
  assert.equal(events.filter(e=>e.type==='thumbnail'&&e.page===51).length,0,'old publication work cannot reach its replacement')
  assert(canvases.every(c=>c.width===0&&c.height===0),'owned preview canvases release pixel storage')
}
{
  const callbacks=new Map();let serial=0
  const slow=deferred(),{context,events}=adapter({setTimeout:(f,ms)=>{assert.equal(ms,20000);callbacks.set(++serial,f);return serial},clearTimeout:id=>callbacks.delete(id)})
  const page={getViewport:({scale})=>({width:600*scale,height:800*scale}),render:()=>({promise:Promise.resolve(),cancel(){}})}
  context.document.createElement=()=>({width:0,height:0,getContext:()=>({}),toDataURL:()=> 'data:image/png;base64,AA=='})
  context.publication={numPages:2,getPage:async n=>n===1?slow.promise:page}
  await vm.runInContext("pdf=publication;dispatch({action:'thumbnailWindow',session:'sidebar',pages:[0],request:9})",context)
  for(let i=0;i<10;i++)await Promise.resolve()
  assert.equal(callbacks.size,1,'a stalled preview has a bounded failure result')
  callbacks.values().next().value()
  for(let i=0;i<20;i++)await Promise.resolve()
  assert.equal(events.find(e=>e.type==='thumbnailError').page,0)
  await vm.runInContext("dispatch({action:'thumbnailWindow',session:'sidebar',pages:[1],request:10})",context)
  for(let i=0;i<20;i++)await Promise.resolve()
  slow.resolve(page);for(let i=0;i<20;i++)await Promise.resolve()
  assert.equal(events.filter(e=>e.type==='thumbnail'&&e.request===9).length,0)
  assert.equal(events.filter(e=>e.type==='thumbnail'&&e.request===10).length,1)
  assert.equal(callbacks.size,0)
}
console.log(JSON.stringify({status:'passed',scope:'Actual adapter outline hierarchy/chunks, named PDF/EPUB destinations, publisher references and bounded/cancelled/scanned-PDF previews; controlled APIs, no native rendering acceptance'}))
