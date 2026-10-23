// BusyBooks content adapter. Application UI, persistence and commands stay in Flutter.
import './vendor/foliate/view.js'
import { fitScale, validPage, cssColor, tabTarget } from './reading_geometry.mjs'
import { noTypography, reflowableTypography, createLocalFont, prepareLocalFont, installLocalFont, typographyCSS, protectSpecializedFonts, applyFontFamily, validateTypographyUpdate, TypographyWork } from './typography.mjs'
import * as CFI from './vendor/foliate/epubcfi.js'
import { EPUB } from './vendor/foliate/epub.js'
import { Overlayer } from './vendor/foliate/overlayer.js'
import * as pdfjs from './vendor/pdfjs/pdf.mjs'
pdfjs.GlobalWorkerOptions.workerSrc = new URL('./vendor/pdfjs/pdf.worker.mjs', import.meta.url).href
const content = document.querySelector('#content')
const session = new URL(window.location.href).searchParams.get('session') ?? 'probe'
const emit = (type, data = {}) => {
    const json = JSON.stringify({ type, session, ...data })
    if (window.webkit?.messageHandlers?.busybooks) window.webkit.messageHandlers.busybooks.postMessage(json)
    else window.chrome?.webview?.postMessage(json)
    if (window.busybooksProbe) window.busybooksProbe({type,session,...data})
}
let strings={}, chrome={}, spokenAnchor=null, currentRange=null, view, pdf, prefs = {}, location = {}, selection = null, annotations = [], pages = [], labels = []
const fixedContents=new WeakMap()
let noteView=null,noteGeneration=0
let typography=noTypography,localFont={family:'serif',faces:[]},fontSignature='',lastEpubRelocation=null,pinnedTypographyLocation=null
const typographyWork=new TypographyWork()
let appearanceOperation=Promise.resolve(),programmaticSelections=new WeakMap()
function userNavigation(){typographyWork.navigate();pinnedTypographyLocation=null;programmaticSelections=new WeakMap()}
function reportEpubLocation(data){
    lastEpubRelocation=data
    if(typographyWork.active&&typographyWork.canRestore(typographyWork.active))return
    const pin=pinnedTypographyLocation
    reportLocation(pin&&pin.view===view?{...data,anchor:pin.anchor,progress:pin.progress}:data)
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
    if(!book.pageList?.length){emit('metadata',{tocUpdates:[],outlineRevision:revision,tocResolved:true});return}
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
        if(!(fragment instanceof Range))range.selectNodeContents(fragment)
        range.collapse(true)
        const page=publication.getProgressOf(resolved.index,range).pageItem
        return page?.label?{pageLabel:page.label}:null
    },revision,owner)
}
function reportLocation(data) {
    location = data
    emit('location', data)
    reportNavigation()
}
function reportNavigation(){
    const index=location.anchor?.page??location.anchor?.index??0
    const shown=view?.isFixedLayout&&prefs.spread?Math.max(index,...view.renderer.getContents().map(x=>x.index??index)):index
    emit('navigation',{speechNext:view?(view.isFixedLayout?index<view.book.sections.length-1:!view.renderer.atEnd):index<(pdf?.numPages??0)-1,back:view?view.history.canGoBack:historyIndex>0,forward:view?view.history.canGoForward:historyIndex<history.length-1,previous:view?(view.isFixedLayout?index>0:!view.renderer.atStart):index>0,next:view?(view.isFixedLayout?shown<view.book.sections.length-1:!view.renderer.atEnd):index+(prefs.spread?1:0)<(pdf?.numPages??0)-1})
}
function remember() {
    if (historyIndex < 0 || JSON.stringify(history[historyIndex]) !== JSON.stringify(location.anchor)) {
        history.splice(historyIndex+1);history.push(structuredClone(location.anchor));historyIndex = history.length-1
    }
    reportNavigation()
}
function safeDocument(data) {
    // Book documents are never script-capable application contexts. CSP also blocks
    // network requests; sanitize before EPUB resources become Blob URLs.
    const doc = new DOMParser().parseFromString(data,'application/xhtml+xml')
    if (doc.querySelector('parsererror')) throw Error('Invalid EPUB XHTML')
    for (const el of doc.querySelectorAll('script,iframe,object,embed,form,base,meta[http-equiv],link[rel="preload"],link[rel="modulepreload"]')) el.remove()
    for (const el of doc.querySelectorAll('*')) for (const attr of [...el.attributes]) {
        if (/^on/i.test(attr.name) || /^(?:javascript|vbscript):/i.test(attr.value.trim())) el.removeAttribute(attr.name)
    }
    return new XMLSerializer().serializeToString(doc)
}
function reportEpubSelection(doc,index,settle=true){
    const s=doc.getSelection();if(!s?.rangeCount||s.isCollapsed){selection=null;emit('selection',{text:'',anchor:null});return}
    const range=s.getRangeAt(0),progress=view.getProgressOf(index,range)
    selected({text:s.toString(),anchor:{cfi:view.getCFI(index,range),index},reference:progress.pageItem?.label?`${strings.printPage} ${progress.pageItem.label}`:progress.tocItem?.label??location.reference??'',order:index},range,doc,settle)
}
function captureEpubSelections(){
    return (view?.renderer.getContents()??[]).flatMap(({doc,index})=>{
        const s=doc?.getSelection();return s?.rangeCount&&!s.isCollapsed?[{doc,index,range:s.getRangeAt(0).cloneRange(),anchor:s.anchorNode,anchorOffset:s.anchorOffset,focus:s.focusNode,focusOffset:s.focusOffset}]:[]
    })
}
function restoreEpubSelections(work){
    if(!typographyWork.canRestore(work))return
    for(const saved of work.selections??[]){
        if(!view.renderer.getContents().some(part=>part.doc===saved.doc)||!saved.range.startContainer.isConnected)continue
        programmaticSelections.set(saved.doc,saved.range)
        const s=saved.doc.getSelection()
        // Selection mutation does not request native/WebView focus.
        s.setBaseAndExtent(saved.anchor,saved.anchorOffset,saved.focus,saved.focusOffset)
        reportEpubSelection(saved.doc,saved.index,false)
    }
}
async function openEpub(config) {
    const index=await (await fetch('book-index')).json(),sizes=index.resources
    const resource=name=>'book/'+sizes[name].file
    const load=async name=>!Object.hasOwn(sizes,name)?null:await (await fetch(resource(name))).arrayBuffer()
    const loadText=async name=>{
        const buffer=await load(name);if(buffer==null)return null
        const data=new Uint8Array(buffer)
        return new TextDecoder(data[0]===255&&data[1]===254?'utf-16le':data[0]===254&&data[1]===255?'utf-16be':'utf-8').decode(data)
    }
    const book=await new EPUB({loadText,loadBlob:async(name,type)=>{const buffer=await load(name);return buffer==null?null:new Blob([buffer],{type})},getSize:name=>sizes[name]?.size??0}).init()
    // Search, CFI resolution and the rendered publication use the same safe
    // DOM structure. Removing active book elements must not shift search anchors.
    for(const section of book.sections){
        if(!section.createDocument)continue
        const create=section.createDocument
        section.createDocument=async()=>new DOMParser().parseFromString(safeDocument(new XMLSerializer().serializeToString(await create())),'application/xhtml+xml')
    }
    book.transformTarget?.addEventListener('data', e=>{
        if (/xhtml|html|svg/.test(e.detail.type)) e.detail.data=Promise.resolve(e.detail.data).then(async value=>safeDocument(typeof value==='string'?value:await value.text()))
    })
    view=document.createElement('foliate-view');content.className='';content.replaceChildren(view)
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
                if(font===localFont&&view.renderer.getContents().some(x=>x.doc===doc)){
                    view.renderer.render?.()
                    await paintEpub()
                }
            }).catch(error=>emit('navigationError',{message:String(error)}))
        }
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
            const part=view.renderer.getContents().find(x=>x.doc===doc),[cfi,range]=part?.overlayer?.hitTest({x:e.clientX,y:e.clientY})??[]
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
        const index=view.resolveCFI(d.cfi)?.index??0
        currentRange=d.range
        reportEpubLocation({printPage:d.pageItem?.label,tocHref:d.tocItem?.href,tocId:d.tocItem?.id==null?null:`outline:${d.tocItem.id}`,anchor:{cfi:d.cfi,index},progress:d.fraction??0,chapter:d.tocItem?.label??'',reference:d.pageItem?.label?`${strings.printPage} ${d.pageItem.label}`:[d.tocItem?.label,`${Math.round((d.fraction??0)*1000)/10}%`].filter(Boolean).join(' · '),text:d.range?.toString()??view.renderer.getContents().find(x=>x.index===index)?.doc?.body?.innerText??'',screenPage:d.location?.current,totalScreens:d.location?.total})
    })
    view.addEventListener('external-link',e=>{e.preventDefault();emit('external',{url:e.detail.href_})})
    view.addEventListener('link',e=>{
        userNavigation();emit('navigationJump');remember()
        const a=e.detail.a,type=a.getAttributeNS('http://www.idpf.org/2007/ops','type')??a.getAttribute('epub:type')??''
        if(type.split(/\s+/).includes('noteref')){
            e.preventDefault();showFootnote(e.detail.href,location.anchor?.index??0).catch(error=>emit('navigationError',{message:String(error)}))
        }
    })
    view.addEventListener('create-overlay',()=>paintEpub())
    view.addEventListener('draw-annotation',({detail:{draw,annotation}})=>draw(Overlayer.highlight,{color:colors[annotation.color]??colors.yellow}))
    await view.open(book)
    if(view.isFixedLayout){
        const getContents=view.renderer.getContents.bind(view.renderer)
        view.renderer.getContents=()=>getContents().map(x=>({...x,...fixedContents.get(x.doc)}))
    }
    typography=view.isFixedLayout?noTypography:reflowableTypography
    emit('metadata',{title:book.metadata?.title,author:book.metadata?.author,fixed:view.isFixedLayout,typography})
    await applyAppearance(config.appearance??{})
    const saved=config.anchor?.cfi?epubNavigation(config.anchor):null
    if(saved&&!saved.anchor){await view.renderer.goTo(saved);view.history.pushState(saved.index)}
    else await view.init({lastLocation:config.anchor?.cfi,showTextStart:!config.anchor?.cfi})
    await applyAppearance(config.appearance??{})
    annotations=config.annotations??[];await paintEpub()
    const owner=session;requestAnimationFrame(()=>setTimeout(()=>enrichEpubOutline(book,owner).catch(error=>{if(owner===session&&view?.book===book)emit('metadata',{outlineFailed:true});emit('diagnostic',{stage:'outline',message:'Publication outline unavailable'})}),0))
}
async function showFootnote(href,sourceIndex,selectedCFI){
    const epoch=++noteGeneration
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
    map(root,clone);clone.removeAttribute('hidden');clone.style.removeProperty('display')
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
        selected({note:true,text:s.toString(),anchor:{cfi:view.getCFI(resolved.index,mapped),index:resolved.index},reference:progress.pageItem?.label?`${strings.printPage} ${progress.pageItem.label}`:progress.tocItem?.label??location.reference??''},range)
    }
    document.addEventListener('selectionchange',changed)
    dialog.addEventListener('scroll',()=>overlayer.redraw(),{passive:true})
    const observer=new ResizeObserver(()=>overlayer.redraw());observer.observe(article)
    dialog.addEventListener('click',e=>{if(!document.getSelection()?.isCollapsed)return;const[cfi,range]=overlayer.hitTest({x:e.clientX,y:e.clientY});if(cfi&&cfi!=='busybooks-speaking')emit('annotation',{cfi,rect:selectionRect(range)})})
    for(const img of article.querySelectorAll('img[src]')){
        const path=section.resolveHref(img.getAttribute('src'));img.removeAttribute('srcset')
        if(view.book.isExternal(path)){img.removeAttribute('src');continue}
        const blob=await view.book.loadBlob(path,view.book.resources.getItemByHref(path)?.mediaType)
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
        if(view.book.isExternal(href)){emit('external',{url:href});return}
        // Backlinks to the referring section close the note at the exact
        // original passage; cross-references elsewhere remain navigable.
        try{const target=await view.resolveNavigation(href);if(target.index!==sourceIndex){emit('navigationJump');remember();await view.goTo(href)}}
        catch(error){emit('navigationError',{message:String(error)})}
    })
    if(epoch!==noteGeneration){close();return}
    document.body.append(dialog);dialog.showModal();noteView=state;await paintNote()
    if(selectedCFI){const resolved=await view.resolveNavigation(selectedCFI),range=toCopy(resolved.anchor(doc));if(range){suppressSelectionUntil=performance.now()+600;const s=document.getSelection();s.removeAllRanges();s.addRange(range)}}
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
    const parsed=CFI.parse(anchor.cfi),resolved=view.resolveNavigation(anchor.cfi)
    // The engine emits section-only CFIs for fixed pages without a text range.
    // Such a durable location has no in-document range for CFI.toRange().
    return (parsed.parent??parsed).length>1?resolved:{index:anchor.index??resolved.index}
}
async function gotoEpub(anchor){
    const target=anchor.cfi??anchor.href??(anchor.fraction!=null?{fraction:anchor.fraction}:anchor.index)
    if(!anchor.cfi){const resolved=await view.goTo(target);if(!resolved)throw Error(strings.navigationInterrupted);return}
    const resolved=epubNavigation(anchor)
    if(!resolved.anchor){await view.goTo(resolved.index);return}
    const original=await view.book.sections[resolved.index].createDocument()
    const doc=new DOMParser().parseFromString(safeDocument(new XMLSerializer().serializeToString(original)),'application/xhtml+xml'),range=resolved.anchor(doc)
    let node=range.startContainer.nodeType===Node.ELEMENT_NODE?range.startContainer:range.startContainer.parentElement
    for(;node;node=node.parentElement){const type=node.getAttributeNS('http://www.idpf.org/2007/ops','type')??node.getAttribute('epub:type')??'',role=node.getAttribute('role')
        if(type.split(/\s+/).some(x=>x==='footnote'||x==='endnote')||role==='doc-footnote'||role==='doc-endnote'){
            const note=doc.createRange();note.selectNodeContents(node);await showFootnote(view.getCFI(resolved.index,note),location.anchor?.index??0,target);return
        }
    }
    suppressSelectionUntil=performance.now()+600;await view.select(target)
}
async function paintEpub(){
    if(!view)return
    for(const a of annotations)if(a.anchor?.cfi&&a.annotationKind!=='bookmark')await view.addAnnotation({value:a.anchor.cfi,color:a.color})
    await paintSpeaking()
}
async function paintSpeaking(){
    if(view){
        for(const part of view.renderer.getContents()){
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
function bookSpread(book){return book?.rendition?.spread}
async function applyAppearance(p,restoring=null){
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
            const docs=(view?.renderer.getContents()??[]).map(part=>part.doc)
            if(noteView)docs.push(document)
            await Promise.all(docs.map(doc=>prepareLocalFont(doc,font)))
            if(!current())return false
        }
        prefs=next;localFont=font;fontSignature=signature
        if(view){
            const r=view.renderer
            view.style.setProperty('--page-tint',p.color==='dark'?'invert(1) hue-rotate(180deg)':p.color==='sepia'?'sepia(.3)':'none')
            r.setAttribute('gap',`${Math.min(30,((p.margin??32)*2/Math.max(1,content.clientWidth))*100)}%`);r.setAttribute('flow',p.flow??'paginated');r.setAttribute('margin',`${p.margin??32}px`)
            r.setAttribute('max-inline-size',`${p.width??720}px`);r.setAttribute('max-column-count',p.spread?'2':'1')
            if(view.isFixedLayout)r.spread=p.spread?(bookSpread(view.book)??'auto'):'none'
            r.setAttribute('zoom',p.zoom??'fit-page')
            if(typography.fontFamily||typography.textMetrics){
                for(const {doc} of r.getContents()){
                    if(typography.fontFamily){
                        const protectedStyle=protectSpecializedFonts(doc)
                        protectedStyle.disabled=!!p.publisher
                        applyFontFamily(doc,p.publisher?null:font.family)
                        await installLocalFont(doc,font,current)
                    }
                    if(!current())return false
                }
                r.setStyles?.(css(prefs))
                for(const {doc} of r.getContents()){
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
            if(typographyWork.canRestore(work)&&work.anchor?.cfi)await r.goTo(epubNavigation(work.anchor))
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
    annotations=config.annotations??[];prefs=config.appearance??{};css(prefs)
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
            if(owner===session&&pdf===publication&&location.anchor?.page!=null)reportLocation({...location,tocId:pdfTocId(location.anchor),tocHref:pdfTocHref(location.anchor.page)})

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
    const p=pages[index],point=p.viewport?.convertToPdfPoint(0,Math.max(0,y)*p.element.offsetHeight)
    return {page:index,ref:p.ref,y, ...(point?{point}:{})}
}
let observer, layoutGeneration=0, renderRunning=0
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
let pdfLayout
function relayoutPdf(anchor){return pdfLayout=layoutPdf(anchor)}
async function layoutPdf(anchor){
    const epoch=++layoutGeneration;layingOut=true;navigatingPage=anchor?.page??0
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
    const positioned=await gotoPdf(anchor??{page:0},epoch);layingOut=false;return positioned!==false&&epoch===layoutGeneration
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
                else {emit('navigationJump');remember();await gotoPdf(await destinationAnchor(a.dest));remember()}
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
    navigatingPage=index
    let rendered;try{rendered=await queuePage(index,epoch)}catch(error){navigatingPage=null;throw error}
    if(!rendered||epoch!==layoutGeneration){navigatingPage=null;return false}const p=pages[index];if(!p){navigatingPage=null;return false}
    if(prefs.flow!=='scrolled')for(let i=0;i<pages.length;i++)pages[i].element.hidden=i!==index&&!(prefs.spread&&i===index+1)
    const pdfPoint=anchor.point??(anchor.rect?[anchor.rect[0],anchor.rect[3]]:null)
    const point=pdfPoint&&p.viewport?p.viewport.convertToViewportPoint(...pdfPoint):null
    const top=point?point[1]:(anchor.y??0)*p.element.offsetHeight
    if(point)content.scrollLeft=Math.max(0,p.element.offsetLeft+point[0]-content.clientWidth*.25)
    content.scrollTop=p.element.offsetTop+Math.max(0,top)
    suppressSelectionUntil=performance.now()+600
    if(anchor.textOffset!=null)selectPdfText(index,anchor.textOffset,anchor.textLength??1)
    else if(anchor.segments?.length)selectPdfText(index,anchor.segments[0].start,anchor.segments[0].text.length)
    reportLocation({anchor:pdfAnchor(index,Math.max(0,content.scrollTop-p.element.offsetTop)/p.element.offsetHeight),progress:(index+1)/pdf.numPages,reference:pdfReference(index),text:p.text??'',chapter:'',tocHref:pdfTocHref(index),tocId:pdfTocId(anchor),noText:p.text!=null&&!p.text.trim()});navigatingPage=null;return true
}
function pdfText(items){
    let text='',offset=0;const positions=[]
    for(const item of items){const str=item.str??'';for(let i=0;i<str.length;i++){text+=str[i];positions.push(offset+i)}offset+=str.length;if(item.hasEOL){text+=' ';positions.push(offset)}}
    positions.push(offset);return {text,positions}
}
// Each transformed UTF-16 unit retains its complete original character range.
// Locale-independent Unicode lowercase keeps search stable across desktops.
// Expansion (e.g. İ → i + combining dot) cannot shift PDF offsets.
function pdfSearchRanges(text,query){
    const lower=text.toLowerCase(),needle=query.toLowerCase(),starts=[],ends=[]
    if(!needle)return []
    let original=0
    for(const character of text){
        const length=character.toLowerCase().length
        for(let i=0;i<length;i++){starts.push(original);ends.push(original+character.length)}
        original+=character.length
    }
    const matches=[]
    for(let at=lower.indexOf(needle);at>=0;at=lower.indexOf(needle,at+needle.length)){
        const start=starts[at],end=ends[at+needle.length-1]
        if(Number.isFinite(start)&&Number.isFinite(end))matches.push({start,end})
    }
    return matches
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
        segments.push({page:i,ref:p.ref,boxes,start:before.toString().length,text:piece.toString()})
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
let searchTail=Promise.resolve()
function requestSearch(query,queryId){
    const token=++generation
    const operation=searchTail.catch(()=>{}).then(()=>token===generation?search(query,queryId,token):null)
    searchTail=operation;return operation
}
async function search(query,queryId,token){
    emit('searchStart',{queryId})
    const result=(type,data={})=>{if(token===generation)emit(type,{queryId,...data})}
    let batch=[]
    const flush=()=>{if(batch.length){result('matches',{items:batch});batch=[]}}
    const match=value=>{batch.push(value);if(batch.length>=100)flush()}
    try{
        if(!query){result('searchDone');return}
        if(view){for await(const item of view.search({query,drawOptions:{color:cssColor(chrome.accent??0xff3584e4)}})){
            if(token!==generation)return
            if(item.subitems)for(const x of item.subitems)match({anchor:{cfi:x.cfi},excerpt:typeof x.excerpt==='string'?x.excerpt:[x.excerpt?.pre,x.excerpt?.match,x.excerpt?.post].filter(Boolean).join(''),reference:item.label})
            flush();if(item.progress)result('searchProgress',{progress:item.progress});await nextFrame()
        }}else for(let i=0;i<pdf.numPages;i++){
            if(token!==generation)return
            const page=await pdf.getPage(i+1),data=pdfText((await page.getTextContent()).items)
            if(token!==generation)return
            for(const range of pdfSearchRanges(data.text,query))match({anchor:{page:i,textOffset:data.positions[range.start],textLength:data.positions[range.end]-data.positions[range.start]},excerpt:data.text.slice(Math.max(0,range.start-60),range.end+100),reference:pdfReference(i)})
            flush();result('searchProgress',{progress:(i+1)/pdf.numPages});await nextFrame()
        }
        flush();result('searchDone')
    }catch(error){result('searchError',{message:String(error)})}finally{if(token!==generation)view?.clearSearch()}
}
function keys(e){
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
new ResizeObserver(()=>{if(pdf){clearTimeout(window.pdfResizeTimer);window.pdfResizeTimer=setTimeout(()=>relayoutPdf(location.anchor).catch(error=>emit('navigationError',{message:String(error)})),150)}}).observe(content)
function emitPassage(request,ignoreSelection=false){
        let passage=ignoreSelection?null:selection
        if(!passage&&view){const index=view.resolveCFI(location.anchor.cfi)?.index??0;let range=currentRange;if(!range){const doc=view.renderer.getContents().find(x=>x.index===index)?.doc;if(doc){range=doc.createRange();range.selectNodeContents(doc.body??doc.documentElement)}}if(range)passage={text:range.toString(),anchor:{cfi:view.getCFI(index,range),index},reference:location.reference}}
        if(!passage&&pdf){const index=location.anchor?.page??0,p=pages[index],layer=p?.element.querySelector('.textLayer');if(layer){
            const rect=p.element.getBoundingClientRect(),top=Math.max(rect.top,content.getBoundingClientRect().top),spans=[...layer.querySelectorAll('span')].filter(s=>s.getBoundingClientRect().bottom>=top),text=spans.map(s=>s.textContent).join(' '),boxes=spans.map(s=>s.getBoundingClientRect()).map(r=>[...p.viewport.convertToPdfPoint(r.left-rect.left,r.top-rect.top),...p.viewport.convertToPdfPoint(r.right-rect.left,r.bottom-rect.top)])
            passage={text,anchor:{page:index,segments:[{page:index,boxes,start:0,text}]},reference:location.reference}
        }}
    emit('passage',{...(passage??{text:location.text??'',anchor:location.anchor,reference:location.reference}),request,selected:!ignoreSelection&&selection!=null})
}
async function dispatch(c){
    if(c.session!=null&&c.session!==session)return
    try{
    if(['goto','back','forward','next','previous','advanceSpeech'].includes(c.action)){userNavigation();noteGeneration++;for(const dialog of document.querySelectorAll('dialog[open]'))dialog.close()}
    switch(c.action){
    case 'open':typography=noTypography;theme(c.chrome??{});strings=c.labels??{};content.className='loading';content.textContent=strings.loadingBook??'';content.setAttribute('aria-busy','true');content.setAttribute('aria-label',c.title??'');prefs=c.appearance??{};if(c.format==='pdf'){if(await openPdf(c)===false)return}else await openEpub(c);content.removeAttribute('aria-busy');emit('opened',{typography});break
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
    case 'next':if(view)await view.next();else await gotoPdf({page:(location.anchor?.page??0)+(prefs.spread?2:1)});break
    case 'previous':if(view)await view.prev();else await gotoPdf({page:(location.anchor?.page??0)-(prefs.spread?2:1)});break
    case 'goto':{const owner=session;remember();if(view)await gotoEpub(c.anchor);else {const usable=await gotoPdf(c.anchor);if(usable===false)throw Error(strings.navigationInterrupted);remember()}if(c.request!=null&&owner===session)emit('navigationResult',{request:c.request});break}
    case 'back':if(view)view.history.back();else if(historyIndex>0){historyIndex--;await gotoPdf(history[historyIndex])}break
    case 'forward':if(view)view.history.forward();else if(historyIndex<history.length-1){historyIndex++;await gotoPdf(history[historyIndex])}break
    case 'search':await requestSearch(c.query,c.queryId);break
    case 'cancelSearch':generation++;view?.clearSearch();break
    case 'annotations':if(view)for(const a of annotations)if(a.anchor?.cfi)view.deleteAnnotation({value:a.anchor.cfi});annotations=c.value;view?await paintEpub():paintPdf();break
    case 'passage':emitPassage(c.request);break
    case 'advanceSpeech':if(view){if(view.isFixedLayout)await view.goTo((location.anchor?.index??0)+1);else await view.next();}else await gotoPdf({page:(location.anchor?.page??0)+1});emitPassage(c.request,true);break
    case 'focus':if(view)view.renderer.focusView();else content.focus();break
    case 'outline':if(view)await enrichEpubOutline(view.book,session);else if(pdf)await enrichPdfOutline().catch(()=>emit('metadata',{outlineFailed:true}));break
    case 'thumbnailWindow':setThumbnailWindow(c.pages,c.request);break
    case 'thumbnail':if(pdf&&validPage(c.page,pdf.numPages))queueThumbnail(c.page,c.request);break
    case 'flush':await appearanceOperation;emit('location',location);emit('flushed',{request:c.request});break
    }}catch(e){if(c.action==='appearance'){if(c.request!=null)emit('appearanceResult',{request:c.request,message:String(e)});else emit('navigationError',{message:String(e)});return}if(c.action==='goto'&&c.request!=null)emit('navigationResult',{request:c.request,message:String(e)});emit(['goto','back','forward','next','previous','advanceSpeech'].includes(c.action)?'navigationError':'error',{message:String(e)})}
}
const thumbnails=[],thumbnailPending=new Map(),thumbnailTasks=new Map();let thumbnailRunning=0,thumbnailEpoch=0,thumbnailRequest=0
function setThumbnailWindow(indices,request){
    thumbnailEpoch++;thumbnailRequest=request
    for(const task of thumbnailTasks.values())task.cancel();thumbnailTasks.clear();thumbnails.length=0;thumbnailPending.clear()
    for(const index of (Array.isArray(indices)?indices:[]).slice(0,12))if(pdf&&validPage(index,pdf.numPages))queueThumbnail(index,request)
}
function queueThumbnail(index,request){
    if(request!==thumbnailRequest||thumbnailPending.has(index)||thumbnails.length>=12)return
    const job={index,request,epoch:thumbnailEpoch,publication:pdf,owner:session};thumbnailPending.set(index,job);thumbnails.push(job);pumpThumbnails()
}
async function pumpThumbnails(){
    if(thumbnailRunning>=2||!thumbnails.length)return
    const job=thumbnails.shift(),{index,request,epoch,publication,owner}=job;thumbnailRunning++
    const owned=()=>owner===session&&epoch===thumbnailEpoch&&pdf===publication
    const current=()=>owned()&&!job.cancelled
    let canvas,timer,cancel
    const aborted=new Promise(resolve=>{cancel=resolve})
    const work={task:null,cancel:()=>{job.cancelled=true;cancel();work.task?.cancel()}}
    thumbnailTasks.set(job,work)
    const render=async()=>{if(!current())return
        const page=await publication.getPage(index+1);if(!current())return
        const base=page.getViewport({scale:1}),viewport=page.getViewport({scale:Math.min(240/base.width,320/base.height)})
        canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.floor(viewport.width));canvas.height=Math.max(1,Math.floor(viewport.height))
        work.task=page.render({canvasContext:canvas.getContext('2d'),viewport});await work.task.promise
        if(current())emit('thumbnail',{page:index,request,data:canvas.toDataURL(),width:canvas.width,height:canvas.height})
    }
    try{await Promise.race([render(),aborted,new Promise((_,reject)=>{
        timer=setTimeout(()=>{reject(Error('Page preview timed out'));job.cancelled=true;work.task?.cancel()},20000)
    })])}
    catch(error){if(owned()&&error?.name!=='RenderingCancelledException')emit('thumbnailError',{page:index,request,message:String(error)})}
    finally{clearTimeout(timer);if(canvas){canvas.width=0;canvas.height=0}thumbnailTasks.delete(job);if(thumbnailPending.get(index)===job)thumbnailPending.delete(index);thumbnailRunning--;pumpThumbnails()}
    pumpThumbnails()
}
window.busybooks={dispatch};emit('ready')

// Application appearance is resolved in Flutter, including system changes.
