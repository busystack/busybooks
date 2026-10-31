// The same proof runs against the packaged adapter in WebKitGTK and Chromium.
(async()=>{
    const events=[],checks=[],view=document.querySelector('foliate-view'),book=view?.book,content=document.querySelector('#content')
    window.busybooksProbe=event=>events.push(event)
    const assert=(ok,message)=>{if(!ok)throw Error(message)}
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    let request=20000
    const jump=async anchor=>{
        const id=++request;await busybooks.dispatch({action:'goto',anchor,request:id})
        const result=events.find(e=>e.type==='navigationResult'&&e.request===id)
        assert(result&&!result.message,'Destination usable: '+JSON.stringify({anchor,result}))
    }
    const flush=async()=>{const id=++request;await busybooks.dispatch({action:'flush',request:id});assert(events.some(e=>e.type==='flushed'&&e.request===id),'Flush acknowledged');return events.findLast(e=>e.type==='location')}
    Object.assign(content.style,{width:'800px',height:'600px',right:'auto',bottom:'auto'})
    await wait(60)
    if(book?.metadata?.title==='Encoded EPUB 2 review'){
        const rows=items=>items.flatMap(item=>[item,...rows(item.subitems??[])])
        for(const row of rows(book.toc)){
            await jump({href:row.href})
            const target=await view.resolveNavigation(row.href),doc=busybooks.contents().find(x=>x.index===target.index)?.doc
            assert(doc&&target.anchor(doc),'Encoded NCX destination resolves to its document fragment')
        }
        assert(book.toc[1].href.includes('per%25cent'),'NCX retains the encoded percent filename')
        checks.push('epub2-ncx-encoded-paths-and-fragments')
    }else if(!view){
        if(window.expectedAnnotationCount){assert(document.querySelectorAll('.annotation-mark').length>=window.expectedAnnotationCount,'All cold-open annotation chunks paint');checks.push('cold-open-annotation-batches')}
        await busybooks.dispatch({action:'appearance',value:{zoom:'3',spread:false}})
        await jump({page:0});content.scrollLeft=450;content.scrollTop=250
        const before={left:content.scrollLeft,top:content.scrollTop},saved=await flush()
        await jump({page:1});await jump(saved.anchor)
        assert(Math.abs(content.scrollLeft-before.left)<2&&Math.abs(content.scrollTop-before.top)<2,'PDF reopens at both viewport axes')
        await busybooks.dispatch({action:'appearance',value:{spread:true}});await jump({page:1})
        await busybooks.dispatch({action:'previous'})
        assert((await flush()).anchor.page===0,'Previous reaches page 1 from page 2 in a spread')
        await busybooks.dispatch({action:'appearance',value:{spread:false}});await jump({page:0})
        await Promise.all([busybooks.dispatch({action:'next'}),busybooks.dispatch({action:'next'})])
        assert((await flush()).anchor.page===2,'Two rapid Next commands advance two pages')
        content.style.width='760px'
        const navigating=busybooks.dispatch({action:'goto',anchor:{page:1}})
        await wait(180);await navigating;await flush();await wait(180)
        assert((await flush()).anchor.page===1,'Viewport relayout preserves the latest navigation destination')
        checks.push('pdf-two-axis-position','pdf-spread-first-boundary','pdf-relative-command-order','pdf-resize-navigation-order')
    }else if(book.comic){
        for(const spread of [false,true]){
            await busybooks.dispatch({action:'appearance',value:{spread,zoom:'fit-page'}})
            for(let page=0;page<3;page++){
                await jump({page});assert(busybooks.contents().some(x=>x.index===page),'Consecutive wide pages remain navigable')
            }
        }
        await busybooks.dispatch({action:'appearance',value:{spread:true,zoom:'3',direction:'ltr'}})
        await jump({page:3})
        const renderer=view.renderer
        renderer.scrollLeft=2200;renderer.scrollTop=150
        const before={left:renderer.scrollLeft,top:renderer.scrollTop},saved=await flush()
        assert(saved.anchor.page===4,'Companion page owns the saved panned point')
        await jump({page:0});await jump(saved.anchor)
        // Public View lifecycle may replace the renderer while preserving the
        // application book. Compare the current native viewport, never the
        // detached renderer that supplied the saved physical position.
        assert(Math.abs(view.renderer.scrollLeft-before.left)<2&&Math.abs(view.renderer.scrollTop-before.top)<2,'Comic pan restores exactly across a spread')
        const load=book.sections[5].load
        let release
        const gate=new Promise(resolve=>release=resolve)
        book.sections[5].load=async()=>{await gate;return load()}
        const navigating=busybooks.dispatch({action:'goto',anchor:{page:5}})
        await wait(50)
        const id=++request,flushing=busybooks.dispatch({action:'flush',request:id})
        await wait(50)
        assert(!events.some(e=>e.type==='flushed'&&e.request===id),'Flush remains pending while a comic page loads')
        release();await Promise.all([navigating,flushing]);book.sections[5].load=load
        assert(events.findLast(e=>e.type==='location').anchor.page===5,'Flush snapshots the settled comic page')
        checks.push('consecutive-centered-comic-pages','companion-pan-round-trip','comic-flush-awaits-page-load')
    }else{
        const part=index=>busybooks.contents().find(x=>x.index===index)
        const fb2=!!book.sections[0].identity
        const first=fb2?'sections/0.xhtml':'OPS/chapter%232.xhtml'
        const destination=fb2?'sections/0.xhtml#later':'OPS/chapter%232.xhtml#later'
        if(!fb2){
            assert(book.metadata.title==='Reader review regressions','The original container package, rather than a literal-percent alias, supplies metadata')
            for(const row of book.toc){const target=await view.resolveNavigation(row.href);if(row.label==='Broken optional'){assert(!target,'Malformed optional outline entry remains unavailable');continue}if(row.label==='External reference'){assert(row.href==='https://example.invalid/reference#chapter'&&book.isExternal(row.href)&&!target,'External NAV URL is preserved without becoming an internal destination');continue}assert(target?.index>=0,'Encoded table-of-contents destination resolves: '+row.href)}
            const literal=book.sections.findIndex(section=>section.sourceHref==='OPS/chapter%25232.xhtml')
            if(literal>=0){
                const guide=book.landmarks?.find(row=>row.label==='External reference')
                assert(guide?.href==='https://example.invalid/reference#guide'&&book.isExternal(guide.href),'External guide URL is preserved')
                assert(!performance.getEntriesByType('resource').some(entry=>entry.name.startsWith('https://example.invalid/')),'Reading external metadata does not fetch its destination')
                await jump({href:'OPS/chapter%25232.xhtml#decoy'})
                assert(part(literal)?.doc.getElementById('decoy')?.textContent.includes('distinct publication resource'),'Literal percent and encoded hash filenames retain separate identities')
                checks.push('encoded-package-and-resource-collision-identity','external-nav-and-guide-metadata-without-fetch')
            }
            await jump({href:'OPS/per%25cent.xhtml#percent'})
            assert(part(1)?.doc.getElementById('percent'),'Literal percent filename loads and navigates')
            await jump({href:'OPS/%d0%b0%d1%80%d1%82.xhtml#unicode'})
            assert(part(2)?.doc.getElementById('unicode'),'Equivalent Unicode percent escapes share a resource')
            await jump({href:'OPS/chapter%232.xhtml#chapter%3Atwo'})
            const resolved=await view.resolveNavigation('OPS/chapter%232.xhtml#chapter%3Atwo')
            assert(resolved.anchor(part(0).doc)?.id==='chapter:two','Encoded fragment decodes once')
            const doc=part(0).doc
            for(const id of ['ordinary','legacy']){
                const node=doc.getElementById(id),href=node.getAttribute('href')??node.getAttributeNS('http://www.w3.org/1999/xlink','href')
                assert(href?.startsWith('blob:'),'SVG image resource rewritten: '+id)
                const image=new Image();image.src=href;await image.decode();assert(image.naturalWidth===10,'SVG image resolves to packaged bytes')
            }
            if(literal>=0){
                let sprite
                for(const id of ['external-sprite','legacy-sprite','filter-sprite']){
                    const node=doc.getElementById(id),href=node.getAttribute('href')??node.getAttributeNS('http://www.w3.org/1999/xlink','href')
                    assert(href?.startsWith('blob:')&&href.endsWith('#icon'),'SVG use/feImage preserve their original fragment: '+id)
                    sprite=href
                }
                const image=new Image();image.src=doc.getElementById('fragment-image').getAttribute('href');await image.decode()
                assert(image.naturalWidth===10&&image.src.endsWith('#preserved'),'SVG image resource keeps its fragment')
                const frame=document.createElement('iframe');frame.style.cssText='position:fixed;bottom:0;right:0;width:10px;height:8px;opacity:0';frame.setAttribute('tabindex','-1')
                const ready=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('SVG resource did not load')),3000);frame.onload=()=>{clearTimeout(timer);resolve()};frame.onerror=()=>{clearTimeout(timer);reject(Error('SVG resource failed'))}})
                frame.src=sprite.slice(0,sprite.indexOf('#'));document.body.append(frame);await ready
                assert(frame.contentWindow.getComputedStyle(frame.contentDocument.getElementById('color')).fill==='rgb(53, 132, 228)','Original SVG identity and relative PI stylesheet render the expected color')
                frame.remove()
                checks.push('svg-fragment-resources-and-relative-stylesheet')
            }
            checks.push('encoded-filenames-and-fragments','svg-href-and-xlink-images')
        }else{
            await jump({href:first})
            const image=part(0).doc.querySelector('img');await image.decode();assert(image.naturalWidth===2,'Encoded FB2 image resolves')
            checks.push('fb2-encoded-image')
        }
        await jump({href:destination});const targetPage=(await flush()).screenPage
        assert(targetPage>0,'Cross-reference destination is later in the chapter')
        await jump({href:first})
        part(0).doc.getElementById('ref1').click()
        for(let i=0;i<100&&!document.querySelector('dialog.footnote[open]');i++)await wait(10)
        const dialog=document.querySelector('dialog.footnote[open]')
        assert(dialog,'Footnote opens')
        const cross=dialog.querySelector('a[href*="#later"]');assert(cross,'Note contains same-chapter cross-reference');cross.click()
        for(let i=0;i<100;i++){await wait(10);if(events.findLast(e=>e.type==='location')?.screenPage===targetPage)break}
        assert((await flush()).screenPage===targetPage,'Note cross-reference navigates within its referring chapter')
        checks.push('footnote-same-chapter-cross-reference')
        const id=++request;await busybooks.dispatch({action:'search',query:'quick brown fox',queryId:id})
        const matches=events.filter(e=>e.type==='matches'&&e.queryId===id).flatMap(e=>e.items)
        assert(matches.some(e=>e.excerpt.includes('quick brown fox')),'Search excerpt includes inline emphasis')
        checks.push('inline-search-excerpt')
    }
    const value={type:'formatProof',passed:true,checks}
    window.reviewResult=value
    const json=JSON.stringify(value)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json);else window.chrome.webview.postMessage(json)
})().catch(error=>{
    const value={type:'formatProof',passed:false,message:String(error),stack:error.stack};window.reviewResult=value
    const json=JSON.stringify(value)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json);else window.chrome.webview.postMessage(json)
})
