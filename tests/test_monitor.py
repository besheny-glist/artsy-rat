import importlib.util,json,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('monitor',Path(__file__).parents[1]/'scripts/monitor_sources.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class MonitorTests(unittest.TestCase):
 def test_budapest_only(self):
  sources=json.loads((m.ROOT/'monitor-sources.json').read_text())
  self.assertEqual(len(sources),len({s['id'] for s in sources}))
  for s in sources:
   self.assertEqual(s['city'],'Budapest')
   if s['kind']=='exindex':self.assertIn('budapest',s['address'].lower())
 def test_exindex_dates_and_dedup(self):
  block='<div class="event-item"><h2 class="entry-title"><a href="/en/event/light/">Folded Light</a></h2><div class="event-on-view">2026-11-01</div></div>'
  items,_,_=m.parse(block*2,'https://exindex.hu/en/venue/sample/','exindex')
  self.assertEqual(len(items),1);self.assertEqual(items[0]['url'],'https://exindex.hu/en/event/light');self.assertEqual(items[0]['date_label'],'2026-11-01')
 def test_atom_and_unsafe_links(self):
  xml='<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>New exhibition</title><link href="https://example.org/exhibitions/new"/><updated>2026-11-01</updated></entry><entry><title>Unsafe link</title><link href="javascript:alert(1)"/></entry></feed>'
  items,_,_=m.parse(xml,'https://example.org/feed','rss');self.assertEqual(len(items),1)
 def test_private_network_blocked(self):
  for ip in ['127.0.0.1','192.168.0.1','169.254.169.254','::1']:
   with patch.object(m.socket,'getaddrinfo',return_value=[(None,None,None,None,(ip,80))]):
    with self.assertRaises(ValueError):m.public_url('https://example.org')
 def test_failure_not_success(self):
  source=dict(id='x',name='Gallery',url='https://example.org',kind='webpage',category='gallery')
  with patch.object(m,'allowed_fetch',side_effect=TimeoutError('timeout')):
   info,items=m.scan(source,None);self.assertEqual(info['status'],'error');self.assertEqual(items,[])
 def test_paused_source_never_fetched(self):
  with patch.object(m,'allowed_fetch') as fetch:
   info,items=m.scan(dict(id='x',enabled=False),None);fetch.assert_not_called();self.assertEqual(info['status'],'paused')
if __name__=='__main__':unittest.main()
