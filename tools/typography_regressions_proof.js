// Production adapter, real native font collection and real Foliate documents.
(async()=>{
    const assert=(value,message)=>{if(!value)throw Error(message)}
    const events=[],checks=[],view=document.querySelector('foliate-view')
    window.busybooksProbe=event=>events.push(event)
    const doc=()=>view.renderer.getContents()[0].doc
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
        const original=FontFace.prototype.load
        let release,started
        const entered=new Promise(resolve=>started=resolve),gate=new Promise(resolve=>release=resolve)
        FontFace.prototype.load=function(){started();return gate.then(()=>original.call(this))}
        const changing=apply(1,{},81)
        await entered
        // Hide invalidates the controller's pending write. The same committed
        // snapshot is used on return to the retained renderer.
        const cancelling=busybooks.dispatch({action:'cancelAppearance'})
        release();await changing;await cancelling;FontFace.prototype.load=original
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
        checks.push('cancelled-font-retained-return-committed-raster-and-passage')
        // Cancellation after publication of styles, while layout readiness is
        // still pending, must roll back immediately and reject late restoration.
        const fontSet=doc().fonts,ready=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(fontSet),'ready').get
        const committedAlias=family()
        let readyEntered,readyRelease,hold=true
        const readyStarted=new Promise(resolve=>readyEntered=resolve),readyGate=new Promise(resolve=>readyRelease=resolve)
        Object.defineProperty(fontSet,'ready',{configurable:true,get(){if(hold&&family()!==committedAlias){readyEntered();return readyGate}return ready.call(this)}})
        const late=apply(1,{},84);await readyStarted
        await busybooks.dispatch({action:'cancelAppearance'})
        assert(raster(family())===before,'Cancellation after style mutation must restore committed glyphs')
        hold=false;readyRelease();await late;delete fontSet.ready
        assert(events.some(e=>e.type==='appearanceResult'&&e.request===84&&e.cancelled),'Layout-stage cancellation must not be acknowledged as success')
        // Navigation during a delayed font load owns the passage on rollback.
        let enterNavigation,releaseNavigation
        const navigationStarted=new Promise(resolve=>enterNavigation=resolve),navigationGate=new Promise(resolve=>releaseNavigation=resolve)
        FontFace.prototype.load=function(){enterNavigation();return navigationGate.then(()=>original.call(this))}
        const navigating=apply(1,{},85);await navigationStarted
        await busybooks.dispatch({action:'goto',anchor:{index:1}})
        const navigationCancel=busybooks.dispatch({action:'cancelAppearance'})
        FontFace.prototype.load=original;releaseNavigation();await navigating;await navigationCancel
        assert(view.renderer.getContents()[0].index===1,'Cancellation cannot undo subsequent user navigation')
        assert(raster(family())===before,'The newly navigated chapter must use the committed family')
        checks.push('post-style-cancellation-and-navigation-ownership')
        // Hold rollback layout itself, accept a newer selection, then finish
        // both obsolete tasks in reverse order. Neither may repaint that choice.
        const retained=doc().fonts,getReady=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(retained),'ready').get,retainedAlias=family()
        let enteredOld,releaseOld,enteredRollback,releaseRollback,holding=true
        const oldStarted=new Promise(resolve=>enteredOld=resolve),oldGate=new Promise(resolve=>releaseOld=resolve)
        const rollbackStarted=new Promise(resolve=>enteredRollback=resolve),rollbackGate=new Promise(resolve=>releaseRollback=resolve)
        FontFace.prototype.load=function(){enteredOld();return oldGate.then(()=>original.call(this))}
        const oldChange=apply(1,{},86);await oldStarted
        Object.defineProperty(retained,'ready',{configurable:true,get(){if(holding&&family()===retainedAlias){enteredRollback();return rollbackGate}return getReady.call(this)}})
        const oldCancel=busybooks.dispatch({action:'cancelAppearance'});await rollbackStarted
        FontFace.prototype.load=original
        await apply(1,{},87)
        const newest=raster(family())
        assert(newest!==before,'Newer accepted family must actually render different glyphs')
        holding=false;releaseRollback();releaseOld();await oldChange;await oldCancel;delete retained.ready
        assert(raster(family())===newest,'A late load or rollback cannot overwrite a newer selection')
        checks.push('newer-choice-supersedes-delayed-rollback')
    }
    window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:true,checks}))
})().catch(error=>window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify({type:'typographyProof',passed:false,message:String(error),stack:error.stack})))
