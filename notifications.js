'use strict';
// Keep existing inline feedback, and surface it where users can see it.
(()=>{
 const box=document.createElement('aside');box.className='app-notification';box.hidden=true;box.setAttribute('popover','manual');
 const message=document.createElement('p');message.setAttribute('role','alert');message.setAttribute('aria-atomic','true');
 const close=document.createElement('button');close.type='button';close.textContent='×';box.append(message,close);document.body.append(box);
 const text=k=>window.I18N?.[document.documentElement.lang]?.[k]||window.I18N?.en?.[k]||k;
 function dismiss(){if(box.matches(':popover-open'))box.hidePopover();box.hidden=true;message.textContent='';}
 window.notifyUser=value=>{const valueText=String(value||'').trim();if(!valueText||['busy','imageProcessing'].some(key=>Object.values(window.I18N||{}).some(locale=>locale[key]===valueText)))return;close.setAttribute('aria-label',text('close'));message.textContent=valueText;box.hidden=false;if(box.showPopover&&!box.matches(':popover-open'))box.showPopover();};
 close.onclick=dismiss;document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!box.hidden)dismiss();});
 const previous=new WeakMap();
 const feedback='[role="status"],[role="alert"]';
 new MutationObserver(records=>{
  const elements=new Set();
  for(const record of records){if(box.contains(record.target))continue;const el=record.target.nodeType===1?record.target:record.target.parentElement;const parent=el?.closest(feedback);if(parent)elements.add(parent);for(const node of record.addedNodes){if(node.nodeType!==1||box.contains(node))continue;if(node.matches(feedback))elements.add(node);node.querySelectorAll(feedback).forEach(item=>elements.add(item));}}
  for(const el of elements){if(!el.isConnected||box.contains(el))continue;const value=[...el.childNodes].filter(n=>n.nodeType===3||(n.nodeType===1&&!n.matches('input,textarea,button,select'))).map(n=>n.textContent).join(' ').trim();if(value&&previous.get(el)!==value)window.notifyUser(value);previous.set(el,value);}
 }).observe(document.body,{subtree:true,childList:true,characterData:true});
 document.addEventListener('invalid',e=>{if(e.target.validationMessage)window.notifyUser(e.target.validationMessage);},true);
 window.addEventListener('unhandledrejection',()=>window.notifyUser(text('unexpectedError')));
 window.addEventListener('error',e=>{if(e.error)window.notifyUser(text('unexpectedError'));});
})();
