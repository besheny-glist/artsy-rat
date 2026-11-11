'use strict';
window.backend = (()=>{
 const config=window.ARTSY_CONFIG||{}; const ready=!!(config.supabaseUrl&&config.supabaseAnonKey);
 let session=null;try{session=JSON.parse(sessionStorage.getItem('artsy-session')||'null');}catch{}
 const persist=s=>{session=s;try{s?sessionStorage.setItem('artsy-session',JSON.stringify(s)):sessionStorage.removeItem('artsy-session');}catch{}};
 async function request(path,{method='GET',body,auth=true,headers={}}={}){
  if(!ready)throw Error('NOT_CONFIGURED');
  const res=await fetch(config.supabaseUrl+path,{method,headers:{apikey:config.supabaseAnonKey,'Content-Type':'application/json',...(auth&&session?{Authorization:'Bearer '+session.access_token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await res.text();let data;try{data=text?JSON.parse(text):null;}catch{data=null;}
  if(!res.ok){const e=Error('REQUEST_FAILED');e.status=res.status;e.code=typeof data?.error_code==='string'?data.error_code:typeof data?.code==='string'?data.code:'';throw e;}return data;
 }
 return {ready,get session(){return session;},
 async initialize(){if(!ready)return; const p=new URLSearchParams(location.hash.slice(1));if(p.has('access_token')&&p.has('refresh_token')){persist({access_token:p.get('access_token'),refresh_token:p.get('refresh_token')});history.replaceState(null,'',location.pathname+location.search+'#account');}
 if(session){try{const refreshed=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},auth:false});persist(refreshed);}catch{persist(null);}}},
 async login(email,password){persist(await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password},auth:false}));},
 async signup(email,password){const result=await request('/auth/v1/signup?redirect_to='+encodeURIComponent(location.origin+location.pathname),{method:'POST',auth:false,body:{email,password}});if(result?.access_token)persist(result);return result;},
 reset:email=>request('/auth/v1/recover?redirect_to='+encodeURIComponent(location.origin+location.pathname),{method:'POST',auth:false,body:{email}}),
 async logout(){try{await request('/auth/v1/logout',{method:'POST'});}finally{persist(null);}},
 user:()=>request('/auth/v1/user'),
 profile:data=>request('/auth/v1/user',{method:'PUT',body:{data:{...(data.profile_kind?{profile_kind:data.profile_kind}:{}),display_name:data.display_name,avatar_image:data.avatar_image,...(data.taste_cards?{taste_cards:data.taste_cards}:{})}}}),
 password:password=>request('/auth/v1/user',{method:'PUT',body:{password}}),
 socialRows:(table,query='')=>request('/rest/v1/'+table+'?select=*'+query),
 socialSave:(table,row,conflict)=>request('/rest/v1/'+table+(conflict?'?on_conflict='+conflict:''),{method:'POST',body:row,headers:{Prefer:conflict?'resolution=merge-duplicates,return=representation':'return=representation'}}),
 rpc:(name,body={})=>request('/rest/v1/rpc/'+name,{method:'POST',body}),
 posts:()=>request('/rest/v1/rpc/public_catalog',{method:'POST',body:{}}),
 importedState:()=>request('/rest/v1/rpc/imported_story_state',{method:'POST',body:{},auth:false}),
 drafts:()=>request('/rest/v1/posts?select=*&order=created_at.desc'),
 save:post=>request('/rest/v1/posts'+(post.id?'?id=eq.'+encodeURIComponent(post.id):''),{method:post.id?'PATCH':'POST',body:{title:post.title,summary:post.summary,body:post.body,language:post.language,images:post.images||[],author:post.author||'',source:post.source||'',links:post.links||[],translations:post.translations||{},rich_body:post.rich_body||'',image_meta:post.image_meta||{},design:post.design||{},...(!post.id&&post.source_id?{source_id:post.source_id}:{})},headers:{Prefer:'return=representation'}}),
 async uploadSubmission(file){if(!session)throw Error('loginRequired');if(file.size>10485760)throw Error('imageTooLarge');if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('imageFormat');const u=await request('/auth/v1/user');const path=u.id+'/'+crypto.randomUUID()+'.'+file.type.split('/')[1];const r=await fetch(config.supabaseUrl+'/storage/v1/object/submission-images/'+path,{method:'POST',headers:{apikey:config.supabaseAnonKey,Authorization:'Bearer '+session.access_token,'Content-Type':file.type},body:file,signal:AbortSignal.timeout(45000)});if(!r.ok)throw Error('imageUploadFailed');return config.supabaseUrl+'/storage/v1/object/public/submission-images/'+path;},
 async uploadAvatar(file){
 if(!ready||!session)throw Error('NOT_CONFIGURED');
 if(file.type!=='image/jpeg'||file.size>2097152)throw Error('avatarInvalid');
 const current=await request('/auth/v1/user');
 const path=current.id+'/'+crypto.randomUUID()+'.jpg';
 const res=await fetch(config.supabaseUrl+'/storage/v1/object/avatars/'+path,{method:'POST',signal:AbortSignal.timeout(45000),headers:{apikey:config.supabaseAnonKey,Authorization:'Bearer '+session.access_token,'Content-Type':'image/jpeg'},body:file});
 if(!res.ok)throw Error('REQUEST_FAILED');return config.supabaseUrl+'/storage/v1/object/public/avatars/'+path;
 },
 async upload(file){
 if(!ready||!session)throw Error('NOT_CONFIGURED');
 if(file.size>10485760)throw Error('imageTooLarge');if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('imageFormat');
 const path=crypto.randomUUID()+'.'+({'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file.type]);
 const res=await fetch(config.supabaseUrl+'/storage/v1/object/post-images/'+path,{method:'POST',signal:AbortSignal.timeout(45000),headers:{apikey:config.supabaseAnonKey,Authorization:'Bearer '+session.access_token,'Content-Type':file.type},body:file});
 if(!res.ok)throw Error('REQUEST_FAILED');return config.supabaseUrl+'/storage/v1/object/public/post-images/'+path;
 },
 deliver:()=>request('/functions/v1/deliver',{method:'POST',body:{}}),
 deliveries:()=>request('/rest/v1/deliveries?select=status&limit=10000'),
 };
})();
