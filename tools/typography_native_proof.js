// Runs only in the disposable native probe, outside release assets.
(async()=>{
    const post=data=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',...data}))
    const assert=(condition,message)=>{if(!condition)throw Error(message)}
    const view=document.querySelector('foliate-view'),checks=[],events=[]
    window.busybooksProbe=event=>events.push(event)
    const font=(index,publisher=false)=>({publisher,font:nativeFontData[index].choice,resolvedFont:nativeFontData[index].resolved,size:20,weight:400,line:1.5,flow:'paginated',margin:32,width:720})
    const apply=(index,publisher=false,request=1)=>busybooks.dispatch({action:'appearance',value:font(index,publisher),request})
    const doc=()=>busybooks.contents()[0].doc
    const style=node=>node.ownerDocument.defaultView.getComputedStyle(node)
    const family=()=>style(doc().querySelector('#typography')).fontFamily
    const pixels=(family,variant='')=>{
        const canvas=doc().createElement('canvas');canvas.width=600;canvas.height=60
        const c=canvas.getContext('2d');c.font=`${variant} 24px ${family}`;c.fillText('A quiet library — 0123456789.',2,40)
        return {width:c.measureText('A quiet library — 0123456789.').width,data:canvas.toDataURL()}
    }
    const awaitElement=(selector)=>new Promise((resolve,reject)=>{
        if(document.querySelector(selector))return resolve(document.querySelector(selector))
        const observer=new MutationObserver(()=>{const el=document.querySelector(selector);if(el){observer.disconnect();clearTimeout(timer);resolve(el)}})
        observer.observe(document.body,{childList:true,subtree:true});const timer=setTimeout(()=>{observer.disconnect();reject(Error('Missing '+selector))},10000)
    })
    await doc().fonts.load('24px '+family())
    const publicationFamily=family(),publicationPixels=pixels(publicationFamily)
    const initialHistory=[view.history.canGoBack,view.history.canGoForward]
    const firstDoc=doc(),range=firstDoc.createRange();range.selectNodeContents(firstDoc.querySelector('#p8'));range.collapse(true)
    const passage=view.getCFI(0,range)
    await busybooks.dispatch({action:'goto',anchor:{cfi:passage}})
    const historyBefore=[view.history.canGoBack,view.history.canGoForward]
    const mark=firstDoc.createRange();mark.setStart(firstDoc.querySelector('#p8').firstChild,0);mark.setEnd(firstDoc.querySelector('#p8').firstChild,32)
    const highlight=view.getCFI(0,mark),selectedText=mark.toString()
    firstDoc.getSelection().removeAllRanges();firstDoc.getSelection().addRange(mark)
    await busybooks.dispatch({action:'annotations',value:[{id:'font-highlight',annotationKind:'highlight',anchor:{cfi:highlight,index:0},color:'yellow',text:selectedText}]})
    const metrics=[]
    for(let i=0;i<3;i++){
        await apply(i)
        const f=family(),rendered=pixels(f)
        metrics.push(rendered)
        assert(f.includes('busybooks-local-'),'Private local font alias is applied to publisher-important paragraphs')
        assert([...doc().fonts].filter(f=>f.family.includes('busybooks-local-')&&f.status==='loaded').length>=1,'Resolved local faces actually loaded')
        const prose=doc().querySelector('#typography'),bold=prose.querySelector('strong'),italic=prose.querySelector('em'),code=prose.querySelector('code')
        assert(+style(bold).fontWeight>+style(prose).fontWeight,'Bold remains distinguishable')
        assert(style(italic).fontStyle==='italic','Italic remains distinguishable')
        assert(+parseFloat(style(doc().querySelector('h1')).fontSize)>+parseFloat(style(prose).fontSize),'Heading hierarchy remains')
        assert(!style(code).fontFamily.includes('busybooks-local-'),'Code keeps its family')
        assert(rendered.data!==pixels(f,'bold').data&&rendered.data!==pixels(f,'italic').data,'Actual normal/bold/italic raster differs')
        const resolved=await view.resolveNavigation(passage),rect=resolved.anchor(doc()).getBoundingClientRect(),frame=doc().defaultView.frameElement.getBoundingClientRect()
        assert(rect.right>=0&&rect.left<=frame.width,'Durable passage stays on the displayed page')
        assert(JSON.stringify(historyBefore)===JSON.stringify([view.history.canGoBack,view.history.canGoForward]),'Typography does not create history entries')
        const anchor=await view.resolveNavigation(highlight),marked=anchor.anchor(doc()),box=[...marked.getClientRects()].find(r=>r.width>0&&r.height>0)
        const hit=busybooks.contents()[0].overlayer.hitTest({x:box.left+box.width/2,y:box.top+box.height/2})
        assert(hit[0]===highlight&&hit[1].toString()===selectedText,'Highlight remains attached to its text after reflow')
        assert(doc().getSelection().toString()===selectedText,'Existing text selection survives font reflow')
        checks.push('loaded-rendered-family-'+i)
    }
    await busybooks.dispatch({action:'speaking',anchor:{cfi:highlight,index:0}})
    assert(busybooks.contents()[0].overlayer.element.querySelectorAll('g').length>=2,'Read-aloud underline and highlight repaint after reflow')
    await busybooks.dispatch({action:'speaking',anchor:null})
    await busybooks.dispatch({action:'search',query:'library',queryId:77})
    assert(events.some(e=>e.type==='matches'&&e.items.length),'Search still finds publication text after reflow')
    checks.push('highlight-selection-search-and-narration-anchors')
    assert(metrics[0].data!==metrics[1].data,'Two installed families produce different actual glyphs')
    assert(metrics[1].data!==publicationPixels.data,'Installed family defeats unrelated embedded same-name font')
    await apply(1,true)
    assert(family()===publicationFamily,'Publisher family restored')
    assert(pixels(family()).data===publicationPixels.data,'Publisher embedded glyphs restored')
    checks.push('publisher-and-embedded-collision')
    await Promise.all([apply(0,false,20),apply(1,false,21),apply(2,false,22)])
    assert(pixels(family()).data===metrics[2].data,'Newest A→B→C selection wins')
    checks.push('rapid-newest-selection')
    const nextDoc=await view.book.sections[1].createDocument(),r=nextDoc.createRange();r.selectNodeContents(nextDoc.querySelector('#p4'));r.collapse(true)
    const target=view.getCFI(1,r)
    await Promise.all([apply(1,false,30),busybooks.dispatch({action:'goto',anchor:{cfi:target}})])
    assert(busybooks.contents()[0].index===1,'Navigation during font work is not undone')
    assert(doc().documentElement.dir==='rtl','Publication direction survives')
    assert(style(doc().querySelector('#typography')).fontFamily.includes('busybooks-local-'),'New chapter has selected family')
    checks.push('navigation-chapter-direction-and-multilingual')
    const note=awaitElement('dialog.footnote[open]')
    const noteLink=[...doc().querySelectorAll('a')].find(a=>a.getAttributeNS('http://www.idpf.org/2007/ops','type')==='noteref');noteLink.click()
    const dialog=await note
    assert(style(dialog.querySelector('p')).fontFamily.includes('busybooks-local-'),'Reflowable footnote has the same private family')
    dialog.close();checks.push('footnote-family')
    await Promise.all([apply(0,false,40),apply(0,true,41)])
    assert(!family().includes('busybooks-local-'),'Reset/publisher supersedes pending customization')
    checks.push('publisher-during-update')
    post({passed:true,checks,metrics:metrics.map(m=>m.width),initialHistory})
})().catch(error=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:false,message:String(error),stack:error.stack})))
