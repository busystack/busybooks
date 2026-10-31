// BusyBooks configuration and passage navigation around Foliate's public API.
// The renderer and its methods remain unmodified.
export function readerContents(view, metadata) {
    const parts=view?.renderer?.getContents()??[]
    if(!view?.isFixedLayout)return parts
    return parts.flatMap(part=>{
        const result={...part,...metadata.get(part.doc)}
        return Number.isInteger(result.index)&&result.index>=0?[result]:[]
    })
}

export class FixedLayoutIntegration {
    constructor(view,book,metadata,onLocation,onRenderer) {
        this.view=view;this.book=book;this.metadata=metadata;this.onLocation=onLocation
        this.rendition={...book.rendition};this.direction=book.dir
        this.activeIndex=0;this.busy=false;this.signature=null;this.preferences={}
        this.onRenderer=onRenderer
    }
    prepare(preferences,index=0) {
        this.preferences={...preferences};this.activeIndex=index
        // A publisher's centered page is a complete spread. Asking the public
        // renderer for single-page configuration also handles consecutive
        // centered pages without changing section order or any CFI base.
        const centered=this.book.sections[index]?.pageSpread==='center'
        const spread=!preferences.spread||centered?'none':this.rendition.spread??'auto'
        const direction=this.book.comic&&preferences.direction&&preferences.direction!=='auto'
            ?preferences.direction:this.direction
        const signature=JSON.stringify([spread,direction])
        const changed=signature!==this.signature
        this.signature=signature
        this.book.rendition={...this.rendition,spread}
        this.book.dir=direction
        return changed
    }
    style() {
        const renderer=this.view.renderer
        // Standard host CSS keeps overflowing artwork reachable; it does not
        // reach into Foliate's closed shadow tree or replace its layout code.
        renderer.style.direction='ltr'
        renderer.style.justifyContent='safe center'
        renderer.style.alignItems='safe center'
        renderer.setAttribute('zoom',this.preferences.zoom??'fit-page')
        this.onRenderer?.(renderer)
    }
    async configure(preferences,index=this.activeIndex) {
        const renderer=this.view.renderer,previous=this.book.sections[this.activeIndex]
        const destination=this.book.sections[index]
        const from=renderer?.getSpreadOf(previous),to=renderer?.getSpreadOf(destination)
        const changesSide=index!==this.activeIndex&&from&&to&&from.index===to.index&&from.side!==to.side
        const changed=this.prepare(preferences,index)
        if(changed||changesSide||this.needsReopen){
            // open/close are the documented View lifecycle. Retain the same
            // application book and its original sections/locators. BusyBooks
            // owns fixed-layout navigation history independently of this view.
            this.view.close()
            await this.view.open(this.book)
            this.needsReopen=false
        }
        this.style()
        return changed
    }
    contents(){return readerContents(this.view,this.metadata)}
    visibleContents(){return this.contents().filter(part=>part.doc.defaultView?.frameElement?.getBoundingClientRect().width>0)}
    async goTo(target,{select=false,preferences=this.preferences}={}) {
        const resolved=await target,index=resolved?.index
        if(!Number.isInteger(index)||index<0||index>=this.book.sections.length)
            throw Error('Publication page is unavailable')
        const previousIndex=this.activeIndex
        this.busy=true
        try{
            await this.configure(preferences,index)
            await this.view.renderer.goTo({index})
            const part=this.contents().find(part=>part.index===index)
            if(!part?.doc?.documentElement||part.doc.querySelector('parsererror'))
                throw Error('Publication did not produce a readable page')
            let range=null
            if(typeof resolved.anchor==='function'){
                const destination=resolved.anchor(part.doc)
                if(destination?.startContainer)range=destination
                else if(destination?.nodeType){range=part.doc.createRange();range.selectNodeContents(destination)}
                else throw Error('Publication passage is unavailable')
                if(select){
                    const selection=part.doc.getSelection()
                    selection.removeAllRanges();selection.addRange(range)
                }
                this.reveal(part.doc,range)
            }
            this.activeIndex=index
            this.onLocation?.({index,range})
            return {index,range}
        }catch(error){
            this.activeIndex=previousIndex
            this.needsReopen=true
            throw error
        }finally{this.busy=false}
    }
    reveal(doc,range) {
        const frame=doc.defaultView?.frameElement
        if(!frame)return
        const rect=range.getClientRects()[0]??range.getBoundingClientRect()
        const bounds=frame.getBoundingClientRect(),renderer=this.view.renderer
        const viewport=renderer.getBoundingClientRect()
        const scaleX=bounds.width/frame.clientWidth,scaleY=bounds.height/frame.clientHeight
        const x=bounds.left+rect.left*scaleX,y=bounds.top+rect.top*scaleY
        const right=bounds.left+rect.right*scaleX,bottom=bounds.top+rect.bottom*scaleY
        const dx=x<viewport.left?x-viewport.left:right>viewport.left+renderer.clientWidth
            ?Math.min(right-viewport.left-renderer.clientWidth,x-viewport.left):0
        const dy=y<viewport.top?y-viewport.top:bottom>viewport.top+renderer.clientHeight
            ?Math.min(bottom-viewport.top-renderer.clientHeight,y-viewport.top):0
        renderer.scrollBy({left:dx,top:dy})
    }
    focus() {
        const part=this.contents().find(part=>part.index===this.activeIndex)
        part?.doc.defaultView?.focus()
    }
}
