'use strict';
// Both sections share the same admin-only database policies and post lifecycle.
window.contentModel = {
 additionalLinks(post) {
  const key=value=>{try{const u=new URL(value);if(!['http:','https:'].includes(u.protocol))return null;u.pathname=u.pathname.replace(/\/+$/,'')||'/';return u.href;}catch{return null;}};
  const seen=new Set([key(post.source)]);
  return (post.links||[]).filter(link=>{const url=key(link.url);if(!url||seen.has(url))return false;seen.add(url);return true;});
 },
 wall(posts) {
  const eligible=posts.filter(p=>!p.deleted_at&&p.status!=='draft'&&!p.design?.exhibition?.demo&&['journal','exhibitions','events'].includes(this.section(p)));
  const selected=['left','right'].map(slot=>eligible.find(p=>p.design?.homeSlot===slot));
  const fallback=eligible.filter(p=>this.section(p)==='journal'&&!selected.some(x=>x?.id===p.id));
  return selected.map(p=>p||fallback.shift()).filter(Boolean);
 },
 section: p => ['exhibitions','events','notes','newsletter'].includes(p.design?.section) ? p.design.section : 'journal',
 merge(remote, bootstrap, imported) {
  const known = new Set([...imported.map(p=>p.source_id), ...remote.map(p=>p.source_id)].filter(Boolean));
  return [...remote, ...bootstrap.filter(p=>!known.has(p.id))].sort((a,b)=>new Date(b.published_at)-new Date(a.published_at));
 },
 async ensureManaged(post, backend, baseURL) {
  if (!post.bootstrap) return post;
  const find = async () => (await backend.drafts()).find(p=>p.source_id===post.id);
  let row = await find();
  if (!row) {
   try {
    const {bootstrap,...data}=post;
    [row] = await backend.save({...data,id:null,source_id:post.id,images:(post.images||[]).map(u=>new URL(u,baseURL).href),image_meta:Object.fromEntries(Object.entries(post.image_meta||{}).map(([u,meta])=>[new URL(u,baseURL).href,meta]))});
   } catch(error) {
    if(error.status!==409)throw error;
    row=await find();if(!row)throw error;
   }
  }
  if(row.deleted_at)throw Error('deleted');
  if(row.status!=='published') {
   await backend.rpc('publish_post',{post_id:row.id,send_newsletter:false});
   row={...row,status:'published'};
  }
  return row;
 }
};
