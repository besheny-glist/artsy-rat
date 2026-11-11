import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const site = Deno.env.get('SITE_URL') || 'https://besheny-glist.github.io/artsy-rat/';
const origin = new URL(site).origin;
const cors = {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL')!, key=(Object.values(JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}'))[0] as string || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 const db=createClient(url,key,{auth:{persistSession:false}});
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
 if(!token)return reply({error:'Unauthorized'},401);
 const {data:{user},error:authError}=await db.auth.getUser(token);
 if(authError||!user)return reply({error:'Unauthorized'},401);
 const {data:admin}=await db.from('admins').select('user_id').eq('user_id',user.id).maybeSingle();
 if(!admin)return reply({error:'Forbidden'},403);
 const apiKey=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('MAIL_FROM');
 if(!apiKey||!from)return reply({error:'Email provider is not configured'},503);
 const {data:jobs,error}=await db.rpc('claim_deliveries');
 if(error)return reply({error:'Queue unavailable'},500);
 let sent=0,failed=0,cancelled=0;
 for(const job of jobs||[]){
  try{
   const {data:sub,error:se}=await db.from('subscriptions').select('*').eq('user_id',job.user_id).maybeSingle();
   if(se)throw se;
   if(!sub?.subscribed){const {error:e}=await db.from('deliveries').update({status:'cancelled',lease_until:null}).eq('id',job.id);if(e)throw e;cancelled++;continue;}
   const {data:current,error:pe}=await db.from('posts').select('deleted_at').eq('id',job.post_id).single();if(pe)throw pe;if(current.deleted_at){await db.from('deliveries').update({status:'cancelled'}).eq('id',job.id);cancelled++;continue;}
   const original=job.post_snapshot;if(!original)throw Error('Missing publication snapshot');const post={...original,...(original.translations?.[job.recipient_language]||{})};
   const {data:recipient,error:ue}=await db.auth.admin.getUserById(job.user_id);if(ue||!recipient.user.email||!recipient.user.email_confirmed_at)throw Error('Recipient unavailable');
   const unsubscribe=url+'/functions/v1/unsubscribe?token='+sub.unsubscribe_token;
   const label={en:'Unsubscribe',hu:'Leiratkozás',ru:'Отписаться'}[post.language as 'en'|'hu'|'ru'];
   const escape=(v:unknown)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
   const images=(original.images||[]).filter((u:string)=>{try{return new URL(u).protocol==='https:';}catch{return false;}});
   const html='<h1>'+escape(post.title)+'</h1><p>'+escape(post.summary)+'</p><div style="white-space:pre-wrap">'+escape(post.body)+'</div>'+images.map((u:string)=>'<p><img style="max-width:100%;height:auto" src="'+escape(u)+'" alt="'+escape(original.image_meta?.[u]?.alt||post.title)+'"></p>').join('')+'<p><a href="'+escape(site+'#post='+job.post_id)+'">ARTsy RAT</a></p><p><a href="'+escape(unsubscribe)+'">'+escape(label)+'</a></p>';
   const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+apiKey,'Content-Type':'application/json','Idempotency-Key':'artsy-'+job.id},body:JSON.stringify({from,to:[job.recipient_email],subject:post.title,html,text:post.summary+'\n\n'+post.body+'\n\n'+site+'#post='+job.post_id+'\n\n'+label+': '+unsubscribe})});
   if(!response.ok)throw Error('Provider rejected delivery');
   const result=await response.json();const {error:saveError}=await db.from('deliveries').update({status:'sent',provider_id:result.id,lease_until:null}).eq('id',job.id).eq('status','sending');if(saveError)throw saveError;sent++;
  }catch{
   await db.from('deliveries').update({status:'failed',lease_until:new Date(Date.now()+60000).toISOString()}).eq('id',job.id).eq('status','sending');failed++;
  }
  // Keep below the default provider rate limit; 5 messages per invocation.
  await new Promise(r=>setTimeout(r,600));
 }
 return reply({processed:(jobs||[]).length,sent,failed,cancelled});
});
