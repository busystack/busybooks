// Production adapter, real native font collection and real Foliate documents.
(async()=>{
    const assert=(value,message)=>{if(!value)throw Error(message)}
    const events=[],checks=[],view=document.querySelector('foliate-view')
    window.busybooksProbe=event=>events.push(event)
    const doc=()=>busybooks.contents()[0].doc
    const style=node=>node.ownerDocument.defaultView.getComputedStyle(node)
    const font=(index,extra={})=>({publisher:false,font:nativeFontData[index].choice,resolvedFont:nativeFontData[index].resolved,size:20,weight:400,line:1.5,flow:'paginated',margin:32,width:720,...extra})
    const apply=(index,extra={},request=1)=>busybooks.dispatch({action:'appearance',request,value:font(index,extra)})
    const raster=(family,weight=400,italic=false,where=doc())=>{
        const canvas=where.createElement('canvas');canvas.width=700;canvas.height=70
        const c=canvas.getContext('2d');c.font=`${italic?'italic ':''}${weight} 28px ${family}`
        c.fillText('A quiet library — 0123456789.',2,45);return canvas.toDataURL()
    }
    const family=()=>style(doc().querySelector('#typography')).fontFamily
    if(typographyProbeMode==='weights'||typographyProbeMode==='system'){
        await apply(3)
        const rendered=[]
        for(const weight of [300,400,500,600,700]){
            await apply(3,{weight})
            const pixels=raster(family(),weight)
            assert(pixels===raster(JSON.stringify(nativeFontData[3].choice.family),weight),'Private family must render the actual installed '+weight+' face')
            rendered.push(pixels)
        }
        assert(new Set(rendered).size===5,'All five installed body weights must produce distinct glyphs')
        for(const weight of [300,400,500,600,700])assert(raster(family(),weight,true)===raster(JSON.stringify(nativeFontData[3].choice.family),weight,true),'Installed italic weight '+weight+' must match')
        checks.push('five-actual-weights-and-italic-rasters')
    }else if(typographyProbeMode==='specialist'||typographyProbeMode==='specialist-cold'){
        const expected='"BusyBooks Specialist"',reference=raster(expected)
        assert(style(doc().querySelector('.symbol')).fontFamily===expected,'Cold open must preserve the publication specialist family')
        await apply(1)
        await busybooks.dispatch({action:'goto',anchor:{index:1}})
        assert(style(doc().querySelector('.symbol')).fontFamily===expected,'New chapter must preserve the publication specialist family')
        assert(raster(style(doc().querySelector('.symbol')).fontFamily)===reference,'Specialist glyphs must match publication originals')
        await apply(0)
        await apply(1)
        await busybooks.dispatch({action:'appearance',request:22,value:{...font(1),publisher:true}})
        assert(style(doc().querySelector('.symbol')).fontFamily===expected,'Publisher restoration must use specialist originals')
        checks.push('new-chapter-and-cold-custom-open-specialist-originals')
    }else if(typographyProbeMode==='cancellation'){
        await apply(0)
        const range=doc().createRange();range.selectNodeContents(doc().querySelector('#p8'));range.collapse(true)
        const passage=view.getCFI(0,range)
        await busybooks.dispatch({action:'goto',anchor:{cfi:passage}})
        const openedNote=new Promise((resolve,reject)=>{
            const observer=new MutationObserver(()=>{const note=document.querySelector('dialog.footnote[open]');if(note){observer.disconnect();clearTimeout(timer);resolve(note)}})
            observer.observe(document.body,{childList:true,subtree:true});const timer=setTimeout(()=>{observer.disconnect();reject(Error('Footnote did not open'))},10000)
        })
        ;[...doc().querySelectorAll('a')].find(a=>a.getAttributeNS('http://www.idpf.org/2007/ops','type')==='noteref').click()
        const note=await openedNote
        assert(nativeCommittedAppearance?.font?.family===nativeFontData[0].choice.family,'Regression must use the book preference read back from SQLite')
        const saved={...nativeCommittedAppearance,resolvedFont:nativeFontData[0].resolved},before=raster(family()),history=[view.history.canGoBack,view.history.canGoForward]
        // Use the real asynchronous FontFace operations. Exact delayed-load and
        // rollback ordering are tested with owned objects in typography_probe.mjs.
        const changing=apply(1,{},81)
        const cancelling=busybooks.dispatch({action:'cancelAppearance'})
        await changing;await cancelling
        assert(raster(family())===before,'Cancellation must restore the displayed committed font')
        assert(raster(style(note.querySelector('p')).fontFamily,400,false,document)===before,'The open footnote must retain the committed rendered family too')
        assert(events.some(e=>e.type==='appearanceResult'&&e.request===81&&e.cancelled),'A cancelled font change must not report success')
        await busybooks.dispatch({action:'appearance',request:83,value:{color:'sepia'}})
        assert(raster(family())===before,'Adapter preferences must also retain the committed family after cancellation')
        await busybooks.dispatch({action:'appearance',request:82,value:saved})
        assert(raster(family())===before,'Retained reader return must agree with the committed choice')
        const resolved=view.resolveNavigation(passage),rect=resolved.anchor(doc()).getBoundingClientRect(),frame=doc().defaultView.frameElement.getBoundingClientRect()
        assert(rect.right>=0&&rect.left<=frame.width,'Hide/return must keep the logical passage displayed')
        assert(JSON.stringify(history)===JSON.stringify([view.history.canGoBack,view.history.canGoForward]),'Cancellation must not add reading history')
        checks.push('real-font-load-cancellation-committed-raster-footnote-passage-history')
        const observeFamily=(test,action,message)=>new Promise((resolve,reject)=>{
            const observer=new MutationObserver(()=>{
                if(!test())return
                observer.disconnect();clearTimeout(timer)
                try{resolve({operation:action()})}catch(error){reject(error)}
            })
            observer.observe(doc().body,{attributes:true,attributeFilter:['style'],subtree:true})
            const timer=setTimeout(()=>{observer.disconnect();reject(Error(message))},10000)
        })
        // Observe an actual published inline-family change, then invalidate it
        // while the adapter is still completing native font/layout work.
        const committedAlias=family()
        const styled=observeFamily(()=>family()!==committedAlias,()=>busybooks.dispatch({action:'cancelAppearance'}),'Native candidate family was not published')
        const late=apply(1,{},84),postStyle=await styled
        await Promise.all([late,postStyle.operation])
        assert(raster(family())===before,'Cancellation after style mutation must restore committed glyphs')
        assert(events.some(e=>e.type==='appearanceResult'&&e.request===84&&e.cancelled),'Layout-stage cancellation must not be acknowledged as success')
        // Native navigation and a real pending replacement overlap. The exact
        // delayed-load ordering has separate controlled adapter coverage.
        const navigating=apply(1,{},85)
        const navigation=busybooks.dispatch({action:'goto',anchor:{index:1}})
        const navigationCancel=busybooks.dispatch({action:'cancelAppearance'})
        await Promise.all([navigating,navigation,navigationCancel])
        assert(busybooks.contents()[0].index===1,'Cancellation cannot undo subsequent user navigation')
        assert(raster(family())===before,'The newly navigated chapter must use the committed family')
        checks.push('native-post-style-cancellation-and-overlapping-navigation-ownership')
        // Observe rollback publication itself and immediately submit a newer
        // choice. No engine constructor, method or property is replaced.
        const retainedAlias=family()
        let stage=0,oldCancel,newChange
        const superseded=new Promise((resolve,reject)=>{
            const observer=new MutationObserver(()=>{
                if(stage===0&&family()!==retainedAlias){
                    stage=1;oldCancel=busybooks.dispatch({action:'cancelAppearance'})
                }else if(stage===1&&family()===retainedAlias){
                    stage=2;observer.disconnect();clearTimeout(timer)
                    newChange=apply(1,{},87);resolve()
                }
            })
            observer.observe(doc().body,{attributes:true,attributeFilter:['style'],subtree:true})
            const timer=setTimeout(()=>{observer.disconnect();reject(Error('Native candidate and rollback families were not both published'))},10000)
        })
        const oldChange=apply(1,{},86)
        await superseded;await Promise.all([oldChange,oldCancel,newChange])
        const newest=raster(family())
        assert(newest!==before,'Newer accepted family must actually render different glyphs')
        assert(events.some(e=>e.type==='appearanceResult'&&e.request===86&&e.cancelled),'Superseded native candidate must not report success')
        assert(events.some(e=>e.type==='appearanceResult'&&e.request===87&&!e.message),'Newer native choice must succeed')
        await doc().fonts.ready
        assert(raster(family())===newest,'A late load or rollback cannot overwrite a newer selection')
        checks.push('native-observed-rollback-superseded-by-newer-choice')
    }
    window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:true,checks}))
})().catch(error=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:false,message:String(error),stack:error.stack})))
