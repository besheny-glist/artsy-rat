const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const source=fs.readFileSync('social.js','utf8').split(' async function syncSaved()')[1].split('\n return {syncSaved')[0];
function setup(rows){const context=vm.createContext({user:{id:'one'},saved:['other-account'],catalog:[{id:'post',source_id:'original'}],backend:{socialRows:()=>rows},localStorage:{removeItem(){}},render(){},notifyUser(){},S:k=>k});vm.runInContext('async function syncSaved()'+source,context);return context;}
test('sign-in replaces cached hearts with only this account’s saved posts',async()=>{const c=setup(Promise.resolve([{post_id:'post',saved:true}]));await c.syncSaved();assert.deepEqual(Array.from(c.saved),['original']);});
test('a pending saved-post response cannot repopulate hearts after logout',async()=>{let resolve;const c=setup(new Promise(r=>resolve=r));const pending=c.syncSaved();c.user=null;c.saved=[];resolve([{post_id:'post',saved:true}]);await pending;assert.deepEqual(Array.from(c.saved),[]);});
test('guest saves merge with account saves, deduplicating source IDs and preserving passport fields',async()=>{
 const c=setup(Promise.resolve([{post_id:'existing',saved:true},{post_id:'post',saved:false,note:'My impression'}]));
 c.catalog.push({id:'existing'});let cleared=false;const writes=[];let notice;
 c.localStorage={getItem:()=>JSON.stringify(['original','post','existing']),removeItem(){cleared=true;}};
 c.backend.socialSave=async(table,row,key)=>writes.push({table,row:{...row},key});c.notifyUser=value=>notice=value;
 await c.syncSaved();assert.deepEqual(Array.from(c.saved).sort(),['existing','original']);
 assert.equal(writes.length,1);assert.deepEqual(writes[0].row,{user_id:'one',post_id:'post',saved:true});
 assert.equal(cleared,true);assert.equal(notice,'imported');
});
test('failed import retains browser saves for retry and never reports success',async()=>{
 const c=setup(Promise.resolve([]));let cleared=false;let notice;
 c.localStorage={getItem:()=>JSON.stringify(['original']),removeItem(){cleared=true;}};
 c.backend.socialSave=async()=>{throw Error('offline');};c.notifyUser=value=>notice=value;
 await c.syncSaved();assert.equal(cleared,false);assert.equal(notice,'keepLocal');
});
