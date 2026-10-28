// Executed by the disposable WebKitGTK probe, never bundled with the app.
function postFormatProof(data){
    if(data.type==='formatProof')window.reviewResult=data
    const json=JSON.stringify(data)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json)
    else window.chrome.webview.postMessage(json)
}
(async()=>{
    const post=postFormatProof
    const assert=(condition,message)=>{if(!condition)throw Error(message)}
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    const events=[],checks=[],view=document.querySelector('foliate-view'),book=view.book
    window.busybooksProbe=event=>events.push(event)
    const until=async(predicate,label)=>{for(let i=0;i<200;i++){const value=predicate();if(value)return value;await wait(25)}throw Error('Timed out: '+label)}
    const dispatch=busybooks.dispatch
    let request=100
    const goto=async anchor=>{const id=++request;await dispatch({action:'goto',anchor,request:id});const reply=events.find(e=>e.type==='navigationResult'&&e.request===id);assert(reply&&!reply.message,'Navigation succeeds: '+JSON.stringify(reply))}
    const doc=index=>busybooks.contents().find(part=>part.index===index)?.doc
    if(book.comic){
        let maximum=0;const timings=[]
        const last=book.sections.length-1
        for(let i=0;i<=last;i++){
            const clock=performance.now();await goto({page:i});timings.push(performance.now()-clock)
            const image=doc(i)?.querySelector('img');assert(image?.naturalWidth>0&&image.getBoundingClientRect().width>0,'Page decoded and laid out '+i);assert(image.naturalWidth===book.sections[i].width&&image.naturalHeight===book.sections[i].height,'Oriented image dimensions match preparation '+i)
            maximum=Math.max(maximum,book.liveResources());assert(book.liveResources()<=2,'No departed page resources remain')
            if(i===9||i===59||i===last){post({type:'formatMetric',page:i,live:book.liveResources()});await wait(100)}
        }
        checks.push('all-pages-decoded','bounded-live-pages','jpeg-png-webp')
        await goto({page:Math.min(3,last)})
        const target=Math.min(3,last)
        for(const [spread,direction,zoom] of [[false,'rtl','3'],[true,'ltr','fit-width'],[true,'rtl','fit-page'],[false,'ltr','fit-page']]){
            await dispatch({action:'appearance',value:{spread,direction,zoom}})
            const recent=events.filter(e=>e.type==='location').at(-1)
            assert(recent.anchor.page===target,'Selected page stable through view changes')
            await dispatch({action:'beginRegion'})
            const page=doc(target)
            for(const [key,shift] of [['ArrowRight',false],['ArrowDown',true],['Enter',false]])page.dispatchEvent(new page.defaultView.KeyboardEvent('keydown',{key,shiftKey:shift,bubbles:true,cancelable:true}))
            const selected=events.filter(e=>e.type==='regionSelected').at(-1)
            assert(selected?.anchor?.page===target&&selected.anchor.region.length===4,'Keyboard region captures one page')
            assert(selected.rect.width===1&&selected.rect.height===1&&selected.rect.x>=0&&selected.rect.y>=0,'Region editor uses a compact visible native anchor')
            const annotation={id:'annotation-native-region',annotationKind:'region',anchor:selected.anchor,text:'',color:'blue',reference:selected.reference}
            await dispatch({action:'annotations',value:[annotation]});await goto({page:0});await goto(selected.anchor)
            const mark=doc(target).querySelector('[data-region-id]'),image=doc(target).querySelector('img'),bounds=image.getBoundingClientRect(),paint=mark.getBoundingClientRect(),region=selected.anchor.region
            assert(Math.abs((paint.left-bounds.left)/bounds.width-region[0])<.002&&Math.abs(paint.width/bounds.width-region[2])<.002,'Region aligns with oriented image')
            if(zoom==='3'){
                const frame=doc(target).defaultView.frameElement,before=frame.getBoundingClientRect().top,count=events.filter(e=>e.type==='annotation').length
                for(const [type,x,y] of [['pointerdown',200,200],['pointermove',140,80],['pointerup',140,80]])mark.dispatchEvent(new (doc(target).defaultView.PointerEvent)(type,{bubbles:true,cancelable:true,pointerId:321,button:0,screenX:x,screenY:y}))
                mark.dispatchEvent(new (doc(target).defaultView.MouseEvent)('click',{bubbles:true,cancelable:true,detail:1}))
                await wait(80)
                assert(frame.getBoundingClientRect().top<before-1,'Dragging a region pans the zoomed page')
                assert(events.filter(e=>e.type==='annotation').length===count,'Panning does not open the region editor')
            }
            mark.click();assert(events.some(e=>e.type==='annotation'&&e.id===annotation.id),'Saved region hit testing')
            await dispatch({action:'beginRegion'});doc(target).dispatchEvent(new (doc(target).defaultView.KeyboardEvent)('keydown',{key:'Escape',bubbles:true,cancelable:true}));assert(!document.querySelector('#region-hint'),'Escape cancels selection')
        }
        checks.push('rtl-ltr-spreads-zoom','region-keyboard-create-restore-hit-test-cancel','pan-through-regions')
        await dispatch({action:'chrome',value:{dark:true}})
        assert(view.style.getPropertyValue('--page-tint')==='none','Artwork colors preserved')
        await dispatch({action:'thumbnailWindow',pages:[target],request:++request});await until(()=>events.find(e=>e.type==='thumbnail'&&e.page===target),'bounded thumbnail')
        await goto({page:last});await dispatch({action:'back'});assert(events.filter(e=>e.type==='location').at(-1).anchor.page===target,'Back returns to previous page jump')
        await dispatch({action:'forward'});assert(events.filter(e=>e.type==='location').at(-1).anchor.page===last,'Forward returns to jump')
        checks.push('thumbnail','history','artwork-colors')
        post({type:'formatProof',passed:true,checks,maximumLivePages:maximum,pages:book.sections.length,navigationMedianMs:timings.sort((a,b)=>a-b)[Math.floor(timings.length/2)],navigationMaxMs:Math.max(...timings)})
        return
    }
    if(view.isFixedLayout){
        await dispatch({action:'appearance',value:{spread:false,zoom:'fit-page'}})
        await goto({index:0})
        const source=doc(0),paragraph=source.querySelector('#p0')
        assert(paragraph,'Fixed fixture has its original deterministic paragraph')
        const text=source.createTreeWalker(paragraph,NodeFilter.SHOW_TEXT).nextNode(),range=source.createRange()
        range.setStart(text,2);range.setEnd(text,15)
        const expected=range.toString(),selection=source.getSelection()
        selection.removeAllRanges();selection.addRange(range)
        const selected=await until(()=>events.find(event=>event.type==='selection'&&event.text===expected),'fixed-layout selection')
        const anchor=selected.anchor
        assert(anchor.index===0&&anchor.cfi.startsWith(book.sections[0].cfi.slice(0,-1)+'!'),'Fixed selection retains its original spine CFI')
        const annotation={id:'annotation-native-fixed',annotationKind:'highlight',anchor,text:expected,color:'yellow',reference:selected.reference}
        await dispatch({action:'annotations',value:[annotation]})
        const aligned=()=>{
            const part=busybooks.contents().find(part=>part.index===0)
            if(!part?.overlayer)return false
            const exact=view.resolveCFI(anchor.cfi).anchor(part.doc),rect=exact.getClientRects()[0]
            if(!rect?.width||!rect.height)return false
            const [key,painted]=part.overlayer.hitTest({x:rect.left+rect.width/2,y:rect.top+rect.height/2})
            return key===anchor.cfi&&painted.toString()===expected&&part.overlayer.element.querySelectorAll('rect').length>0
        }
        await until(aligned,'fixed-layout highlight alignment')
        for(const [spread,zoom] of [[true,'fit-page'],[false,'3'],[true,'fit-width']]){
            await dispatch({action:'appearance',value:{spread,zoom}})
            await goto({index:1});await goto(anchor)
            assert(doc(0).getSelection().toString()===expected,'Fixed range survives active-side, spread and zoom changes')
            await until(aligned,'fixed-layout highlight after layout')
        }
        const content=document.querySelector('#content')
        Object.assign(content.style,{width:'700px',height:'500px',right:'auto',bottom:'auto'})
        post({type:'formatResize'});await wait(300);await goto(anchor)
        assert(doc(0).getSelection().toString()===expected,'Fixed text CFI survives viewport/native resize')
        await until(aligned,'fixed-layout highlight after resize')
        await dispatch({action:'search',query:'library',queryId:17})
        await until(()=>events.find(event=>event.type==='searchDone'&&event.queryId===17),'fixed-layout search')
        const matches=events.filter(event=>event.type==='matches'&&event.queryId===17).flatMap(event=>event.items)
        assert(matches.length>0,'Fixed EPUB text is searchable through the application literal matcher')
        for(const match of [matches[0],matches.at(-1)]){
            await goto(match.anchor)
            const selected=busybooks.contents().find(part=>part.index===match.anchor.index)?.doc.getSelection().toString()
            assert(selected?.toLowerCase()==='library','Fixed search navigation selects the exact original range')
        }
        await goto({index:0})
        const footnoteSource=doc(0),heading=footnoteSource.querySelector('#chapter'),headingRange=footnoteSource.createRange()
        headingRange.selectNodeContents(heading)
        const returnCFI=view.getCFI(0,headingRange),beforeFootnote=events.filter(event=>event.type==='location').at(-1).anchor.cfi
        footnoteSource.getSelection().removeAllRanges()
        const noteLink=[...footnoteSource.querySelectorAll('a')].find(link=>(link.getAttributeNS('http://www.idpf.org/2007/ops','type')??link.getAttribute('epub:type'))==='noteref')
        assert(noteLink,'The fixed EPUB retains its original footnote reference')
        noteLink.click()
        const footnote=await until(()=>document.querySelector('dialog.footnote[open]'),'fixed-layout footnote')
        footnote.querySelector('article a').click()
        await until(()=>events.filter(event=>event.type==='location').at(-1)?.anchor.cfi===returnCFI,'fixed-layout footnote return passage')
        assert(!document.querySelector('dialog.footnote[open]'),'Following the footnote link closes its dialog')
        await dispatch({action:'back'})
        assert(events.filter(event=>event.type==='location').at(-1).anchor.cfi===beforeFootnote,'Fixed footnote link preserves its source in owned history')
        await dispatch({action:'forward'})
        const returnedCFI=events.filter(event=>event.type==='location').at(-1).anchor.cfi
        const savedDestination=view.resolveCFI(returnCFI).anchor(doc(0)),returnedDestination=view.resolveCFI(returnedCFI).anchor(doc(0))
        // The official CFI API canonicalizes duplicate element endpoints to a
        // point. Compare their exact original DOM coordinates, not spelling.
        assert(savedDestination.startContainer===doc(0).querySelector('#chapter')&&savedDestination.startOffset===0,'Saved footnote destination identifies its original heading start')
        assert(returnedDestination.startContainer===savedDestination.startContainer&&returnedDestination.startOffset===savedDestination.startOffset&&returnedDestination.endContainer===savedDestination.endContainer&&returnedDestination.endOffset===savedDestination.endOffset&&returnedDestination.toString()===savedDestination.toString(),'Fixed footnote Forward restores the exact original saved source coordinates')
        await goto(anchor)
        const fixedChecks=['fixed-text-selection','original-cfi','highlight-hit-alignment','active-side-and-spread','zoom-and-resize','exact-literal-search-navigation','footnote-passage-and-owned-history']
        if(nativeSavedProof){await goto(nativeSavedProof.anchor);assert(doc(0).getSelection().toString()===nativeSavedProof.text,'Fixed saved annotation reopens after cache rebuild');fixedChecks.push('saved-range-after-cache-rebuild')}
        post({type:'formatSaved',anchor,text:expected,annotations:[annotation]})
        post({type:'formatProof',passed:true,checks:fixedChecks,sections:book.sections.length,searchMatches:matches.length})
        return
    }
    let index=-1
    for(let i=0;i<book.sections.length;i++)if((await book.sections[i].createDocument()).querySelector('#passage')){index=i;break}
    assert(index>=0,'Fixture has a deterministic passage')
    await view.goTo(index)
    let passage=doc(index).querySelector('#passage'),text=doc(index).createTreeWalker(passage,NodeFilter.SHOW_TEXT).nextNode()
    const range=doc(index).createRange();range.setStart(text,2);range.setEnd(text,Math.min(30,text.length))
    const selectedText=range.toString(),selection=doc(index).getSelection();selection.removeAllRanges();selection.addRange(range)
    const captured=await until(()=>events.find(e=>e.type==='selection'&&e.text===selectedText),'selection event')
    const anchor=captured.anchor
    if(book.sections[index].identity){assert(anchor.kind==='fb2'&&anchor.version===1&&anchor.section===book.sections[index].identity,'Typed FB2 range locator')}
    if(book.pageList?.length){const progress=view.getProgressOf(index,range);assert(progress.pageItem?.label==='17','NCX print page survives fallback resolution');checks.push('publisher-page-reference')}
    const annotation={id:'annotation-native-text',annotationKind:'highlight',anchor,text:selectedText,color:'yellow',reference:captured.reference}
    const savedAnnotations=[annotation];let noteProof
    await dispatch({action:'annotations',value:[annotation]})
    for(const size of [30,18,26]){
        await dispatch({action:'appearance',value:{publisher:false,size,line:1.8,margin:45}})
        await goto(anchor)
        assert(doc(index).getSelection().toString()===selectedText,'Text range survives typography')
    }
    post({type:'formatResize'});await wait(300);await goto(anchor)
    assert(doc(index).getSelection().toString()===selectedText,'Text range survives native resize')
    if(nativeSavedProof){
        await goto(nativeSavedProof.anchor);assert(doc(nativeSavedProof.anchor.index).getSelection().toString()===nativeSavedProof.text,'Saved range survives cache rebuild and native restart')
        if(nativeSavedProof.noteProof){
            await goto(nativeSavedProof.noteProof.anchor)
            const dialog=await until(()=>document.querySelector('dialog.footnote[open]'),'saved note after cache rebuild')
            assert(document.getSelection().toString()===nativeSavedProof.noteProof.text,'Saved note annotation survives cache rebuild and native restart')
            dialog.close();await goto(anchor);checks.push('note-survives-cache-restart')
        }
    }
    await wait(50);await dispatch({action:'passage',request:4321})
    const passageEvent=await until(()=>events.find(e=>e.type==='passage'&&e.request===4321),'read-aloud/dictionary passage')
    assert(passageEvent.text===selectedText&&passageEvent.anchor.cfi===anchor.cfi,'Text assistance uses the selected durable passage')
    checks.push('selection','typed-locator','highlight','typography','native-resize','text-assistance-passage')
    await dispatch({action:'search',query:'library',queryId:17})
    await until(()=>events.find(e=>e.type==='searchDone'&&e.queryId===17),'search completion')
    const matches=events.filter(e=>e.type==='matches').flatMap(e=>e.items);assert(matches.length>0,'Real text search')
    if(anchor.kind==='fb2')assert(matches.every(m=>m.anchor.kind==='fb2'&&Number.isInteger(m.anchor.index)&&m.anchor.section),'Every search locator is typed')
    for(const match of [matches[0],matches.at(-1)]){
        await goto(match.anchor)
        assert(busybooks.contents().some(p=>p.doc.getSelection().toString().toLowerCase()==='library')||document.getSelection()?.toString().toLowerCase()==='library','Exact search range selected across sections and notes')
    }
    checks.push('exact-search-navigation')
    await goto(anchor)
    const noteLink=doc(index).querySelector('[role="doc-noteref"],a[epub\\:type="noteref"]')
    if(noteLink){
        doc(index).getSelection().removeAllRanges();noteLink.click()
        const dialog=await until(()=>document.querySelector('dialog.footnote[open]'),'footnote')
        if(anchor.kind==='fb2'||book.sections[index].contentHref?.endsWith('.xml'))assert([...dialog.querySelectorAll('img')].length>0,'Embedded note image retained')
        await Promise.all([...dialog.querySelectorAll('img')].map(i=>i.decode()))
        const p=[...dialog.querySelectorAll('p')].find(p=>!p.closest('header'))??dialog.querySelector('p'),node=p.firstChild,noteRange=document.createRange();noteRange.setStart(node,0);noteRange.setEnd(node,Math.min(12,node.length));const noteText=noteRange.toString();document.getSelection().removeAllRanges();document.getSelection().addRange(noteRange)
        const note=await until(()=>events.find(e=>e.type==='selection'&&e.note&&e.text===noteText),'footnote selection')
        assert(note.anchor.kind===anchor.kind,'Note uses same locator contract')
        noteProof={anchor:note.anchor,text:noteText};savedAnnotations.push({...annotation,id:'annotation-native-note',anchor:note.anchor,text:noteText})
        await dispatch({action:'annotations',value:savedAnnotations})
        dialog.close();await goto(note.anchor)
        await until(()=>document.querySelector('dialog.footnote[open]'),'restored footnote annotation')
        assert(document.getSelection().toString()===noteText,'Note annotation reopens exact note range')
        const backlink=document.querySelector('dialog.footnote[open] a[href]');if(backlink)backlink.click();else document.querySelector('dialog.footnote[open]').close()
        checks.push('footnotes-images-backlinks','note-annotation-restoration')
    }
    await goto(anchor)
    post({type:'formatSaved',anchor,text:selectedText,annotations:savedAnnotations,noteProof})
    post({type:'formatProof',passed:true,checks,sections:book.sections.length,searchMatches:matches.length})
})().catch(error=>postFormatProof({type:'formatProof',passed:false,message:String(error),stack:error.stack}))
