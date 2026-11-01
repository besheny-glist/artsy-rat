'use strict';
window.backend = (()=>{
 const config=window.ARTSY_CONFIG||{}; const ready=!!(config.supabaseUrl&&config.supabaseAnonKey);
 let session=null;try{session=JSON.parse(sessionStorage.getItem('artsy-session')||'null');}catch{}
 const persist=s=>{session=s;try{s?sessionStorage.setItem('artsy-session',JSON.stringify(s)):sessionStorage.removeItem('artsy-session');}catch{}};
 async function request(path,{method='GET',body,auth=true,headers={}}={}){
  if(!ready)throw Error('NOT_CONFIGURED');
  const res=await fetch(config.supabaseUrl+path,{method,headers:{apikey:config.supabaseAnonKey,'Content-Type':'application/json',...(auth&&session?{Authorization:'Bearer '+session.access_token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await res.text();let data;try{data=text?JSON.parse(text):null;}catch{data=null;}
  if(!res.ok){const e=Error('REQUEST_FAILED');e.status=res.status;throw e;}return data;
 }
 return {ready,get session(){return session;},
 async initialize(){if(!ready)return; const p=new URLSearchParams(location.hash.slice(1));if(p.has('access_token')&&p.has('refresh_token')){persist({access_token:p.get('access_token'),refresh_token:p.get('refresh_token')});history.replaceState(null,'',location.pathname+location.search+'#account');}
 if(session){try{const refreshed=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},auth:false});persist(refreshed);}catch{persist(null);}}},
 async login(email,password){persist(await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password},auth:false}));},
 signup:(email,password)=>request('/auth/v1/signup',{method:'POST',auth:false,body:{email,password}}),
 reset:email=>request('/auth/v1/recover',{method:'POST',auth:false,body:{email}}),
 async logout(){try{await request('/auth/v1/logout',{method:'POST'});}finally{persist(null);}},
 user:()=>request('/auth/v1/user'),
 password:password=>request('/auth/v1/user',{method:'PUT',body:{password}}),
 rpc:(name,body={})=>request('/rest/v1/rpc/'+name,{method:'POST',body}),
 posts:()=>request('/rest/v1/posts?status=eq.published&select=id,title,summary,body,language,published_at&order=published_at.desc',{auth:false}),
 drafts:()=>request('/rest/v1/posts?select=*&order=created_at.desc'),
 save:post=>request('/rest/v1/posts'+(post.id?'?id=eq.'+encodeURIComponent(post.id):''),{method:post.id?'PATCH':'POST',body:{title:post.title,summary:post.summary,body:post.body,language:post.language},headers:{Prefer:'return=representation'}}),
 deliver:()=>request('/functions/v1/deliver',{method:'POST',body:{}}),
 deliveries:()=>request('/rest/v1/deliveries?select=status&limit=10000'),
 };
})();
