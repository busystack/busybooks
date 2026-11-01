// EPUB-contained DTBook only. Keep the content tree, IDs and publisher tag
// selectors stable; supply HTML semantics and default block presentation.
export function adaptXMLIsland(text, stylesheet, namespace) {
    const source=new DOMParser().parseFromString(text,'application/xml')
    if(source.querySelector('parsererror'))throw Error('Damaged EPUB XML island')
    if(!namespace||source.documentElement.namespaceURI!==namespace)throw Error('EPUB XML island namespace does not match its manifest')
    const ns='http://www.w3.org/1999/xhtml',doc=document.implementation.createDocument(ns,'html')
    const head=doc.createElementNS(ns,'head'),body=doc.createElementNS(ns,'body'),link=doc.createElementNS(ns,'link')
    link.setAttribute('rel','stylesheet');link.setAttribute('href',stylesheet)
    head.append(link);doc.documentElement.append(head,body)
    // Import the original vocabulary and namespaces so publisher CSS selectors,
    // IDs and text ranges have the same tree in rendering and createDocument.
    body.append(doc.importNode(source.documentElement,true))
    return new XMLSerializer().serializeToString(doc)
}
export function adaptDTBook(text) {
    const source=new DOMParser().parseFromString(text,'application/xml')
    if(source.documentElement.localName!=='dtbook')return text
    if(source.querySelector('parsererror'))throw Error('Damaged EPUB DTBook')
    const ns='http://www.w3.org/1999/xhtml',doc=document.implementation.createDocument(ns,'html')
    const head=doc.createElementNS(ns,'head'),body=doc.createElementNS(ns,'body')
    doc.documentElement.append(head,body)
    const lang=source.documentElement.getAttribute('xml:lang')??source.documentElement.getAttribute('lang')
    if(lang)doc.documentElement.setAttribute('lang',lang)
    const style=doc.createElementNS(ns,'style')
    style.textContent='frontmatter,bodymatter,rearmatter,level,level1,level2,level3,level4,level5,level6,doctitle,docauthor,byline,dateline,epigraph,poem,linegroup,line,div,sidebar,prodnote,imggroup,caption,annotation,note {display:block} doctitle,levelhd,hd {display:block;font-size:1.3em;font-weight:bold} pagenum {font-size:.8em} img {max-width:100%} table {border-collapse:collapse} td,th {padding:.25em}'
    head.append(style)
    for(const node of source.childNodes)if(node.nodeType===7&&node.target==='xml-stylesheet'){
        const href=/href\s*=\s*['"]([^'"]+)['"]/.exec(node.data)?.[1]
        if(href){const link=doc.createElementNS(ns,'link');link.setAttribute('rel','stylesheet');link.setAttribute('href',href);head.append(link)}
    }
    function convert(node){
        if(node.nodeType===3||node.nodeType===4)return doc.createTextNode(node.textContent)
        if(node.nodeType!==1)return null
        const name=node.localName,el=doc.createElementNS(ns,name==='noteref'?'a':name==='pagenum'?'span':name)
        for(const attr of node.attributes)if(!/^on/i.test(attr.name)&&!['xmlns','smilref'].includes(attr.localName)&&!/^xmlns:/.test(attr.name))el.setAttribute(attr.name,attr.value)
        if(name==='noteref'){el.setAttribute('role','doc-noteref');const ref=node.getAttribute('idref');if(ref)el.setAttribute('href',ref)}
        if(name==='note')el.setAttribute('role','doc-footnote')
        if(name==='pagenum'){el.setAttribute('role','doc-pagebreak');el.setAttribute('aria-label',node.textContent.trim())}
        if(/^level[1-6]?$/.test(name)){el.setAttribute('role','region');el.classList.add(name)}
        if(name==='levelhd'||name==='hd'){el.setAttribute('role','heading');el.setAttribute('aria-level',String(Math.min(6,Math.max(1,[...ancestors(node)].filter(n=>/^level[1-6]?$/.test(n.localName)).length))))}
        for(const child of node.childNodes){const converted=convert(child);if(converted)el.append(converted)}
        return el
    }
    function* ancestors(node){for(let parent=node.parentElement;parent;parent=parent.parentElement)yield parent}
    const book=[...source.documentElement.children].find(n=>n.localName==='book')
    if(!book)throw Error('EPUB DTBook has no book content')
    for(const node of book.childNodes){const converted=convert(node);if(converted)body.append(converted)}
    return new XMLSerializer().serializeToString(doc)
}
