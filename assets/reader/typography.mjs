// Application adapter utilities. All family/face names are data, never script,
// HTML, or preformatted CSS supplied by a publication.
export const noTypography = Object.freeze({fontFamily:false,textMetrics:false})
export const reflowableTypography = Object.freeze({fontFamily:true,textMetrics:true})
export function validFamily(value){
    return typeof value==='string'&&value.length>0&&value.length<=256&&value.trim()===value&&!/[\u0000-\u001f\u007f-\u009f\ud800-\udfff\ufffd]/u.test(value)
}
export function cssString(value){
    if(!validFamily(value))throw Error('Invalid font family')
    return '"'+value.replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"'
}
export function fontChoice(value){
    if(['serif','sans-serif','monospace'].includes(value))return {generic:value}
    const family=typeof value==='string'?value:value?.family
    if(!validFamily(family))throw Error('Invalid font family')
    return {family}
}
export function localSources(face){
    if(!Array.isArray(face.sources)||!face.sources.length||face.sources.length>8||!Number.isInteger(face.weight)||face.weight<1||face.weight>1000||typeof face.italic!=='boolean')throw Error('Invalid local font face')
    return face.sources.map(name=>'local('+cssString(name)+')').join(',')
}
const fonts=new WeakMap()
const preparedFonts=new WeakMap()
export function createLocalFont(resolution){
    if(!resolution?.faces?.length)return {family:'serif',faces:[]}
    if(!validFamily(resolution.family)||resolution.faces.length>18)throw Error('Invalid resolved font')
    const alias='busybooks-local-'+Array.from(crypto.getRandomValues(new Uint32Array(4)),n=>n.toString(16)).join('-')
    const seen=new Set(),faces=[]
    for(const face of resolution.faces){
        const source=localSources(face),key=JSON.stringify([source,face.weight,face.italic])
        if(seen.has(key))continue
        seen.add(key);faces.push({name:alias,source,descriptors:{weight:String(face.weight),style:face.italic?'italic':'normal'}})
    }
    // Missing faces remain missing: CSS can then synthesize emphasis from the
    // actual regular face. Labeling a regular face as bold would suppress that.
    return {family:cssString(alias)+', serif',faces}

}
export function prepareLocalFont(doc,font){
    if(!font.faces.length)return Promise.resolve()
    let prepared=preparedFonts.get(doc)
    if(!prepared){prepared=new WeakMap();preparedFonts.set(doc,prepared)}
    if(prepared.has(font))return prepared.get(font).ready
    const faces=font.faces.map(f=>new FontFace(f.name,f.source,f.descriptors))
    const entry={faces,loaded:false,ready:null}
    // Load without removing the visible family or publishing the candidate.
    // A cancelled load must leave both its pixels and FontFaceSet intact.
    entry.ready=Promise.all(faces.map(f=>f.load())).then(()=>{entry.loaded=true},error=>{prepared.delete(font);throw error})
    prepared.set(font,entry);return entry.ready
}
export function activateLocalFont(doc,font){
    const installed=fonts.get(doc)
    if(installed?.font===font)return
    const entry=font.faces.length?preparedFonts.get(doc)?.get(font):{faces:[],loaded:true}
    if(!entry?.loaded)throw Error('Local font is not ready')
    for(const face of entry.faces)doc.fonts.add(face)
    if(installed)for(const face of installed.faces)doc.fonts.delete(face)
    fonts.set(doc,{font,faces:entry.faces})
}
export async function installLocalFont(doc,font,current=()=>true){
    // FontFace.load(local(...)) rejects absent faces. fonts.check() is never an
    // existence test: that method can succeed through fallback.
    await prepareLocalFont(doc,font)
    if(!current())return false
    activateLocalFont(doc,font);return true
}
const specialized='pre,code,kbd,samp,var,math,svg,[role="math"],[data-busybooks-preserve-font]'
const exclusions=specialized.split(',').flatMap(s=>[s,s+' *']).join(',')
const prose='p,li,blockquote,dd,dt,div,section,article,h1,h2,h3,h4,h5,h6,span,a,em,strong,b,i,small,sub,sup,td,th,figcaption,caption,label'
export function typographyCSS(p,family,scope='',capabilities=reflowableTypography){
    if(p.publisher)return ''
    const root=scope||'body',prefix=scope?scope+' ':''
    const bodies=prose.split(',').map(s=>prefix+s).join(',')
    const selector=`:where(${root},${bodies}):not(:where(${exclusions}))`
    const number=(v,min,max,fallback)=>typeof v==='number'&&Number.isFinite(v)?Math.min(max,Math.max(min,v)):fallback
    const size=number(p.size,12,40,20),weight=number(p.weight,300,700,400),line=number(p.line,1,2.2,1.5),paragraph=number(p.paragraph,0,2,.6)
    // Only family is replaced on headings and inline emphasis. Their authored
    // size, weight and style retain hierarchy/bold/italic. Code/math/symbol
    // families and their descendants keep publication typography.
    const families=capabilities.fontFamily?`${selector}{font-family:${family}!important}`:''
    const metrics=capabilities.textMetrics?`${root}{font-size:${size}px!important;font-weight:${weight};line-height:${line}!important}${prefix}p,${prefix}li,${prefix}blockquote,${prefix}dd{font-size:${size}px!important;line-height:${line}!important;text-align:${['start','justify','center'].includes(p.align)?p.align:'start'}!important;hyphens:${p.hyphenate===false?'none':'auto'}!important}${prefix}p{margin-block:${paragraph}em!important}`:''
    return families+metrics
}
// Keep specialist fonts even when their parent body's inherited family changes.
// CSSOM serializes the publication's *computed* family as a property value.
const protectedFonts=new WeakMap()
export function protectSpecializedFonts(doc){
    if(protectedFonts.has(doc))return protectedFonts.get(doc)
    const sheet=doc.createElement('style');doc.head?.append(sheet)
    let index=0
    for(const node of doc.querySelectorAll('pre,code,kbd,samp,var,math,svg,[role="math"],[class],[style]')){
        const family=doc.defaultView.getComputedStyle(node).fontFamily
        if(!node.matches('pre,code,kbd,samp,var,math,svg,[role="math"]')&&!/math|symbol|dingbat|icon/i.test(family+' '+node.getAttribute('class')))continue
        node.setAttribute('data-busybooks-preserve-font',String(index))
        const i=sheet.sheet.insertRule(`[data-busybooks-preserve-font="${index++}"]{}`,sheet.sheet.cssRules.length)
        sheet.sheet.cssRules[i].style.setProperty('font-family',family,'important')
    }
    protectedFonts.set(doc,sheet);return sheet
}
export class TypographyWork {
    revision=0; navigation=0; active=null
    begin(anchor){
        const previous=this.active
        const work={revision:++this.revision,navigation:this.navigation,anchor:previous?.navigation===this.navigation?previous.anchor:anchor}
        this.active=work;return work
    }
    current(work){return this.active===work}
    canRestore(work){return this.current(work)&&this.navigation===work.navigation}
    navigate(){this.navigation++}
    finish(work){if(this.current(work))this.active=null}
}

