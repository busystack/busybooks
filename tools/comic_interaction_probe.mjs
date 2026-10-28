// Actual reader handlers with controlled event targets; native geometry is
// checked separately by formats_native_proof.js in WebKitGTK.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const source=readFileSync(new URL('../assets/reader/reader.js',import.meta.url),'utf8')
const marks=[],scroll=[],events=[]
class Target {
    dataset={};style={};listeners=new Map()
    addEventListener(type,handler){const list=this.listeners.get(type)??[];list.push(handler);this.listeners.set(type,list)}
    removeEventListener(type,handler){this.listeners.set(type,(this.listeners.get(type)??[]).filter(x=>x!==handler))}
    fire(type,data={}){const event={button:0,pointerId:1,screenX:200,screenY:200,clientX:200,clientY:200,detail:1,target:this,preventDefault(){},stopPropagation(){},...data};for(const handler of [...this.listeners.get(type)??[]])handler(event)}
    closest(){return this.dataset.regionId?this:null}
    setPointerCapture(){}
    setAttribute(){}
    remove(){const index=marks.indexOf(this);if(index>=0)marks.splice(index,1)}
}
const img=new Target(),doc=new Target(),body=new Target()
Object.assign(img,{offsetLeft:0,offsetTop:0,clientWidth:600,clientHeight:900,getBoundingClientRect:()=>({left:0,top:0,width:600,height:900})})
body.append=mark=>marks.push(mark)
Object.assign(doc,{body,querySelector:()=>img,querySelectorAll:()=>[...marks],createElement:()=>new Target()})
const context=vm.createContext({getContents:publication=>publication.renderer.getContents(),doc,strings:{},keys(){},isComic:()=>true,regionSelection:null,view:{renderer:{getContents:()=>[{doc,index:0}],scrollBy:delta=>scroll.push(delta)},book:{sections:[{pageId:'a'.repeat(64)}]}},annotations:[{id:'saved-region',annotationKind:'region',anchor:{page:0,pageId:'a'.repeat(64),region:[.1,.2,.3,.4]},color:'blue'}],colors:{blue:'blue'},regionPopoverRect:()=>({x:20,y:30,width:1,height:1}),emit:(type,data)=>events.push({type,...data}),setTimeout})
vm.runInContext(source.slice(source.indexOf('function setupComicPage'),source.indexOf('function beginRegion'))+source.slice(source.indexOf('function paintRegions'),source.indexOf('async function mountFoliate'))+';setupComicPage(doc,0)',context)
const mark=marks[0]
doc.fire('pointerdown',{target:mark})
mark.fire('pointermove',{screenX:140,screenY:80})
mark.fire('pointerup')
mark.fire('click')
assert.equal(scroll.length,1)
assert.equal(scroll[0].left,60);assert.equal(scroll[0].top,120)
assert.equal(events.length,0,'Dragging a saved region pans without opening its editor')
mark.fire('click',{detail:0})
assert.equal(events.at(-1).id,'saved-region','Keyboard activation still opens the saved region')
doc.fire('pointerdown',{target:mark})
mark.fire('pointermove',{screenX:199,screenY:199})
mark.fire('pointerup');mark.fire('click')
assert.equal(scroll.length,1,'Pointer jitter does not pan')
assert.equal(events.length,2,'An ordinary region click opens its editor')
doc.fire('pointerdown',{target:img})
img.fire('pointermove',{screenX:180,screenY:170});img.fire('pointerup')
assert.equal(scroll.length,2,'Ordinary artwork drag remains panning')
console.log(JSON.stringify({status:'passed',checks:8,scope:'Comic drag panning over artwork and saved regions, click/keyboard activation and pointer jitter; controlled events'}))
