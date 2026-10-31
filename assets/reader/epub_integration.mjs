// BusyBooks' supplied loader and book interface around unmodified Foliate EPUB.
// Original archive bytes and itemref order/IDs remain the locator authority.
import { EPUB } from './vendor/foliate/epub.js'
import { adaptDTBook, adaptXMLIsland } from './dtbook.mjs'

const OPF='http://www.idpf.org/2007/opf',XLINK='http://www.w3.org/1999/xlink'
const XHTML='application/xhtml+xml',HTML='text/html',SVG='image/svg+xml',CSS='text/css'
const contentTypes=new Set([XHTML,HTML,SVG])
const imageTypes=new Set(['image/png','image/jpeg','image/gif','image/webp'])
const external=href=>/^(?!blob:)[a-z][a-z\d+.-]*:/i.test(href)
const encodePath=value=>value.split('/').map(encodeURIComponent).join('/')
const split=href=>{const at=href.indexOf('#');return at<0?[href,'']:[href.slice(0,at),href.slice(at+1)]}
const instructionHref=/(\bhref\s*=\s*)(['"])(.*?)\2/i
const setInstructionHref=(data,value)=>data.replace(instructionHref,(_,name,quote)=>name+quote+value+quote)
const serialize=doc=>new XMLSerializer().serializeToString(doc)
const parse=(text,type='application/xml')=>{
    const doc=new DOMParser().parseFromString(text,type)
    if(doc.querySelector('parsererror'))throw Error('Invalid publication document')
    return doc
}

// Archive paths are decoded once; URL fragments never become archive paths.
export function resolvePublicationHref(href,base=''){
    if(typeof href!=='string')throw Error('Invalid publication destination')
    if(external(href)||href.startsWith('blob:'))return href
    const root='https://busybooks.invalid/'
    const url=new URL(href,root+encodePath(base))
    if(url.origin!=='https://busybooks.invalid')return url.href
    return encodePath(decodeURIComponent(url.pathname.slice(1)))+url.hash
}

function cssReferences(text,visit){
    // Only URL-bearing tokens change; publisher declarations and text stay intact.
    return text.replace(/url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^)]*?))\s*\)|@import\s+(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')/gi,
        (token,a,b,c,d,e)=>{
            const value=a??b??c??d??e,changed=visit(value.trim())
            if(changed===value.trim())return token
            return /^@import/i.test(token)?`@import "${changed}"`:`url("${changed}")`
        })
}

function srcsetReferences(text,visit){
    let cursor=0,result=''
    while(cursor<text.length){
        const start=cursor
        while(cursor<text.length&&/[\t\n\f\r ,]/.test(text[cursor]))cursor++
        result+=text.slice(start,cursor)
        const urlStart=cursor
        while(cursor<text.length&&!/[\t\n\f\r ]/.test(text[cursor]))cursor++
        let end=cursor
        while(end>urlStart&&text[end-1]===',')end--
        result+=visit(text.slice(urlStart,end))+text.slice(end,cursor)
        if(end<cursor)continue
        const descriptor=cursor;let brackets=0
        while(cursor<text.length){const c=text[cursor++];if(c==='(')brackets++;if(c===')')brackets--;if(c===','&&!brackets)break}
        result+=text.slice(descriptor,cursor)
    }
    return result
}