const inlineFamilies=new WeakMap()
export function applyFontFamily(root,family){
    let originals=inlineFamilies.get(root)
    if(!originals){originals=new Map();inlineFamilies.set(root,originals)}
    if(family==null){
        for(const [node,original]of originals){
            if(original.value)node.style.setProperty('font-family',original.value,original.priority)
            else node.style.removeProperty('font-family')
        }
        originals.clear();return
    }
    const nodes=[...(root.body?[root.body]:[root]),...root.querySelectorAll(prose)]
    for(const node of nodes){
        if(!node.style||node.closest(specialized))continue
        if(!originals.has(node))originals.set(node,{value:node.style.getPropertyValue('font-family'),priority:node.style.getPropertyPriority('font-family')})
        // A controlled inline property can supersede publisher !important
        // family rules without flattening weight, style, size or direction.
        node.style.setProperty('font-family',family,'important')
    }
}

export function validateTypographyUpdate(value,capabilities){
    if(!capabilities.fontFamily&&(Object.hasOwn(value,'font')||Object.hasOwn(value,'resolvedFont')))throw Error('Font replacement is unavailable')
    if(!capabilities.textMetrics&&['size','weight','line','paragraph','align','hyphenate','margin','width'].some(key=>Object.hasOwn(value,key)))throw Error('Text customization is unavailable')
    if(!capabilities.fontFamily&&!capabilities.textMetrics&&Object.hasOwn(value,'publisher'))throw Error('Publisher typography cannot be replaced')
}
