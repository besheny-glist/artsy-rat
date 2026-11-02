const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
const fn=source.slice(source.indexOf('async function compactAvatar('),source.indexOf('function setupProfile('));
test('oversized avatar gives a size-specific error before decoding',async()=>{
 const ctx=vm.createContext({URL:{createObjectURL(){throw Error('must not decode');}}});
 vm.runInContext(fn,ctx);
 await assert.rejects(ctx.compactAvatar({size:5242881,type:'image/jpeg'}),{message:'avatarTooLarge'});
});
test('unsupported avatar format gives an actionable format error',async()=>{
 const ctx=vm.createContext({});vm.runInContext(fn,ctx);
 await assert.rejects(ctx.compactAvatar({size:100,type:'image/heic'}),{message:'imageFormat'});
});
test('unreadable images release their object URL',async()=>{
 let released=false;
 const ctx=vm.createContext({setTimeout,clearTimeout,URL:{createObjectURL:()=> 'blob:preview',revokeObjectURL(){released=true;}},Image:class{decode(){return Promise.reject(Error('corrupt'));}}});
 vm.runInContext(fn,ctx);await assert.rejects(ctx.compactAvatar({size:100,type:'image/png'}));assert.equal(released,true);
});
