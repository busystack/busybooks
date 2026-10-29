// Run the production command/appearance/CSS path with application-owned renderer
// interfaces. Native/browser page treatment is checked by theme_native_proof.js.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import * as typographyUtilities from '../assets/reader/typography.mjs'
const source=(await fs.readFile(process.env.BUSYBOOKS_READER_SOURCE??new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
  .replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
const readerCSS=await fs.readFile(new URL('../assets/reader/reader.css',import.meta.url),'utf8')
assert.match(readerCSS,/\.pdf-page canvas\{[^}]*filter:var\(--page-tint,none\)/,'the effective tint must reach the PDF canvas, not just its surround')
function style(){const values=new Map();return {setProperty:(name,value)=>values.set(name,value),getPropertyValue:name=>values.get(name)??''}}
function adapter(kind){
  const bodyStyle=style(),viewStyle=style(),styles=[],anchors=[],preserves=[],events=[]
  const content={clientWidth:900,addEventListener(){},style:style()}
  const fakeView={isFixedLayout:kind!=='reflowable',style:viewStyle,book:{sections:[{},{},{}]},renderer:{setAttribute(){},setStyles:value=>styles.push(value),getContents:()=>[]}}
  const context=vm.createContext({...typographyUtilities,URL,console,Uint8Array,Uint32Array,setTimeout,clearTimeout,structuredClone,
    cssColor:()=> '#123456',readerContents:publication=>publication?.renderer.getContents()??[],requestAnimationFrame:callback=>callback(),
    pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},matchMedia:()=>({matches:false}),
    document:{querySelector:()=>content,querySelectorAll:()=>[],addEventListener(){},body:{style:bodyStyle}},
    window:{location:{href:'https://busybooks.local/?session=appearance'},addEventListener(){},chrome:{webview:{postMessage:value=>events.push(JSON.parse(value))}}},
    fakeView,layout:async (anchor,preserveSelection)=>{anchors.push(structuredClone(anchor));preserves.push(preserveSelection);return true},
  })
  vm.runInContext(source,context)
  vm.runInContext(`activeFormat=${JSON.stringify(kind==='pdf'?'pdf':kind==='comic'?'cbz':'epub')};
    location={anchor:{${kind==='pdf'?'page:2,y:.42':'index:2'}},progress:.6};
    selection={anchor:{page:2},text:'owned fixture selection'};
    annotations=[{id:'owned-theme-fixture',annotationKind:'bookmark',anchor:{page:2}}];
    prefs={color:'system',publisher:true,size:22};
    ${kind==='pdf'?'pdf={numPages:3};relayoutPdf=layout;':`view=fakeView;typography=${kind==='reflowable'?'{fontFamily:false,textMetrics:true}':'noTypography'};${kind==='reflowable'?'':'fixedLayout={activeIndex:2,goTo:layout};'}`}
    savedSelection=selection;savedAnnotations=JSON.stringify(annotations);savedLocation=JSON.stringify(location);`,context)
  const run=code=>vm.runInContext(code,context)
  return {context,events,bodyStyle,viewStyle,styles,anchors,preserves,run,
    async apply(value){context.nextAppearance=value;await run("dispatch({action:'appearance',session:'appearance',request:12,value:nextAppearance})");assert(events.at(-1)?.type==='appearanceResult'&&!events.at(-1).message,JSON.stringify(events.at(-1)))} }
}
const inverted='invert(1) hue-rotate(180deg)'
const cases=[
  {color:'system',application:'system',desktopDark:true,tint:inverted,dark:true},
  {color:'system',application:'system',desktopDark:false,tint:'none',dark:false},
  {color:'light',application:'dark',desktopDark:false,tint:'none',dark:false},
  {color:'light',application:'dark',desktopDark:true,tint:'none',dark:false},
  {color:'dark',application:'light',desktopDark:false,tint:inverted,dark:true},
  {color:'dark',application:'light',desktopDark:true,tint:inverted,dark:true},
  {color:'sepia',application:'dark',desktopDark:false,tint:'sepia(.3)',dark:false},
  {color:'sepia',application:'light',desktopDark:true,tint:'sepia(.3)',dark:false},
  {color:'system',application:'light',desktopDark:true,tint:'none',dark:false},
  {color:'system',application:'dark',desktopDark:false,tint:inverted,dark:true},
]
let checks=0
for(const kind of ['pdf','fixed','reflowable','comic']){
  const f=adapter(kind)
  for(const item of cases){
    // The reader's System setting intentionally follows resolved app brightness.
    const systemDark=item.application==='system'?item.desktopDark:item.application==='dark'
    await f.apply({color:item.color,systemDark})
    const expectedTint=kind==='comic'?'none':kind==='reflowable'&&item.dark?'none':item.tint
    assert.equal((kind==='pdf'?f.bodyStyle:f.viewStyle).getPropertyValue('--page-tint'),expectedTint,JSON.stringify({kind,...item}))
    if(kind==='pdf')assert.equal(f.preserves.at(-1),true,'PDF appearance uses the owned selection-preserving layout transaction')
    assert.equal(f.run('prefs.color'),item.color,'resolution must not rewrite the stored choice')
    assert.equal(f.run('JSON.stringify(location)===savedLocation'),true,'color changes retain the exact location')
    assert.equal(f.run('selection===savedSelection'),true,'color changes do not replace selection intent')
    assert.equal(f.run('JSON.stringify(annotations)===savedAnnotations'),true,'color changes do not rewrite annotations')
    if(kind==='reflowable'){
      assert(f.styles.at(-1).includes(`color-scheme:${item.dark?'dark':'light'}`))
      assert(f.styles.at(-1).includes(`background:${item.dark?'#202124':item.color==='sepia'?'#f4ecd8':'#ffffff'}!important`))
    }
    checks++
  }
  // An already open System publication follows dark -> light -> dark without
  // replacing its page or changing its saved System choice.
  for(const systemDark of [true,false,true]){
    await f.apply({color:'system',systemDark})
    assert.equal(f.run('prefs.color'),'system')
    assert.equal((kind==='pdf'?f.bodyStyle:f.viewStyle).getPropertyValue('--page-tint'),kind==='comic'||kind==='reflowable'?'none':systemDark?inverted:'none')
    assert.equal(f.run('JSON.stringify(location)===savedLocation'),true)
    checks++
  }
}
console.log(JSON.stringify({status:'passed',checks,scope:'Production appearance dispatch/CSS: effective PDF and fixed-page treatment, app/desktop System overrides, live changes, reflowable CSS without double inversion, comic artwork, retained state. Native rendering qualified separately.'}))
