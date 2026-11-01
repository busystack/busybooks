// Actual packaged adapter, DOM selection and native message frames.
(async()=>{
    const events=[],frames=[],checks=[]
    const assert=(value,message)=>{if(!value)throw Error(message)}
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))
    window.busybooksProbe=event=>events.push(event)
    const bridge=window.webkit?.messageHandlers?.busybooks??window.chrome?.webview
    const post=bridge.postMessage.bind(bridge)
    bridge.postMessage=json=>{frames.push(json);post(json)}
    const view=document.querySelector('foliate-view'),book=view?.book
    if(book?.comic){
        const section=book.sections[0],doc=busybooks.contents()[0]?.doc,img=doc?.querySelector('img')
        await img?.decode()
        assert(section.width===900&&section.height===600&&section.pageSpread==='center','Oriented comic descriptor is landscape and centered')
        assert(img?.naturalWidth===900&&img.naturalHeight===600,'Native JPEG decoder displays EXIF-oriented geometry despite marker fill')
        checks.push('oriented-marker-fill-comic')
    }else{
        const text=view?'📚'.repeat(300000):'x'.repeat(525000)
        const doc=view?busybooks.contents()[0]?.doc:document
        const host=view?doc.body:document.querySelector('.textLayer span')
        assert(host,'A real rendered text document exists')
        const node=doc.createTextNode(text)
        if(view){
            const span=doc.createElement('span');span.style.cssText='position:absolute;white-space:pre;font-size:1px;line-height:1px';span.append(node);host.append(span)
        }else{host.replaceChildren(node)}
        const range=doc.createRange();range.selectNodeContents(node)
        const selected=doc.getSelection();selected.removeAllRanges();selected.addRange(range)
        doc.dispatchEvent(new Event('selectionchange'))
        await wait(60)
        const selection=events.findLast(e=>e.type==='selection'&&e.text===text)
        assert(selection,'Large selection is delivered intact from the actual DOM')
        if(!view){
            assert(selection.anchor.segments[0].length===text.length,'PDF anchor stores UTF-16 length')
            assert(!Object.hasOwn(selection.anchor.segments[0],'text'),'PDF anchor does not duplicate the quotation')
            checks.push('verified-pdf-snapshot-renders','compact-pdf-selection')
        }
        const chunks=frames.map(json=>JSON.parse(json)).filter(frame=>frame.type==='bridgeChunk')
        assert(chunks.length>1,'Oversized native events are chunked')
        const transfer=chunks.filter(frame=>frame.bridgeRevision===chunks[0].bridgeRevision)
        assert(JSON.parse(transfer.map(frame=>frame.chunk).join('')).text===text,'Native event frames reconstruct the complete quotation')
        await busybooks.dispatch({action:'passage',request:700})
        assert(events.findLast(e=>e.type==='passage')?.text===text,'On-demand narration retains the complete selection')
        selected.removeAllRanges()
        await busybooks.dispatch({action:'flush',request:701})
        const location=events.findLast(e=>e.type==='location')
        assert(location&&!Object.hasOwn(location,'text'),'Flushed location omits passage text')
        assert(events.at(-1).type==='flushed','Location precedes the flush acknowledgement')
        checks.push('native-large-selection-frames','on-demand-narration','compact-flushed-location')
    }
    assert(frames.every(json=>new TextEncoder().encode(json).byteLength<=1048576),'Every native frame respects the byte limit')
    window.reviewResult={passed:true,checks}
    const result={type:'formatProof',session:'probe',...window.reviewResult}
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(JSON.stringify(result))
    else window.chrome.webview.postMessage(JSON.stringify(result))
})().catch(error=>{
    window.reviewResult={passed:false,error:String(error),stack:error.stack}
    const result=JSON.stringify({type:'formatProof',...window.reviewResult})
    if(window.webkit?.messageHandlers?.busybooks)window.webkit.messageHandlers.busybooks.postMessage(result)
    else window.chrome.webview.postMessage(result)
})
