(async()=>{
    const post=data=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',...data}))
    const view=document.querySelector('foliate-view'),doc=view?.renderer.getContents().map(x=>x.doc).find(d=>d?.querySelector('p'))
    const sample=()=>doc?JSON.stringify(['fontFamily','fontSize','fontWeight','fontStyle'].map(k=>doc.defaultView.getComputedStyle(doc.querySelector('p'))[k])):document.querySelector('.pdf-page canvas')?.toDataURL()
    const before=sample(),text=doc?.body.textContent??document.querySelector('.textLayer')?.textContent
    let reply
    window.busybooksProbe=event=>{if(event.type==='appearanceResult'&&event.request===99)reply=event}
    await busybooks.dispatch({action:'appearance',request:99,value:{publisher:false,font:nativeFontData[1].choice,resolvedFont:nativeFontData[1].resolved,size:32}})
    if(!reply?.message)throw Error('Unsupported font application was not rejected')
    if(sample()!==before)throw Error('Fixed page rendering changed')
    if((doc?.body.textContent??document.querySelector('.textLayer')?.textContent)!==text)throw Error('Fixed text/text layer changed')
    if(doc&&[...doc.fonts].some(f=>f.family.includes('busybooks-local-')))throw Error('Fixed publication received application FontFaces')
    post({passed:true,checks:[doc?'fixed-layout-keeps-publisher-typography':'pdf-keeps-page-and-text-layer','unsupported-font-rejected']})
})().catch(error=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:false,message:String(error)})))
