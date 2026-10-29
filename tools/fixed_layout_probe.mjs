// Application integration around the exact upstream renderer, with a controlled DOM.
// Real native rendering, source alignment and focus require the native probes.
import assert from 'node:assert/strict'
import { FixedLayoutIntegration, readerContents } from '../assets/reader/fixed_layout_integration.mjs'

const names=['HTMLElement','ResizeObserver','CSSStyleSheet','customElements','document']
const previous=new Map(names.map(name=>[name,Object.getOwnPropertyDescriptor(globalThis,name)]))
const documents=new Map()
let selected=null,focused=null
class Element extends EventTarget {
  style={};children=[];scrollLeft=0;scrollTop=0
  constructor(tag='host'){super();this.tag=tag}
  append(child){child.parentElement=this;this.children.push(child)}
  replaceChildren(...children){this.children=children}
  setAttribute(name,value){if(this.constructor.observedAttributes?.includes(name))this.attributeChangedCallback(name,null,value)}
  attachShadow(){return this.root=new Element('shadow')}
  querySelectorAll(tag){return this.children.flatMap(child=>[...(child.tag===tag?[child]:[]),...child.querySelectorAll(tag)])}
  get clientWidth(){return parseFloat(this.style.width)||600}
  get clientHeight(){return parseFloat(this.style.height)||800}
  getBoundingClientRect(){
    if(this.style.display==='none'||this.parentElement?.style.display==='none')return {left:0,top:0,right:0,bottom:0,width:0,height:0}
    const scale=parseFloat(this.style.transform?.match(/scale\(([^)]+)/)?.[1]??1)
    return {left:0,top:0,right:this.clientWidth*scale,bottom:this.clientHeight*scale,width:this.clientWidth*scale,height:this.clientHeight*scale}
  }
  set src(value){this.contentDocument=documents.get(value);this.contentDocument.defaultView.frameElement=this;queueMicrotask(()=>this.dispatchEvent(new Event('load')))}
  scrollBy({left,top}){this.scrollLeft+=left;this.scrollTop+=top}
}
try{
  for(const name of names)assert.equal(globalThis[name],undefined,'Synthetic Node probe must not replace a native '+name)
  Object.assign(globalThis,{
    HTMLElement:Element,ResizeObserver:class{observe(){}unobserve(){}},CSSStyleSheet:class{replaceSync(){}},customElements:{define(){}},
    document:{createElement:tag=>new Element(tag)},
  })
  const {FixedLayout}=await import('../assets/reader/vendor/foliate/fixed-layout.js')
  for(const id of ['cover','left','right'])documents.set(id,{
    documentElement:{localName:'html'},querySelector:()=>null,
    defaultView:{focus:()=>{focused=id}},getSelection:()=>({removeAllRanges(){selected=null},addRange(range){selected=range}}),
  })
  const metadata=new WeakMap(),locations=[]
  const view={isFixedLayout:true,opens:0,
    async open(book){this.book=book;this.renderer=new FixedLayout();this.opens++;this.renderer.addEventListener('load',event=>metadata.set(event.detail.doc,{index:event.detail.index}));this.renderer.open(book)},
    close(){this.renderer.destroy()},
  }
  const sections=[...documents.keys()].map(id=>({load:async()=>id}))
  const book={dir:'ltr',rendition:{viewport:{width:600,height:800}},sections}
  const configuredRenderers=new Set()
  const integration=new FixedLayoutIntegration(view,book,metadata,location=>locations.push(location),renderer=>configuredRenderers.add(renderer))
  integration.prepare({spread:false,zoom:'3'})
  await view.open(book)
  await integration.goTo({index:1})
  await integration.goTo({index:2})
  assert.equal(integration.activeIndex,2)
  assert.equal(locations.at(-1).index,2)
  assert.equal(readerContents(view,metadata).find(part=>part.index===2).doc,documents.get('right'))
  integration.focus();assert.equal(focused,'right')
  const range={startContainer:{},getClientRects:()=>[{left:40,right:80,top:600,bottom:620}]}
  await integration.goTo({index:2,anchor:()=>range},{select:true})
  assert.equal(selected,range);assert.equal(locations.at(-1).range,range);assert(view.renderer.scrollTop>0)
  await integration.goTo({index:1,anchor:()=>range},{select:true})
  integration.focus();assert.equal(focused,'left');assert.equal(integration.activeIndex,1)
  // A same-spread side change must survive the upstream renderer's next resize.
  await integration.goTo({index:1},{preferences:{spread:true,zoom:'3'}})
  await integration.goTo({index:2},{preferences:{spread:true,zoom:'3'}})
  view.renderer.attributeChangedCallback('zoom',null,'2')
  assert.equal(view.renderer.index,2)
  assert.equal(integration.visibleContents().at(-1).index,2)
  assert(configuredRenderers.size>1,'Configuration hooks run again for replaced renderers')
  assert(configuredRenderers.has(view.renderer),'The current renderer receives its owned event/bounds configuration')
  for(const dir of ['ltr','rtl'])for(const spread of [false,true]){
    const centered={dir,rendition:{viewport:{width:900,height:600}},sections:[...documents.keys()].map(id=>({pageSpread:'center',load:async()=>id}))}
    const current=new FixedLayoutIntegration(view,centered,metadata,location=>locations.push(location))
    current.prepare({spread});view.close();await view.open(centered)
    for(const [index,section] of centered.sections.entries()){
      await current.goTo({index})
      assert.equal(view.renderer.getSpreadOf(section)?.index,index,'Every centered page remains individually navigable')
      assert.equal(current.activeIndex,index);assert.equal(locations.at(-1).index,index)
    }
  }
  // A failed upstream load must not poison the next attempt's spread index.
  let fail=true
  const failing={dir:'ltr',rendition:{spread:'none',viewport:{width:600,height:800}},sections:[{load:async()=> 'cover'},{load:async()=>{if(fail)throw Error('fixture source failed');return 'left'}}]}
  const recovering=new FixedLayoutIntegration(view,failing,metadata,location=>locations.push(location))
  recovering.prepare({spread:false});view.close();await view.open(failing);await recovering.goTo({index:0})
  const previousLocation=locations.at(-1)
  await assert.rejects(recovering.goTo({index:1}),/fixture source failed/)
  assert.equal(recovering.activeIndex,0);assert.equal(locations.at(-1),previousLocation)
  fail=false;await recovering.goTo({index:1});assert.equal(recovering.activeIndex,1)
  view.close()
  console.log(JSON.stringify({status:'passed',scope:'application configuration and navigation through unmodified upstream fixed-layout API: single/spread, active side after resize, range selection/scroll, focus, centered pages, direction and failed-load recovery; controlled DOM, no native rendering acceptance'}))
}finally{
  for(const [name,descriptor] of previous){if(descriptor)Object.defineProperty(globalThis,name,descriptor);else delete globalThis[name]}
}
