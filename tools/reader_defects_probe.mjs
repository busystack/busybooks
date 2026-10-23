// Execute the real adapter with controlled APIs. These are range/async-contract
// regressions; they do not substitute for WebKit/WebView2 acceptance.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import * as typographyUtilities from '../assets/reader/typography.mjs'
import { validPage } from '../assets/reader/reading_geometry.mjs'
const source=(await fs.readFile(process.env.BUSYBOOKS_READER_SOURCE??new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
  .replace(/^import .*\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
function adapter(){
  const events=[]
  const content={addEventListener(){},setAttribute(){},removeAttribute(){},style:{}}
  const context=vm.createContext({...typographyUtilities,AbortController,URL,console,Uint8Array,setTimeout,validPage,requestAnimationFrame:f=>f(),
    pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},
    document:{querySelectorAll:()=>[],querySelector:()=>content,addEventListener(){},getSelection:()=>null,body:{style:{setProperty(){}}}},
    window:{location:{href:'https://busybooks.local/?session=test'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}}})
  vm.runInContext(source,context)
  return {context,events}
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
console.log(JSON.stringify({status:'passed',scope:'Unicode PDF ranges, item boundaries, first-page rejection/cancellation, retry, correlated Go To outcomes and text assistance after returning from notes; controlled adapter APIs'}))
