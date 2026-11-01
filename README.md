# ARTsy RAT

Art discovery in Budapest. Live frontend: https://besheny-glist.github.io/artsy-rat/

## Current version

English by default, with Hungarian and Russian switching. Fictional exhibition examples, filters, browser-local plans, personal invitation links, account screen and editorial studio preview.

Prepared integrations: Supabase email/password authentication, password reset/change, server-controlled admin role, rich-text editor with photo uploads, typography, animation, preview, publish, trash and restore, permanent published stories, opt-in subscriptions, language-specific newsletter queues and Resend delivery with unsubscribe links.

**Supabase and Resend are not connected yet.** No real admin account or subscription exists. Account forms are disabled until public configuration is supplied. The editor can be previewed without pretending to publish. [Activation instructions](docs/SETUP.md).

## Development

```sh
python3 -m http.server 4173
node --test tests/*.test.cjs
```

No build dependencies. GitHub Actions runs tests and publishes only the public HTML, CSS and JavaScript to Pages on push to main. Backend files, tests and documents are not in the Pages artifact.

## Backend

- `supabase/migrations/001_platform.sql`: roles, posts, subscriptions, RLS, publishing transaction and queue leases.
- `supabase/functions/deliver`: validates admin token and sends queued emails through Resend.
- `supabase/functions/unsubscribe`: confirmed token-based opt-out.
- `config.js`: public project URL and anon key only. Never commit service-role or Resend secrets.

There is no public admin/admin password. Create an email account and assign its UUID to the server-side admin allowlist. Password changes are available in My account after connection.

## Verification and limits

Automated frontend/API contract tests run in CI. Database policies, Edge Functions and real email delivery need the acceptance tests in [SETUP](docs/SETUP.md) against your provisioned project. These have not been integration-tested on a live backend.

Published stories stay in Supabase. Sending is resumable and separate from publication. The browser processes batches while open; admin can resume pending emails. No scheduled background dispatcher or bounce webhook is configured yet. `sent` means provider acceptance. Plans remain local to the browser. Individual invitation Open Graph previews are not implemented.

[Product scope](docs/product.md) · [Manual UI checks](docs/testing.md)

The administrator studio manages both Exhibitions and Letters & stories. Existing static entries appear in the same list as database posts and are imported on first edit or deletion without sending a newsletter. Both sections support images, rich text, translations, deletion and restoration. See docs/SETUP.md for setup and import behavior.

Typography: self-hosted Literata and Golos Text (SIL Open Font License). Font files and licenses are in `assets/fonts/`; Cyrillic and extended Latin subsets support RU and HU.
