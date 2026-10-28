import assert from 'node:assert/strict'
import { resolvePublicationHref } from '../assets/reader/epub_integration.mjs'

const cases=[
    ['chapter%232.xhtml#chapter%3Atwo','OPS/book.opf','OPS/chapter%232.xhtml#chapter%3Atwo'],
    ['per%25cent.xhtml#percent','OPS/book.opf','OPS/per%25cent.xhtml#percent'],
    ['%d0%b0%d1%80%d1%82.xhtml#unicode','OPS/book.opf','OPS/%D0%B0%D1%80%D1%82.xhtml#unicode'],
    ['../chapter%20one.xhtml?ignored=1#part','OPS/sub/book.opf','OPS/chapter%20one.xhtml#part'],
    ['#local','OPS/chapter#one.xhtml','OPS/chapter%23one.xhtml#local'],
    ['image%3Fname.png#fragment','OPS/chapter.xhtml','OPS/image%3Fname.png#fragment'],
    ['/OPS/one.xhtml#part','other/book.opf','OPS/one.xhtml#part'],
    ['https://example.invalid/book#part','OPS/book.opf','https://example.invalid/book#part'],
    ['//example.invalid/book','OPS/book.opf','https://example.invalid/book'],
]
for(const [href,base,expected] of cases)assert.equal(resolvePublicationHref(href,base),expected)
assert.throws(()=>resolvePublicationHref('missing%zz.xhtml','OPS/book.opf'),URIError)
assert.throws(()=>resolvePublicationHref(null,'OPS/book.opf'),/Invalid publication destination/)
console.log(JSON.stringify({status:'passed',scope:'Application EPUB URL/path separation, encoded names/fragments, Unicode and malformed destinations; no rendering acceptance',checks:cases.length+2}))
