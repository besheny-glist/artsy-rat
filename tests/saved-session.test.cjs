const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const source=fs.readFileSync('social.js','utf8').split('\n').find(line=>line.includes('async function syncSaved()'));
function setup(rows){const context=vm.createContext({user:{id:'one'},saved:['other-account'],catalog:[{id:'post',source_id:'original'}],backend:{socialRows:()=>rows},localStorage:{removeItem(){}},render(){},notifyUser(){},S:k=>k});vm.runInContext(source,context);return context;}
test('sign-in replaces cached hearts with only this account’s saved posts',async()=>{const c=setup(Promise.resolve([{post_id:'post',saved:true}]));await c.syncSaved();assert.deepEqual(Array.from(c.saved),['original']);});
test('a pending saved-post response cannot repopulate hearts after logout',async()=>{let resolve;const c=setup(new Promise(r=>resolve=r));const pending=c.syncSaved();c.user=null;c.saved=[];resolve([{post_id:'post',saved:true}]);await pending;assert.deepEqual(Array.from(c.saved),[]);});
