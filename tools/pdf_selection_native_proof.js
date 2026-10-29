// Actual PDF.js text layers and BusyBooks adapter, using supported DOM APIs.
// The maintained Chromium review runner supplies the original PDF and assets.
(async()=>{
    const events=[],checks=[],content=document.querySelector('#content')
    window.busybooksProbe=event=>events.push(event)
    const assert=(value,message)=>{if(!value)throw Error(message)}
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    let request=70000,revision=1000
    const dispatch=async(action,extra={})=>busybooks.dispatch({action,...extra})
    const flush=async()=>{
        const id=++request;await dispatch('flush',{request:id})
        assert(events.some(event=>event.type==='flushed'&&event.request===id),'Renderer flush completes')
        return events.findLast(event=>event.type==='location')
    }
    const page=index=>content.querySelector(`.pdf-page[data-index="${index}"]`)
    const layer=index=>page(index)?.querySelector('.textLayer')
    const text=index=>layer(index)?.textContent??''
    const point=(index,offset)=>{
        const walker=document.createTreeWalker(layer(index),NodeFilter.SHOW_TEXT)
        let node,total=0,last
        while((node=walker.nextNode())){
            last=node
            if(offset<=total+node.length)return [node,offset-total]
            total+=node.length
        }
        if(last&&offset===total)return [last,last.length]
        throw Error('Unmappable source endpoint '+index+':'+offset)
    }
    const sourcePoint=(node,offset)=>{
        const element=node.nodeType===Node.ELEMENT_NODE?node:node.parentElement
        const target=element.closest('.textLayer'),container=element.closest('.pdf-page')
        assert(target&&container,'Selection belongs to a PDF text layer')
        const before=document.createRange();before.selectNodeContents(target);before.setEnd(node,offset)
        return {page:Number(container.dataset.index),offset:before.toString().length}
    }
    const snapshot=()=>{
        const selection=document.getSelection()
        if(!selection.rangeCount||selection.isCollapsed)return null
        return {anchor:sourcePoint(selection.anchorNode,selection.anchorOffset),
            focus:sourcePoint(selection.focusNode,selection.focusOffset),raw:selection.getRangeAt(0).toString()}
    }
    const select=async(startPage,start,endPage,end,backward=false)=>{
        const a=point(startPage,start),b=point(endPage,end),selection=document.getSelection()
        selection.setBaseAndExtent(...(backward?b:a),...(backward?a:b))
        for(let i=0;i<50;i++){
            if(snapshot()&&events.some(event=>event.type==='selection'&&event.anchor))break
            await wait(20)
        }
        await wait(20)
        const saved=snapshot(),payload=events.findLast(event=>event.type==='selection'&&event.anchor)
        assert(saved&&payload,'Logical source selection is published: '+JSON.stringify({saved,events:events.slice(-8)}))
        return {saved,payload}
    }
    const settled=()=>events.filter(event=>event.type==='selection'&&event.settled).length
    const resize=async width=>{content.style.width=width+'px';await wait(250);await flush();await wait(40)}
    const assertSelection=(expected,message)=>assert(JSON.stringify(snapshot())===JSON.stringify(expected),message+': '+JSON.stringify({expected,actual:snapshot()}))
    Object.assign(content.style,{width:'820px',height:'600px',right:'auto',bottom:'auto'})
    await dispatch('appearance',{value:{flow:'scrolled',zoom:'fit-width',spread:false}})
    await dispatch('goto',{anchor:{page:1}});await dispatch('goto',{anchor:{page:0}})
    await wait(250);await flush()
    assert(layer(0)&&layer(1),'Both actual PDF text layers are rendered')
    const first=text(0).indexOf('exact'),second=text(1).indexOf('library')
    assert(first>=0&&second>=0,'Fixture words exist')
    // Pause in the same turn, before the browser's selectionchange callback.
    // Geometry must capture the actual range, not require a published cache.
    document.getSelection().setBaseAndExtent(...point(0,first),...point(0,first+5))
    const immediate=snapshot()
    await dispatch('layoutVisibility',{visible:false,revision:++revision,request:++request})
    content.style.width='740px'
    await dispatch('layoutVisibility',{visible:true,revision:++revision,request:++request})
    await wait(250);await flush();await wait(40)
    assertSelection(immediate,'Geometry captures selection before its pending browser event')
    checks.push('capture-before-selectionchange')
    for(const backward of [false,true]){
        const {saved,payload}=await select(0,first,1,second+7,backward)
        const originalAnchor=JSON.stringify(payload.anchor),beforeSettled=settled(),position=await flush()
        await resize(backward?620:680)
        assertSelection(saved,'Multi-page endpoints and direction survive geometry')
        assert(JSON.stringify(events.findLast(event=>event.type==='selection'&&event.anchor).anchor)===originalAnchor,'Original PDF-unit anchor is unchanged')
        assert(settled()===beforeSettled,'Resize does not settle/reopen a selection popup')
        assert((await flush()).anchor.page===position.anchor.page,'Geometry retains the source page')
        checks.push(backward?'multi-page-backward':'multi-page-forward')
    }
    const {saved}=await select(0,first,0,first+5)
    const hiddenSettled=settled()
    const editor=document.createElement('input');editor.value='Notebook keeps focus';document.body.append(editor)
    await dispatch('layoutVisibility',{visible:false,revision:++revision,request:++request})
    editor.focus();document.getSelection().removeAllRanges();content.style.width='420px'
    await wait(200)
    content.style.width='720px'
    await dispatch('layoutVisibility',{visible:true,revision:++revision,request:++request})
    await wait(250);await flush();await wait(40)
    assertSelection(saved,'Collapsed/revealed geometry retains the logical PDF range')
    assert(document.activeElement===editor,'Selection restoration does not focus the publication')
    assert(settled()===hiddenSettled,'Hidden geometry does not reopen the selection popup')
    checks.push('hidden-resume-without-focus-theft')
    await select(0,first,0,first+5)
    content.style.width='640px';document.getSelection().removeAllRanges()
    await wait(250);await flush();await wait(40)
    assert(snapshot()===null,'A deliberately cleared selection is not revived')
    checks.push('clear-before-relayout')
    const other=text(0).indexOf('library')
    await select(0,first,0,first+5)
    content.style.width='760px'
    const replacement=await select(0,other,0,other+7,true)
    await wait(250);await flush();await wait(40)
    assertSelection(replacement.saved,'A replacement selection supersedes the old range')
    checks.push('replacement-before-relayout')
    await select(0,first,0,first+5)
    content.style.width='660px'
    await dispatch('goto',{anchor:{page:1,textOffset:second,textLength:7}})
    await wait(250);await flush();await wait(40)
    assert(snapshot()?.anchor.page===1&&document.getSelection().toString()==='library','Accepted navigation supersedes an earlier geometry selection')
    checks.push('navigation-supersedes-geometry')
    await dispatch('goto',{anchor:{page:0}})
    await select(0,first,0,first+5)
    const link=page(0).querySelector('a.pdf-link')
    assert(link,'Fixture has an internal PDF destination')
    content.style.width='700px'
    // Keyboard activation follows click without a primary pointerdown. Public
    // focus/click exercise that path without changing dependency behavior.
    link.focus({preventScroll:true});link.click()
    await wait(250);await flush();await wait(40)
    assert(snapshot()===null,'Internal-link acceptance abandons the prior selection before queueing')
    assert((await flush()).anchor.page===3,'Internal destination survives geometry')
    await resize(630)
    assert(snapshot()===null&&(await flush()).anchor.page===3,'Later geometry cannot revive the link origin selection')
    await dispatch('back');assert((await flush()).anchor.page===0,'Internal link preserves navigation history')
    checks.push('keyboard-link-supersedes-geometry')
    editor.remove()
    const value={type:'formatProof',passed:true,checks}
    window.reviewResult=value
    const json=JSON.stringify(value)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json);else window.chrome.webview.postMessage(json)
})().catch(error=>{
    const value={type:'formatProof',passed:false,message:String(error),stack:error.stack};window.reviewResult=value
    const json=JSON.stringify(value)
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(json);else window.chrome.webview.postMessage(json)
})
