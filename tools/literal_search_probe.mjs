// Search contract and the actual BusyBooks adapter under controlled APIs.
// Browser rendering and native focus are separate acceptance checks.
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import vm from 'node:vm'
import * as literal from '../assets/reader/literal_search.mjs'
import * as typography from '../assets/reader/typography.mjs'
import { validPage } from '../assets/reader/reading_geometry.mjs'
for (const [text, query, expected] of [
    ['.* [a] % _', '.*', [[0,2]]], ['catalog Cat', 'cat', [[0,3],[8,11]]],
    ['  a  ', '  ', [[0,2],[3,5]]], ['aaaaa','aa',[[0,2],[2,4]]],
    ['École ecole', 'é', [[0,1]]], ['e\u0301 é', 'é', [[3,4]]],
    ['e\u0301', '\u0301', [[1,2]]], ['КНИГА 中文書', 'книга', [[0,5]]],
    ['КНИГА 中文書', '文', [[7,8]]], ['𐐀 😀 𐐨', '𐐨', [[0,2],[6,8]]],
    ['İIıi', 'i', [[1,2],[3,4]]], ['ſKΣςσ', 's', [[0,1]]],
    ['ſKΣςσ','k',[[1,2]]], ['ſKΣςσ','σ',[[2,3],[3,4],[4,5]]],
    ['Straße STRASSE', 'ss', [[11,13]]], ['anything','',[]],
]) {
    assert.deepEqual([...literal.literalRanges(text,query)].map(x=>[x.start,x.end]),expected,`${JSON.stringify(text)} / ${JSON.stringify(query)}`)
}
const formatted=[...literal.literalTextMatches(['前 ', 'hel', 'lo', ' 😀後'], 'HELLO 😀', (...bounds)=>bounds)]
assert.deepEqual(formatted[0].range,[1,0,3,3])
assert.equal(formatted[0].excerptParts.match,'hello 😀')
assert.deepEqual([...literal.literalTextMatches(['abc', '', 'def'], 'cde', (...bounds)=>bounds)][0].range,[0,2,2,2])

const source=(await fs.readFile(new URL('../assets/reader/reader.js',import.meta.url),'utf8'))
    .replace(/^import .*\r?\n/gm,'').replaceAll('import.meta.url',"'https://busybooks.local/reader.js'")
function adapter() {
    const events=[], content={addEventListener(){},setAttribute(){},removeAttribute(){},style:{}}
    const context=vm.createContext({...literal,...typography,AbortController,URL,console,Uint8Array,setTimeout,clearTimeout,validPage,
        requestAnimationFrame:f=>f(),pdfjs:{GlobalWorkerOptions:{}},ResizeObserver:class{observe(){}},
        document:{querySelectorAll:()=>[],querySelector:()=>content,addEventListener(){},getSelection:()=>null,body:{style:{setProperty(){}}}},
        textWalker:function*(doc,fn){yield* fn(doc.strings,(...bounds)=>bounds)},
        window:{location:{href:'https://busybooks.local/?session=test'},chrome:{webview:{postMessage:x=>events.push(JSON.parse(x))}}}})
    vm.runInContext(source,context)
    return {events,context,run:code=>vm.runInContext(code,context)}
}
// Current blank/scanned pages never decide whole-PDF availability.
for (const items of [[],[{str:'searchable body'}]]) {
    const {run,context,events}=adapter(); context.items=items
    await run("location={noText:true};pdf={numPages:2,getPage:async page=>({getTextContent:async()=>({items:page===1?[]:items})})}; search('body',1,generation)")
    assert.equal(events.at(-1).type,'searchDone')
    assert.equal(events.at(-1).total,items.length)
    assert.equal(events.filter(e=>e.type==='matches').flatMap(e=>e.items).length,items.length)
}
// Bounded display windows retain the exact complete count and absolute indices.
{
    const {run,events}=adapter()
    await run("pdf={numPages:3,getPage:async()=>({getTextContent:async()=>({items:[{str:'a '.repeat(1000)}]})})}; search('a',2,generation,2500,200)")
    const matches=events.filter(e=>e.type==='matches').flatMap(e=>e.items)
    assert.equal(events.at(-1).total,3000);assert.equal(matches.length,200)
    assert.equal(matches[0].index,2500);assert.equal(matches.at(-1).index,2699)
    assert.equal(matches[0].anchor.page,2);assert.equal(matches[0].anchor.textOffset,1000)
}
// EPUB/FB2 search calls publication document/range APIs, never patched search.
for (const format of ['epub','fb2']) {
    const {run,context,events}=adapter();context.format=format
    await run("activeFormat=format;view={book:{sections:[{identity:'body:0/part:0',createDocument:async()=>({strings:['a HEL','LO 😀z']})}]},getCFI:(index,range)=>'epubcfi('+range.join(',')+')',getProgressOf:()=>({tocItem:{label:'Chapter'}}),search(){throw Error('Must not call vendor matcher')}}; search('hello 😀',3,generation)")
    const match=events.find(e=>e.type==='matches').items[0]
    assert.equal(match.anchor.cfi,'epubcfi(0,2,1,5)');assert.equal(match.excerptParts.match,'HELLO 😀')
    if(format==='fb2')assert.equal(match.anchor.section,'body:0/part:0')
    assert.equal(events.at(-1).total,1)
}
// Failure after matches keeps truthful incomplete status; cancellation emits no
// late completion, and an empty query never asks the publication for text.
{
    const {run,events}=adapter()
    await run("pdf={numPages:2,getPage:async i=>{if(i===2)throw Error('read failure');return {getTextContent:async()=>({items:[{str:'match'}]})}}}; search('match',4,generation)")
    assert.equal(events.at(-1).type,'searchError');assert.equal(events.at(-1).incomplete,true)
    assert.equal(events.find(e=>e.type==='matches').items.length,1)
}
{
    const {run,events}=adapter()
    await run("pdf={numPages:1,getPage:async()=>{generation++;return {getTextContent:async()=>({items:[{str:'match'}]})}}}; search('match',5,generation)")
    assert.deepEqual(events.filter(x=>x.type!=='ready').map(x=>x.type),['searchStart'])
}
{
    const {run,events}=adapter()
    await run("pdf={getPage(){throw Error('empty query read')}};search('',6,generation)")
    assert.deepEqual(events.filter(x=>x.type!=='ready').map(x=>x.type),['searchStart','searchDone']);assert.equal(events.at(-1).total,0)
}
// Older and pre-search same-revision cancellation may arrive late from native
// evaluation. Neither may interrupt the newer owned request.
for (const cancelledRevision of [8,9]) {
    const {run,events}=adapter()
    run("pdf={numPages:1,getPage:()=>new Promise(resolve=>release=()=>resolve({getTextContent:async()=>({items:[{str:'match'}]})}))};pendingSearch=requestSearch('match',9)")
    await new Promise(setImmediate)
    await run(`dispatch({action:'cancelSearch',queryId:${cancelledRevision}})`)
    await run('release();pendingSearch')
    assert.equal(events.at(-1).type,'searchDone');assert.equal(events.at(-1).queryId,9)
    assert.equal(events.at(-1).total,1)
}
{
    const {run,events}=adapter()
    await run("dispatch({action:'cancelSearch',queryId:10});requestSearch('match',9)")
    assert.equal(events.some(e=>e.type==='searchStart'),false,'a cancelled older request never starts')
}
console.log(JSON.stringify({status:'passed',scope:'application Unicode literal/nonoverlap contract, formatting and PDF item ranges, whole-PDF availability, bounded complete counts, EPUB/FB2 locators, cancellation and incomplete errors; controlled APIs'}))
