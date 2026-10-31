// Optional native Chromium counterpart to the WebKitGTK weight probe. Uses the
// same production registration and native resolution JSON; no helper enumerates
// fonts and no test font is installed into the developer's environment.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {execFileSync} from 'node:child_process'
const data=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const module=fs.readFileSync(new URL('../assets/reader/typography.mjs',import.meta.url),'utf8')
const root=fs.mkdtempSync(path.join(os.tmpdir(),'busybooks-chromium-typography-'))
try{
    const html=`<!doctype html><pre id="result">pending</pre><script type="module">
    import {createLocalFont,installLocalFont,cssString} from 'data:text/javascript;base64,${Buffer.from(module).toString('base64')}';
    const resolved=${JSON.stringify(data[2].resolved).replaceAll('<','\\u003c')};
    const raster=(family,weight,italic=false)=>{const c=document.createElement('canvas');c.width=700;c.height=70;const x=c.getContext('2d');x.font=(italic?'italic ':'')+weight+' 28px '+family;x.fillText('A quiet library — 0123456789.',2,45);return c.toDataURL()};
    try{const font=createLocalFont(resolved);await installLocalFont(document,font);const actual=[],comparisons=[];
      for(const w of [300,400,500,600,700]){actual.push(raster(font.family,w));comparisons.push({weight:w,normal:raster(font.family,w)===raster(cssString(resolved.family),w),italic:raster(font.family,w,true)===raster(cssString(resolved.family),w,true)})}
      const distinct=new Set(actual).size;document.querySelector('#result').textContent=JSON.stringify({passed:distinct===5&&comparisons.every(c=>c.normal&&c.italic),distinct,comparisons,faces:resolved.faces.map(f=>[f.weight,f.italic])});
    }catch(e){document.querySelector('#result').textContent=JSON.stringify({passed:false,error:String(e)})}
    </script>`
    const file=path.join(root,'proof.html');fs.writeFileSync(file,html)
    const dom=execFileSync(process.env.BUSYBOOKS_CHROMIUM_BIN??'/usr/bin/google-chrome',['--headless','--no-sandbox','--no-first-run','--no-default-browser-check','--disable-background-networking','--user-data-dir='+path.join(root,'profile'),'--allow-file-access-from-files','--virtual-time-budget=10000','--dump-dom','file://'+file],{encoding:'utf8',timeout:30000,stdio:['ignore','pipe','pipe']})
    const raw=dom.match(/<pre id="result">([^<]*)<\/pre>/)?.[1]
    if(!raw||raw==='pending')throw Error('Chromium proof did not finish')
    const result=JSON.parse(raw.replaceAll('&quot;','"').replaceAll('&amp;','&'))
    console.log(JSON.stringify(result));if(!result.passed)process.exitCode=1
}finally{fs.rmSync(root,{recursive:true,force:true})}
