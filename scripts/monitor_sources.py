#!/usr/bin/env python3
"""Public-source monitor. Standard library only; no login or auto-publication."""
import concurrent.futures, datetime as dt, hashlib, ipaddress, json, os, re, socket, threading, time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit, unquote
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError
from urllib.robotparser import RobotFileParser
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent
AGENT='ARTsyRATMonitor/1.0 (+https://besheny-glist.github.io/artsy-rat/)'
VOID={'br','img','input','meta','link','hr','source','area','base','embed','wbr'}
class Node:
 def __init__(self,tag='',attrs=None,parent=None):self.tag=tag;self.attrs=attrs or {};self.parent=parent;self.children=[]
 def text(self):return ' '.join(' '.join(c if isinstance(c,str) else c.text() for c in self.children).split())
 def find(self,tag=None,cls=None):
  result=[]
  for c in self.children:
   if isinstance(c,Node):
    if (tag is None or c.tag==tag) and (cls is None or cls in c.attrs.get('class','').split()):result.append(c)
    result+=c.find(tag,cls)
  return result
class Tree(HTMLParser):
 def __init__(self,html):super().__init__(convert_charrefs=True);self.root=Node();self.current=self.root;self.feed(html)
 def handle_starttag(self,tag,attrs):
  n=Node(tag,dict(attrs),self.current);self.current.children.append(n)
  if tag not in VOID:self.current=n
 def handle_endtag(self,tag):
  n=self.current
  while n.parent:
   if n.tag==tag:self.current=n.parent;return
   n=n.parent
 def handle_data(self,data):
  if self.current.tag not in {'script','style','noscript'}:self.current.children.append(data)
def canonical(url):
 p=urlsplit(url);return urlunsplit((p.scheme.lower(),p.netloc.lower(),p.path.rstrip('/') or '/',p.query,''))
def identifier(url):return hashlib.sha256(canonical(url).encode()).hexdigest()
def public_url(url):
 p=urlsplit(url)
 if p.scheme not in ('http','https') or not p.hostname or p.username or p.password or p.port not in (None,80,443):raise ValueError('unsafe_url')
 for a in socket.getaddrinfo(p.hostname,p.port or (443 if p.scheme=='https' else 80),type=socket.SOCK_STREAM):
  if not ipaddress.ip_address(a[4][0]).is_global:raise ValueError('unsafe_url')
 return url
class Redirects(HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):return super().redirect_request(req,fp,code,msg,headers,public_url(newurl))
def fetch(url,headers=None):
 public_url(url)
 with build_opener(Redirects()).open(Request(url,headers={'User-Agent':AGENT,**(headers or {})}),timeout=20) as res:
  content=res.read(2_000_001)
  if len(content)>2_000_000:raise ValueError('response_too_large')
  return content.decode(res.headers.get_content_charset() or 'utf-8',errors='replace'),res.geturl()
robots={};locks={};guard=threading.Lock()
def allowed_fetch(url):
 host=urlsplit(url).netloc
 with guard:lock=locks.setdefault(host,threading.Lock())
 with lock:
  if host not in robots:
   robot_url=urljoin(url,'/robots.txt');robot=RobotFileParser()
   try:raw,_=fetch(robot_url);robot.parse(raw.splitlines())
   except HTTPError as e:
    if e.code==404:robot.parse([])
    elif e.code in (401,403):raise ValueError('robots_blocked')
    else:raise
   robots[host]=robot
  if not robots[host].can_fetch(AGENT,url):raise ValueError('robots_blocked')
  delay=robots[host].crawl_delay(AGENT) or .4
  if delay>30:raise ValueError('crawl_delay_requires_manual')
  time.sleep(delay)
  return fetch(url)
def candidate(title,url,date=''):
 title=' '.join(title.replace('→','').split())[:180]
 if len(title)<3 or urlsplit(url).scheme not in ('http','https'):return None
 return {'id':identifier(url),'title':title,'url':canonical(url),'date_label':date[:160]}
