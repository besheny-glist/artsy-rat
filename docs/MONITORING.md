# Editorial monitoring

Open `#studio` as an administrator, then **Monitoring**. Sources are restricted to Budapest: 71 venue entries with Budapest addresses in the exindex directory, 27 museum/cultural-attraction websites from Budapestinfo and the Museum of Fine Arts. Some institutions have both an exindex entry and an official website.

The initial catalogue is in `monitor-sources.json`; it is a snapshot, not a guarantee that every historical venue still operates. Source dates and original links remain visible. Exindex venue pages provide exhibition headlines; museum websites provide matching event/news links or page-change notices. First discovery is not publication date. Review relevance before publishing.

The `Monitor Budapest sources` GitHub workflow checks public pages at 06:17 and 18:17 UTC. GitHub may delay scheduled runs. Manual runs are available through Actions. Results are committed to `monitor-feed.json`; a successful collection triggers the Pages workflow. Refresh inbox loads the most recent run, not a new crawl. Failed or blocked sources show an error rather than a successful scan.

Supabase migration `008_monitoring.sql` stores admin-only editorial reviews and source overrides. Only public names/URLs/configuration are exposed through the read-only source-directory RPC; no user profiles, emails or editorial decisions are public. The collector uses the existing publishable key, not a service-role secret. If it cannot read overrides it retains the previous feed rather than reactivating paused sources.

Editors can shortlist, hide, prepare a draft, add a public source or pause it. Preparing a post copies only the headline, source URL and venue into the existing editor. Text, dates and permitted photos must be completed before saving. It never automatically publishes or emails subscribers. Instagram and Facebook links are manual bookmarks; automated authenticated social access is not configured.

Run checks with `python3 -m unittest discover -s tests -p 'test_monitor.py'` and `node --test tests/*.test.cjs`.
