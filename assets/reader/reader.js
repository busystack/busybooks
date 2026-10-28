// BusyBooks content adapter. Application UI, persistence and commands stay in Flutter.
import './vendor/foliate/view.js'
import { textWalker } from './vendor/foliate/text-walker.js'
import { literalRanges, literalTextMatches, excerptParts } from './literal_search.mjs'
import { fitScale, validPage, cssColor, tabTarget } from './reading_geometry.mjs'
import { noTypography, reflowableTypography, createLocalFont, prepareLocalFont, installLocalFont, typographyCSS, protectSpecializedFonts, applyFontFamily, validateTypographyUpdate, TypographyWork } from './typography.mjs'
import * as CFI from './vendor/foliate/epubcfi.js'
import { makePreparedFB2 } from './prepared_book.mjs'
import { makeComicBook, comicAnchor, normalizedRegion, decodeComicImage } from './comic_book.mjs'
import { makeEpubBook } from './epub_integration.mjs'
import { FixedLayoutIntegration, readerContents } from './fixed_layout_integration.mjs'
import { Overlayer } from './vendor/foliate/overlayer.js'
import * as pdfjs from './vendor/pdfjs/pdf.mjs'
pdfjs.GlobalWorkerOptions.workerSrc = new URL('./vendor/pdfjs/pdf.worker.mjs', import.meta.url).href
const content = document.querySelector('#content')
const session = new URL(window.location.href).searchParams.get('session') ?? 'probe'
const bridgePayloadCharacters=16*1024*1024,bridgeChunkCharacters=32*1024
let bridgeRevision=0,commandTransfer=null,commandRevision=-1
function postBridge(json){
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json)
    else window.chrome?.webview?.postMessage(json)
}
function emit(type,data={}){
    const message={type,session,...data},json=JSON.stringify(message)
    if(json.length>bridgePayloadCharacters){postBridge(JSON.stringify({type:'bridgeError',session,direction:'event',message:'Reader bridge payload limit exceeded'}));return false}
    if(utf8Length(json)<=131072)postBridge(json)
    else {
        const revision=++bridgeRevision
        for(let offset=0;offset<json.length;offset+=bridgeChunkCharacters){
            const end=Math.min(json.length,offset+bridgeChunkCharacters)
            postBridge(JSON.stringify({type:'bridgeChunk',session,bridgeRevision:revision,offset,total:json.length,chunk:json.slice(offset,end),complete:end===json.length}))
        }
    }
    if(window.busybooksProbe)window.busybooksProbe(message)
    return true
}
function receiveCommand(frame){
    if(frame.action!=='bridgeChunk'){
        if(commandTransfer){commandTransfer=null;throw Error('Incomplete reader bridge transfer')}
        return frame
    }
    const {bridgeRevision:revision,offset,total,chunk,complete}=frame
    const invalid=()=>{commandTransfer=null;throw Error('Invalid reader bridge transfer')}
    if(!Number.isSafeInteger(revision)||revision<0||!Number.isSafeInteger(offset)||!Number.isSafeInteger(total)||
        total<1||total>bridgePayloadCharacters||typeof chunk!=='string'||!chunk.length||chunk.length>bridgeChunkCharacters||typeof complete!=='boolean')invalid()
    if(revision<commandRevision||revision===commandRevision&&!commandTransfer)return null
    if(offset===0){if(revision<=commandRevision||commandTransfer)invalid();commandRevision=revision;commandTransfer={revision,total,size:0,chunks:[]}}
    const transfer=commandTransfer
    if(!transfer||revision!==transfer.revision||offset!==transfer.size||total!==transfer.total||transfer.size+chunk.length>total)invalid()
    transfer.chunks.push(chunk);transfer.size+=chunk.length
    if(complete!==(transfer.size===total))invalid()
    if(!complete)return null
    commandTransfer=null
    const command=JSON.parse(transfer.chunks.join(''))
    if(command.session!==session||command.action==='bridgeChunk')invalid()
    return command
}
let strings={}, chrome={}, spokenAnchor=null, currentRange=null, view, pdf, prefs = {}, location = {}, selection = null, annotations = [], pages = [], labels = []
const fixedContents=new WeakMap()
const observedComicRenderers=new WeakSet()
let fixedLayout=null
function getContents(publication=view){return readerContents(publication,fixedContents)}
function configureFixedRenderer(renderer){
    if(!isComic()||observedComicRenderers.has(renderer))return
    observedComicRenderers.add(renderer)
    const publication=view
    renderer.addEventListener('scroll',()=>{
        clearTimeout(window.comicScrollTimer)
        window.comicScrollTimer=setTimeout(()=>{
            if(view!==publication||view.renderer!==renderer||fixedLayout?.busy)return
            captureComicLocation();reportLocation(location)
        },200)
    },{passive:true})
}
let noteView=null,noteGeneration=0,cacheFailureReported=false
let typography=noTypography,localFont={family:'serif',faces:[]},fontSignature='',lastEpubRelocation=null,pinnedTypographyLocation=null
const typographyWork=new TypographyWork()
let appearanceOperation=Promise.resolve(),programmaticSelections=new WeakMap()
let annotationOperation=Promise.resolve(),annotationRevision=-1,annotationTransfer=null
function receiveAnnotations(command){
    const revision=command.revision??annotationRevision+1
    if(revision<annotationRevision)return
    let value=command.value
    if(typeof command.chunk==='string'){
        if(command.offset===0){annotationRevision=revision;annotationTransfer={revision,size:0,chunks:[]}}
        const transfer=annotationTransfer
        if(!transfer||transfer.revision!==revision)return
        if(command.offset!==transfer.size)throw Error('Incomplete annotation transfer')
        transfer.chunks.push(command.chunk);transfer.size+=command.chunk.length
        if(!command.complete)return
        value=JSON.parse(transfer.chunks.join(''))
    }
    if(!Array.isArray(value))throw Error('Invalid annotation snapshot')
    annotationRevision=revision;annotationTransfer=null
    const operation=annotationOperation.catch(()=>{}).then(async()=>{
        if(revision!==annotationRevision)return
        if(view)for(const a of annotations)if(a.anchor?.cfi){
            if(fixedLayout)for(const part of getContents(view))part.overlayer?.remove(a.anchor.cfi)
            else await view.deleteAnnotation({value:a.anchor.cfi})
        }
        annotations=value
        if(view){await paintEpub();if(noteView)await paintNote()}else if(pdf)paintPdf()
    })
    annotationOperation=operation;return operation
}
function userNavigation(){typographyWork.navigate();pinnedTypographyLocation=null;programmaticSelections=new WeakMap()}
function reportEpubLocation(data){
    lastEpubRelocation=data
    if(typographyWork.active&&typographyWork.canRestore(typographyWork.active))return
    const pin=pinnedTypographyLocation
    reportLocation(pin&&pin.view===view?{...data,anchor:pin.anchor,progress:pin.progress}:data)
}
let activeFormat='epub',navigationTail=Promise.resolve(),regionSelection=null
const isComic=()=>activeFormat==='cbz'||activeFormat==='cbr'
function textAnchor(cfi,index){
    const resolved=index??view.resolveCFI(cfi)?.index
    if(activeFormat==='fb2'){
        const section=view.book.sections[resolved];if(!section)throw Error('Invalid FB2 section')
        return {kind:'fb2',version:1,section:section.identity,index:resolved,cfi}
    }
    return {cfi,...(index!=null?{index}:{} )}
}
let generation = 0, history = [], historyIndex = -1
const colors = { yellow: '#f5d547', green: '#70c77d', blue: '#6ab7ed', pink: '#e997ba' }
let selectionTimer, suppressSelectionUntil=0, navigatingPage=null, layingOut=false
function selectionRect(range, doc=document) {
    const frame=doc.defaultView?.frameElement,parent=frame?.getBoundingClientRect()
    const sx=parent&&frame.clientWidth?parent.width/frame.clientWidth:1,sy=parent&&frame.clientHeight?parent.height/frame.clientHeight:1
    const rects=[...range.getClientRects()].map(r=>({left:(parent?.left??0)+r.left*sx,top:(parent?.top??0)+r.top*sy,right:(parent?.left??0)+r.right*sx,bottom:(parent?.top??0)+r.bottom*sy}))
    const rect=rects.filter(r=>r.right>0&&r.bottom>0&&r.left<content.clientWidth&&r.top<content.clientHeight).at(-1)??{left:0,top:0,right:1,bottom:1}
    const x=Math.max(0,rect.left),y=Math.max(0,rect.top)
    return {x,y,width:Math.max(1,Math.min(content.clientWidth,rect.right)-x),height:Math.max(1,Math.min(content.clientHeight,rect.bottom)-y)}
}
function selected(data,range,doc=document,settle=true) {
    selection={...data,rect:selectionRect(range,doc)};emit('selection',selection)
    clearTimeout(selectionTimer)
    if(settle)selectionTimer=setTimeout(()=>{if(selection?.text&&performance.now()>suppressSelectionUntil)emit('selection',{...selection,settled:true})},450)
}
function theme(value){
    chrome=value
    for(const [name,key] of [['canvas','canvas'],['foreground','foreground'],['selection','selection'],['accent','accent']])
        if(value[key]!=null)document.body.style.setProperty(`--${name}`,cssColor(value[key]))
    document.documentElement.style.colorScheme=value.dark?'dark':'light'
    document.documentElement.style.setProperty('--motion',value.reducedMotion?'0ms':'120ms')
}
const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve))
function flatten(items) {
    const entries=[],pending=(items??[]).map(item=>({item,depth:0})).reverse()
    while(pending.length){const {item,depth}=pending.pop();if(entries.length>=100000)throw Error('Outline exceeds its record limit')
        entries.push({id:`outline:${entries.length}`,label:item.label??item.title??'',href:item.href??'',depth})
        for(let i=(item.subitems?.length??0)-1;i>=0;i--)pending.push({item:item.subitems[i],depth:depth+1})
    }return entries
}
let outlineRevision=0
function utf8Length(text){let size=0;for(const c of text){const n=c.codePointAt(0);size+=n<128?1:n<2048?2:n<65536?3:4}return size}
function publishOutline(entries,revision){
    let chunk=[],bytes=0,offset=0
    for(const entry of entries){const size=utf8Length(JSON.stringify(entry))+1
        if(size>524288)throw Error('Outline entry exceeds its message limit')
        if(bytes+size>131072&&chunk.length){emit('metadata',{toc:chunk,tocOffset:offset,tocComplete:false,outlineRevision:revision});offset+=chunk.length;chunk=[];bytes=0}
        chunk.push(entry);bytes+=size
    }
    emit('metadata',{toc:chunk,tocOffset:offset,tocComplete:true,outlineRevision:revision})
}
async function resolveOutline(entries,resolve,revision,owner){
    let index=0,pending=[]
    const current=()=>owner===session&&revision===outlineRevision
    const publish=complete=>{if(current()&&(pending.length||complete)){emit('metadata',{tocUpdates:pending,outlineRevision:revision,tocResolved:complete});pending=[]}}
    async function worker(){while(index<entries.length&&current()){
        const i=index++,entry=entries[i]
        try{const update=await resolve(entry,i);if(current()&&update){Object.assign(entry,update);pending.push({...entry})}}
        catch{} // An unusable optional destination never disables its siblings.
        if(pending.length>=128)publish(false)
        if(i%16===0)await new Promise(resolve=>setTimeout(resolve,0))
    }}
    await Promise.all([worker(),worker()]);publish(true)
}
async function enrichEpubOutline(book,owner){
    if(owner!==session||view?.book!==book)return
    const revision=++outlineRevision,entries=flatten(book.toc)
    publishOutline(entries,revision)
    if(isComic()){for(const entry of entries){entry.anchor=comicAnchor(book,Number(entry.href))}publishOutline(entries,revision);emit('metadata',{tocUpdates:[],outlineRevision:revision,tocResolved:true});return}
    if(activeFormat!=='fb2'&&!book.pageList?.length){emit('metadata',{tocUpdates:[],outlineRevision:revision,tocResolved:true});return}
    const documents=new Map()
    await resolveOutline(entries,async entry=>{
        if(!entry.href)return null
        const publication=view;if(!publication||publication.book!==book)return null
        const resolved=await publication.resolveNavigation(entry.href)
        if(!documents.has(resolved.index)){
            documents.set(resolved.index,book.sections[resolved.index].createDocument())
            while(documents.size>4)documents.delete(documents.keys().next().value)
        }
        const doc=await documents.get(resolved.index),fragment=resolved.anchor(doc)
        const range=fragment instanceof Range?fragment:doc.createRange()
        if(!(fragment instanceof Range))range.selectNodeContents(fragment||doc.body)
        range.collapse(true)
        const page=publication.getProgressOf(resolved.index,range).pageItem
        return {...(page?.label?{pageLabel:page.label}:{}),...(activeFormat==='fb2'?{anchor:textAnchor(publication.getCFI(resolved.index,range),resolved.index)}:{})}
    },revision,owner)
}
function reportLocation(data) {
    const {text,...position}=data
    location = position
    emit('location', position)
    reportNavigation()
}
function reportNavigation(){
    const index=location.anchor?.page??location.anchor?.index??0
    const shown=fixedLayout?Math.max(index,...fixedLayout.visibleContents().map(x=>x.index)):index
    emit('navigation',{speechNext:isComic()?false:view?(view.isFixedLayout?index<view.book.sections.length-1:!view.renderer.atEnd):index<(pdf?.numPages??0)-1,back:fixedLayout?historyIndex>0:view?view.history.canGoBack:historyIndex>0,forward:fixedLayout?historyIndex<history.length-1:view?view.history.canGoForward:historyIndex<history.length-1,previous:view?(view.isFixedLayout?index>0:!view.renderer.atStart):index>0,next:view?(view.isFixedLayout?shown<view.book.sections.length-1:!view.renderer.atEnd):index+(prefs.spread?1:0)<(pdf?.numPages??0)-1})
}
function reportFixedLocation({index,range}){
    currentRange=range
    if(isComic()){
        reportLocation({anchor:comicAnchor(view.book,index),progress:(index+1)/view.book.sections.length,reference:`${strings.page} ${index+1}`,text:'',noText:true})
        view.book.releaseExcept(new Set(getContents(view).map(part=>part.index)))
        paintRegions();return
    }
    const progress=view.getProgressOf(index,range),cfi=view.getCFI(index,range)
    const data={anchor:textAnchor(cfi,index),progress:view.getSectionFractions()[index]??0,chapter:progress.tocItem?.label??'',reference:progress.pageItem?.label?`${strings.printPage} ${progress.pageItem.label}`:progress.tocItem?.label??'',text:range?.toString()??'',tocHref:progress.tocItem?.href,tocId:progress.tocItem?.id==null?null:`outline:${progress.tocItem.id}`,printPage:progress.pageItem?.label}
    reportEpubLocation(data)
}
function remember() {
    if(isComic())captureComicLocation()
    if (historyIndex < 0 || JSON.stringify(history[historyIndex]) !== JSON.stringify(location.anchor)) {
        history.splice(historyIndex+1);history.push(structuredClone(location.anchor));historyIndex = history.length-1
    }
    reportNavigation()
}
function cacheResourceFailure(error){
    if(error?.name==='AbortError')throw error
    if(!cacheFailureReported){cacheFailureReported=true;emit('error',{message:String(error),cacheFailure:true})}
    throw Object.assign(error instanceof Error?error:Error(String(error)),{cacheFailureReported:true})
}
function safeDocument(data) {
    // Book documents are never script-capable application contexts. CSP also blocks
    // network requests; sanitize before EPUB resources become Blob URLs.
    const doc = new DOMParser().parseFromString(data,'application/xhtml+xml')
    if (doc.querySelector('parsererror')) cacheResourceFailure(Error('Invalid publication XHTML'))
    for (const el of doc.querySelectorAll('script,iframe,object,embed,form,base,meta[http-equiv],link[rel="preload"],link[rel="modulepreload"]')) el.remove()
    for (const el of doc.querySelectorAll('*')) for (const attr of [...el.attributes]) {
        if (/^on/i.test(attr.name) || /^(?:javascript|vbscript):/i.test(attr.value.trim())) el.removeAttribute(attr.name)
    }
    return new XMLSerializer().serializeToString(doc)
}
function reportEpubSelection(doc,index,settle=true){
    const s=doc.getSelection();if(!s?.rangeCount||s.isCollapsed){selection=null;emit('selection',{text:'',anchor:null});return}
    const range=s.getRangeAt(0),progress=view.getProgressOf(index,range)
    selected({text:s.toString(),anchor:textAnchor(view.getCFI(index,range),index),reference:progress.pageItem?.label?`${strings.printPage} ${progress.pageItem.label}`:progress.tocItem?.label??location.reference??'',order:index},range,doc,settle)
}
function captureEpubSelections(){
    return (getContents(view)??[]).flatMap(({doc,index})=>{
        const s=doc?.getSelection();if(!s?.rangeCount||s.isCollapsed)return []
        const range=s.getRangeAt(0).cloneRange()
        return [{doc,index,range,cfi:view.getCFI(index,range),backwards:s.anchorNode===range.endContainer&&s.anchorOffset===range.endOffset,anchor:s.anchorNode,anchorOffset:s.anchorOffset,focus:s.focusNode,focusOffset:s.focusOffset}]
    })
}
function restoreEpubSelections(work){
    if(!typographyWork.canRestore(work))return
    for(const saved of work.selections??[]){
        let doc=saved.doc,range=saved.range,anchor=saved.anchor,anchorOffset=saved.anchorOffset,focus=saved.focus,focusOffset=saved.focusOffset
        if(!getContents(view).some(part=>part.doc===doc)||!range.startContainer.isConnected){
            if(!saved.cfi)continue
            doc=getContents(view).find(part=>part.index===saved.index)?.doc
            if(!doc)continue
            range=view.resolveCFI(saved.cfi).anchor(doc)
            anchor=saved.backwards?range.endContainer:range.startContainer;anchorOffset=saved.backwards?range.endOffset:range.startOffset
            focus=saved.backwards?range.startContainer:range.endContainer;focusOffset=saved.backwards?range.startOffset:range.endOffset
        }
        programmaticSelections.set(doc,range)
        const s=doc.getSelection()
        // Selection mutation does not request native/WebView focus.
        s.setBaseAndExtent(anchor,anchorOffset,focus,focusOffset)
        reportEpubSelection(doc,saved.index,false)
    }
}
async function boundedResourceBuffer(response,maximum,expected=null){
    if(!response.ok)throw Error('Publication resource is unavailable')
    if(!Number.isSafeInteger(maximum)||maximum<0||expected!=null&&(!Number.isSafeInteger(expected)||expected<0||expected>maximum))throw Error('Publication resource exceeds its media limit')
    const reader=response.body?.getReader()
    if(!reader)throw Error('Bounded publication resource streaming is unavailable')
    const chunks=[];let size=0
    try{
        for(;;){
            const {done,value}=await reader.read();if(done)break
            size+=value.byteLength
            if(size>maximum||expected!=null&&size>expected){await reader.cancel();throw Error('Publication resource exceeds its media limit or declared size')}
            chunks.push(value)
        }
    }finally{reader.releaseLock()}
    if(expected!=null&&size!==expected)throw Error('Publication resource size does not match its index')
    const buffer=new Uint8Array(size);let offset=0
    for(const chunk of chunks){buffer.set(chunk,offset);offset+=chunk.byteLength}
    return buffer.buffer
}
async function openFoliate(config) {
    const index=JSON.parse(new TextDecoder().decode(await boundedResourceBuffer(await fetch('book-index'),16*1024*1024))),sizes=index.resources
    if(config.format==='epub'&&index.version!==4)throw Error('Unsupported EPUB cache version')
    const resource=name=>'book/'+sizes[name].file
    const load=async(name,options,text=false)=>{
        if(!Object.hasOwn(sizes,name))return null
        try{
            const resourceMaximum=config.format==='epub'?sizes[name].maximumBytes:config.format==='fb2'?(name.startsWith('sections/')?4*1024*1024:16*1024*1024):64*1024*1024
            if(!Number.isSafeInteger(resourceMaximum)||resourceMaximum<0||resourceMaximum>64*1024*1024)throw Error('Invalid publication resource budget')
            const maximum=text?Math.min(4*1024*1024,resourceMaximum):resourceMaximum
            if(!Number.isSafeInteger(sizes[name].size)||sizes[name].size<0||sizes[name].size>maximum)throw Error('Publication resource exceeds its media limit')
            const buffer=await boundedResourceBuffer(await fetch(resource(name),options),maximum,sizes[name].size)
            const expected=sizes[name].sha256
            if(typeof expected!=='string'||!/^([a-f0-9]{64})$/.test(expected))throw Error('Publication resource digest is missing')
            const digest=await crypto.subtle.digest('SHA-256',buffer)
            const actual=[...new Uint8Array(digest)].map(byte=>byte.toString(16).padStart(2,'0')).join('')
            if(actual!==expected)throw Error('Publication resource digest does not match its index')
            return buffer
        }catch(error){cacheResourceFailure(error)}
    }
    const loadText=async(name,options)=>{
        const buffer=await load(name,options,true);if(buffer==null)return null
        const data=new Uint8Array(buffer)
        try{return new TextDecoder(data[0]===255&&data[1]===254||data[0]===60&&data[1]===0?'utf-16le':data[0]===254&&data[1]===255||data[0]===0&&data[1]===60?'utf-16be':'utf-8',{fatal:true}).decode(data)}
        catch(error){cacheResourceFailure(error)}
    }
    const loader={loadText,loadBlob:async(name,type,options)=>{const buffer=await load(name,options);return buffer==null?null:new Blob([buffer],{type:type??''})},getSize:name=>sizes[name]?.size??0}
    let book
    switch(config.format){
        case 'epub':book=await makeEpubBook(index,loader,safeDocument);break
        case 'fb2':book=await makePreparedFB2(index,loader,safeDocument);break
        case 'cbz':case 'cbr':book=makeComicBook(index,loader);break
        default:throw Error('Unsupported publication format')
    }
    try{await mountFoliate(book,config)}catch(error){
        // Cleanup of an uninitialized upstream paginator can fail independently.
        // Preserve the publication's original load error and discard this view.
        if(view?.book===book){
            const failed=view
            view=null;fixedLayout=null
            try{failed.close()}catch(cleanup){emit('diagnostic',{stage:'cleanup',message:String(cleanup)})}
            failed.remove()
        }
        try{book.destroy?.()}catch(cleanup){emit('diagnostic',{stage:'cleanup',message:String(cleanup)})}
        throw error
    }
}
async function verifyComicPage(){
    const current=view,parts=getContents(current).filter(x=>x.index===location.anchor?.page)
    if(!parts.length)throw Error('Comic page did not lay out')
    for(const {doc} of parts){const img=doc.querySelector('img');await img?.decode();if(current!==view||!img?.naturalWidth||!img.getBoundingClientRect().width)throw Error('Comic page failed to decode or lay out')}
    await nextFrame()
}
function captureComicLocation(){
    if(!view||location.anchor?.page==null)return
    const viewport=view.renderer.getBoundingClientRect()
    const parts=getContents(view).flatMap(part=>{
        const frame=part.doc.defaultView?.frameElement,bounds=frame?.getBoundingClientRect()
        if(!bounds?.width||!bounds.height||!part.doc.querySelector('img'))return []
        const x=Math.max(0,Math.min(bounds.width,viewport.left-bounds.left)),y=Math.max(0,Math.min(bounds.height,viewport.top-bounds.top))
        const distance=(bounds.left+x-viewport.left)**2+(bounds.top+y-viewport.top)**2
        return [{index:part.index,position:[x/bounds.width,y/bounds.height],distance,left:bounds.left,right:bounds.left+bounds.width}]
    })
    // When the spread fits horizontally, retain its explicitly selected page.
    // The viewport's left edge belongs to the companion even without panning.
    // An overflowing spread can instead save the page actually reached by pan.
    const overflow=parts.length&&Math.max(...parts.map(part=>part.right))-Math.min(...parts.map(part=>part.left))>viewport.width+1
    parts.sort((a,b)=>a.distance-b.distance||Number(b.index===location.anchor.page)-Number(a.index===location.anchor.page)||a.index-b.index)
    const part=(!overflow&&parts.find(part=>part.index===location.anchor.page))||parts[0];if(!part)return
    location={...location,anchor:comicAnchor(view.book,part.index,{position:part.position}),progress:(part.index+1)/view.book.sections.length,reference:`${strings.page} ${part.index+1}`}
}
function restoreComicPosition(anchor){
    const part=getContents(view).find(x=>x.index===(anchor?.page??location.anchor?.page)),frame=part?.doc.defaultView.frameElement
    if(!frame)return
    const bounds=frame.getBoundingClientRect(),viewport=view.renderer.getBoundingClientRect(),region=anchor?.region,position=anchor?.position
    if(region){normalizedRegion(region);view.renderer.scrollBy({left:bounds.left+(region[0]+region[2]/2)*bounds.width-(viewport.left+viewport.width/2),top:bounds.top+(region[1]+region[3]/2)*bounds.height-(viewport.top+viewport.height/2)})}
    else if(position)view.renderer.scrollBy({left:bounds.left+position[0]*bounds.width-viewport.left,top:bounds.top+position[1]*bounds.height-viewport.top})
}
function setupComicPage(doc,index){
    const img=doc.querySelector('img');if(!img)return
    doc.body.style.position='relative';doc.body.setAttribute('tabindex','0')
    doc.addEventListener('keydown',keys)
    doc.addEventListener('pointerdown',event=>{
        if(event.button!==0)return
        if(regionSelection){
            if(regionSelection.index!==index)return
            event.preventDefault();const bounds=img.getBoundingClientRect(),x=Math.max(0,Math.min(1,(event.clientX-bounds.left)/bounds.width)),y=Math.max(0,Math.min(1,(event.clientY-bounds.top)/bounds.height))
            regionSelection.start=[x,y];regionSelection.rect=[Math.min(x,.999),Math.min(y,.999),.001,.001];regionSelection.pointer=event.pointerId;img.setPointerCapture(event.pointerId);paintRegions();return
        }
        // Drag panning belongs to the normal reader, outside selection mode.
        const region=event.target.closest('[data-region-id]'),target=region??img
        let x=event.screenX,y=event.screenY,moved=false
        delete target.dataset.regionDragged
        try{target.setPointerCapture(event.pointerId)}catch{} // A cancelled/replaced pointer may already be gone.
        const move=e=>{if(!moved&&Math.hypot(x-e.screenX,y-e.screenY)<3)return;moved=true;view.renderer.scrollBy({left:x-e.screenX,top:y-e.screenY});x=e.screenX;y=e.screenY}
        const up=()=>{target.removeEventListener('pointermove',move);target.removeEventListener('pointerup',up);target.removeEventListener('pointercancel',up);if(moved&&region){target.dataset.regionDragged='true';setTimeout(()=>delete target.dataset.regionDragged,0)}}
        target.addEventListener('pointermove',move);target.addEventListener('pointerup',up);target.addEventListener('pointercancel',up);if(!region)event.preventDefault()
    })
    img.addEventListener('pointermove',event=>{
        const state=regionSelection;if(!state||state.index!==index||state.pointer!==event.pointerId)return
        const bounds=img.getBoundingClientRect(),x=Math.max(0,Math.min(1,(event.clientX-bounds.left)/bounds.width)),y=Math.max(0,Math.min(1,(event.clientY-bounds.top)/bounds.height)),[sx,sy]=state.start
        state.rect=[Math.min(sx,x),Math.min(sy,y),Math.abs(sx-x),Math.abs(sy-y)];paintRegions()
    })
    img.addEventListener('pointerup',event=>{if(regionSelection?.pointer===event.pointerId){regionSelection.pointer=null;try{normalizedRegion(regionSelection.rect);confirmRegion()}catch{}}})
    doc.addEventListener('dragstart',e=>e.preventDefault())
    paintRegions()
}
function beginRegion(){
    if(!isComic())return
    cancelRegion()
    const index=location.anchor?.page??0
    regionSelection={index,rect:[.25,.25,.5,.5]}
    const hint=document.createElement('div');hint.id='region-hint';hint.setAttribute('role','status');hint.textContent=strings.regionInstructions??'Select a region. Arrows move; Shift+Arrows resize; Enter confirms; Escape cancels.'
    document.body.append(hint);paintRegions();if(fixedLayout)fixedLayout.focus();else view.renderer.focusView()
}
function cancelRegion(){if(!regionSelection)return;regionSelection=null;document.querySelector('#region-hint')?.remove();paintRegions()}
function regionPopoverRect(mark,doc){
    const range=doc.createRange();range.selectNode(mark)
    const rect=selectionRect(range,doc)
    // A full image region can leave no side large enough for a native popover.
    // Anchor its editor to the visible center; persistent geometry stays intact.
    return {x:rect.x+rect.width/2,y:rect.y+rect.height/2,width:1,height:1}
}
function confirmRegion(){
    const state=regionSelection;if(!state)return
    const region=normalizedRegion(state.rect).slice(),part=getContents(view).find(x=>x.index===state.index),mark=part?.doc.querySelector('[data-region-selection]')
    const rect=regionPopoverRect(mark??part.doc.querySelector('img'),part.doc),anchor=comicAnchor(view.book,state.index,{region})
    cancelRegion();selection=null;emit('regionSelected',{anchor,text:'',reference:`${strings.page} ${state.index+1}`,rect})
}
function regionKey(event){
    if(!['Escape','Enter','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return false
    event.preventDefault();event.stopPropagation()
    if(event.key==='Escape'){cancelRegion();return true}
    if(event.key==='Enter'){confirmRegion();return true}
    const rect=regionSelection.rect,step=event.ctrlKey ? .001 : .01,axis=['ArrowLeft','ArrowRight'].includes(event.key)?0:1,delta=['ArrowLeft','ArrowUp'].includes(event.key)?-step:step
    if(event.shiftKey)rect[axis+2]=Math.max(.001,Math.min(1-rect[axis],rect[axis+2]+delta))
    else rect[axis]=Math.max(0,Math.min(1-rect[axis+2],rect[axis]+delta))
    paintRegions();return true
}
function paintRegions(){
    if(!isComic()||!view)return
    for(const {doc,index} of getContents(view)){
        if(!doc?.body)continue
        doc.querySelectorAll('[data-region-id],[data-region-selection]').forEach(x=>x.remove())
        const img=doc.querySelector('img');if(!img)continue
        img.style.cursor=regionSelection?'crosshair':'grab'
        const items=annotations.filter(a=>a.annotationKind==='region'&&a.anchor?.page===index&&a.anchor.pageId===view.book.sections[index]?.pageId)
        if(regionSelection?.index===index)items.push({id:null,anchor:{region:regionSelection.rect},color:'blue'})
        for(const annotation of items){
            const [x,y,w,h]=annotation.anchor.region,mark=doc.createElement(annotation.id?'button':'div')
            if(annotation.id){mark.dataset.regionId=annotation.id;mark.setAttribute('aria-label',strings.regionNote??'Region note')}else mark.dataset.regionSelection='true'
            Object.assign(mark.style,{position:'absolute',boxSizing:'border-box',left:`${img.offsetLeft+x*img.clientWidth}px`,top:`${img.offsetTop+y*img.clientHeight}px`,width:`${w*img.clientWidth}px`,height:`${h*img.clientHeight}px`,border:`3px solid ${colors[annotation.color]??colors.yellow}`,background:'transparent',padding:'0',pointerEvents:annotation.id&&!regionSelection?'auto':'none'})
            mark.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();if(mark.dataset.regionDragged&&event.detail!==0)return;emit('annotation',{id:annotation.id,rect:regionPopoverRect(mark,doc)})});doc.body.append(mark)
        }
    }
}
async function mountFoliate(book,config){
    book.transformTarget?.addEventListener('data', e=>{
        if (/xhtml|html|svg/.test(e.detail.type)) e.detail.data=Promise.resolve(e.detail.data).then(async value=>safeDocument(typeof value==='string'?value:await value.text()))
    })
    view=document.createElement('foliate-view');content.className='';content.replaceChildren(view)
    fixedLayout=book.rendition?.layout==='pre-paginated'
        ?new FixedLayoutIntegration(view,book,fixedContents,reportFixedLocation,configureFixedRenderer):null
    fixedLayout?.prepare(config.appearance??{},config.anchor?.page??config.anchor?.index??0)
    view.history.addEventListener('index-change',reportNavigation)
    view.addEventListener('load',({detail:{doc,index}})=>{
        doc.addEventListener('pointerdown',userNavigation,{passive:true})
        doc.addEventListener('wheel',userNavigation,{passive:true})
        doc.addEventListener('touchstart',userNavigation,{passive:true})
        if(typography.fontFamily){
            const font=localFont,owner=view
            protectSpecializedFonts(doc).disabled=!!prefs.publisher
            applyFontFamily(doc,prefs.publisher?null:font.family)
            installLocalFont(doc,font,()=>owner===view&&font===localFont).then(async installed=>{
                if(!installed||owner!==view||font!==localFont||prefs.publisher)return
                await doc.fonts.ready
                if(font===localFont&&getContents(view).some(x=>x.doc===doc)){
                    view.renderer.render?.()
                    await paintEpub()
                }
            }).catch(error=>emit('navigationError',{message:String(error)}))
        }
        if(isComic()){fixedContents.set(doc,{index});setupComicPage(doc,index);return}
        if(view.isFixedLayout){
            const overlayer=new Overlayer();fixedContents.set(doc,{index,overlayer})
            doc.documentElement.append(overlayer.element)
            const observer=new ResizeObserver(()=>overlayer.redraw());observer.observe(doc.documentElement)
            doc.fonts?.ready?.then(()=>paintEpub());requestAnimationFrame(()=>paintEpub())
        }
        doc.addEventListener('selectionchange',()=>{
            if(typographyWork.active&&typographyWork.canRestore(typographyWork.active))return
            const s=doc.getSelection(),expected=programmaticSelections.get(doc),range=s?.rangeCount?s.getRangeAt(0):null
            const programmatic=expected&&range&&range.startContainer===expected.startContainer&&range.startOffset===expected.startOffset&&range.endContainer===expected.endContainer&&range.endOffset===expected.endOffset
            programmaticSelections.delete(doc)
            reportEpubSelection(doc,index,!programmatic)
        })
        doc.addEventListener('click',e=>{
            if(!doc.getSelection()?.isCollapsed)return
            const part=getContents(view).find(x=>x.doc===doc),[cfi,range]=part?.overlayer?.hitTest({x:e.clientX,y:e.clientY})??[]
            if(cfi&&cfi!=='busybooks-speaking')emit('annotation',{cfi,rect:selectionRect(range,doc)})
        })
        doc.body?.setAttribute('tabindex','0');doc.addEventListener('keydown',keys)
        doc.addEventListener('dblclick',e=>{
            if(e.target.tagName?.toLowerCase()==='img'){
                const dialog=document.createElement('dialog'),img=document.createElement('img')
                img.src=e.target.src;img.alt=e.target.alt;dialog.append(img);dialog.addEventListener('close',()=>dialog.remove());dialog.addEventListener('click',()=>dialog.close());document.body.append(dialog);dialog.showModal()
            }
        })
    })
    view.addEventListener('relocate',({detail:d})=>{
        if(fixedLayout?.busy)return
        const index=view.resolveCFI(d.cfi)?.index??0
        currentRange=d.range
        if(isComic()){
            reportLocation({anchor:comicAnchor(book,index),progress:(index+1)/book.sections.length,reference:`${strings.page} ${index+1}`,text:'',noText:true})
            book.releaseExcept(new Set(getContents(view).map(x=>x.index)))
            paintRegions();return
        }
        reportEpubLocation({printPage:d.pageItem?.label,tocHref:d.tocItem?.href,tocId:d.tocItem?.id==null?null:`outline:${d.tocItem.id}`,anchor:textAnchor(d.cfi,index),progress:d.fraction??0,chapter:d.tocItem?.label??'',reference:d.pageItem?.label?`${strings.printPage} ${d.pageItem.label}`:[d.tocItem?.label,`${Math.round((d.fraction??0)*1000)/10}%`].filter(Boolean).join(' · '),text:d.range?.toString()??getContents(view).find(x=>x.index===index)?.doc?.body?.innerText??'',screenPage:d.location?.current,totalScreens:d.location?.total})
    })
    view.addEventListener('external-link',e=>{e.preventDefault();emit('external',{url:e.detail.href_})})
    view.addEventListener('link',e=>{
        userNavigation();emit('navigationJump');remember()
        const a=e.detail.a,type=a.getAttributeNS('http://www.idpf.org/2007/ops','type')??a.getAttribute('epub:type')??''
        if(type.split(/\s+/).includes('noteref')||a.getAttribute('role')==='doc-noteref'){
            e.preventDefault();showFootnote(e.detail.href,location.anchor?.index??0,null,a).catch(error=>emit('navigationError',{message:String(error)}))
        }else if(fixedLayout){
            e.preventDefault()
            queueNavigation(async()=>{await gotoEpub({href:e.detail.href});remember()}).catch(error=>emit('navigationError',{message:String(error)}))
        }
    })
    view.addEventListener('create-overlay',()=>paintEpub())
    view.addEventListener('draw-annotation',({detail:{draw,annotation}})=>draw(Overlayer.highlight,{color:colors[annotation.color]??colors.yellow}))
    await view.open(book)
    fixedLayout?.style()
    typography=view.isFixedLayout?noTypography:reflowableTypography
    emit('metadata',{title:book.metadata?.title,author:book.metadata?.author,fixed:view.isFixedLayout,typography,...(isComic()?{pages:book.sections.length,labels:book.sections.map((_,i)=>String(i+1))}:{})})
    await applyAppearance(config.appearance??{})
    if(isComic()&&config.anchor?.pageId&&book.sections[config.anchor.page]?.pageId!==config.anchor.pageId)throw Error('Saved comic page identity does not match')
    const saved=isComic()?{index:config.anchor?.page??0}:config.anchor?.cfi?epubNavigation(config.anchor):null
    if(fixedLayout){
        const target=saved??(config.anchor?.cfi?epubNavigation(config.anchor):{index:0})
        await fixedLayout.goTo(target)
    }
    else if(saved&&!saved.anchor){await view.renderer.goTo(saved);view.history.pushState(saved.index)}
    else await view.init({lastLocation:config.anchor?.cfi,showTextStart:!config.anchor?.cfi})
    if(!getContents(view).some(({doc})=>doc?.documentElement&&!doc.querySelector('parsererror')))
        throw book.takeLoadError?.()??Error('Publication did not produce a readable first document')
    await applyAppearance(config.appearance??{})
    annotations=config.annotations??annotations;await paintEpub()
    if(fixedLayout)remember()
    if(isComic()){await verifyComicPage();restoreComicPosition(config.anchor);paintRegions()}
    const owner=session;requestAnimationFrame(()=>setTimeout(()=>enrichEpubOutline(book,owner).catch(error=>{if(owner===session&&view?.book===book)emit('metadata',{outlineFailed:true});emit('diagnostic',{stage:'outline',message:'Publication outline unavailable'})}),0))
}
async function showFootnote(href,sourceIndex,selectedCFI,sourceLink=null){
    const epoch=++noteGeneration,publication=view,ownerSession=session
    for(const old of document.querySelectorAll('dialog.footnote[open]'))old.close()
    const resolved=await view.resolveNavigation(href),section=view.book.sections[resolved.index]
    const original=await section.createDocument()
    const doc=new DOMParser().parseFromString(safeDocument(new XMLSerializer().serializeToString(original)),'application/xhtml+xml')
    if(epoch!==noteGeneration)return
    const target=resolved.anchor(doc),node=target instanceof Range?target.commonAncestorContainer:target
    if(!node?.nodeType)throw Error('Footnote target is unavailable')
    const dialog=document.createElement('dialog'),urls=[];dialog.className='footnote';dialog.setAttribute('aria-label',strings.footnote??'')
    const root=node.nodeType===Node.TEXT_NODE?node.parentElement:node,article=document.createElement('article'),clone=document.importNode(root,true)
    const originals=new WeakMap(),copies=new WeakMap()
    function map(from,to){originals.set(to,from);copies.set(from,to);for(let i=0;i<from.childNodes.length;i++)map(from.childNodes[i],to.childNodes[i])}
    map(root,clone);clone.removeAttribute('hidden')
    const rootStyle=document.createElement('span').style
    rootStyle.cssText=clone.getAttribute('style')??'';rootStyle.removeProperty('display');clone.setAttribute('style',rootStyle.cssText)
    article.append(clone);article.dir=doc.documentElement.dir||view.book.dir||'ltr';article.lang=doc.documentElement.lang||view.language?.canonical||'';dialog.append(article)
    await styleFootnote(dialog)
    function toCopy(range){const result=document.createRange(),start=copies.get(range.startContainer),end=copies.get(range.endContainer);if(!start||!end)return null;result.setStart(start,range.startOffset);result.setEnd(end,range.endOffset);return result}
    const overlayer=new Overlayer();overlayer.element.style.position='fixed';dialog.append(overlayer.element)
    const state={dialog,doc,index:resolved.index,overlayer,toCopy,drawn:new Set()}
    function changed(){
        const s=document.getSelection();if(!s?.rangeCount||s.isCollapsed){if(selection?.note){selection=null;emit('selection',{anchor:null,text:''})}return}
        const range=s.getRangeAt(0);if(!article.contains(range.commonAncestorContainer))return
        const mapped=doc.createRange(),start=originals.get(range.startContainer),end=originals.get(range.endContainer)
        mapped.setStart(start??root,start?range.startOffset:0);mapped.setEnd(end??root,end?range.endOffset:root.childNodes.length)
        const progress=view.getProgressOf(resolved.index,mapped)
        selected({note:true,text:s.toString(),anchor:textAnchor(view.getCFI(resolved.index,mapped),resolved.index),reference:progress.pageItem?.label?`${strings.printPage} ${progress.pageItem.label}`:progress.tocItem?.label??location.reference??''},range)
    }
    document.addEventListener('selectionchange',changed)
    dialog.addEventListener('scroll',()=>overlayer.redraw(),{passive:true})
    const observer=new ResizeObserver(()=>overlayer.redraw());observer.observe(article)
    dialog.addEventListener('click',e=>{if(!document.getSelection()?.isCollapsed)return;const[cfi,range]=overlayer.hitTest({x:e.clientX,y:e.clientY});if(cfi&&cfi!=='busybooks-speaking')emit('annotation',{cfi,rect:selectionRect(range)})})
    for(const img of article.querySelectorAll('img[src]')){
        const path=section.resolveHref(img.getAttribute('src'));img.removeAttribute('srcset')
        if(view.book.isExternal(path)){img.removeAttribute('src');continue}
        const blob=await view.book.loadBlob(path,view.book.resourceTypes?.get(path))
        if(blob){const url=URL.createObjectURL(blob);urls.push(url);img.src=url}
    }
    const close=()=>{observer.disconnect();document.removeEventListener('selectionchange',changed);if(noteView===state)noteView=null;if(selection?.note){selection=null;emit('selection',{anchor:null,text:''})}for(const url of urls)URL.revokeObjectURL(url);dialog.remove()}
    dialog.addEventListener('close',close);dialog.addEventListener('cancel',close)
    dialog.addEventListener('click',async e=>{
        const a=e.target.closest('a[href]')
        if(!a){if(e.target===dialog)dialog.close();return}
        e.preventDefault();dialog.close()
        const href=section.resolveHref(a.getAttribute('href')),type=a.getAttributeNS('http://www.idpf.org/2007/ops','type')??a.getAttribute('epub:type')??''
        if(type.split(/\s+/).includes('backlink')||a.getAttribute('role')==='doc-backlink')return
        if(publication!==view||ownerSession!==session||epoch!==noteGeneration)return
        if(publication.book.isExternal(href)){emit('external',{url:href});return}
        try{
            await followFootnoteLink(href,sourceIndex,sourceLink,publication,epoch,ownerSession)
        }
        catch(error){emit('navigationError',{message:String(error)})}
    })
    if(epoch!==noteGeneration){close();return}
    document.body.append(dialog);dialog.showModal();noteView=state;await paintNote()
    if(selectedCFI){const resolved=await view.resolveNavigation(selectedCFI),range=toCopy(resolved.anchor(doc));if(range){suppressSelectionUntil=performance.now()+600;const s=document.getSelection();s.removeAllRanges();s.addRange(range)}}
}
async function followFootnoteLink(href,sourceIndex,sourceLink,publication,epoch,ownerSession){
    const current=()=>publication===view&&ownerSession===session&&epoch===noteGeneration
    if(!current())return
    const target=await publication.resolveNavigation(href)
    if(!current())return
    if(sourceLink&&target?.index===sourceIndex){
        const destination=target.anchor?.(sourceLink.ownerDocument)
        if(destination===sourceLink||destination===sourceLink.parentElement&&destination?.localName==='sup')return
    }
    const navigate=async()=>{
        if(!current())return
        userNavigation();emit('navigationJump');remember()
        if(fixedLayout?.view===publication){
            await gotoEpub({href})
            if(current())remember()
        }else await publication.goTo(href)
    }
    if(fixedLayout?.view===publication)await queueNavigation(navigate)
    else await navigate()
}
async function paintNote(){
    const state=noteView;if(!state)return
    for(const cfi of state.drawn)state.overlayer.remove(cfi);state.drawn.clear()
    for(const a of [...annotations,...(spokenAnchor?.cfi?[{anchor:spokenAnchor,color:'speech'}]:[])]){if(!a.anchor?.cfi||a.annotationKind==='bookmark'||a.anchor.index!=null&&a.anchor.index!==state.index)continue
        const resolved=await view.resolveNavigation(a.anchor.cfi);if(noteView!==state)return
        if(resolved.index!==state.index)continue
        const range=state.toCopy(resolved.anchor(state.doc));if(range){const key=a.color==='speech'?'busybooks-speaking':a.anchor.cfi;state.overlayer.add(key,range,a.color==='speech'?Overlayer.underline:Overlayer.highlight,{color:a.color==='speech'?cssColor(chrome.accent):colors[a.color]??colors.yellow});state.drawn.add(key)}
    }
}
function epubNavigation(anchor){
    if(activeFormat==='fb2'&&(anchor.kind!=='fb2'||anchor.version!==1||view.book.sections[anchor.index]?.identity!==anchor.section))throw Error('FB2 locator section does not match this book')
    const parsed=CFI.parse(anchor.cfi),resolved=view.resolveNavigation(anchor.cfi)
    // The engine emits section-only CFIs for fixed pages without a text range.
    // Such a durable location has no in-document range for CFI.toRange().
    return (parsed.parent??parsed).length>1?resolved:{index:anchor.index??resolved.index}
}
async function gotoEpub(anchor){
    view.book?.takeLoadError?.()
    if(isComic()){if(anchor.pageId&&view.book.sections[anchor.page]?.pageId!==anchor.pageId)throw Error('Comic page identity does not match');await fixedLayout.goTo({index:anchor.page??anchor.index??Number(anchor.href)},{preferences:prefs});await verifyComicPage();restoreComicPosition(anchor);paintRegions();return}
    const target=anchor.cfi??anchor.href??(anchor.fraction!=null?{fraction:anchor.fraction}:anchor.index)
    if(!anchor.cfi){
        if(fixedLayout){await fixedLayout.goTo(await view.resolveNavigation(target),{preferences:prefs});return}
        const resolved=await view.goTo(target);if(!resolved)throw view.book?.takeLoadError?.()??Error(strings.navigationInterrupted);return
    }
    const resolved=epubNavigation(anchor)
    if(!resolved.anchor){
        if(fixedLayout)await fixedLayout.goTo(resolved,{preferences:prefs})
        else if(!await view.goTo(resolved.index))throw view.book?.takeLoadError?.()??Error(strings.navigationInterrupted)
        return
    }
    const original=await view.book.sections[resolved.index].createDocument()
    const doc=new DOMParser().parseFromString(safeDocument(new XMLSerializer().serializeToString(original)),'application/xhtml+xml'),range=resolved.anchor(doc)
    let node=range.startContainer.nodeType===Node.ELEMENT_NODE?range.startContainer:range.startContainer.parentElement
    for(;node;node=node.parentElement){const type=node.getAttributeNS('http://www.idpf.org/2007/ops','type')??node.getAttribute('epub:type')??'',role=node.getAttribute('role')
        if(type.split(/\s+/).some(x=>x==='footnote'||x==='endnote')||role==='doc-footnote'||role==='doc-endnote'){
            const note=doc.createRange();note.selectNodeContents(node);await showFootnote(view.getCFI(resolved.index,note),location.anchor?.index??0,target);return
        }
    }
    suppressSelectionUntil=performance.now()+600
    if(fixedLayout)await fixedLayout.goTo(resolved,{select:true,preferences:prefs});else{
        await view.select(target)
        const failure=view.book?.takeLoadError?.();if(failure)throw failure
    }
    // Returning from a note can leave the same range selected in its original
    // iframe, so the browser emits no new selectionchange. Synchronize native
    // actions and text assistance without opening a selection popover.
    const selectedDocument=getContents(view).find(part=>part.index===resolved.index)?.doc
    if(selectedDocument)reportEpubSelection(selectedDocument,resolved.index,false)
}
async function paintEpub(){
    if(!view)return
    if(isComic()){paintRegions();return}
    for(const a of annotations)if(a.anchor?.cfi&&a.annotationKind!=='bookmark'){
        if(fixedLayout){
            const resolved=await view.resolveNavigation(a.anchor.cfi)
            const part=getContents(view).find(part=>part.index===resolved?.index)
            if(part?.overlayer){part.overlayer.remove(a.anchor.cfi);part.overlayer.add(a.anchor.cfi,resolved.anchor(part.doc),Overlayer.highlight,{color:colors[a.color]??colors.yellow})}
        }else await view.addAnnotation({value:a.anchor.cfi,color:a.color})
    }
    await paintSpeaking()
}
async function paintSpeaking(){
    if(view){
        for(const part of getContents(view)){
            part.overlayer?.remove('busybooks-speaking')
            if(!spokenAnchor?.cfi)continue
            const resolved=await view.resolveNavigation(spokenAnchor.cfi)
            if(resolved.index===part.index){const range=resolved.anchor(part.doc);part.overlayer?.add('busybooks-speaking',range,Overlayer.underline,{color:cssColor(chrome.accent),width:3,writingMode:getComputedStyle(part.doc.documentElement).writingMode})}
        }
    }else paintPdf()
    if(noteView)await paintNote()
}
async function styleFootnote(dialog){
    if(!typography.fontFamily&&!typography.textMetrics)return
    const font=localFont,appearance=prefs,owner=view,current=()=>font===localFont&&appearance===prefs&&owner===view
    if(typography.fontFamily&&!await installLocalFont(document,font,current))return false
    if(!current())return false
    let style=dialog.querySelector('style[data-busybooks-typography]')
    if(!style){style=document.createElement('style');style.setAttribute('data-busybooks-typography','');dialog.append(style)}
    style.textContent=typographyCSS(appearance,font.family,'.footnote article',typography)
    if(typography.fontFamily)applyFontFamily(dialog.querySelector('article'),appearance.publisher?null:font.family)
    return true
}
function css(p) {
    const dark=p.color==='dark'||p.color==='system'&&p.systemDark
    const bg=dark?'#202124':p.color==='sepia'?'#f4ecd8':'#ffffff', fg=dark?'#eeeeec':'#242424'
    // Canvas follows the resolved application surface; publication artwork is
    // never inverted in response to application theme changes.
    document.body.style.setProperty('--book-bg',bg);document.body.style.setProperty('--book-foreground',fg)
    document.body.style.setProperty('--page-bg','#ffffff')
    document.body.style.setProperty('--page-tint',p.color==='dark'?'invert(1) hue-rotate(180deg)':p.color==='sepia'?'sepia(.3)':'none')
    // Foliate installs these styles before emitting section load. Family is
    // applied only through controlled properties AFTER specialist capture, so
    // the load handler always measures the publication's original families.
    return `:root,body{color-scheme:${dark?'dark':'light'};background:${bg}!important;color:${fg}!important;--overlayer-highlight-opacity:.3}${typographyCSS(p,localFont.family,'',{...typography,fontFamily:false})}img,svg{max-width:100%}::selection{background:${cssColor(chrome.selection??0x663584e4)}}`
}
async function applyAppearance(p,restoring=null){
    if(isComic())captureComicLocation()
    const owner=view,previousWork=typographyWork.active,work=typographyWork.begin(location.anchor),original=location
    work.selections=restoring?.selections??(previousWork?.navigation===work.navigation?previousWork.selections:captureEpubSelections())
    work.previous=restoring??previousWork?.previous??{prefs,localFont,fontSignature}
    const next={...prefs,...p}
    if(next.color==='system'&&next.systemDark===undefined)next.systemDark=matchMedia('(prefers-color-scheme: dark)').matches
    const signature=JSON.stringify([next.publisher,next.resolvedFont])
    const font=restoring?.localFont??(typography.fontFamily&&signature!==fontSignature?(next.publisher?{family:'serif',faces:[]}:createLocalFont(next.resolvedFont)):localFont)
    const current=()=>owner===view&&typographyWork.current(work)
    try{
        if(typography.fontFamily){
            const docs=(getContents(view)??[]).map(part=>part.doc)
            if(noteView)docs.push(document)
            await Promise.all(docs.map(doc=>prepareLocalFont(doc,font)))
            if(!current())return false
        }
        prefs=next;localFont=font;fontSignature=signature
        if(view){
            if(fixedLayout){
                const index=work.anchor?.page??work.anchor?.index??fixedLayout.activeIndex
                const target=work.anchor?.cfi?epubNavigation(work.anchor):{index}
                await fixedLayout.goTo(target,{preferences:prefs})
                if(!current())return false
            }
            const r=view.renderer
            view.style.setProperty('--page-tint',isComic()?'none':p.color==='dark'?'invert(1) hue-rotate(180deg)':p.color==='sepia'?'sepia(.3)':'none')
            r.setAttribute('gap',`${Math.min(30,((p.margin??32)*2/Math.max(1,content.clientWidth))*100)}%`);r.setAttribute('flow',p.flow??'paginated');r.setAttribute('margin',`${p.margin??32}px`)
            r.setAttribute('max-inline-size',`${p.width??720}px`);r.setAttribute('max-column-count',p.spread?'2':'1')
            r.setAttribute('zoom',p.zoom??'fit-page')
            if(typography.fontFamily||typography.textMetrics){
                for(const {doc} of getContents(view)){
                    if(typography.fontFamily){
                        const protectedStyle=protectSpecializedFonts(doc)
                        protectedStyle.disabled=!!p.publisher
                        applyFontFamily(doc,p.publisher?null:font.family)
                        await installLocalFont(doc,font,current)
                    }
                    if(!current())return false
                }
                r.setStyles?.(css(prefs))
                for(const {doc} of getContents(view)){
                    // FontFace readiness plus FontFaceSet.ready includes the
                    // document layout that consumes the new fonts. Force style
                    // evaluation before reading the current ready promise.
                    doc.documentElement.getBoundingClientRect()
                    await doc.fonts.ready
                    if(!current())return false
                }
                // Foliate's public render() expands columns synchronously.
                // renderer.goTo awaits anchor layout/scroll without history.pushState.
                r.render?.()
            }else css(prefs)
            if(isComic()&&work.anchor?.page!=null)restoreComicPosition(work.anchor)
            if(!fixedLayout&&typographyWork.canRestore(work)&&work.anchor?.cfi)await r.goTo(epubNavigation(work.anchor))
            if(!current())return false
            for(const dialog of document.querySelectorAll('dialog.footnote[open]'))await styleFootnote(dialog)
            if(!current())return false
            await paintEpub()
            if(!current())return false
            restoreEpubSelections(work)
            if(typographyWork.canRestore(work)&&lastEpubRelocation&&work.anchor){
                const settled={...lastEpubRelocation,anchor:work.anchor,progress:original.progress}
                pinnedTypographyLocation={view,anchor:work.anchor,progress:original.progress}
                typographyWork.finish(work);reportLocation(settled)
            }
        }else if(pdf){css(prefs);await relayoutPdf(work.anchor);if(!current())return false}
        return true
    }finally{typographyWork.finish(work)}
}
async function cancelAppearance(){
    const work=typographyWork.active
    if(!work)return true
    const previous={...work.previous,...(typographyWork.canRestore(work)?{selections:work.selections}:{})}
    typographyWork.finish(work)
    // Restore the last settled snapshot. Its faces are already prepared, and
    // restoration captures the current logical passage after any navigation.
    return applyAppearance(previous.prefs,previous)
}

