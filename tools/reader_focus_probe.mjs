// Fresh, application-owned interfaces around the application adapter. These
// fixtures do not load or replace any browser/engine implementation.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
const source=(await fs.readFile(new URL('../assets/reader/reader.js',import.meta.url),'utf8')).replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
const events=[],frames=[],rootListeners=new Map(),listeners=new Map()
const target={closest:()=>null},content={clientWidth:900,clientHeight:600,style:{setProperty(){}},addEventListener(){},contains:value=>value===target}
let connected=true,selected=true,left=30
const range={get startContainer(){return {isConnected:connected}},getClientRects:()=>[{left,top:40,right:left+70,bottom:60}]}
const selectedText={get rangeCount(){return selected?1:0},get isCollapsed(){return !selected},getRangeAt:()=>range,toString:()=> 'library'}
const doc={addEventListener:(name,listener)=>{const group=listeners.get(name)??[];group.push(listener);listeners.set(name,group)},getSelection:()=>selectedText,defaultView:{frameElement:{clientWidth:800,clientHeight:600,getBoundingClientRect:()=>({left:10,top:20,width:800,height:600})}}}
const publication={parts:[{doc,index:0}]}
const document={querySelector:name=>name==='#content'?content:null,querySelectorAll:()=>[],addEventListener:(name,listener)=>rootListeners.set(name,listener),body:{style:{setProperty(){}}},getSelection:()=>({rangeCount:0,isCollapsed:true})}
const context=vm.createContext({URL,console,setTimeout,clearTimeout,performance:{now:()=>0},
 requestAnimationFrame:callback=>frames.push(callback),ResizeObserver:class{observe(){}},
 document,window:{location:{href:'https://busybooks.local/?session=focus-probe'},chrome:{webview:{postMessage:text=>events.push(JSON.parse(text))}}},
 pdfjs:{GlobalWorkerOptions:{}},noTypography:{fontFamily:false,textMetrics:false},TypographyWork:class{},
 readerContents:value=>value?.parts??[],fixtureDoc:doc,fixtureView:publication})
vm.runInContext(source,context)
vm.runInContext('view=fixtureView;observePublicationFocus(fixtureDoc,view)',context)
const pointer=listeners.get('pointerdown')[0],focus=listeners.get('focusin')[0]
events.length=0
pointer({type:'pointerdown',isTrusted:false,target})
assert.equal(events.length,0,'synthetic probe input cannot impersonate native user focus')
pointer({type:'pointerdown',isTrusted:true,target})
assert.equal(events.at(-1).type,'contentFocus');assert.equal(events.at(-1).source,'pointer');assert.equal(events.at(-1).session,'focus-probe')
focus({type:'focusin',isTrusted:true,target});assert.equal(events.at(-1).source,'focus')
events.length=0
vm.runInContext('view={parts:[]}',context)
pointer({type:'pointerdown',isTrusted:true,target})
assert.equal(events.length,0,'a detached publication document cannot report focus for its replacement')
vm.runInContext('view=fixtureView',context)
publication.parts=[]
pointer({type:'pointerdown',isTrusted:true,target})
assert.equal(events.length,0,'a no-longer-visible fixed page cannot report focus')
publication.parts=[{doc,index:0}]
const anchor={cfi:'epubcfi(/6/2!/4/2,/1:53,/1:60)',index:0}
context.fixtureAnchor=anchor
vm.runInContext("selection={text:'library',anchor:fixtureAnchor,reference:'Chapter 1'};refreshSelectionGeometry()",context)
assert.deepEqual(events.at(-1).anchor,anchor,'resize preserves the original durable source coordinates')
assert.deepEqual(events.at(-1).rect,{x:40,y:60,width:70,height:20})
assert.notEqual(events.at(-1).settled,true,'resize must not request a selection popover')
left=80
events.length=0
vm.runInContext('scheduleSelectionGeometry();scheduleSelectionGeometry()',context)
while(frames.length)frames.shift()()
assert.equal(events.length,1,'a resize burst publishes only its latest geometry')
assert.equal(events[0].rect.x,90)
events.length=0
vm.runInContext('scheduleSelectionGeometry();view={parts:[]}',context)
while(frames.length)frames.shift()()
assert.equal(events.length,0,'late resize work cannot publish into a replacement renderer')
vm.runInContext('view=fixtureView',context)
connected=false
vm.runInContext('refreshSelectionGeometry()',context)
assert.equal(events.at(-1).anchor,null,'a detached range clears stale native selection')
console.log(JSON.stringify({status:'passed',scope:'Owned focus protocol: trusted input/current visible document only; bounded resize geometry retains exact source anchor, suppresses popovers, rejects replacement work and clears detached selection; native focus verified separately'}))
