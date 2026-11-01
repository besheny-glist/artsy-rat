'use strict';
// Both sections share the same admin-only database policies and post lifecycle.
window.contentModel = {
 wall(posts) {
  const eligible=posts.filter(p=>!p.deleted_at&&p.status!=='draft'&&!p.design?.exhibition?.demo);
  const selected=['left','right'].map(slot=>eligible.find(p=>p.design?.homeSlot===slot));
  const fallback=eligible.filter(p=>this.section(p)==='journal'&&!selected.some(x=>x?.id===p.id));
  return selected.map(p=>p||fallback.shift()).filter(Boolean);
 },
 section: p => p.design?.section === 'exhibitions' ? 'exhibitions' : 'journal',
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
