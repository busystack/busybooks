// Actual adapter functions with controlled asynchronous rendering and geometry.
// Browser layout and publication loading are exercised by review_native_proof.js.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import * as typography from '../assets/reader/typography.mjs'
import { validPage } from '../assets/reader/reading_geometry.mjs'
import { comicAnchor } from '../assets/reader/comic_book.mjs'
const {search}=await import(process.env.BUSYBOOKS_SEARCH_SOURCE??new URL('../assets/reader/vendor/foliate/search.js',import.meta.url))

const source=(await fs.readFile(process.env.BUSYBOOKS_READER_SOURCE??new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
    .replace(/^import .*\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
const failures=[]
async function check(name,run){
    let timer
    try{await Promise.race([run(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Controlled operation did not settle')),10000)})]);console.log(JSON.stringify({status:'passed',check:name}))}
    catch(error){failures.push(name);console.error(name+': '+error.stack)}
    finally{clearTimeout(timer)}
}
function adapter(){
    const events=[],content={scrollLeft:0,scrollTop:0,clientWidth:800,clientHeight:600,style:{},addEventListener(){},setAttribute(){},removeAttribute(){},replaceChildren(){}}
    const document={querySelectorAll:()=>[],querySelector:()=>content,addEventListener(){},getSelection:()=>null,body:{style:{setProperty(){}}}}
    const context=vm.createContext({...typography,AbortController,URL,console,Uint8Array,setTimeout,clearTimeout,structuredClone,validPage,comicAnchor,performance,
        requestAnimationFrame:()=>{},pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},document,
        window:{location:{href:'https://busybooks.local/?session=review'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}}})
    vm.runInContext(source,context)
    const run=code=>vm.runInContext(code,context)
    run(`pdf={numPages:5};pages=Array.from({length:5},()=>({element:{offsetTop:0,offsetLeft:0,offsetHeight:1000,hidden:false},viewport:{convertToPdfPoint:(x,y)=>[x,y],convertToViewportPoint:(x,y)=>[x,y]}}));queuePage=async()=>true`)
    return {events,content,context,document,run}
}
await check('F06: an older PDF render cannot commit after a newer destination',async()=>{
    const {run,events}=adapter()
    run('pending={};queuePage=index=>new Promise(resolve=>pending[index]=resolve);older=gotoPdf({page:1});newer=gotoPdf({page:3})')
    await run('pending[3](true);newer')
    await run('pending[1](true);older')
    assert.deepEqual(events.filter(x=>x.type==='location').map(x=>x.anchor.page),[3])
    assert.equal(run('location.anchor.page'),3)
})
await check('F06: two rapid relative PDF commands advance twice',async()=>{
    const {run,events}=adapter()
    run(`activeFormat='pdf';location={anchor:{page:0}};pending={};queuePage=index=>new Promise(resolve=>pending[index]=resolve);first=dispatch({action:'next'});second=dispatch({action:'next'})`)
    await new Promise(setImmediate)
    await run('pending[1](true);first')
    await new Promise(setImmediate)
    await run('pending[2]?.(true);second')
    assert.deepEqual(events.filter(x=>x.type==='location').map(x=>x.anchor.page),[1,2])
})
await check('F04: flush drains comic navigation before its saved snapshot',async()=>{
    const {run,events}=adapter()
    run(`activeFormat='cbz';pdf=null;view={isFixedLayout:true,book:{format:'cbz',sections:[{pageId:'a'},{pageId:'b'}]},renderer:{getContents:()=>[],getBoundingClientRect:()=>({left:0,top:0})}};location={anchor:comicAnchor(view.book,0)};gotoEpub=()=>new Promise(resolve=>release=()=>{reportLocation({anchor:comicAnchor(view.book,1)});resolve()});navigation=dispatch({action:'goto',anchor:{page:1}})`)
    await new Promise(setImmediate)
    run(`flushing=dispatch({action:'flush',request:5})`)
    await new Promise(setImmediate)
    assert.equal(events.some(x=>x.type==='flushed'),false)
    await run('release();navigation;flushing')
    assert.equal(events.at(-2).anchor.page,1)
    assert.equal(events.at(-1).type,'flushed')
})
await check('F05: comic companion-page pan survives a saved-position round trip',async()=>{
    const {run,context,content,events}=adapter()
    let left=2200
    context.parts=[0,1].map(index=>({index,doc:{querySelector:()=>({}),defaultView:{frameElement:{getBoundingClientRect:()=>({left:index*1800-left,top:0,width:1800,height:2400})}}}}))
    context.scrollBy=delta=>{left+=delta.left}
    run(`activeFormat='cbz';pdf=null;view={book:{format:'cbz',sections:[{pageId:'a'},{pageId:'b'}]},renderer:{getContents:()=>parts,getBoundingClientRect:()=>({left:0,top:0,width:800,height:600}),scrollBy}};location={anchor:comicAnchor(view.book,0)}`)
    await run(`dispatch({action:'flush'})`)
    const anchor=events.findLast(x=>x.type==='location').anchor
    assert.equal(anchor.page,1)
    left=0;context.saved=anchor
    run('restoreComicPosition(saved)')
    assert(Math.abs(left-2200)<.001)
    assert.equal(content.scrollLeft,0)
})
await check('F07: PDF anchors retain both viewport axes',async()=>{
    const {run,content}=adapter()
    content.scrollLeft=450;content.scrollTop=250
    run('saved=pdfAnchor(0,.25)')
    content.scrollLeft=0;content.scrollTop=0
    await run('gotoPdf(saved)')
    assert.equal(content.scrollLeft,450);assert.equal(content.scrollTop,250)
})
await check('F08: Previous from physical PDF page 2 reaches the first spread',async()=>{
    const {run,events}=adapter()
    run(`activeFormat='pdf';prefs={spread:true};location={anchor:{page:1}}`)
    await run(`dispatch({action:'previous'})`)
    assert.equal(events.findLast(x=>x.type==='location')?.anchor.page,0)
    assert.equal(events.some(x=>x.type==='navigationError'),false)
})
await check('F02: annotation chunks commit atomically and obsolete transfers cannot repaint',async()=>{
    const {run,context}=adapter()
    run('pdf=null')
    const records=Array.from({length:400},(_,i)=>({id:String(i),text:'漢📘\u0001'.repeat(500),anchor:{page:i}})),encoded=JSON.stringify(records)
    for(let offset=0;offset<encoded.length;offset+=32768){
        const end=Math.min(encoded.length,offset+32768)
        context.command={action:'annotations',revision:1,offset,chunk:encoded.slice(offset,end),complete:end===encoded.length}
        await run('dispatch(command)')
        if(end<encoded.length)assert.equal(run('annotations.length'),0)
    }
    assert.deepEqual(JSON.parse(run('JSON.stringify(annotations)')),records)
    await run(`dispatch({action:'annotations',revision:2,offset:0,chunk:'[',complete:false})`)
    await run(`dispatch({action:'annotations',revision:3,value:[{id:'current'}]})`)
    await run(`dispatch({action:'annotations',revision:2,offset:1,chunk:']',complete:true})`)
    assert.equal(run('annotations[0].id'),'current')
    await run(`dispatch({action:'annotations',revision:4,value:[]})`)
    assert.equal(run('annotations.length'),0)
})
await check('F12: opening with zero rendered documents reports failure',async()=>{
    const {run,context,document,events}=adapter()
    const book={sections:[{}],metadata:{}}
    const publication={isFixedLayout:false,renderer:{getContents:()=>[]},history:{addEventListener(){},canGoBack:false,canGoForward:false},addEventListener(){},open:async()=>{},init:async()=>{}}
    context.publication=publication;context.book=book;document.createElement=()=>publication
    run(`pdf=null;publication.book=book;theme=()=>{};applyAppearance=async()=>true;paintEpub=async()=>{};openFoliate=config=>mountFoliate(book,config)`)
    await run(`dispatch({action:'open',format:'epub'})`)
    assert.equal(events.some(x=>x.type==='opened'),false)
    assert(events.some(x=>x.type==='error'&&x.message.includes('first document')))
})
await check('F16: text-search excerpts and ranges span formatting boundaries and exact endpoints',async()=>{
    for(const sensitivity of ['base','variant','accent'])for(const [strs,query] of [
        [['quick ','brown ','fox'],'quick brown fox'],[['same',' and ','same'],'same and same'],[['a','b','c'],'abc'],[['same'],'same'],[['ab','ab'],'aba'],[['','ABC',''],'ABC'],
    ]){
        const matches=[...search(strs,query,{sensitivity})]
        assert.equal(matches[0]?.excerpt.match,query,JSON.stringify({strs,query,sensitivity,matches}))
    }
    const matches=[...search(['İABC'],'ABC',{sensitivity:'accent'})]
    assert.equal(matches[0].range.startOffset,1);assert.equal(matches[0].range.endOffset,4)
    const turkish=[...search(['I\u0307ABC'],'ABC',{sensitivity:'accent',locales:'tr'})]
    assert.equal(turkish[0].range.startOffset,2);assert.equal(turkish[0].range.endOffset,5)
    assert.equal([...search(['qui','ck'],'quick',{granularity:'word'})][0]?.excerpt.match,'quick')
    assert.equal([...search(['e','\u0301','clair'],'éclair')][0]?.excerpt.match.normalize('NFC'),'éclair')
    assert.deepEqual([...search(['text'],'')],[])
})
if(failures.length){console.error(JSON.stringify({status:'failed',checks:failures}));process.exitCode=1}