def parse(html,url,kind):
 tree=Tree(html).root;items=[];metadata={}
 if kind=='rss':
  xml=ET.fromstring(html)
  for el in xml.iter():
   if el.tag.split('}')[-1] not in ('item','entry'):continue
   fields={c.tag.split('}')[-1]:c for c in el}
   title=''.join(fields['title'].itertext()) if 'title' in fields else ''
   link=fields.get('link');href=(link.get('href') or link.text or '') if link is not None else ''
   date=next((fields[k].text for k in ('pubDate','published','updated') if k in fields),'')
   if href:items.append(candidate(Tree(title).root.text(),urljoin(url,href),date or ''))
 elif kind=='exindex':
  for block in tree.find(cls='event-item')[:8]:
   headings=block.find(cls='entry-title');dates=block.find(cls='event-on-view')
   if headings and headings[0].find('a'):
    a=headings[0].find('a')[0];items.append(candidate(a.text(),urljoin(url,a.attrs.get('href','')),dates[0].text() if dates else ''))
  addresses=tree.find(cls='helyszin_cim');sites=tree.find(cls='helyszin_url')
  metadata['address']=addresses[0].text()[:220] if addresses else ''
  metadata['official_url']=sites[0].find('a')[0].attrs.get('href','') if sites and sites[0].find('a') else ''
 elif kind=='telegram':
  for block in tree.find(cls='tgme_widget_message')[-12:]:
   text=block.find(cls='tgme_widget_message_text');times=block.find('time');post=block.attrs.get('data-post','')
   if text and post:items.append(candidate(' '.join(text[0].text().split()[:20]),'https://t.me/'+post,times[0].attrs.get('datetime','') if times else ''))
 elif kind=='webpage':
  main=(tree.find('main') or [tree])[0]
  for a in main.find('a'):
   href=urljoin(url,a.attrs.get('href',''));p=urlsplit(href);text=a.text()
   if p.scheme not in ('https','http') or p.netloc!=urlsplit(url).netloc:continue
   if not re.search(r'exhib|kiall|kiáll|event|program|aktual|news|/hir|/cikk',p.path,re.I):continue
   if text.lower().strip() in {'read more','bővebben','további információ','to the exhibition','tovább'}:
    parent=a.parent
    for _ in range(3):
     if not parent:break
     headings=[n for n in parent.find() if n.tag in ('h1','h2','h3','h4')]
     if headings:text=headings[0].text();break
     parent=parent.parent
    else:text=unquote(p.path.rstrip('/').rsplit('/',1)[-1]).replace('-',' ')
   if len(text)<8 or text.lower().strip() in {'exhibitions','all exhibitions','current exhibitions','past exhibitions','programmes','programs','news','kiállítások','események','programok','all programmes','previous programmes','calendar','hírlevél','hírek, információk','időszaki kiállítások','állandó kiállítások','on-line kiállítások','vándorkiállítások kölcsönzése'}:continue
   items.append(candidate(text,href))
 else:raise ValueError('manual_source')
 unique={i['id']:i for i in items if i}
 return list(unique.values())[:12],metadata,hashlib.sha256((tree.find('main') or [tree])[0].text().encode()).hexdigest()
def load_overrides():
 config=(ROOT/'config.js').read_text();base=re.search(r"supabaseUrl:\s*'([^']+)'",config)[1];key=re.search(r"supabaseAnonKey:\s*'([^']+)'",config)[1]
 raw,_=fetch(base+'/rest/v1/rpc/monitor_source_directory',{'apikey':key})
 return json.loads(raw)
def scan(source,old):
 now=dt.datetime.now(dt.timezone.utc).isoformat();out={**source,'checked_at':now,'status':'ok','count':0};found=[]
 if not source.get('enabled',True):return {**out,'status':'paused'},[]
 if source['kind']=='manual':return {**out,'status':'manual'},[]
 try:
  raw,final=allowed_fetch(source['url']);found,meta,fingerprint=parse(raw,final,source['kind']);out.update(meta);out['fingerprint']=fingerprint;out['count']=len(found)
  if not found:
   out['status']='watching_page'
   if old and old.get('fingerprint') and old['fingerprint']!=fingerprint:found=[candidate('Page updated: '+source['name'],source['url'])]
  for i in found:i.update(source_id=source['id'],source_name=source['name'],category=source['category'],discovered_at=now,kind=source['kind'])
 except Exception as e:
  out['status']='error';out['error']=('HTTP '+str(e.code)) if isinstance(e,HTTPError) else str(e)[:180]
 return out,found

def main():
 sources=json.loads((ROOT/'monitor-sources.json').read_text());config_error=None
 try:
  overrides=load_overrides()
  sources=[s for s in overrides if s.get('place_id') and not s.get('retired')]
  if not sources:raise RuntimeError('Curated source registry is empty; refusing legacy sources')
 except Exception as e:
  # Never silently reactivate paused sources when configuration is unavailable.
  raise RuntimeError('Cannot read source settings; retaining previous scan') from e
 previous=json.loads((ROOT/'monitor-feed.json').read_text()) if (ROOT/'monitor-feed.json').exists() else {}
 oldsources={s['id']:s for s in previous.get('sources',[])};items={i['id']:i for i in previous.get('items',[])};results=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
  for source,found in pool.map(lambda s:scan(s,oldsources.get(s['id'])),sources):
   results.append(source)
   for item in found:
    if item['id'] in items:item['discovered_at']=items[item['id']]['discovered_at']
    items[item['id']]=item
   print(source['name'],source['status'],source.get('count',0),flush=True)
 enabled={s['id'] for s in sources if s.get('enabled',True)}
 output={'generated_at':dt.datetime.now(dt.timezone.utc).isoformat(),'schedule':'06:17 / 18:17 UTC','sources':results,'items':sorted((i for i in items.values() if i['source_id'] in enabled),key=lambda i:i['discovered_at'],reverse=True)[:1500]}
 (ROOT/'monitor-feed.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
