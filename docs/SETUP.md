# Activate accounts, editorial posts and email

The public frontend is on GitHub Pages. Supabase and Resend are prepared in source, but are NOT provisioned or connected. No administrator exists until step 3 is completed. Never use `admin/admin` on the public site.

## 1. Supabase project

Create a project in your own Supabase account. Run `supabase/migrations/001_platform.sql` once in SQL Editor. The migration creates posts, subscriptions, an administrator allowlist and a delivery queue with RLS. Keep email confirmation enabled in Authentication. Set the minimum password length to 12 characters.

Authentication → URL Configuration:
- Site URL: `https://besheny-glist.github.io/artsy-rat/`
- Allowed redirect URL: the same URL.

Set up a custom SMTP sender for Auth messages before inviting real users. Resend SMTP may be used with its documented host/port and a server-side key. Confirmation and password-reset emails are sent by Supabase Auth, separate from the editorial queue.

## 2. Public frontend configuration

Fill in `config.js` with the project URL and **public anon key**. This key is intentionally public and protected by database policies. Never paste a service-role key or Resend API key into this file or GitHub.

Commit and push to main to publish the configured frontend.

## 3. One administrator

Register your own email via the website and confirm the address. In Supabase Authentication → Users copy that user's UUID, then run:

```sql
insert into public.admins(user_id) values ('YOUR_CONFIRMED_USER_UUID');
```

A single row means one admin account. Users cannot promote themselves. The login is the actual email address, not the word `admin`. Log out and sign back in to refresh the role. Change the password in My account. To transfer administration, invite and confirm the recipient's own account, replace the row in `public.admins`, and revoke the previous user's sessions through Supabase. This avoids sharing passwords.

## 4. Resend

Create an account, add a domain you control, and verify the DNS records shown by Resend. The default test sender cannot send a production newsletter to arbitrary people. Create an API key with email sending access. Keep it in Supabase Edge Function secrets only:

- `RESEND_API_KEY`: your secret key
- `MAIL_FROM`: `ARTsy RAT <letters@your-verified-domain>`
- `SITE_URL`: `https://besheny-glist.github.io/artsy-rat/`

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by the Supabase function runtime. Do not expose them in the frontend.

Deploy the `deliver` and `unsubscribe` functions from this repository, using Supabase CLI or the dashboard. CLI from the repository root:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy deliver --no-verify-jwt
supabase functions deploy unsubscribe --no-verify-jwt
```

`deliver` validates the supplied user token against Supabase Auth and checks the administrator allowlist itself. `unsubscribe` is public but requires an unguessable per-subscriber token and an explicit POST confirmation. Do not remove the authorization checks from `deliver`.

## 5. End-to-end acceptance before launch

1. Register two test accounts you own; confirm both emails. Make only one the admin.
2. Verify an ordinary account cannot insert/update posts, call publish_post or claim_deliveries, read subscriber addresses, or send mail. Test the REST API directly, not only the hidden buttons.
3. Subscribe the second account and select the same language as the test story.
4. As admin, write a draft and preview it. Verify it is invisible in a signed-out browser.
5. Publish & email subscribers. Verify the permanent story URL works signed out; verify the email arrives and includes the full story, permalink and unsubscribe link.
6. Repeating publish_post must not create a second delivery. Process pending emails until the queue is empty. Check the Resend dashboard for delivery/bounce status; `sent` in this app means accepted by Resend, not guaranteed inbox arrival.
7. Open the unsubscribe link (GET alone must not unsubscribe), confirm, publish another test story, and verify no new delivery is queued for that user.
8. Change the password and verify the old password no longer signs in. Test reset-password email too.

## Operational limits

This is an initial editorial integration, not a complete marketing automation service. Publication atomically persists the post and queues recipients. Email errors do not undo publication. Five messages are processed per function call; the browser drains successive batches after publication. If you close the browser, open the editorial studio and process pending emails again. Automatic background scheduling is not configured yet.

Only confirmed, opted-in subscribers whose language matches the post receive it. Publish separate posts for translated editions; automatic translation is not implemented. Published text is immutable in this MVP to keep retries consistent. Drafts may be edited. Saved exhibition plans remain browser-local and do not sync with the account yet.

The queue uses unique post/user pairs, row locking and Resend idempotency keys. Uncertain deliveries older than 20 hours enter `review`; reconcile with Resend before taking action. Do not reset them blindly, since provider idempotency keys expire. Delivery failure details and bounce events require checking the provider dashboard; webhook ingestion and automatic suppression are future work.

Do not launch broadly before reviewing sender identity/contact details, privacy text, provider plans/limits and the acceptance checks above. No real subscriber emails were sent during development.
