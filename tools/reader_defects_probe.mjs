// Execute the real adapter with controlled APIs. These are range/async-contract
// regressions; they do not substitute for WebKit/WebView2 acceptance.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import { readerContents } from '../assets/reader/fixed_layout_integration.mjs'
import * as typographyUtilities from '../assets/reader/typography.mjs'
import * as searchUtilities from '../assets/reader/literal_search.mjs'
import { fitScale, validPage } from '../assets/reader/reading_geometry.mjs'
const source=(await fs.readFile(process.env.BUSYBOOKS_READER_SOURCE??new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
  .replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
function adapter(options={}){
  const events=[],resizeObservers=[]
  const content={addEventListener(){},setAttribute(){},removeAttribute(){},style:{}}
  const context=vm.createContext({readerContents,...typographyUtilities,...searchUtilities,AbortController,URL,console,Uint8Array,structuredClone,setTimeout:options.setTimeout??setTimeout,clearTimeout,validPage,fitScale,requestAnimationFrame:options.requestAnimationFrame??(f=>f()),
    pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{constructor(callback){resizeObservers.push(callback)}observe(){}},
    document:{querySelectorAll:()=>[],querySelector:()=>content,addEventListener(){},getSelection:()=>null,body:{style:{setProperty(){}}}},
    window:{location:{href:'https://busybooks.local/?session=test'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}}})
  vm.runInContext(source,context)
  return {context,events,content,resizeObservers}
}
for(const [items,query,expected] of [
  [[{str:'İABC'}],'ABC',[[1,3]]],
  [[{str:'İABC İABC'}],'ABC',[[1,3],[6,3]]],
  [[{str:'aİ'},{str:'BC'}],'İBC',[[1,3]]],
  [[{str:'e\u0301ABC'}],'ABC',[[2,3]]],
  [[{str:'e\u0301ABC'}],'\u0301A',[[1,2]]],
  [[{str:'I\u0301ABC'}],'ABC',[[2,3]]],
  [[{str:'ab',hasEOL:true},{str:'cd'}],'b c',[[1,2]]],
  [[{str:'ABC abc'}],'abc',[[0,3],[4,3]]],
]){
  const {context,events}=adapter()
  context.items=items;context.query=query
  await vm.runInContext('pdf={numPages:1,getPage:async()=>({getTextContent:async()=>({items})})}; search(query,1,generation)',context)
  const matches=events.filter(e=>e.type==='matches').flatMap(e=>e.items)
  assert.deepEqual(matches.map(m=>[m.anchor.textOffset,m.anchor.textLength]),expected)
  for(const m of matches)assert(!m.excerpt.includes('undefined'))
}
{
  const {context,events}=adapter()
  vm.runInContext('layoutGeneration=1;pages=[{epoch:1,element:{childNodes:[]}}];renderPage=async()=>{throw Error("injected first page failure")}',context)
  await assert.rejects(vm.runInContext('queuePage(0,1)',context),/injected first page failure/)
  vm.runInContext('renderPage=async()=>{}',context)
  assert.equal(await vm.runInContext('queuePage(0,1)',context),true,'a failed page can be retried')
  assert.equal(events.some(e=>e.type==='opened'),false)
}
for(const obsolete of [false,true]){
  const {context}=adapter()
  vm.runInContext(`layoutGeneration=1;pages=[{epoch:1,element:{childNodes:[]}}];renderPage=async()=>{${obsolete?'layoutGeneration=2;':''}throw Object.assign(Error('cancelled'),{name:'RenderingCancelledException'})}`,context)
  assert.equal(await vm.runInContext('queuePage(0,1)',context),false)
}
for(const outcome of ['failure','cancelled','success']){
  const {context,events}=adapter()
  vm.runInContext(`theme=()=>{};openPdf=async()=>{${outcome==='failure'?"throw Error('injected first page failure')":outcome==='cancelled'?'return false':'return true'}}`,context)
  await vm.runInContext("dispatch({action:'open',format:'pdf'})",context)
  assert.equal(events.some(e=>e.type==='opened'),outcome==='success')
  assert.equal(events.some(e=>e.type==='error'),outcome==='failure')
}
for(const outcome of ['success','failure','cancelled','stale']){
  const {context,events}=adapter()
  vm.runInContext(`remember=()=>{};pdf={numPages:3};gotoPdf=async()=>{${outcome==='failure'?"throw Error('injected Go To failure')":outcome==='cancelled'?'return false':'return true'}}`,context)
  await vm.runInContext(`dispatch({action:'goto',session:'${outcome==='stale'?'obsolete':'test'}',request:17,anchor:{page:2}})`,context)
  const replies=events.filter(e=>e.type==='navigationResult')
  assert.equal(replies.length,outcome==='stale'?0:1)
  if(replies.length){assert.equal(replies[0].request,17);assert.equal('message' in replies[0],outcome!=='success')}
}
for(const success of [true,false]){
  const {context,events}=adapter()
  vm.runInContext(`remember=()=>{};view={goTo:async()=>${success?'({index:1})':'undefined'}}`,context)
  await vm.runInContext("dispatch({action:'goto',session:'test',request:23,anchor:{fraction:.75}})",context)
  const reply=events.find(e=>e.type==='navigationResult')
  assert.equal(reply.request,23);assert.equal('message' in reply,!success)
}
for(const outcome of ['failure','cancelled']){
  const {context,events}=adapter()
  vm.runInContext(`pdf={numPages:2};layoutGeneration=1;pages=[{element:{hidden:false}},{element:{hidden:true}}];queuePage=async()=>{${outcome==='failure'?"throw Error('destination render failure')":'return false'}}`,context)
  if(outcome==='failure')await assert.rejects(vm.runInContext('gotoPdf({page:1})',context),/destination render failure/)
  else assert.equal(await vm.runInContext('gotoPdf({page:1})',context),false)
  assert.equal(vm.runInContext('pages[0].element.hidden',context),false)
  assert.equal(vm.runInContext('pages[1].element.hidden',context),true)
  assert.equal(events.some(e=>e.type==='location'),false)
}
for(const format of ['epub','fb2']){
  const {context,events}=adapter(),cfi='epubcfi(/6/2!/4/2/1:0)'
  const range={startContainer:{nodeType:1,parentElement:null,getAttribute:()=>null,getAttributeNS:()=>null}}
  const sectionDocument={getSelection:()=>({rangeCount:1,isCollapsed:false,getRangeAt:()=>range,toString:()=>'A durable passage'})}
  Object.assign(context,{format,range,cfi,performance:{now:()=>0},clearTimeout,Node:{ELEMENT_NODE:1},DOMParser:class{parseFromString(){return sectionDocument}},XMLSerializer:class{serializeToString(){return ''}},
    publication:{book:{sections:[{identity:'body:0/part:0',createDocument:async()=>sectionDocument}]},renderer:{getContents:()=>[{index:0,doc:sectionDocument}]},
      // The visible range already matches: no browser selectionchange is sent.
      select:async()=>{},getProgressOf:()=>({}),getCFI:()=>cfi}})
  vm.runInContext('activeFormat=format;selection=null;view=publication;safeDocument=x=>x;epubNavigation=()=>({index:0,anchor:()=>range});selectionRect=()=>({x:0,y:0,width:1,height:1})',context)
  await vm.runInContext('gotoEpub({cfi,index:0});',context)
  vm.runInContext('emitPassage(99)',context)
  const selected=events.find(e=>e.type==='selection'),passage=events.find(e=>e.type==='passage')
  assert.equal(selected.text,'A durable passage');assert.equal(passage.text,selected.text)
  assert.equal(passage.anchor.cfi,cfi);assert.equal(passage.selected,true)
  assert.equal(events.some(e=>e.settled),false,'programmatic return does not open a selection popover')
  if(format==='fb2'){assert.equal(passage.anchor.kind,'fb2');assert.equal(passage.anchor.section,'body:0/part:0')}
}
// A hidden native view may stop display frames. Exercise the actual adapter's
// pause/drain/resume queue with fresh application-owned controlled objects.
{
  const {context,events,content,resizeObservers}=adapter()
  Object.assign(content,{clientWidth:700,clientHeight:600,scrollTop:120,scrollLeft:0})
  let release,started=0
  context.renderGate=new Promise(resolve=>{release=resolve})
  context.layoutStarted=()=>{started++}
  vm.runInContext(`activeFormat='pdf';pdf={numPages:1};pdfViewport=[900,600];location={anchor:{page:0,point:[4,120]},reference:'Page 1'};
    pages=[{element:{offsetTop:0,offsetLeft:0,offsetHeight:600},viewport:{convertToPdfPoint:(x,y)=>[x,y]}}];
    relayoutPdf=async()=>{layoutStarted();await renderGate;pdfViewport=[content.clientWidth,content.clientHeight]};
    refreshSelectionGeometry=()=>{};scheduleSelectionGeometry=()=>{};
    queueNavigation(()=>renderGate);schedulePdfResize()`,context)
  // Let the resize timer join the already busy navigation queue.
  await new Promise(resolve=>setTimeout(resolve,170))
  const pause=vm.runInContext("dispatch({action:'layoutVisibility',session:'test',visible:false,revision:1,request:31})",context)
  assert.equal(vm.runInContext('pdfLayoutPaused',context),true)
  assert.equal(events.some(e=>e.type==='layoutVisibility'),false,'pause waits for the existing visible work')
  content.clientWidth=500;content.clientHeight=0
  resizeObservers[0]()
  release();await pause
  assert.equal(started,0,'a resize already queued before pause must revalidate before rendering')
  assert.equal(events.find(e=>e.type==='layoutVisibility').request,31)
  const retained=JSON.stringify(vm.runInContext('location.anchor',context))
  await vm.runInContext("dispatch({action:'flush',session:'test',request:32})",context)
  assert.equal(events.find(e=>e.type==='flushed').request,32,'hidden export can drain without a display frame')
  assert.equal(JSON.stringify(events.find(e=>e.type==='location').anchor),retained,'hidden geometry cannot replace a settled PDF source')
  await new Promise(resolve=>setTimeout(resolve,170))
  assert.equal(started,0)
  content.clientHeight=600
  await vm.runInContext("dispatch({action:'layoutVisibility',session:'test',visible:true,revision:2,request:33})",context)
  await new Promise(resolve=>setTimeout(resolve,170))
  assert.equal(started,1,'resume coalesces the pending sizes into one visible layout')
  await vm.runInContext("dispatch({action:'layoutVisibility',session:'test',visible:false,revision:1,request:34})",context)
  assert.equal(vm.runInContext('pdfLayoutPaused',context),false,'an obsolete hide cannot pause the newer visible owner')
}
{
  const {context,events}=adapter({requestAnimationFrame:()=>{}})
  context.items=[{str:'hidden library'}]
  const work=vm.runInContext("pdf={numPages:2,getPage:async()=>({getTextContent:async()=>({items})})};search('library',1,generation)",context)
  let timer
  try{
    await Promise.race([work,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Search waited for a hidden display frame')),300)})])
  }finally{clearTimeout(timer)}
  assert.equal(events.find(e=>e.type==='searchDone').total,2)
}
for(const cancel of ['stop','expiry']){
  const {context,events}=adapter({setTimeout:(callback,delay)=>setTimeout(callback,delay===10000?5:delay)})
  let navigated=0
  context.navigated=()=>{navigated++}
  vm.runInContext("pdf={numPages:2};activeFormat='pdf';pdfLayoutPaused=true;location={anchor:{page:0}};gotoPdf=async()=>navigated();paintSpeaking=async()=>{}",context)
  const passage=vm.runInContext("dispatch({action:'advanceSpeech',session:'test',request:41})",context)
  if(cancel==='stop')await vm.runInContext("dispatch({action:'speaking',session:'test',anchor:null})",context)
  await passage
  assert.equal(events.find(e=>e.type==='passage').request,41)
  assert.equal(typeof events.find(e=>e.type==='passage').message,'string')
  vm.runInContext('pdfResizePending=false;pdfViewport=[content.clientWidth,content.clientHeight]',context)
  await vm.runInContext("dispatch({action:'layoutVisibility',session:'test',visible:true,revision:2,request:42})",context)
  assert.equal(navigated,0,`${cancel} cannot revive a background passage jump on reveal`)
}
// Only owned DOM/page interfaces are supplied. The actual renderPage link
// callback, layoutPdf finally block and selection bridge remain under test.
function pdfGeometryFixture(options={}){
  const fixture=adapter(options),{context,content}=fixture,created=[]
  const node=tag=>({tagName:tag.toUpperCase(),childNodes:[],style:{setProperty(){}},dataset:{},handlers:new Map(),
    offsetTop:0,offsetLeft:0,offsetHeight:600,hidden:false,
    append(child){this.childNodes.push(child)},setAttribute(){},querySelectorAll:()=>[],
    querySelector(name){return this.childNodes.find(child=>name==='.textLayer'?child.className==='textLayer':child.tagName===name.toUpperCase())},
    addEventListener(name,callback){this.handlers.set(name,callback)}})
  const native={rangeCount:1,isCollapsed:false,removeAllRanges(){this.rangeCount=0;this.isCollapsed=true}}
  context.document.getSelection=()=>native
  context.document.createElement=tag=>{const value=node(tag);if(tag==='canvas')value.getContext=()=>({});created.push(value);return value}
  context.IntersectionObserver=class{observe(){}disconnect(){}}
  context.performance={now:()=>0}
  Object.assign(content,{clientWidth:800,clientHeight:600,scrollLeft:0,scrollTop:0,
    append(){},replaceChildren(){native.removeAllRanges();vm.runInContext('pdfSelection()',context)}})
  const memory={hasSelection:true,ownsPending:false,pinnedPages:new Set(),pending:null,invalidations:0,
    expectedSelection:()=>true,
    invalidate(){this.invalidations++;this.hasSelection=false;this.ownsPending=false;this.pending=null;this.pinnedPages.clear()},
    beginRelayout(){const work={};this.pending=work;this.ownsPending=true;this.pinnedPages=new Set([0]);return work},
    abandon(work){if(!work||this.pending!==work)return false;this.hasSelection=false;this.ownsPending=false;this.pending=null;this.pinnedPages.clear();return true}}
  const viewport={width:600,height:800,convertToPdfPoint:(x,y)=>[x,y],convertToViewportRectangle:value=>value}
  const page={pageNumber:1,rotate:0,ref:{num:10,gen:0},getViewport:()=>viewport,
    render:()=>({promise:Promise.resolve(),cancel(){}}),getTextContent:async()=>({items:[{str:'original passage'}]}),
    getAnnotations:async()=>[{subtype:'Link',rect:[1,2,3,4],dest:'chapter-two'}]}
  context.fixtureMemory=memory;context.fixturePage=page;context.fixtureElement=node('section')
  context.fixtureSelection={text:'original passage',anchor:{page:0,segments:[{page:0,start:0,length:16,boxes:[[1,2,3,4]]}]}}
  context.pdfjs.TextLayer=class{async render(){}cancel(){}}
  vm.runInContext(`activeFormat='pdf';pdf={numPages:2,getPage:async()=>fixturePage};pdfSelectionOwner={publication:pdf,session};
    pdfSelections=fixtureMemory;selection=fixtureSelection;location={anchor:{page:0,y:0}};
    layoutGeneration=1;pages=[{epoch:1,element:fixtureElement}];pdfViewport=[900,600]`,context)
  return {...fixture,created,native,memory,page}
}
{
  const {context,events,created,native,memory}=pdfGeometryFixture()
  await vm.runInContext('renderPage(0,1)',context)
  const link=created.find(node=>node.className==='pdf-link')
  assert(link,'the actual PDF page builds its internal destination link')
  let release,navigated=0
  context.navigationGate=new Promise(resolve=>{release=resolve})
  context.didNavigate=()=>{navigated++}
  vm.runInContext(`navigationTail=navigationGate;destinationAnchor=async()=>({page:1});
    gotoPdf=async anchor=>{didNavigate();location={anchor}}`,context)
  events.length=0
  // Keyboard/assistive activation emits click without any pointerdown event.
  const following=link.handlers.get('click')({detail:0,preventDefault(){}})
  assert.equal(memory.invalidations,1,'link acceptance invalidates logical selection before waiting for navigation')
  assert.equal(native.rangeCount,0,'link acceptance removes the old connected native range')
  assert.equal(vm.runInContext('selection',context),null)
  assert(events.some(event=>event.type==='selection'&&event.anchor===null),'the primary receives the immediate selection clear')
  assert.equal(navigated,0,'destination navigation remains queued')
  release();await following
  assert.equal(navigated,1);assert.equal(vm.runInContext('location.anchor.page',context),1)
  assert.deepEqual(JSON.parse(vm.runInContext('JSON.stringify(history)',context)),[{page:0,y:0},{page:1}],'link navigation retains the exact source and destination history')
  assert.equal(events.some(event=>event.type==='navigationError'),false)
}
{
  const {context,events,memory}=pdfGeometryFixture(),failure=Error('original geometry render failure')
  context.geometryFailure=failure
  vm.runInContext('queuePage=async()=>{throw geometryFailure}',context)
  const resizing=vm.runInContext('layoutPdf(location.anchor,true)',context)
  assert.equal(vm.runInContext('selection===fixtureSelection',context),true,'rebuild collapse is initially protected')
  await assert.rejects(resizing,error=>error===failure,'geometry reports the original rendering failure')
  assert.equal(memory.ownsPending,false);assert.equal(memory.pinnedPages.size,0)
  assert.equal(vm.runInContext('selection',context),null,'failed current geometry clears the stale app selection')
  assert(events.some(event=>event.type==='selection'&&event.anchor===null),'failed geometry clears the primary selection bridge')
}
{
  const {context,events,memory}=pdfGeometryFixture()
  let rejectOld,rejectNew
  context.oldPage=new Promise((_,reject)=>{rejectOld=reject})
  context.newRender=new Promise((_,reject)=>{rejectNew=reject})
  vm.runInContext(`let pageRequests=0;pdf.getPage=()=>++pageRequests===1?oldPage:Promise.resolve(fixturePage);
    queuePage=()=>newRender`,context)
  const old=vm.runInContext('layoutPdf(location.anchor,true)',context)
  const oldFailure=Error('obsolete geometry failure'),newFailure=Error('new current geometry failure')
  const oldRejected=assert.rejects(old,error=>error===oldFailure)
  const newer=vm.runInContext('layoutPdf(location.anchor,true)',context)
  const newRejected=assert.rejects(newer,error=>error===newFailure)
  await new Promise(setImmediate)
  context.newSelection={text:'newer selected source',anchor:{page:1,segments:[{page:1}]}}
  vm.runInContext('selection=newSelection',context)
  const pending=memory.pending
  events.length=0
  rejectOld(oldFailure);await oldRejected
  assert.equal(memory.pending,pending,'obsolete finally cannot abandon the newer geometry work')
  assert.equal(memory.ownsPending,true);assert.equal(memory.pinnedPages.has(0),true)
  assert.equal(vm.runInContext('layingOut&&pdfGeometryMayCollapse',context),true,'obsolete finally cannot reset the newer geometry guards')
  assert.equal(vm.runInContext('selection===newSelection',context),true,'obsolete failure cannot clear or refresh a newer selection')
  assert.equal(events.some(event=>event.type==='selection'),false)
  rejectNew(newFailure);await newRejected
}
for(const obsolete of [false,true]){
  let resize,rejectRender
  const {context,events,native,memory}=pdfGeometryFixture({setTimeout:(callback,delay)=>{
    if(delay===150){resize=callback;return {}}
    return setTimeout(callback,delay)
  }})
  context.sameSizeRender=new Promise((_,reject)=>{rejectRender=reject})
  memory.expectedSelection=()=>false
  memory.restore=async(work,{ensurePage})=>{try{await ensurePage(0);return true}finally{memory.abandon(work)}}
  native.removeAllRanges()
  vm.runInContext(`pdfViewport=[content.clientWidth,content.clientHeight];pdfGeometryMayCollapse=true;
    queuePage=()=>sameSizeRender;schedulePdfResize()`,context)
  const resizing=resize()
  await new Promise(setImmediate)
  assert.equal(memory.ownsPending,true,'same-size resume attempts its owned logical restoration')
  if(obsolete){
    vm.runInContext('layoutGeneration++;selection={text:"newer same-size source",anchor:{page:1,segments:[{page:1}]}}',context)
    memory.beginRelayout()
  }
  const current=vm.runInContext('selection',context),pending=memory.pending
  rejectRender(Error('original same-size rendering failure'));await resizing
  assert(events.some(event=>event.type==='navigationError'&&event.message==='Error: original same-size rendering failure'),'same-size failure retains its original renderer diagnostic')
  if(obsolete){
    assert.equal(memory.pending,pending,'obsolete same-size cleanup retains newer work')
    assert.equal(vm.runInContext('selection',context),current)
    assert.equal(vm.runInContext('pdfGeometryMayCollapse',context),true)
    assert.equal(events.some(event=>event.type==='selection'),false)
    memory.invalidate()
  }else{
    assert.equal(memory.ownsPending,false);assert.equal(memory.pinnedPages.size,0)
    assert.equal(vm.runInContext('pdfGeometryMayCollapse',context),false,'failed same-size resume clears its geometry suppression')
    assert.equal(vm.runInContext('selection',context),null,'failed same-size resume clears stale app selection')
    assert(events.some(event=>event.type==='selection'&&event.anchor===null))
  }
}
console.log(JSON.stringify({status:'passed',scope:'Unicode PDF ranges, item boundaries, first-page rejection/cancellation, retry, correlated Go To outcomes and text assistance, hidden-PDF quiescence/source retention/resume, search without display frames, keyboard-link selection invalidation and current/stale geometry failure cleanup; controlled adapter APIs'}))