async function openPdf(config){
    content.className='pdf'
    pdf=await pdfjs.getDocument({data:new Uint8Array(await (await fetch('publication')).arrayBuffer()),isEvalSupported:false,enableXfa:false,cMapUrl:new URL('./vendor/pdfjs/cmaps/',import.meta.url).href,cMapPacked:true,standardFontDataUrl:new URL('./vendor/pdfjs/standard_fonts/',import.meta.url).href,wasmUrl:new URL('./vendor/pdfjs/wasm/',import.meta.url).href,iccUrl:new URL('./vendor/pdfjs/iccs/',import.meta.url).href}).promise
    labels=Array.from({length:pdf.numPages},(_,i)=>String(i+1))
    // Labels are optional and must not precede the required visible passage.
    // Get the saved passage onto the screen before optional metadata, a full
    // outline traversal or a second render of the cover. Large publications and
    // malformed optional entries must not hold first-page readiness hostage.
    const details={pages:pdf.numPages,labels,fixed:true}
    emit('metadata',details)
    annotations=config.annotations??annotations;prefs=config.appearance??{};css(prefs)
    let layout=relayoutPdf(config.anchor??{page:0,y:0}),usable=await layout
    while(!usable&&pdfLayout&&pdfLayout!==layout){layout=pdfLayout;usable=await layout}
    if(!usable)return false
    content.addEventListener('scroll',()=>{
        if(layingOut)return
        const y=content.scrollTop, page=pages.findIndex(p=>p.element.offsetTop+p.element.offsetHeight>y+content.clientHeight*.25)
        if(page>=0){const p=pages[page];reportLocation({anchor:pdfAnchor(page,Math.max(0,(y-p.element.offsetTop)/p.element.offsetHeight)),progress:(page+1)/pdf.numPages,chapter:'',tocHref:pdfTocHref(page),tocId:pdfTocId(pdfAnchor(page,Math.max(0,(y-p.element.offsetTop)/p.element.offsetHeight))),reference:pdfReference(page),text:p.text??'',noText:p.text!=null&&!p.text.trim()})}
    },{passive:true})
    document.addEventListener('selectionchange',pdfSelection)
    document.addEventListener('click',e=>{
        if(!document.getSelection()?.isCollapsed)return
        for(const p of pages)for(const mark of p.element.querySelectorAll('.annotation-mark[data-id]')){
            const r=mark.getBoundingClientRect();if(e.clientX>=r.left&&e.clientX<=r.right&&e.clientY>=r.top&&e.clientY<=r.bottom)
                emit('annotation',{id:mark.dataset.id,rect:{x:r.x,y:r.y,width:r.width,height:r.height}})
        }
    })
    requestAnimationFrame(()=>setTimeout(()=>enrichPdf(details,config.generateCover!==false),0))
}
async function enrichPdf(details,generateCover){
    const optional=(stage,work)=>work().catch(error=>{if(stage==='outline')emit('metadata',{outlineFailed:true});emit('diagnostic',{stage,message:'Optional publication metadata unavailable'})})
    await Promise.all([
        optional('labels',async()=>{const value=await pdf.getPageLabels();if(value){labels=value;details.labels=value;emit('metadata',details)}}),
        optional('metadata',async()=>{const {info={}}=await pdf.getMetadata();Object.assign(details,{title:info.Title,author:info.Author,language:info.Lang});emit('metadata',details)}),
        optional('outline',enrichPdfOutline),
        ...(generateCover?[optional('cover',async()=>{
            const page=await pdf.getPage(1),viewport=page.getViewport({scale:160/page.getViewport({scale:1}).width}),canvas=document.createElement('canvas')
            canvas.width=viewport.width;canvas.height=Math.min(1000,viewport.height)
            await page.render({canvasContext:canvas.getContext('2d'),viewport,intent:'print'}).promise
            details.cover=canvas.toDataURL();emit('metadata',details)
        })]:[]),
    ])
}
async function enrichPdfOutline(){
            const owner=session,publication=pdf,revision=++outlineRevision
            const sources=[],pending=(await publication.getOutline()??[]).map(item=>({item,depth:0})).reverse()
            while(pending.length){const {item,depth}=pending.pop();if(sources.length>=100000)throw Error('Outline exceeds its record limit')
                sources.push({item,depth});for(let i=(item.items?.length??0)-1;i>=0;i--)pending.push({item:item.items[i],depth:depth+1})}
            const toc=sources.map(({item,depth},i)=>({id:`outline:${i}`,label:item.title??'',href:'',depth}))
            if(owner!==session||pdf!==publication)return
            pdfToc=toc;pdfOutlinePositions.clear();publishOutline(toc,revision)
            await resolveOutline(toc,async(entry,i)=>{const dest=sources[i].item.dest;if(!dest)return null
                let position
                const anchor=await destinationAnchor(dest,value=>position=value)
                if(owner!==session||revision!==outlineRevision||pdf!==publication||!validPage(anchor.page,publication.numPages))return null
                pdfOutlinePositions.set(entry.id,position)
                return {anchor,href:String(anchor.page)}
            },revision,owner)
            if(owner===session&&(pdf??view?.book)===publication&&location.anchor?.page!=null)reportLocation({...location,tocId:pdfTocId(location.anchor),tocHref:pdfTocHref(location.anchor.page)})

}
let pdfToc=[]
const pdfOutlinePositions=new Map()
function pdfTocHref(page){return pdfToc.filter(x=>x.href!==''&&Number(x.href)<=page).at(-1)?.href}
function pdfTocId(anchor){
    const page=anchor?.page;if(!Number.isInteger(page))return null
    const viewport=pages[page]?.viewport
    const point=target=>target.point??(target.rect?[target.rect[0],target.rect[3]]:null)
    const position=(target,id)=>target.page===page&&point(target)&&viewport
        ?viewport.convertToViewportPoint(...point(target))[1]/viewport.height
        :pdfOutlinePositions.get(id)??target.y??0
    const y=position(anchor);let chosen=null
    for(const entry of pdfToc){const target=entry.anchor;if(!target)continue
        if(target.page<page||(target.page===page&&position(target,entry.id)<=y+1e-6)){
            if(!chosen||target.page>chosen.anchor.page||(target.page===chosen.anchor.page&&position(target,entry.id)>=position(chosen.anchor,chosen.id)))chosen=entry
        }
    }return chosen?.id??null
}
function pdfReference(page){return `${strings.page} ${labels[page]||page+1}` }
async function destination(dest){
    if(typeof dest==='string') dest=await pdf.getDestination(dest)
    if(!dest)throw Error('PDF destination is unavailable')
    return typeof dest[0]==='number'?dest[0]:await pdf.getPageIndex(dest[0])
}
async function destinationAnchor(dest,position){
    if(typeof dest==='string')dest=await pdf.getDestination(dest)
    const index=await destination(dest),page=await pdf.getPage(index+1),mode=dest?.[1]?.name
    let anchor={page:index,y:0}
    if(mode==='XYZ')anchor={page:index,point:[dest[2]??page.view[0],dest[3]??page.view[3]]}
    else if(mode==='FitH'||mode==='FitBH')anchor={page:index,point:[page.view[0],dest[2]??page.view[3]]}
    else if(mode==='FitV'||mode==='FitBV')anchor={page:index,point:[dest[2]??page.view[0],page.view[3]]}
    else if(mode==='FitR'){
        const rect=dest.slice(2,6)
        if(rect.length!==4||!rect.every(Number.isFinite)||rect[0]>=rect[2]||rect[1]>=rect[3])throw Error('PDF destination is unavailable')
        anchor={page:index,rect}
    }
    if(anchor.point&&!anchor.point.every(n=>Number.isFinite(n)&&Math.abs(n)<=10000000))throw Error('PDF destination is unavailable')
    if(anchor.rect&&!anchor.rect.every(n=>Number.isFinite(n)&&Math.abs(n)<=10000000))throw Error('PDF destination is unavailable')
    if(position){const viewport=page.getViewport({scale:1}),point=anchor.point??(anchor.rect?[anchor.rect[0],anchor.rect[3]]:null)
        position(point?viewport.convertToViewportPoint(...point)[1]/viewport.height:anchor.y??0)}
    return anchor
}
function pdfAnchor(index,y=0){
    const p=pages[index],point=p.viewport?.convertToPdfPoint(Math.max(0,content.scrollLeft-p.element.offsetLeft),Math.max(0,y)*p.element.offsetHeight)
    return {page:index,ref:p.ref,y, ...(point?{point}:{})}
}
let observer, layoutGeneration=0, pdfNavigationGeneration=0, renderRunning=0
const renderQueue=[],renderTasks=new Set(),geometry=new Map()
function stopRendering(){
    for(const task of renderTasks)task.cancel()
    renderTasks.clear()
    for(const queued of renderQueue.splice(0))queued.resolve(false)
}
function queuePage(index,epoch=layoutGeneration){
    const data=pages[index];if(!data||data.epoch!==epoch)return Promise.resolve(false)
    if(data.rendering)return data.rendering
    data.rendering=new Promise((resolve,reject)=>{renderQueue.push({index,epoch,resolve,reject,data});pumpPages()})
    return data.rendering
}
async function pumpPages(){
    if(renderRunning>=2||!renderQueue.length)return
    const job=renderQueue.shift();renderRunning++
    try{await renderPage(job.index,job.epoch);job.resolve(job.epoch===layoutGeneration)}
    catch(error){
        job.data.rendering=null;job.data.element.replaceChildren?.()
        if(error?.name==='RenderingCancelledException'||job.epoch!==layoutGeneration)job.resolve(false)
        else job.reject(error)
    }
    finally{renderRunning--;pumpPages();trimPages()}
    pumpPages()
}
function trimPages(){
    const current=location.anchor?.page??0,range=document.getSelection()?.rangeCount?document.getSelection().getRangeAt(0):null
    for(let i=0;i<pages.length;i++){
        const p=pages[i]
        if(i===navigatingPage||Math.abs(i-current)<=4||!p.element.childNodes.length||range?.intersectsNode(p.element))continue
        p.element.replaceChildren();p.rendering=null;p.text=null;geometry.get(i)?.cleanup()
    }
}
let pdfLayout,pdfViewport
function relayoutPdf(anchor){return pdfLayout=layoutPdf(anchor)}
async function layoutPdf(anchor){
    const epoch=++layoutGeneration;layingOut=true;navigatingPage=anchor?.page??0
    try{
        stopRendering();observer?.disconnect();content.replaceChildren();pages=[]
        const initial=await pdf.getPage((anchor?.page??0)+1)
        if(epoch!==layoutGeneration)return false
        geometry.set(initial.pageNumber-1,initial)
        const fallback=initial.getViewport({scale:1,rotation:(initial.rotate+(prefs.rotation??0))%360})
        content.style.display=prefs.spread?'flex':'block';content.style.flexWrap='wrap';content.style.alignContent='start';content.style.justifyContent='center'
        for(let i=0;i<pdf.numPages;i++){
            const known=geometry.get(i)
            const base=known?.getViewport({scale:1,rotation:(known.rotate+(prefs.rotation??0))%360})??fallback
            const scale=fitScale(base.width,base.height,content.clientWidth,content.clientHeight,prefs.zoom,prefs.spread)
            const el=document.createElement('section');el.className='pdf-page';el.tabIndex=0;el.setAttribute('aria-label',pdfReference(i));el.style.width=`${base.width*scale}px`;el.style.height=`${base.height*scale}px`;el.dataset.index=i
            if(prefs.flow!=='scrolled'&&i!==(anchor?.page??0)&&!(prefs.spread&&i===(anchor?.page??0)+1))el.hidden=true
            content.append(el);pages.push({element:el,scale,epoch})
        }
        observer=new IntersectionObserver(entries=>{for(const e of entries)if(e.isIntersecting)queuePage(Number(e.target.dataset.index),epoch).catch(error=>{if(epoch===layoutGeneration)emit('navigationError',{message:String(error)})})},{root:content,rootMargin:'400px'})
        for(const p of pages)observer.observe(p.element)
        const rendered=await queuePage(anchor?.page??0,epoch)
        if(!rendered||epoch!==layoutGeneration)return false
        const positioned=await gotoPdf(anchor??{page:0},epoch);return positioned!==false&&epoch===layoutGeneration
    }finally{if(epoch===layoutGeneration){layingOut=false;pdfViewport=[content.clientWidth,content.clientHeight]}}
}
async function renderPage(index,epoch){
    const data=pages[index];if(!data||data.epoch!==epoch)return
    const page=await pdf.getPage(index+1);if(epoch!==layoutGeneration)return
    geometry.set(index,page);data.ref=page.ref
    const base=page.getViewport({scale:1,rotation:(page.rotate+(prefs.rotation??0))%360})
    data.scale=fitScale(base.width,base.height,content.clientWidth,content.clientHeight,prefs.zoom,prefs.spread)
    const viewport=page.getViewport({scale:data.scale,rotation:(page.rotate+(prefs.rotation??0))%360});data.viewport=viewport
    const el=data.element
    // Correcting an estimated placeholder above the viewport must not move the
    // current passage. Every page is fitted against its own rotated geometry.
    const current=pages[location.anchor?.page],before=current?.element.offsetTop
    el.style.width=`${viewport.width}px`;el.style.height=`${viewport.height}px`
    if(before!=null)content.scrollTop+=current.element.offsetTop-before
    const canvas=document.createElement('canvas'),ratio=Math.min(2,window.devicePixelRatio||1,Math.sqrt(16777216/(viewport.width*viewport.height)),8192/Math.max(viewport.width,viewport.height))
    canvas.width=Math.ceil(viewport.width*ratio);canvas.height=Math.ceil(viewport.height*ratio);el.append(canvas)
    const task=page.render({canvasContext:canvas.getContext('2d'),viewport,transform:[ratio,0,0,ratio,0,0]});renderTasks.add(task)
    try{await task.promise}finally{renderTasks.delete(task)}
    if(epoch!==layoutGeneration)return
    const text=await page.getTextContent();if(epoch!==layoutGeneration)return
    data.text=pdfText(text.items).text
    const layer=document.createElement('div');layer.className='textLayer';layer.style.setProperty('--scale-factor',data.scale);layer.style.setProperty('--total-scale-factor',data.scale);el.append(layer)
    const textTask=new pdfjs.TextLayer({textContentSource:text,container:layer,viewport});renderTasks.add(textTask)
    try{await textTask.render()}finally{renderTasks.delete(textTask)}
    if(epoch!==layoutGeneration)return
    const links=await page.getAnnotations();if(epoch!==layoutGeneration)return
    for(const a of links)if(a.subtype==='Link'){
        const box=viewport.convertToViewportRectangle(a.rect),link=document.createElement('a');link.href='#';link.className='pdf-link';link.tabIndex=0;link.setAttribute('aria-label',a.url??(a.dest?strings.page:''))
        Object.assign(link.style,{left:`${Math.min(box[0],box[2])}px`,top:`${Math.min(box[1],box[3])}px`,width:`${Math.abs(box[2]-box[0])}px`,height:`${Math.abs(box[3]-box[1])}px`})
        link.addEventListener('click',async e=>{
            e.preventDefault()
            try{
                if(a.url)emit('external',{url:a.url})
                else {emit('navigationJump');await queueNavigation(async()=>{userNavigation();remember();await gotoPdf(await destinationAnchor(a.dest));remember()})}
            }catch(error){emit('navigationError',{message:String(error)})}
        })
        el.append(link)
    }
    if(location.anchor?.page===index)emit('pageText',{page:index,noText:!data.text.trim(),text:data.text})
    paintPdf()
}
async function gotoPdf(anchor,epoch=layoutGeneration){
    const index=typeof anchor==='number'?anchor:anchor.page
    if(!validPage(index,pdf.numPages)){emit('navigationError',{message:strings.invalidPage});return false}
    const navigation=++pdfNavigationGeneration,current=()=>navigation===pdfNavigationGeneration&&epoch===layoutGeneration
    navigatingPage=index
    let rendered;try{rendered=await queuePage(index,epoch)}catch(error){if(current())navigatingPage=null;throw error}
    if(!current())return false
    if(!rendered){navigatingPage=null;return false}const p=pages[index];if(!p){navigatingPage=null;return false}
    if(prefs.flow!=='scrolled')for(let i=0;i<pages.length;i++)pages[i].element.hidden=i!==index&&!(prefs.spread&&i===index+1)
    const pdfPoint=anchor.point??(anchor.rect?[anchor.rect[0],anchor.rect[3]]:null)
    const point=pdfPoint&&p.viewport?p.viewport.convertToViewportPoint(...pdfPoint):null
    const top=point?point[1]:(anchor.y??0)*p.element.offsetHeight
    // Persisted anchors include y and describe the viewport origin. Explicit
    // document destinations retain their reading inset.
    content.scrollLeft=point?Math.max(0,p.element.offsetLeft+point[0]-(anchor.y==null?content.clientWidth*.25:0)):0
    content.scrollTop=p.element.offsetTop+Math.max(0,top)
    suppressSelectionUntil=performance.now()+600
    if(anchor.textOffset!=null)selectPdfText(index,anchor.textOffset,anchor.textLength??1)
    else if(anchor.segments?.length)selectPdfText(index,anchor.segments[0].start,anchor.segments[0].length??anchor.segments[0].text?.length??1)
    reportLocation({anchor:pdfAnchor(index,Math.max(0,content.scrollTop-p.element.offsetTop)/p.element.offsetHeight),progress:(index+1)/pdf.numPages,reference:pdfReference(index),text:p.text??'',chapter:'',tocHref:pdfTocHref(index),tocId:pdfTocId(anchor),noText:p.text!=null&&!p.text.trim()});navigatingPage=null;return true
}
function pdfText(items){
    let text='',offset=0;const positions=[]
    for(const item of items){const str=item.str??'';for(let i=0;i<str.length;i++){text+=str[i];positions.push(offset+i)}offset+=str.length;if(item.hasEOL){text+=' ';positions.push(offset)}}
    positions.push(offset);return {text,positions}
}
function selectPdfText(index,start,length){
    const layer=pages[index]?.element.querySelector('.textLayer');if(!layer)return
    const walker=document.createTreeWalker(layer,NodeFilter.SHOW_TEXT),range=document.createRange();let node,offset=0,found=false
    while((node=walker.nextNode())){
        const end=offset+node.textContent.length
        if(!found&&start<=end){range.setStart(node,Math.max(0,start-offset));found=true}
        if(found&&start+length<=end){range.setEnd(node,Math.max(0,start+length-offset));break}offset=end
    }
    if(found){const selected=document.getSelection();selected.removeAllRanges();selected.addRange(range);const rect=range.getBoundingClientRect();content.scrollTop+=rect.top-content.getBoundingClientRect().top-content.clientHeight*.35}
}
function pdfSelection(){
    const s=document.getSelection();if(!s?.rangeCount||s.isCollapsed){selection=null;emit('selection',{text:'',anchor:null});return}
    const r=s.getRangeAt(0),segments=[]
    for(let i=0;i<pages.length;i++){
        const p=pages[i],layer=p.element.querySelector('.textLayer');if(!layer||!r.intersectsNode(layer))continue
        const all=document.createRange();all.selectNodeContents(layer)
        const piece=r.cloneRange();if(piece.compareBoundaryPoints(Range.START_TO_START,all)<0)piece.setStart(all.startContainer,all.startOffset)
        if(piece.compareBoundaryPoints(Range.END_TO_END,all)>0)piece.setEnd(all.endContainer,all.endOffset)
        const rect=p.element.getBoundingClientRect(),boxes=[...piece.getClientRects()].filter(x=>x.width&&x.height).map(x=>[...p.viewport.convertToPdfPoint(x.left-rect.left,x.top-rect.top),...p.viewport.convertToPdfPoint(x.right-rect.left,x.bottom-rect.top)])
        const before=all.cloneRange();before.setEnd(piece.startContainer,piece.startOffset)
        segments.push({page:i,ref:p.ref,boxes,start:before.toString().length,length:piece.toString().length})
    }
    if(!segments.length)return
    selected({text:s.toString(),anchor:{page:segments[0].page,segments},reference:pdfReference(segments[0].page),order:segments[0].page},r)
}
function paintPdf(){
    for(const p of pages)p.element.querySelectorAll('.annotation-mark').forEach(x=>x.remove())
    for(const a of [...annotations,...(spokenAnchor?[{id:'busybooks-speaking',anchor:spokenAnchor,color:'speech'}]:[])])for(const s of a.anchor?.segments??[]){const p=pages[s.page];if(!p?.viewport||!p.element.querySelector('canvas'))continue
        for(const box of s.boxes){const [x1,y1,x2,y2]=p.viewport.convertToViewportRectangle(box),mark=document.createElement('div');mark.className='annotation-mark';mark.dataset.id=a.id;mark.style.background=a.color==='speech'?'transparent':colors[a.color]??colors.yellow;if(a.color==='speech'){mark.style.borderBottom=`3px solid ${cssColor(chrome.accent)}`;mark.style.opacity='1';delete mark.dataset.id}
            Object.assign(mark.style,{left:`${Math.min(x1,x2)}px`,top:`${Math.min(y1,y2)}px`,width:`${Math.abs(x2-x1)}px`,height:`${Math.abs(y2-y1)}px`});p.element.append(mark)}
    }
}
let searchTail=Promise.resolve(),searchCommandRevision=-1,searchStartedRevision=-1
function acceptSearchCommand(queryId,starting){
    // Native method replies/evaluations can settle late after a focus handoff.
    // A cancel sent before its same-revision search cannot cancel that search
    // if delivery is delayed; closing uses a newer revision from Flutter.
    if(queryId==null)return true
    if(!Number.isSafeInteger(queryId)||queryId<0||queryId<searchCommandRevision||
        !starting&&queryId<=searchStartedRevision)return false
    searchCommandRevision=queryId
    if(starting)searchStartedRevision=queryId
    return true
}
function requestSearch(query,queryId,offset=0,limit=200){
    if(!acceptSearchCommand(queryId,true))return Promise.resolve()
    const token=++generation
    const operation=searchTail.catch(()=>{}).then(()=>token===generation?search(query,queryId,token,offset,limit):null)
    searchTail=operation;return operation
}
async function search(query,queryId,token,offset=0,limit=200){
    const sourceView=view,sourcePdf=pdf
    offset=Number.isSafeInteger(offset)&&offset>=0?offset:0
    limit=Number.isSafeInteger(limit)&&limit>0?Math.min(limit,500):200
    const current=()=>token===generation&&sourceView===view&&sourcePdf===pdf
    const result=(type,data={})=>{if(current())emit(type,{queryId,...data})}
    result('searchStart',{offset,limit})
    let batch=[],total=0
    const flush=()=>{if(batch.length){result('matches',{items:batch});batch=[]}}
    // Count every occurrence, but only materialize/transfer a bounded window.
    const match=make=>{const index=total++;if(index>=offset&&index<offset+limit){batch.push({...make(),index});if(batch.length>=100)flush()}}
    const excerpt=parts=>({excerpt:parts.pre+parts.match+parts.post,excerptParts:parts})
    try{
        if(isComic())throw Error('This image publication has no searchable text')
        if(!query){result('searchDone',{total:0,offset,limit});return}
        if(sourceView){
            // Supported publication and CFI APIs keep the application matcher
            // independent of Foliate's unchanged search implementation.
            const sections=sourceView.book.sections
            for(let index=0;index<sections.length;index++){
                if(!current())return
                const section=sections[index]
                if(section.createDocument){
                    const doc=await section.createDocument()
                    if(!current())return
                    let count=0
                    const matcher=(strings,makeRange)=>literalTextMatches(strings,query,makeRange)
                    for(const item of textWalker(doc,matcher)){
                        if(!current())return
                        match(()=>({anchor:textAnchor(sourceView.getCFI(index,item.range),index),...excerpt(item.excerptParts),reference:sourceView.getProgressOf(index,item.range).tocItem?.label??''}))
                        // A dense chapter must still yield for request cancellation.
                        if(++count%1000===0){flush();await nextFrame();if(!current())return}
                    }
                }
                flush();result('searchProgress',{progress:(index+1)/sections.length});await nextFrame()
            }
        }else if(sourcePdf)for(let i=0;i<sourcePdf.numPages;i++){
            if(!current())return
            const page=await sourcePdf.getPage(i+1),data=pdfText((await page.getTextContent()).items)
            if(!current())return
            let count=0
            for(const range of literalRanges(data.text,query)){
                match(()=>({anchor:{page:i,textOffset:data.positions[range.start],textLength:data.positions[range.end]-data.positions[range.start]},...excerpt(excerptParts(data.text,range)),reference:pdfReference(i)}))
                if(++count%1000===0){flush();await nextFrame();if(!current())return}
            }
            flush();result('searchProgress',{progress:(i+1)/sourcePdf.numPages});await nextFrame()
        }else throw Error('The publication reader is not ready')
        flush();result('searchDone',{total,offset,limit})
    }catch(error){flush();result('searchError',{message:String(error),total,offset,limit,incomplete:true})}
}
function keys(e){
    if(regionSelection&&regionKey(e))return
    if(isComic()&&!e.ctrlKey&&!e.altKey&&!e.metaKey&&['Home','End'].includes(e.key)){e.preventDefault();dispatch({action:'goto',anchor:{page:e.key==='Home'?0:view.book.sections.length-1}});return}
    if(['PageDown','PageUp','ArrowRight','ArrowLeft','ArrowUp','ArrowDown','Home','End'].includes(e.key))userNavigation()
    if(e.target?.isContentEditable||['INPUT','TEXTAREA','SELECT'].includes(e.target?.tagName))return
    if(e.key==='Escape'&&document.querySelector('dialog[open]')){e.preventDefault();[...document.querySelectorAll('dialog[open]')].at(-1).close();return}
    const modified=e.ctrlKey||e.altKey||e.metaKey
    if(document.querySelector('dialog[open]')&&!modified)return
    if(e.shiftKey&&!modified&&['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','PageUp','PageDown'].includes(e.key)){
        const doc=e.currentTarget,selected=doc.getSelection?.()??document.getSelection()
        if(!selected.rangeCount){
            if(currentRange&&currentRange.startContainer.ownerDocument===doc){const caret=currentRange.cloneRange();caret.collapse(true);selected.addRange(caret)}
            else{const visible=pdf?pages[location.anchor?.page??0]?.element.querySelector('.textLayer'):null,body=visible??doc.body??content,walker=doc.createTreeWalker(body,NodeFilter.SHOW_TEXT);const first=walker.nextNode();if(first){const caret=doc.createRange();caret.setStart(first,0);caret.collapse(true);selected.addRange(caret)}}
        }
        const style=getComputedStyle(selected.anchorNode?.parentElement??doc.documentElement),vertical=style.writingMode.startsWith('vertical')
        const inline=vertical?['ArrowUp','ArrowDown'].includes(e.key):['ArrowLeft','ArrowRight'].includes(e.key)
        const direction=e.key==='ArrowLeft'?'left':e.key==='ArrowRight'?'right':['ArrowUp','PageUp'].includes(e.key)?'backward':'forward'
        selected.modify?.('extend',direction,['PageUp','PageDown'].includes(e.key)?'paragraph':inline?'character':'line')
        e.preventDefault();return
    }
    if(!modified&&['ArrowRight','ArrowLeft','PageDown','PageUp',' '].includes(e.key)){
        e.preventDefault();emit('key',{key:e.key,control:false,alt:false,shift:e.shiftKey,meta:false})
    } else if(modified||/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(e.key)||e.key==='Escape'||e.key==='Tab'){
        if(e.key==='Tab'){
            if(document.querySelector('dialog[open]'))return
            e.preventDefault()
            const doc=e.currentTarget,frame=doc.defaultView?.frameElement,origin=frame?.getBoundingClientRect(),sx=origin&&frame.clientWidth?origin.width/frame.clientWidth:1,sy=origin&&frame.clientHeight?origin.height/frame.clientHeight:1
            const items=[...doc.querySelectorAll('a[href],[tabindex]:not([tabindex="-1"]),button:not([disabled])')].filter(el=>{
                if(el===doc.body||el===content)return false
                const r=el.getBoundingClientRect(),left=(origin?.left??0)+r.left*sx,top=(origin?.top??0)+r.top*sy
                return r.width>0&&r.height>0&&left+r.width*sx>0&&top+r.height*sy>0&&left<content.clientWidth&&top<content.clientHeight
            })
            const target=tabTarget(items,doc.activeElement,e.shiftKey)
            if(target)target.focus({preventScroll:true});else emit('focusChrome',{backwards:e.shiftKey});return
        }
        if(e.ctrlKey&&!e.shiftKey&&!e.altKey&&!e.metaKey&&['c','a'].includes(e.key.toLowerCase()))return
        e.preventDefault();emit('key',{key:e.key,control:e.ctrlKey,alt:e.altKey,shift:e.shiftKey,meta:e.metaKey})
    }
}
document.addEventListener('keydown',keys)
content.addEventListener('pointerdown',userNavigation,{passive:true})
content.addEventListener('wheel',userNavigation,{passive:true})
content.addEventListener('touchstart',userNavigation,{passive:true})
new ResizeObserver(()=>{if(pdf){clearTimeout(window.pdfResizeTimer);window.pdfResizeTimer=setTimeout(()=>queueNavigation(async()=>{
    // Layout itself changes scrollbars. Only rebuild for a new settled viewport,
    // and let earlier navigation finish before capturing its current anchor.
    if(pdfViewport?.[0]===content.clientWidth&&pdfViewport?.[1]===content.clientHeight)return
    await relayoutPdf(location.anchor)
}).catch(error=>emit('navigationError',{message:String(error)})),150)}}).observe(content)
function emitPassage(request,ignoreSelection=false){
    if(isComic()){emit('passage',{request,text:'',anchor:location.anchor,reference:location.reference,selected:false});return}
        let passage=ignoreSelection?null:selection
        if(!passage&&view){const index=view.resolveCFI(location.anchor.cfi)?.index??0;let range=currentRange;if(!range){const doc=getContents(view).find(x=>x.index===index)?.doc;if(doc){range=doc.createRange();range.selectNodeContents(doc.body??doc.documentElement)}}if(range)passage={text:range.toString(),anchor:textAnchor(view.getCFI(index,range),index),reference:location.reference}}
        if(!passage&&pdf){const index=location.anchor?.page??0,p=pages[index],layer=p?.element.querySelector('.textLayer');if(layer){
            const rect=p.element.getBoundingClientRect(),top=Math.max(rect.top,content.getBoundingClientRect().top),spans=[...layer.querySelectorAll('span')].filter(s=>s.getBoundingClientRect().bottom>=top),text=spans.map(s=>s.textContent).join(' '),boxes=spans.map(s=>s.getBoundingClientRect()).map(r=>[...p.viewport.convertToPdfPoint(r.left-rect.left,r.top-rect.top),...p.viewport.convertToPdfPoint(r.right-rect.left,r.bottom-rect.top)])
            passage={text,anchor:{page:index,segments:[{page:index,boxes,start:0,length:text.length}]},reference:location.reference}
        }}
    emit('passage',{...(passage??{text:location.text??'',anchor:location.anchor,reference:location.reference}),request,selected:!ignoreSelection&&selection!=null})
}
function queueNavigation(operation){
    const work=navigationTail.catch(()=>{}).then(operation);navigationTail=work;return work
}
async function dispatch(c){
    if(c.session!=null&&c.session!==session)return
    try{c=receiveCommand(c);if(!c)return}catch(error){emit('bridgeError',{direction:'command',message:String(error)});return}
    if((isComic()||fixedLayout||activeFormat==='pdf')&&['goto','back','forward','next','previous','advanceSpeech','appearance','cancelAppearance','flush'].includes(c.action)){
        return queueNavigation(()=>dispatchCommand(c))
    }
    return dispatchCommand(c)
}
async function dispatchCommand(c){
    if(c.session!=null&&c.session!==session)return
    try{
    if(['goto','back','forward','next','previous','advanceSpeech'].includes(c.action)){cancelRegion();userNavigation();noteGeneration++;for(const dialog of document.querySelectorAll('dialog[open]'))dialog.close()}
    switch(c.action){
    case 'open':await annotationOperation;cacheFailureReported=false;activeFormat=c.format;annotations=c.annotations??annotations;typography=noTypography;theme(c.chrome??{});strings=c.labels??{};content.className='loading';content.textContent=strings.loadingBook??'';content.setAttribute('aria-busy','true');content.setAttribute('aria-label',c.title??'');prefs=c.appearance??{};if(c.format==='pdf'){if(await openPdf(c)===false)return}else if(['epub','fb2','cbz','cbr'].includes(c.format))await openFoliate(c);else throw Error('Unsupported publication format');content.removeAttribute('aria-busy');emit('opened',{typography});break
    case 'beginRegion':beginRegion();break
    case 'chrome':theme(c.value);break
    case 'cancelAppearance':{
        const operation=cancelAppearance();appearanceOperation=operation.then(()=>true,()=>false)
        await operation;break
    }
    case 'appearance':{
        // The adapter rejects unsupported typography even if a caller bypasses
        // the shared controller. Fixed documents never install local FontFaces.
        if(!view&&!pdf)throw Error('Reader is unavailable')
        validateTypographyUpdate(c.value,typography)
        // Dispatch owns error feedback; flush only drains the latest layout task.
        const operation=applyAppearance(c.value);appearanceOperation=operation.then(()=>true,()=>false)
        const applied=await operation
        if(c.request!=null)emit('appearanceResult',{request:c.request,...(!applied?{cancelled:true,message:'Appearance change cancelled'}:{})})
        break
    }
    case 'speaking':spokenAnchor=c.anchor;await paintSpeaking();break
    case 'next':if(fixedLayout){const shown=fixedLayout.visibleContents().map(part=>part.index);await gotoEpub(isComic()?{page:Math.min(view.book.sections.length-1,Math.max(fixedLayout.activeIndex,...shown)+1)}:{index:Math.min(view.book.sections.length-1,Math.max(fixedLayout.activeIndex,...shown)+1)})}else if(view)await view.next();else await gotoPdf({page:Math.min(pdf.numPages-1,(location.anchor?.page??0)+(prefs.spread?2:1))});break
    case 'previous':if(fixedLayout){const shown=fixedLayout.visibleContents().map(part=>part.index),index=Math.max(0,Math.min(fixedLayout.activeIndex,...shown)-1);await gotoEpub(isComic()?{page:index}:{index})}else if(view)await view.prev();else await gotoPdf({page:Math.max(0,(location.anchor?.page??0)-(prefs.spread?2:1))});break
    case 'goto':{const owner=session;remember();if(view){await gotoEpub(c.anchor);if(fixedLayout)remember();}else {const usable=await gotoPdf(c.anchor);if(usable===false)throw Error(strings.navigationInterrupted);remember()}if(c.request!=null&&owner===session)emit('navigationResult',{request:c.request});break}
    case 'back':if(fixedLayout){if(historyIndex>0){const target=historyIndex-1;await gotoEpub(history[target]);historyIndex=target;reportNavigation()}}else if(view)view.history.back();else if(historyIndex>0){historyIndex--;await gotoPdf(history[historyIndex])}break
    case 'forward':if(fixedLayout){if(historyIndex<history.length-1){const target=historyIndex+1;await gotoEpub(history[target]);historyIndex=target;reportNavigation()}}else if(view)view.history.forward();else if(historyIndex<history.length-1){historyIndex++;await gotoPdf(history[historyIndex])}break
    case 'search':await requestSearch(c.query,c.queryId,c.offset,c.limit);break
    case 'cancelSearch':if(acceptSearchCommand(c.queryId,false)){generation++;view?.clearSearch()}break
    case 'annotations':await receiveAnnotations(c);break
    case 'passage':emitPassage(c.request);break
    case 'advanceSpeech':if(fixedLayout)await gotoEpub({index:(location.anchor?.index??0)+1});else if(view)await view.next();else await gotoPdf({page:(location.anchor?.page??0)+1});emitPassage(c.request,true);break
    case 'focus':if(fixedLayout)fixedLayout.focus();else if(view)view.renderer.focusView();else content.focus();break
    case 'outline':if(view)await enrichEpubOutline(view.book,session);else if(pdf)await enrichPdfOutline().catch(()=>emit('metadata',{outlineFailed:true}));break
    case 'thumbnailWindow':setThumbnailWindow(c.pages,c.request);break
    case 'thumbnail':if((pdf||isComic())&&validPage(c.page,pdf?.numPages??view.book.sections.length))queueThumbnail(c.page,c.request);break
    case 'flush':await appearanceOperation;await annotationOperation;if(isComic())captureComicLocation();else if(pdf&&location.anchor?.page!=null){const index=location.anchor.page,p=pages[index];if(p)location={...location,anchor:pdfAnchor(index,Math.max(0,content.scrollTop-p.element.offsetTop)/p.element.offsetHeight)}}emit('location',location);emit('flushed',{request:c.request});break
    }}catch(e){if(isComic()&&view?.book?.releaseExcept)view.book.releaseExcept(new Set(getContents(view).map(x=>x.index)));if(c.action==='appearance'){if(c.request!=null)emit('appearanceResult',{request:c.request,message:String(e)});else emit('navigationError',{message:String(e)});return}if(c.action==='goto'&&c.request!=null)emit('navigationResult',{request:c.request,message:String(e)});if(e.cacheFailureReported||c.action==='open'&&cacheFailureReported)return;emit(['goto','back','forward','next','previous','advanceSpeech'].includes(c.action)?'navigationError':'error',{message:String(e),cacheFailure:c.action==='open'&&c.format!=='pdf'})}
}
const thumbnails=[],thumbnailPending=new Map(),thumbnailTasks=new Map();let thumbnailRunning=0,thumbnailEpoch=0,thumbnailRequest=0
function setThumbnailWindow(indices,request){
    thumbnailEpoch++;thumbnailRequest=request
    for(const task of thumbnailTasks.values())task.cancel();thumbnailTasks.clear();thumbnails.length=0;thumbnailPending.clear()
    for(const index of (Array.isArray(indices)?indices:[]).slice(0,12))if((pdf||isComic())&&validPage(index,pdf?.numPages??view.book.sections.length))queueThumbnail(index,request)
}
function queueThumbnail(index,request){
    if(request!==thumbnailRequest||thumbnailPending.has(index)||thumbnails.length>=12)return
    const job={index,request,epoch:thumbnailEpoch,publication:pdf??view?.book,owner:session};thumbnailPending.set(index,job);thumbnails.push(job);pumpThumbnails()
}
async function pumpThumbnails(){
    if(thumbnailRunning>=2||!thumbnails.length)return
    const job=thumbnails.shift(),{index,request,epoch,publication,owner}=job;thumbnailRunning++
    const owned=()=>owner===session&&epoch===thumbnailEpoch&&(pdf??view?.book)===publication
    const current=()=>owned()&&!job.cancelled
    let canvas,timer,cancel
    const aborted=new Promise(resolve=>{cancel=resolve})
    const controller=new AbortController()
    const work={task:null,cancel:()=>{job.cancelled=true;cancel();controller.abort();work.task?.cancel()}}
    thumbnailTasks.set(job,work)
    const render=async()=>{if(!current())return
        if(publication.comic){
            const data=await (await fetch('book/'+publication.sections[index].pageId,{signal:controller.signal})).blob();if(!current())return
            const decoded=await decodeComicImage(data,controller.signal)
            try{if(!current())return;canvas=document.createElement('canvas');const scale=Math.min(240/decoded.width,320/decoded.height);canvas.width=Math.max(1,Math.floor(decoded.width*scale));canvas.height=Math.max(1,Math.floor(decoded.height*scale));canvas.getContext('2d').drawImage(decoded.image,0,0,canvas.width,canvas.height);if(current())emit('thumbnail',{page:index,request,data:canvas.toDataURL(),width:canvas.width,height:canvas.height})}finally{decoded.release()}
            return
        }
        const page=await publication.getPage(index+1);if(!current())return
        const base=page.getViewport({scale:1}),viewport=page.getViewport({scale:Math.min(240/base.width,320/base.height)})
        canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.floor(viewport.width));canvas.height=Math.max(1,Math.floor(viewport.height))
        work.task=page.render({canvasContext:canvas.getContext('2d'),viewport});await work.task.promise
        if(current())emit('thumbnail',{page:index,request,data:canvas.toDataURL(),width:canvas.width,height:canvas.height})
    }
    try{await Promise.race([render(),aborted,new Promise((_,reject)=>{
        timer=setTimeout(()=>{reject(Error('Page preview timed out'));job.cancelled=true;controller.abort();work.task?.cancel()},20000)
    })])}
    catch(error){if(owned()&&error?.name!=='RenderingCancelledException')emit('thumbnailError',{page:index,request,message:String(error)})}
    finally{clearTimeout(timer);if(canvas){canvas.width=0;canvas.height=0}thumbnailTasks.delete(job);if(thumbnailPending.get(index)===job)thumbnailPending.delete(index);thumbnailRunning--;pumpThumbnails()}
    pumpThumbnails()
}
window.busybooks={dispatch,contents:()=>getContents(view)};emit('ready')

// Application appearance is resolved in Flutter, including system changes.

window.addEventListener?.('pagehide',()=>{generation++;thumbnailEpoch++;for(const task of thumbnailTasks.values())task.cancel();cancelRegion();view?.close();view?.book?.destroy?.();pdf?.destroy()},{once:true})
