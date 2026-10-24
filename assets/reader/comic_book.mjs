export function comicAnchor(book,index,extra={}) {
    if(!Number.isInteger(index)||index<0||index>=book.sections.length)throw Error('Invalid comic page')
    return {kind:'comic',version:1,format:book.format,page:index,pageId:book.sections[index].pageId,...extra}
}
export function normalizedRegion(rect) {
    if(!Array.isArray(rect)||rect.length!==4||rect.some(n=>!Number.isFinite(n)))throw Error('Invalid image region')
    const [x,y,w,h]=rect
    if(x<0||y<0||w<=0||h<=0||x+w>1.000000001||y+h>1.000000001)throw Error('Image region is outside its page')
    return rect
}
export async function decodeComicImage(blob,signal) {
    const url=URL.createObjectURL(blob),image=new Image()
    let cancel
    const abort=()=>cancel?.(Error('Comic image decoding cancelled'))
    try {
        if(signal?.aborted)throw Error('Comic image decoding cancelled')
        signal?.addEventListener('abort',abort,{once:true})
        image.src=url;await Promise.race([image.decode(),new Promise((_,reject)=>{cancel=reject})])
        if(!image.naturalWidth||!image.naturalHeight||image.naturalWidth>16000||image.naturalHeight>16000||image.naturalWidth*image.naturalHeight>33554432)throw Error('Comic image exceeds decoded pixel limits')
        return {image,url,width:image.naturalWidth,height:image.naturalHeight,release:()=>{image.src='';URL.revokeObjectURL(url)}}
    } catch(error){image.src='';URL.revokeObjectURL(url);throw error}
    finally{signal?.removeEventListener('abort',abort)}
}
export function makeComicBook(index,loader) {
    if(![1,2].includes(index.version)||!['cbz','cbr'].includes(index.format))throw Error('Unsupported comic cache version')
    const live=new Map(),pending=new Map(),controller=new AbortController()
    let closed=false
    const book={format:index.format,comic:true,metadata:index.metadata,dir:index.metadata?.direction??'ltr',rendition:{layout:'pre-paginated',spread:'both'}}
    book.sections=index.pages.map((page,i)=>{
        const unload=()=>{const state=live.get(i);if(state){URL.revokeObjectURL(state.document);URL.revokeObjectURL(state.image);live.delete(i)}}
        return {id:page.name,pageId:page.file,size:page.size,width:page.width,height:page.height,
            pageSpread:page.wide||page.width>page.height?'center':undefined,
            cfi:`epubcfi(/6/${(i+1)*2})`,
            load:async()=>{
                if(live.has(i))return live.get(i).document
                if(pending.has(i))return pending.get(i)
                const operation=(async()=>{
                    const decoded=await decodeComicImage(await loader.loadBlob(page.name,null,{signal:controller.signal}),controller.signal)
                    const {width,height,url}=decoded
                    // The detached decoder image does not retain another full
                    // page after the iframe takes ownership of the same Blob.
                    decoded.image.src=''
                    if(closed){URL.revokeObjectURL(url);throw Error('Comic closed')}
                    const html=`<html xmlns="http://www.w3.org/1999/xhtml"><head><meta name="viewport" content="width=${width},height=${height}"/><style>html,body{margin:0;padding:0;width:${width}px;height:${height}px;overflow:hidden;background:white}img{display:block;width:100%;height:100%;image-orientation:from-image;user-select:none;-webkit-user-select:none}body{touch-action:pan-x pan-y}</style></head><body tabindex="0"><img alt="${i+1}" src="${url}"/></body></html>`
                    const document=URL.createObjectURL(new Blob([html],{type:'application/xhtml+xml'}))
                    live.set(i,{document,image:url});return document
                })()
                pending.set(i,operation)
                try{return await operation}finally{pending.delete(i)}
            },unload,
        }
    })
    book.toc=index.pages.flatMap((page,i)=>page.bookmark?[{label:page.bookmark,href:String(i)}]:[])
    book.resolveHref=href=>({index:Number(href)})
    book.isExternal=()=>false
    book.releaseExcept=indices=>{for(const i of live.keys())if(!indices.has(i))book.sections[i].unload()}
    book.destroy=()=>{closed=true;controller.abort();book.releaseExcept(new Set())}
    book.liveResources=()=>live.size
    return book
}
