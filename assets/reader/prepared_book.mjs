// Foliate book interface over the worker's deterministic FB2 documents.
// No generic/demo loaders, network resources or replacement publication.
export async function makePreparedFB2(index,loader,sanitize) {
    if(index.version!==1||index.format!=='fb2')throw Error('Unsupported FB2 cache version')
    const live=new Map(),pending=new Map(),controller=new AbortController(),book={metadata:index.metadata,toc:index.toc??[],dir:'ltr'}
    let closed=false
    const resolve=href=>href.startsWith('sections/')||href.startsWith('binary/')?href:href
    book.isExternal=href=>/^[a-z][a-z\d+.-]*:/i.test(href)
    book.loadBlob=loader.loadBlob
    book.resources={getItemByHref:()=>({mediaType:''})}
    book.sections=index.sections.map((section,i)=>{
        const path=section.path
        const createDocument=async()=>{
            if(closed)throw Error('FB2 closed')
            return new DOMParser().parseFromString(sanitize(await loader.loadText(path,{signal:controller.signal})),'application/xhtml+xml')
        }
        return {id:path,identity:section.id,notes:section.notes,size:loader.getSize(path),cfi:`epubcfi(/6/${(i+1)*2})`,
            createDocument,resolveHref:resolve,
            load:async()=>{
                if(live.has(i))return live.get(i)[0]
                if(pending.has(i))return pending.get(i)
                const operation=(async()=>{
                    const urls=[]
                    try{
                        const doc=await createDocument()
                        for(const img of doc.querySelectorAll('img[src]')){
                            const blob=await loader.loadBlob(img.getAttribute('src'),null,{signal:controller.signal})
                            if(closed)throw Error('FB2 closed')
                            if(blob){const url=URL.createObjectURL(blob);urls.push(url);img.setAttribute('src',url)}else img.removeAttribute('src')
                        }
                        const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(doc)],{type:'application/xhtml+xml'}))
                        live.set(i,[url,...urls]);return url
                    }catch(error){for(const url of urls)URL.revokeObjectURL(url);throw error}
                })()
                pending.set(i,operation)
                try{return await operation}finally{pending.delete(i)}
            },
            unload:()=>{for(const url of live.get(i)??[])URL.revokeObjectURL(url);live.delete(i)},
        }
    })
    book.resolveHref=href=>{
        const [path,hash]=href.split('#'),i=book.sections.findIndex(s=>s.id===path)
        if(i<0)throw Error('FB2 destination is unavailable')
        return {index:i,anchor:hash?doc=>doc.getElementById(decodeURIComponent(hash)):()=>0}
    }
    book.splitTOCHref=href=>href.split('#')
    book.getTOCFragment=(doc,id)=>doc.getElementById(decodeURIComponent(id))
    book.destroy=()=>{closed=true;controller.abort();for(const section of book.sections)section.unload()}
    return book
}
