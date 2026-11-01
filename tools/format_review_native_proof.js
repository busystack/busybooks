// The same actual-reader proof runs in Chromium and the native WebKitGTK host.
(async()=>{
    const events=[],checks=[],view=document.querySelector('foliate-view'),book=view.book
    window.busybooksProbe=event=>events.push(event)
    const assert=(ok,message)=>{if(!ok)throw Error(message)}
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    let request=8000
    const goto=async anchor=>{
        const id=++request;await busybooks.dispatch({action:'goto',anchor,request:id})
        const result=events.find(event=>event.type==='navigationResult'&&event.request===id)
        assert(result&&!result.message,'Navigation acknowledged: '+JSON.stringify(result))
    }
    const part=index=>busybooks.contents().find(item=>item.index===index)
    const typed=(cfi,index)=>book.sections[index].identity
        ?{kind:'fb2',version:1,section:book.sections[index].identity,index,cfi}:{cfi,index}
    const finish=data=>{
        window.reviewResult=data
        const message=JSON.stringify(data)
        if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(message)
        else window.chrome.webview.postMessage(message)
    }
    window.finishReview=finish
    if(book.comic){
        const content=document.querySelector('#content')
        Object.assign(content.style,{width:'800px',height:'600px',right:'auto',bottom:'auto'})
        await wait(60)
        let regions=0
        const sizes=[]
        for(const direction of ['ltr','rtl'])for(const spread of [false,true])for(const zoom of ['0.5','1.5','3']){
            await busybooks.dispatch({action:'appearance',value:{spread,direction,zoom}})
            const indices=book.sections.map((_,index)=>index)
            for(const index of indices){
                for(const [x,y] of [[0,0],[.96,0],[0,.96],[.96,.96]]){
                    const anchor={kind:'comic',version:1,format:book.format,page:index,pageId:book.sections[index].pageId,region:[x,y,.04,.04]}
                    await goto(anchor)
                    const renderer=view.renderer,bounds=renderer.getBoundingClientRect(),frame=part(index).doc.defaultView.frameElement.getBoundingClientRect()
                    const region={left:frame.left+x*frame.width,top:frame.top+y*frame.height,right:frame.left+(x+.04)*frame.width,bottom:frame.top+(y+.04)*frame.height}
                    assert(region.left>=bounds.left-2&&region.right<=bounds.left+renderer.clientWidth+2
                        &&region.top>=bounds.top-2&&region.bottom<=bounds.top+renderer.clientHeight+2,
                        `Saved corner is reachable: ${JSON.stringify({direction,spread,zoom,index,region,bounds:bounds.toJSON(),scroll:renderer.scrollLeft})}`)
                    if(index===0&&zoom==='3'&&!spread&&x===0&&y===0){
                        sizes.push({direction,viewport:renderer.clientWidth,outerViewport:bounds.width,pageWidth:frame.width,left:frame.left-bounds.left})
                        assert(Math.abs(frame.width-1800)<2,'600px artwork is 1800px at 300%')
                        assert(frame.left>=bounds.left-2,'Zoomed starting edge is reachable')
                    }
                    regions++
                }
            }
            // Also check the last page's starting edge after an actual viewport
            // resize, at every zoom/presentation/direction combination.
            Object.assign(content.style,{width:'500px',height:'800px'});await wait(60)
            const index=indices.at(-1)
            await goto({kind:'comic',version:1,format:book.format,page:index,pageId:book.sections[index].pageId,region:[0,0,.04,.04]})
            const r=view.renderer,v=r.getBoundingClientRect(),f=part(index).doc.defaultView.frameElement.getBoundingClientRect()
            assert(f.left>=v.left-2&&f.top>=v.top-2,'Upper-left edge remains reachable after resize')
            Object.assign(content.style,{width:'800px',height:'600px'});await wait(60)
        }
        await busybooks.dispatch({action:'appearance',value:{spread:false,direction:'ltr',zoom:'0.5'}});await goto({page:0});await wait(50)
        const r=view.renderer,frame=part(0).doc.defaultView.frameElement.getBoundingClientRect(),v=r.getBoundingClientRect()
        assert(Math.abs((frame.left+frame.right)/2-(v.left+r.clientWidth/2))<2,'A fitting page remains centered')
        checks.push('all-four-page-corners','saved-regions-actually-visible','numeric-zoom-single-spread-ltr-rtl','resize-overflow-reachability','fitting-page-centered')
        if(nativeSavedProof){
            await busybooks.dispatch({action:'appearance',value:{spread:true,direction:'rtl',zoom:'3'}})
            for(const annotation of nativeSavedProof.annotations){
                await goto(annotation.anchor)
                assert(part(0).doc.querySelector(`[data-region-id="${annotation.id}"]`),'Saved region note paints after data reopen/cache deletion')
                const frame=part(0).doc.defaultView.frameElement.getBoundingClientRect(),viewport=view.renderer.getBoundingClientRect(),[x,y,w,h]=annotation.anchor.region
                assert(frame.left+x*frame.width>=viewport.left-2&&frame.left+(x+w)*frame.width<=viewport.left+view.renderer.clientWidth+2
                    &&frame.top+y*frame.height>=viewport.top-2&&frame.top+(y+h)*frame.height<=viewport.top+view.renderer.clientHeight+2,'Restored region is visible at zoom')
            }
            checks.push('persisted-regions-visible-after-cache-restart')
        }
        const savedAnnotations=[[0,0],[.96,0],[0,.96],[.96,.96]].map(([x,y],i)=>({id:`annotation-review-edge-${i}`,annotationKind:'region',anchor:{kind:'comic',version:1,format:book.format,page:0,pageId:book.sections[0].pageId,region:[x,y,.04,.04]},text:'',color:'blue',reference:'Page 1'}))
        const saved={type:'formatSaved',anchor:savedAnnotations[0].anchor,text:'',annotations:savedAnnotations}
        const message=JSON.stringify(saved)
        if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(message);else window.chrome.webview.postMessage(message)
        finish({type:'formatProof',passed:true,checks,regions,sizes,restoredFromCacheRebuild:!!nativeSavedProof});return
    }
    let outlineProof=[]
    if(book.sections[0].identity){
        const flatten=items=>items.flatMap(item=>[item,...flatten(item.subitems??[])])
        const rows=flatten(book.toc)
        assert(rows.length===3&&new Set(rows.map(row=>row.href)).size===3,'Unnamed nested chapters have distinct destinations')
        for(const row of rows){
            const resolved=await view.resolveNavigation(row.href),doc=await book.sections[resolved.index].createDocument(),node=resolved.anchor(doc)
            assert(node.querySelector('header').textContent===row.label,'Outline resolves its own chapter heading')
            const range=doc.createRange();range.selectNodeContents(node);range.collapse(true)
            const anchor=typed(view.getCFI(resolved.index,range),resolved.index)
            outlineProof.push({label:row.label,href:row.href,anchor})
            await goto(anchor)
            const selected=part(resolved.index).doc.getSelection().getRangeAt(0).startContainer
            assert((selected.nodeType===1?selected:selected.parentElement).closest('section').id===node.id,'Chapter navigation reaches the distinct canonical section')
        }
        if(nativeSavedProof?.outlineProof){
            assert(JSON.stringify(outlineProof)===JSON.stringify(nativeSavedProof.outlineProof),'Outline CFIs survive cache deletion and restart')
            for(const row of nativeSavedProof.outlineProof)await goto(row.anchor)
        }
        checks.push('idless-distinct-outline-destinations','distinct-typed-outline-cfis','cache-rebuild-stable-outline')
    }else{
        assert(book.sections[1].sourceHref==='OPS/start.pdf'&&book.sections[1].contentHref==='OPS/first.xhtml','Original spine identity and resolved content stay separate')
        await view.goTo(1)
        const embedded=part(1).doc.querySelector('img')
        await embedded?.decode()
        assert(embedded?.naturalWidth===240&&embedded?.naturalHeight===320,'Embedded resource resolution retains the actual PNG while spine content resolves to XHTML')
        for(const href of ['OPS/start.pdf#passage','OPS/raster.png#passage','OPS/first.xhtml#passage']){
            const target=await view.resolveNavigation(href);assert(target.index===1&&target.anchor(part(1).doc)?.id==='passage','All fallback aliases navigate to the exact passage in the original spine slot')
        }
        const nested=book.toc?.[0]?.subitems?.find(row=>row.label==='Nested passage')
        const nestedTarget=await view.resolveNavigation(nested?.href)
        assert(nestedTarget?.index===1&&nestedTarget.anchor(part(1).doc)?.id==='passage','NCX destinations preserve their original fragment through content fallback')
        checks.push('pdf-png-xhtml-spine-chain','embedded-raster-kept','original-spine-and-alias-navigation')
    }
    const index=book.sections[0].identity?0:1
    await view.goTo(index)
    const doc=part(index).doc,node=doc.querySelector('#passage').firstChild,range=doc.createRange()
    range.setStart(node,2);range.setEnd(node,30)
    const text=range.toString(),anchor=typed(view.getCFI(index,range),index)
    const legacy={...anchor,cfi:anchor.cfi.replace(/\[busybooks-section-[^\]]+\]/g,'')}
    for(const size of [18,30]){
        await busybooks.dispatch({action:'appearance',value:{publisher:false,size}})
        await goto(legacy)
        assert(part(index).doc.getSelection().toString()===text,'Existing CFIs without generated-ID assertions still resolve')
    }
    if(nativeSavedProof){await goto(nativeSavedProof.anchor);assert(part(index).doc.getSelection().toString()===nativeSavedProof.text,'Passage survives cache rebuild and reopening')}
    await Promise.all([...part(index).doc.querySelectorAll('img')].map(image=>image.decode()))
    if(!book.sections[0].identity){
        assert(anchor.cfi.startsWith('epubcfi(/6/4!'),'CFI retains the original spine itemref position')
        assert(view.getProgressOf(index,range).pageItem?.label==='17','Publisher page references resolve through the fallback')
    }
    checks.push('durable-passage-and-typography','legacy-cfi-compatibility','images-decoded')
    const annotation={id:'annotation-review-passage',annotationKind:'highlight',anchor:legacy,text,color:'yellow',reference:'Review passage'}
    await busybooks.dispatch({action:'annotations',value:[annotation]})
    const saved={type:'formatSaved',anchor:legacy,text,annotations:[annotation],outlineProof}
    const message=JSON.stringify(saved)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(message)
    else window.chrome.webview.postMessage(message)
    finish({type:'formatProof',passed:true,checks,outlineProof,restoredFromCacheRebuild:!!nativeSavedProof})
})().catch(error=>{
    const value={type:'formatProof',passed:false,message:String(error),stack:error.stack}
    if(window.finishReview)window.finishReview(value)
    else {window.reviewResult=value;const json=JSON.stringify(value);if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json);else window.chrome.webview.postMessage(json)}
})