export async function makeEpubBook(index,loader,sanitize){
    const paths=new Map(),nativePaths=new Map(),engineNames=new Map(),prepared=new Map()
    let loadFailure=null
    const remember=(uri,metadata)=>{
        const queue=prepared.get(uri)??[]
        queue.push(metadata);prepared.set(uri,queue)
    }
    const take=uri=>{
        const queue=prepared.get(uri),metadata=queue?.shift()
        if(!queue?.length)prepared.delete(uri)
        return metadata
    }
    for(const name of Object.keys(index.resources)){
        paths.set(encodePath(name),name)
    }
    const originalPath=uri=>typeof uri==='string'?nativePaths.get(uri)??null:null
    const container=parse(await loader.loadText('META-INF/container.xml'))
    const rootfile=[...container.getElementsByTagNameNS('urn:oasis:names:tc:opendocument:xmlns:container','rootfile')]
        .find(el=>el.getAttribute('media-type')==='application/oebps-package+xml')
    const packagePath=rootfile?.getAttribute('full-path')
    if(!packagePath||!Object.hasOwn(index.resources,packagePath))throw Error('EPUB package is unavailable')
    const packageDoc=parse(await loader.loadText(packagePath))
    const manifest=packageDoc.getElementsByTagNameNS(OPF,'manifest')[0]
    const spine=packageDoc.getElementsByTagNameNS(OPF,'spine')[0]
    if(!manifest||!spine)throw Error('EPUB package has no manifest or spine')
    const legacy=packageDoc.documentElement.getAttribute('version')?.startsWith('2.')
    const normalizedType=type=>type==='application/x-dtbook+xml'||legacy&&type==='text/x-oeb1-document'?XHTML:legacy&&type==='text/x-oeb1-css'?CSS:type
    const items=[...manifest.children].filter(el=>el.localName==='item').map(el=>({
        el,id:el.getAttribute('id'),href:resolvePublicationHref(el.getAttribute('href'),packagePath),
        type:normalizedType(el.getAttribute('media-type')),fallback:el.getAttribute('fallback'),
        style:el.getAttribute('fallback-style'),namespace:el.getAttribute('required-namespace'),
        properties:el.getAttribute('properties')?.split(/\s+/)??[],
    }))
    const byID=new Map(items.map(item=>[item.id,item])),byHref=new Map(items.map(item=>[item.href,item]))
    for(const item of items)if(!external(item.href)){
        const path=decodeURIComponent(split(item.href)[0])
        paths.set(encodePath(path),path)
    }
    const spellings=new Map()
    for(const [canonical,path] of paths){
        const spelling=decodeURI(canonical),group=spellings.get(spelling)??[]
        group.push({canonical,path});spellings.set(spelling,group)
    }
    let serial=0
    for(const [spelling,group] of spellings){
        for(const {canonical,path} of group){
            let name=canonical
            if(group.length>1){
                do{name='__busybooks_loader_'+serial++}while(spellings.has(name))
            }
            engineNames.set(canonical,name)
            nativePaths.set(group.length>1?name:spelling,path)
        }
    }
    const engineReference=href=>{
        if(external(href)||href.startsWith('blob:'))return href
        const [path,fragment]=split(href)
        return '/'+(engineNames.get(path)??path)+(fragment?'#'+fragment:'')
    }
    let packageRequest='__busybooks_package'
    while(nativePaths.has(packageRequest)||spellings.has(packageRequest))packageRequest+='_'
    rootfile.setAttribute('full-path',packageRequest)
    function endpoint(item,forContent){
        const seen=new Set()
        while(item){
            if(seen.has(item.id))throw Error('Cyclic EPUB manifest fallback')
            seen.add(item.id)
            if(contentTypes.has(item.type)||!forContent&&imageTypes.has(item.type))return item
            if(item.style){
                const style=byID.get(item.style)
                if(style?.type!==CSS||!item.namespace)throw Error('Invalid EPUB XML island stylesheet')
                return {...item,type:XHTML,islandStyle:style.href}
            }
            if(!item.fallback)throw Error('Unsupported EPUB content without a fallback: '+item.type)
            item=byID.get(item.fallback)
        }
        throw Error('Missing EPUB manifest fallback target')
    }
    const spineItems=[...spine.children].filter(el=>el.localName==='itemref').map(el=>{
        const source=byID.get(el.getAttribute('idref'))
        if(!source)throw Error('EPUB spine item is unavailable')
        return {source,content:endpoint(source,true)}
    })
    const contentByHref=new Map()
    for(const item of items)if(contentTypes.has(item.type))contentByHref.set(item.href,item)
    for(const {content} of spineItems)contentByHref.set(content.href,content)
    for(const item of items){
        const target=spineItems.find(row=>row.source===item)?.content??item
        item.el.setAttribute('href',engineReference(target.href))
        item.el.setAttribute('media-type',target.type)
    }
    for(const reference of packageDoc.getElementsByTagNameNS(OPF,'reference')){
        const href=reference.getAttribute('href')
        if(href)reference.setAttribute('href',engineReference(resolvePublicationHref(href,packagePath)))
    }
    const navPaths=new Set(items.filter(item=>item.properties.includes('nav')||item.type==='application/x-dtbncx+xml').map(item=>item.href))
    const resourceTypes=new Map(items.map(item=>[item.href,item.type]))
    const recordHref=uri=>{
        const [path,fragment]=split(uri)
        const original=originalPath(path)
        return (original==null?path:encodePath(original))+(fragment?'#'+fragment:'')
    }
    function resource(href,base){
        if(!href||href.startsWith('#')||external(href)||href.startsWith('blob:'))return {value:href,fragment:''}
        const resolved=resolvePublicationHref(href,base),[path,fragment]=split(resolved),item=byHref.get(path)
        const target=item&&(item.fallback||item.style)&&!contentTypes.has(item.type)&&!imageTypes.has(item.type)&&item.type!==CSS&&!/^(?:font\/|application\/(?:font-|vnd\.ms-opentype))/.test(item.type)?endpoint(item,false):item
        return {value:engineReference(target?.href??path),fragment}
    }
    function prepareCSS(text,base){
        const fragments=[]
        const value=cssReferences(text,href=>{
            const target=resource(href,base)
            fragments.push(target.fragment)
            return target.value
        })
        return {value,fragments}
    }
    function restoreCSS(text,fragments){let i=0;return cssReferences(text,value=>{const fragment=fragments[i++];return fragment&&value.startsWith('blob:')?value+'#'+fragment:value})}
    function prepareDocument(doc,base,navigation=false){
        const records=[],instructions=[]
        for(const [ordinal,node] of [...doc.childNodes].entries())if(node.nodeType===7&&node.target==='xml-stylesheet'){
            const href=instructionHref.exec(node.data)?.[3]
            if(href==null)continue
            const target=resource(href,base)
            instructions.push({ordinal,original:node.data,fragment:target.fragment})
            node.data=setInstructionHref(node.data,target.value)
        }
        for(const [ordinal,el] of [...doc.querySelectorAll('*')].entries()){
            const attributes=[]
            const attr=(name,namespace=null)=>{
                const value=namespace?el.getAttributeNS(namespace,name):el.getAttribute(name)
                if(value==null)return
                const target=resource(value,base)
                if(namespace)el.setAttributeNS(namespace,'xlink:'+name,target.value);else el.setAttribute(name,target.value)
                if(target.fragment)attributes.push({name,namespace,fragment:target.fragment})
            }
            let svgHref
            if(el.namespaceURI==='http://www.w3.org/2000/svg'&&['image','use','feImage'].includes(el.localName)){
                const href=el.getAttribute('href')
                if(href!=null&&!href.startsWith('#')&&!external(href)){
                    const target=resource(href,base)
                    svgHref={fragment:target.fragment,xlink:el.getAttributeNS(XLINK,'href')}
                    el.removeAttribute('href');el.setAttributeNS(XLINK,'xlink:href',target.value)
                }
            }
            if(el.localName==='link')attr('href')
            for(const name of ['src','poster','data'])if(!(navigation&&el.localName==='content'&&name==='src'))attr(name)
            if(!svgHref&&el.hasAttributeNS(XLINK,'href')&&!el.hasAttribute('href'))attr('href',XLINK)
            const srcset=el.hasAttribute('srcset')?[]:null
            if(srcset)el.setAttribute('srcset',srcsetReferences(el.getAttribute('srcset'),href=>{const target=resource(href,base);srcset.push(target.fragment);return target.value}))
            const style=el.hasAttribute('style')?prepareCSS(el.getAttribute('style'),base):null
            if(style)el.setAttribute('style',style.value)
            const sheet=el.localName==='style'?prepareCSS(el.textContent,base):null
            if(sheet)el.textContent=sheet.value
            if(attributes.length||svgHref||srcset||style||sheet)records.push({ordinal,attributes,svgHref,srcset,style:style?.fragments,sheet:sheet?.fragments})
        }
        return {elements:records,instructions}
    }
    function restoreDocument(doc,{elements:records,instructions}){
        for(const row of instructions){
            const node=doc.childNodes[row.ordinal],href=node?.nodeType===7?instructionHref.exec(node.data)?.[3]:null
            if(href==null)throw Error('Publication resource transform changed its stylesheet instruction')
            // Keep the publisher's valid attribute formatting around the
            // official loader's resolved URL; its PI formatter can join attrs.
            node.data=setInstructionHref(row.original,href+(row.fragment&&href.startsWith('blob:')?'#'+row.fragment:''))
        }
        const elements=[...doc.querySelectorAll('*')]
        for(const row of records){
            const el=elements[row.ordinal]
            if(!el)throw Error('Publication resource transform changed its element structure')
            for(const {name,namespace,fragment} of row.attributes){
                const value=namespace?el.getAttributeNS(namespace,name):el.getAttribute(name)
                if(value?.startsWith('blob:')){if(namespace)el.setAttributeNS(namespace,'xlink:'+name,value+'#'+fragment);else el.setAttribute(name,value+'#'+fragment)}
            }
            if(row.svgHref){
                const value=el.getAttributeNS(XLINK,'href')
                el.setAttribute('href',value+(row.svgHref.fragment&&value?.startsWith('blob:')?'#'+row.svgHref.fragment:''))
                if(row.svgHref.xlink==null)el.removeAttributeNS(XLINK,'href');else el.setAttributeNS(XLINK,'xlink:href',row.svgHref.xlink)
            }
            if(row.srcset){let i=0;el.setAttribute('srcset',srcsetReferences(el.getAttribute('srcset'),value=>{const fragment=row.srcset[i++];return fragment&&value.startsWith('blob:')?value+'#'+fragment:value}))}
            if(row.style)el.setAttribute('style',restoreCSS(el.getAttribute('style'),row.style))
            if(row.sheet)el.textContent=restoreCSS(el.textContent,row.sheet)
        }
    }
    async function documentText(path){
        let text=await loader.loadText(path)
        if(!text)throw Error('Publication resource is unavailable: '+path)
        const item=contentByHref.get(encodePath(path))
        text=adaptDTBook(text)
        if(item?.islandStyle){
            const stylesheet=new URL('/'+item.islandStyle,'https://busybooks.invalid/').pathname
            text=adaptXMLIsland(text,stylesheet,item.namespace)
        }
        let doc
        const type=item?.type===HTML?HTML:item?.type===SVG?SVG:XHTML
        try{doc=parse(text,type)}catch(error){if(type!==XHTML)throw error;doc=parse(text,HTML)}
        for(const el of doc.querySelectorAll('style[type="text/x-oeb1-css"],link[type="text/x-oeb1-css"]'))el.setAttribute('type',CSS)
        return sanitize(serialize(doc))
    }
    const supplied={
        loadText:async(uri,options)=>{
            // The container's private loader key never changes the original
            // package DOM, itemref CFIs, publication bytes or public hrefs.
            if(uri==='META-INF/container.xml')return serialize(container)
            if(uri===packageRequest)return serialize(packageDoc)
            const path=originalPath(uri)
            if(!path)return null
            const canonical=encodePath(path),item=contentByHref.get(canonical)
            if(item||navPaths.has(canonical)){
                const doc=parse(await documentText(path),item?.type===SVG?SVG:XHTML)
                if(navPaths.has(canonical))for(const el of doc.querySelectorAll('a[href],content[src]')){
                    const name=el.localName==='content'?'src':'href',href=el.getAttribute(name)
                    try{decodeURIComponent(href);el.setAttribute(name,engineReference(resolvePublicationHref(href,path)).replaceAll('%','%25'))}catch{el.setAttribute(name,'')}
                }
                const records=prepareDocument(doc,path,navPaths.has(canonical))
                remember(uri,{kind:'document',records})
                return serialize(doc)
            }
            const text=await loader.loadText(path,options)
            if(resourceTypes.get(canonical)===CSS&&text!=null){const css=prepareCSS(text,path);remember(uri,{kind:'css',fragments:css.fragments});return css.value}
            if(path==='META-INF/encryption.xml'&&text){
                const doc=parse(text)
                for(const el of doc.querySelectorAll('CipherReference[URI]'))el.setAttribute('URI',decodeURI(engineReference(resolvePublicationHref(el.getAttribute('URI'))).slice(1)))
                return serialize(doc)
            }
            return text
        },
        loadBlob:(uri,...args)=>{const path=originalPath(uri);return path==null?null:loader.loadBlob(path,...args)},
        getSize:uri=>{const path=originalPath(uri);return path==null?0:loader.getSize(path)},
    }
    const upstream=await new EPUB(supplied).init()
    upstream.transformTarget.addEventListener('data',event=>{
        event.detail.data=Promise.resolve(event.detail.data).then(async value=>{
            // Recursive resource loads can supply a raw Blob without the text
            // preparation step. Only consume metadata for replaced text.
            const metadata=typeof value==='string'?take(event.detail.name):null
            if(!metadata)return value
            const text=value
            if(metadata.kind==='css')return restoreCSS(text,metadata.fragments)
            const doc=parse(text,event.detail.type===SVG?SVG:XHTML)
            restoreDocument(doc,metadata.records)
            return sanitize(serialize(doc))
        })
    })
    function destination(href){
        if(typeof href!=='string')return null
        try{
            const [path,fragment]=split(resolvePublicationHref(href)),item=byHref.get(path)
            if(!item)return null
            const content=endpoint(item,true)
            const index=spineItems.findIndex(row=>row.source===item||row.content.href===content.href)
            if(index<0)return null
            const id=fragment?decodeURIComponent(fragment):''
            return {index,anchor:id?doc=>doc.getElementById(id)??[...doc.getElementsByName(id)][0]:()=>0}
        }catch{return null}
    }
    const canonicalRows=rows=>rows?.map(row=>({...row,href:typeof row.href==='string'?recordHref(row.href):row.href,subitems:canonicalRows(row.subitems)}))
    const book={
        metadata:structuredClone(upstream.metadata),rendition:structuredClone(upstream.rendition),media:structuredClone(upstream.media),dir:upstream.dir,
        toc:canonicalRows(upstream.toc),pageList:canonicalRows(upstream.pageList),landmarks:canonicalRows(upstream.landmarks),resourceTypes,
        sections:upstream.sections.map((section,i)=>{
            const {source,content}=spineItems[i]
            return {...section,id:content.href,sourceHref:source.href,contentHref:content.href,
                load:async()=>{
                    try{
                        const url=await section.load()
                        if(!url)throw Error('Publication resource is unavailable: '+decodeURIComponent(content.href))
                        return url
                    }catch(error){loadFailure=error;throw error}
                },unload:()=>section.unload(),
                createDocument:async()=>parse(await documentText(paths.get(content.href)),content.type===SVG?SVG:XHTML),
                resolveHref:href=>resolvePublicationHref(href,paths.get(content.href)),
            }
        }),
        resolveCFI:cfi=>upstream.resolveCFI(cfi),resolveHref:destination,isExternal:external,
        splitTOCHref:href=>{const target=destination(href);return target?[spineItems[target.index].content.href,split(href)[1]?decodeURIComponent(split(href)[1]):'']:[null,null]},
        getTOCFragment:(doc,id)=>doc.getElementById(id)??[...doc.getElementsByName(id)][0],
        getCover:()=>upstream.getCover(),getMediaOverlay:()=>upstream.getMediaOverlay(),
        takeLoadError:()=>{const error=loadFailure;loadFailure=null;return error},
        loadBlob:(href,type,options)=>{
            const canonical=resolvePublicationHref(href),path=paths.get(split(canonical)[0])
            return path==null?null:loader.loadBlob(path,type??resourceTypes.get(split(canonical)[0]),options)
        },
        destroy:()=>{prepared.clear();upstream.destroy()},
    }
    return book
}
