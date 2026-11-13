import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
Deno.serve(async req=>{
 const token=new URL(req.url).searchParams.get('token')||'';
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token))return new Response('Invalid unsubscribe link',{status:400});
 if(req.method==='GET')return Response.redirect(new URL('unsubscribe.html#'+token,Deno.env.get('SITE_URL')||'https://artsyrat.eu/'),303);
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 const db=createClient(Deno.env.get('SUPABASE_URL')!,(Object.values(JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}'))[0] as string || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!));
 const {error}=await db.from('subscriptions').update({subscribed:false,updated_at:new Date().toISOString()}).eq('unsubscribe_token',token);
 if(error)return new Response('Please try again.',{status:503});
 return new Response('Unsubscribed. / Sikeres leiratkozás. / Вы отписались.',{headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store'}});
});
