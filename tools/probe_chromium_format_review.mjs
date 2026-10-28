// Actual reader assets, original CSP and controlled https://busybooks.local
// resources. DevTools fulfills every request; no external server/account is used.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawn, spawnSync } from 'node:child_process'

const root=path.resolve(import.meta.dirname,'..'),owned=fs.mkdtempSync(path.join(os.tmpdir(),'busybooks-review-chromium-'))
const fixtures=process.argv.slice(2)
if(!fixtures.length)fixtures.push('comic-deflated.cbz','comic-rar5-solid.cbr','epub2-raster-fallback.epub','fiction-idless.fb2')
const browser=spawn(process.env.BUSYBOOKS_CHROMIUM_BIN??'/usr/bin/google-chrome',[
    '--headless','--no-sandbox','--no-first-run','--no-default-browser-check','--disable-background-networking',
    '--remote-debugging-port=0','--user-data-dir='+path.join(owned,'browser'),'about:blank',
],{stdio:['ignore','ignore','pipe']})
const browserClosed=new Promise(resolve=>browser.once('close',resolve))
let socket
try{
    const endpoint=await new Promise((resolve,reject)=>{
        let log='';const timer=setTimeout(()=>reject(Error('Chromium did not start')),15000)
        browser.stderr.on('data',data=>{log+=data;const match=log.match(/DevTools listening on (ws:\/\/\S+)/);if(match){clearTimeout(timer);resolve(match[1])}})
        browser.once('error',reject);browser.once('exit',code=>{clearTimeout(timer);reject(Error('Chromium exited '+code+': '+log.slice(-3000)))})
    })
    socket=new WebSocket(endpoint)
    await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true})})
    let serial=0;const pending=new Map(),publications=new Map()
    const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{
        const id=++serial,timer=setTimeout(()=>{pending.delete(id);reject(Error('DevTools timeout: '+method))},120000)
        pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}))
    })
    socket.addEventListener('message',async event=>{
        const message=JSON.parse(event.data)
        if(message.id){const waiter=pending.get(message.id);if(waiter){pending.delete(message.id);clearTimeout(waiter.timer);message.error?waiter.reject(Error(JSON.stringify(message.error))):waiter.resolve(message.result)}return}
        if(message.method!=='Fetch.requestPaused')return
        const {requestId,request}=message.params,publication=publications.get(message.sessionId)
        try{
            const url=new URL(request.url);assert.equal(url.origin,'https://busybooks.local')
            const relative=decodeURIComponent(url.pathname.slice(1));let file
            if(relative==='favicon.ico'){await send('Fetch.fulfillRequest',{requestId,responseCode:204,body:''},message.sessionId);return}
            if(relative==='book-index')file=publication.cacheDirectory+'.json'
            else if(relative==='publication')file=publication.publicationPath
            else if(relative.startsWith('book/')){assert(/^[a-f0-9]{64}$/.test(relative.slice(5)));file=path.join(publication.cacheDirectory,relative.slice(5))}
            else {file=path.resolve(root,'assets/reader',relative);assert(file.startsWith(path.join(root,'assets/reader')+path.sep))}
            const type=/\.m?js$/.test(file)?'text/javascript':file.endsWith('.html')?'text/html':file.endsWith('.css')?'text/css':'application/octet-stream'
            await send('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:type}],body:fs.readFileSync(file).toString('base64')},message.sessionId)
        }catch(error){await send('Fetch.failRequest',{requestId,errorReason:'BlockedByClient'},message.sessionId).catch(()=>{});process.stderr.write('Controlled resource rejected: '+String(error)+'\n')}
    })
    const evaluate=async(sessionId,expression)=>{
        const reply=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},sessionId)
        if(reply.exceptionDetails)throw Error(JSON.stringify(reply.exceptionDetails))
        return reply.result.value
    }
    for(const [number,fixture] of fixtures.entries()){
        const profile=path.join(owned,'profile-'+number),original=path.isAbsolute(fixture)?fixture:path.join(root,'test/fixtures/formats',fixture)
        const prepared=spawnSync(process.env.BUSYBOOKS_DART_BIN??'dart',['run','tools/prepare_format_acceptance.dart',profile,original],{cwd:root,encoding:'utf8',env:{...process.env,BUSYBOOKS_COMIC_DECODER:process.env.BUSYBOOKS_COMIC_DECODER??path.join(root,'build/linux/x64/release/bundle/busybooks_comic_archive')}})
        assert.equal(prepared.status,0,prepared.stderr)
        const publication=JSON.parse(prepared.stdout)
        const {targetId}=await send('Target.createTarget',{url:'about:blank'})
        const {sessionId}=await send('Target.attachToTarget',{targetId,flatten:true})
        publications.set(sessionId,publication)
        await send('Page.enable',{},sessionId);await send('Runtime.enable',{},sessionId)
        await send('Fetch.enable',{patterns:[{urlPattern:'*'}]},sessionId)
        await send('Page.addScriptToEvaluateOnNewDocument',{source:`window.probeEvents=[];window.nativeFrames=[];window.nativeSavedProof=null;window.busybooksProbe=event=>window.probeEvents.push(event);window.chrome.webview={postMessage:json=>window.nativeFrames.push(JSON.parse(json))}`},sessionId)
        await send('Page.navigate',{url:'https://busybooks.local/index.html?session=review'},sessionId)
        await evaluate(sessionId,`(async()=>{for(let i=0;i<400;i++){if(window.probeEvents?.some(e=>e.type==='ready'))return;await new Promise(r=>setTimeout(r,25))}throw Error('Reader not ready')})()`)
        if(process.env.BUSYBOOKS_REVIEW_ANNOTATIONS){
            const records=JSON.parse(fs.readFileSync(process.env.BUSYBOOKS_REVIEW_ANNOTATIONS,'utf8')),encoded=JSON.stringify(records)
            await evaluate(sessionId,`window.expectedAnnotationCount=${records.length}`)
            for(let offset=0;offset<encoded.length;offset+=32768){
                const end=Math.min(encoded.length,offset+32768),command={action:'annotations',revision:1,offset,chunk:encoded.slice(offset,end),complete:end===encoded.length}
                assert(Buffer.byteLength(JSON.stringify(command))<1048576,'Every annotation command respects native hosts')
                await evaluate(sessionId,`busybooks.dispatch(${JSON.stringify(command)})`)
            }
        }
        await evaluate(sessionId,`busybooks.dispatch(${JSON.stringify({action:'open',format:publication.format,appearance:{publisher:false,size:22},labels:{page:'Page',printPage:'Print page'}})})`)
        const opened=await evaluate(sessionId,`window.probeEvents.some(e=>e.type==='opened')`)
        if(process.env.BUSYBOOKS_EXPECT_OPEN_ERROR){
            assert(!opened,'Damaged first section must not announce readiness')
            const errors=await evaluate(sessionId,`window.probeEvents.filter(e=>e.type==='error')`)
            assert(errors.some(e=>e.message.includes(process.env.BUSYBOOKS_EXPECT_OPEN_ERROR)),JSON.stringify(errors))
            console.log(JSON.stringify({engine:'Chromium',fixture,passed:true,check:'first-section rejection'}))
            await send('Target.closeTarget',{targetId});publications.delete(sessionId);continue
        }
        assert(opened,JSON.stringify(await evaluate(sessionId,'window.probeEvents')))
        await evaluate(sessionId,fs.readFileSync(process.env.BUSYBOOKS_REVIEW_PROOF??path.join(root,'tools/format_review_native_proof.js'),'utf8'))
        const result=await evaluate(sessionId,'window.reviewResult')
        assert(result?.passed,JSON.stringify(result))
        console.log(JSON.stringify({engine:'Chromium',fixture,...result}))
        await send('Target.closeTarget',{targetId});publications.delete(sessionId)
    }
}finally{
    socket?.close();browser.kill('SIGTERM')
    const forceStop=setTimeout(()=>browser.kill('SIGKILL'),3000)
    let deadline
    try{
        await Promise.race([
            browserClosed,
            new Promise((_,reject)=>{deadline=setTimeout(()=>reject(Error('Chromium did not close after SIGKILL')),6000)}),
        ])
    }finally{clearTimeout(forceStop);clearTimeout(deadline)}
    // Chrome's profile writers can settle just after the parent process closes.
    fs.rmSync(owned,{recursive:true,force:true,maxRetries:10,retryDelay:100})
}
