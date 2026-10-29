// Run by the existing disposable WebKitGTK/Chromium harness with real reader
// assets and publication bytes. No application test channel or vendor changes.
(async()=>{
    const events=[],observations=[],checks=[],view=document.querySelector('foliate-view')
    window.busybooksProbe=event=>events.push(event)
    const post=data=>{
        if(data.type==='formatProof')window.reviewResult=data
        const json=JSON.stringify(data)
        if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json)
        else window.chrome.webview.postMessage(json)
    }
    const assert=(condition,message)=>{if(!condition)throw Error(message)}
    const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    const until=async(predicate,label)=>{for(let i=0;i<200;i++){const result=predicate();if(result)return result;await pause(25)}throw Error('Timed out: '+label)}
    const locationKey=anchor=>JSON.stringify(anchor?.page!=null?{page:anchor.page}:anchor?.cfi?{cfi:anchor.cfi,index:anchor.index}:anchor)
    let request=200
    const flush=async()=>{
        const id=++request
        await busybooks.dispatch({action:'flush',request:id})
        assert(events.some(event=>event.type==='flushed'&&event.request===id),'Current appearance/location drain succeeds')
        return events.filter(event=>event.type==='location').at(-1)?.anchor
    }
    try{
        const pdf=!view,comic=!!view?.book?.comic,reflowable=!!view&&!view.isFixedLayout
        const kind=pdf?'pdf':comic?'comic':reflowable?'reflowable':'fixed'
        if(pdf)await until(()=>document.querySelector('.pdf-page canvas')?.width,'PDF canvas')
        else await until(()=>busybooks.contents().some(part=>part.doc?.body),'Publication page')
        let selectedSnapshot,selectedAnchor,settledCount,annotationBoxes
        const selectionSnapshot=()=>{
            const selection=document.getSelection()
            if(!selection?.rangeCount||selection.isCollapsed)return null
            const endpoint=(node,offset)=>{
                const element=node.nodeType===Node.TEXT_NODE?node.parentElement:node
                const layer=element.closest('.textLayer'),page=element.closest('.pdf-page')
                if(!layer||!page)return null
                const prefix=document.createRange();prefix.selectNodeContents(layer);prefix.setEnd(node,offset)
                return {page:Number(page.dataset.index),offset:prefix.toString().length}
            }
            return {anchor:endpoint(selection.anchorNode,selection.anchorOffset),focus:endpoint(selection.focusNode,selection.focusOffset),text:selection.toString()}
        }
        // Detailed text/annotation checks use only the owned text.pdf fixture.
        // Exact private-publication checks leave passages out of probe logs.
        if(pdf&&window.nativeSavedProof?.themeSelection===true){
            const layer=await until(()=>document.querySelector('.pdf-page:not([hidden]) .textLayer'),'fixture text layer')
            const walker=document.createTreeWalker(layer,NodeFilter.SHOW_TEXT)
            let node
            while((node=walker.nextNode()))if(node.textContent.trim().length>5)break
            assert(node,'Owned selection fixture has a text endpoint')
            const selection=document.getSelection()
            selection.setBaseAndExtent(node,0,node,Math.min(node.length,12))
            const payload=await until(()=>events.filter(event=>event.type==='selection'&&event.anchor?.segments?.length).at(-1),'published fixture selection')
            selectedSnapshot=JSON.stringify(selectionSnapshot());selectedAnchor=JSON.stringify(payload.anchor)
            settledCount=events.filter(event=>event.type==='selection'&&event.settled).length
            const annotation={id:'theme-selection-proof',annotationKind:'highlight',anchor:payload.anchor,text:payload.text,color:'yellow'}
            await busybooks.dispatch({action:'annotations',value:[annotation]})
            annotationBoxes=payload.anchor.segments.reduce((sum,segment)=>sum+segment.boxes.length,0)
            assert(annotationBoxes>0,'Owned fixture annotation has source boxes')
        }
        const before=await flush(),original=locationKey(before)
        for(const [label,color,systemDark,dark] of [
            ['System/app System/desktop Dark','system',true,true],
            ['System/app System/desktop Light','system',false,false],
            ['Light/app Dark','light',true,false],
            ['Dark/app Light','dark',false,true],
            ['Sepia/app Dark','sepia',true,false],
            ['Sepia/app Light','sepia',false,false],
            ['System/app Light/desktop Dark','system',false,false],
            ['System/app Dark/desktop Light','system',true,true],
            ['System live dark','system',true,true],
            ['System live light','system',false,false],
            ['System live dark again','system',true,true],
        ]){
            const id=++request
            await busybooks.dispatch({action:'appearance',request:id,value:{color,systemDark}})
            const reply=events.find(event=>event.type==='appearanceResult'&&event.request===id)
            assert(reply&&!reply.message,label+' preference transaction succeeds: '+JSON.stringify(reply))
            let filter,background
            if(pdf){
                const canvas=await until(()=>document.querySelector('.pdf-page canvas'),'current painted PDF page')
                filter=getComputedStyle(canvas).filter
                assert(getComputedStyle(canvas).width!=='0px','PDF page remains laid out')
            }else{
                filter=getComputedStyle(view).getPropertyValue('--page-tint').trim()
                const page=busybooks.contents().find(part=>part.doc?.body)?.doc
                assert(page,'Publication content remains present')
                background=page.defaultView.getComputedStyle(page.body).backgroundColor
            }
            const inverted=filter.includes('invert(1)')&&filter.includes('hue-rotate(180deg)')
            if(comic)assert(filter==='none','Comic artwork must never be tinted')
            else if(reflowable){
                assert(!filter.includes('invert('),'Reflowable CSS must not be inverted a second time')
                assert(background===(dark?'rgb(32, 33, 36)':color==='sepia'?'rgb(244, 236, 216)':'rgb(255, 255, 255)'),label+' reflowable page itself has effective color: '+background)
            }else if(dark)assert(inverted,label+' requires an inverted PDF/fixed page; computed filter='+filter)
            else if(color==='sepia')assert(filter.includes('sepia('),label+' retains sepia page treatment: '+filter)
            else assert(filter==='none',label+' page remains light: '+filter)
            const after=await flush()
            assert(locationKey(after)===original,label+' retains page/CFI: '+JSON.stringify({before,after}))
            if(selectedSnapshot){
                assert(JSON.stringify(selectionSnapshot())===selectedSnapshot,label+' retains logical PDF selection endpoints, direction and text')
                assert(JSON.stringify(events.filter(event=>event.type==='selection'&&event.anchor).at(-1)?.anchor)===selectedAnchor,label+' retains exact PDF source anchor')
                assert(events.filter(event=>event.type==='selection'&&event.settled).length===settledCount,label+' does not open a new selection popup')
                assert(document.querySelectorAll('.annotation-mark[data-id="theme-selection-proof"]').length===annotationBoxes,label+' retains annotation source boxes')
            }
            observations.push({label,color,systemDark,filter,...(background?{background}:{})})
        }
        if(selectedSnapshot){
            document.getSelection().removeAllRanges()
            await until(()=>document.getSelection().isCollapsed&&!events.filter(event=>event.type==='selection').at(-1)?.anchor,'explicit fixture selection clear')
            await busybooks.dispatch({action:'appearance',request:++request,value:{color:'system',systemDark:false}})
            assert(document.getSelection().isCollapsed,'A theme change cannot revive a deliberately cleared selection')
            checks.push('theme-retains-PDF-selection-source-and-annotations','theme-does-not-reopen-selection-popup','theme-respects-cleared-selection')
        }
        checks.push('effective-page-treatment','explicit-colors','application-System-overrides','live-dark-light-dark','stable-page-or-CFI',comic?'comic-no-tint':reflowable?'reflowable-no-double-inversion':pdf?'computed-PDF-canvas-filter':'fixed-page-filter')
        post({type:'themeMetric',kind,observations})
        post({type:'formatProof',passed:true,scope:'Actual computed PDF canvas filter / fixed-page tint / reflowable document color',kind,checks})
    }catch(error){post({type:'formatProof',passed:false,message:String(error),checks})}
})()
