# Health Pro

Your Health. Our Priority. One app for sport in Bhutan, on the web, Android and iOS, built from a shared **core** and one package per **module**:

| Module | Status | What it does |
|---|---|---|
| Ground booking (`ground_booking`) | On | Book grounds and follow tournaments. These still run on the ground booking website, and Health Pro links to it (see [Bringing ground booking in](#bringing-ground-booking-in-one-domain)). |
| Gym membership (`gym_membership`) | Built, off until you turn it on | The front desk registers members (details, webcam photo, package and its expiry date), sends them a QR card on WhatsApp, and checks them in with it. Owners set packages and prices, see income and choose their staff's roles. |

The backend is Supabase: database, security rules, server functions, the daily job and the account-deletion Edge Function. There is no other server.

## Layout

```
pubspec.yaml                  Dart pub workspace: run `flutter pub get` here
apps/health_pro_app/           the one Flutter app (web, Android, iOS); lib/main.dart lists the modules
packages/health_pro_core/      accounts, profiles, venues and staff, payments, notifications,
                              the module contract, router, home page, admin, theme
packages/ground_booking/      module 1: links to the ground booking website
packages/gym_membership/      module 2: gym plans, memberships, check-in, staff and owner pages
supabase/migrations/          core, then one migration per module
supabase/functions/           Edge Functions (delete-account, admin-users, ask-ai, ask-sportshub; _shared)
supabase/config.toml          auth settings (email codes) and function settings
supabase/templates/code.html  the sign-in email, showing the 6-digit code
supabase/test_users.sql       test accounts, one per role (test_users_remove.sql removes them)
supabase/default_code_for_old_users.sql  run once: accounts from before 6-digit sign-in codes start on 123456
tests/database/               end-to-end checks of the database rules
tests/functions/              checks of the Edge Functions' own logic (Deno)
scripts/                      deploy_supabase.sh, build_web.sh, deploy_web.sh, test_database.sh
```

Modules import only `health_pro_core`, never each other.

## Run the app

1. Put the backend on Supabase once (next section). That also writes `apps/health_pro_app/env.json`. Without it, copy `env.example.json` to `env.json` and fill in the Project URL and the anon (publishable) key from Supabase → Project Settings → API Keys. `env.json` is gitignored.
2. Run the website on http://localhost:3000 (3001 when 3000 is taken), from the `sporthubs` folder:

```sh
./scripts/run_web.sh              # opens Chrome on http://localhost:3000
./scripts/run_web.sh 3001         # a port of your choice
SERVE_ONLY=1 ./scripts/run_web.sh # just serve it; open the address in any browser
```

   In the terminal, `r` hot-reloads, `R` restarts and `q` quits. Or by hand:

```sh
cd apps/health_pro_app
flutter run -d chrome --web-port 3000 --dart-define-from-file=env.json   # website
flutter run --dart-define-from-file=env.json                             # phone or simulator
```

In VS Code, use the "Health Pro (website)" (port 3000), "Health Pro (website, port 3001)" and "Health Pro (phone)" launch configurations.

## Backend (Supabase)

Project: **SportsHub**, ref `iagqntjaywpdxvoxgfhl` (Singapore), `https://iagqntjaywpdxvoxgfhl.supabase.co`.

### Deploy

```sh
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

- `SUPABASE_ACCESS_TOKEN`: supabase.com/dashboard/account/tokens → Generate new token.
- `SUPABASE_DB_PASSWORD`: the database password set when the project was made (Database → Settings → Reset database password if it's lost).
- The database is reached through Health Pro's Session pooler, which works on networks without IPv6; it's built into the script. Deploying to a different project: set `SUPABASE_PROJECT_REF` and `SUPABASE_DB_URL` (that project's **Session pooler** string from the dashboard's Connect button, `[YOUR-PASSWORD]` included; the script puts the password in).
- The auth step fails ("Email template modification is not available for free tier projects…") until SMTP is set up (below). Migrations and functions are deployed before it.

The script applies only the migrations that aren't on the project yet, deploys the Edge Functions, pushes the auth settings in `supabase/config.toml`, and writes `env.json`. Run it again after any change in `supabase/`.

Rules for database changes: every change is a new file in `supabase/migrations/` (never edit one that's applied). Try it on a development project or with `scripts/test_database.sh` first, and back up before applying to the live project (Database → Backups).

### Email: set up SMTP before real users sign up

There are no passwords: people sign in with their email and a 6-digit code they choose. Signing up, and choosing a new one ("Forgot code?"), use a 6-digit code sent by email. An account an admin or a gym owner makes for someone starts with the code `123456`; they must choose their own the first time they sign in. Accounts from before sign-in codes have no code: run `supabase/default_code_for_old_users.sql` once in the SQL Editor to start them on `123456` the same way. Supabase's built-in email sender is only for trying things out: it sends a few emails an hour, and only to your team's addresses. Before launch, add an email provider (Resend, Brevo, Amazon SES...) under Authentication → Emails → SMTP Settings, sending from your Health Pro domain.

### Make yourself an admin

Sign up in the app, then in Supabase → SQL Editor:

```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```

That makes you a **super admin**: you can do everything. You see Health Pro admin on the home page: **Users**, **Roles and permissions**, **Organisations**, **Master data**, **Venues to verify** and **Modules**. From there you make the rest of the team's accounts and give them roles, so the SQL editor is only needed for this first one. Users can't change their own role.

### Test accounts

To try Health Pro as each role: Supabase → SQL Editor → New query, paste `supabase/test_users.sql`, and Run. It makes **Health Pro Test Gym** (verified, with two packages) and one account per role, all with the code `123456` (change its `CODE` line for another). They sign in with email and the 6-digit code, so no email has to arrive.

| Account | Role |
|---|---|
| `test.superadmin@example.com` | Super admin |
| `test.admin@example.com` | Administrator |
| `test.owner@example.com` | Owner of the test gym |
| `test.manager@example.com` | Manager |
| `test.frontdesk@example.com` | Front desk |
| `test.trainer@example.com` | Trainer |
| `test.member@example.com` | Member with an account: 3 months of Monthly at the test gym |

Each role made under Roles and permissions gets `test.<role key>@example.com` too. Run it again after adding a role, or to put the codes and roles back. While gym membership is off, only the super admin and the administrator see the gym's pages. They're real accounts, a super admin among them: remove them before launch with `supabase/test_users_remove.sql`.

### Turning gym membership on

It starts off (`app_modules.is_enabled = false`). While it's off, everyone except super admins and people with `modules.manage` sees nothing of it, and its pages send people home. They see and use everything, so they can test it in production. Then:

1. As an admin, register a gym (Register your venue → Gym), add plans, and verify it under Admin → Venues to verify.
2. Pilot it with a few members.
3. Admin → Modules → turn Gym membership on.

### Daily job

`gym_daily_maintenance()` runs every day at 00:05 Bhutan time with pg_cron. It expires memberships past their end, reminds members on each gym's reminder days (3 days before the end unless the gym chose others) and on the package's last day (with how to renew), and closes requests (old account requests, and requests to join) left for 30 days. Members are told only if they have an account (theirs, or linked to the person the desk registered). Check it's scheduled with `select * from cron.job;`. If the migration couldn't schedule it, turn on pg_cron under Database → Extensions and run in the SQL editor:

```sql
select cron.schedule('gym-daily-maintenance', '5 18 * * *', 'select public.gym_daily_maintenance()');
```

## How it fits together

### A platform of services

Health Pro is a multi-service platform: gym management is the first service, and others (ground booking, coaching...) plug in the same way. Each service is a module. The platform owns the frame; a service only describes itself.

**The side menu is service-driven, not feature-driven** (`PlatformShell`, in health_pro_core):

1. The platform's own pages: **Overview** (`/home`: a welcome, every service's shortcuts and card, what needs attention), **My services** (`/services`: every service, in use or not yet set up) and **Notifications**.
2. **Services**: one collapsible section per service: its icon and colour, the person's role in it, what it's working on (a gym, with a switcher for someone at several) and its pages under small headings, as their roles allow. The section of the page in use opens; the others fold to one line, so 20 services stay a short list (from 7, a box to find one).
3. **Administration** for the Health Pro team, as a section like a service's.
4. Who is signed in: account, light/dark, sign out.

Folded (a computer), the menu is icons and a service's icon opens its pages beside it; on a phone it's a drawer. Every page in a service shows the service and its gym over its title, and a **New** menu of the service's shortcuts.

### Module contract (`HealthProModule`, in health_pro_core)

| Member | Purpose |
|---|---|
| `key` | matches `app_modules.key` |
| `name`, `description`, `icon`, `color` | how the service appears: its menu section, cards and accents |
| `basePaths` | its pages, e.g. `['/gyms']`; closed while it's off |
| `routes` | its GoRoutes, in the platform's frame |
| `publicPaths` | pages visitors can open without an account |
| `venueKinds` | the venue types it serves, offered on Register your venue |
| `navigation(ref, location)` | its section of the side menu (`ServiceNav`): its scope (the gym), its pages in `NavSection`s (each `NavDestination` only if `access.can(...)`), its shortcuts (`ServiceAction`); a way to set it up when there's nothing yet |
| `buildOverviewCard()` | its card on Overview and My services (`ServiceCard`, `ServiceStats`); a plain one if null |
| `playerMenuItems()` | for players and members (pages or external links) |
| `managerMenuItems(venue, access)` | on a venue's Manage page: what `access.can(...)` allows |
| `buildManagerSection()`, `buildWelcome()` | optional manage widget, and the visitors' Welcome page |

### Design system (health_pro_core)

- **Type and colour**: Plus Jakarta Sans everywhere (`brandFont`, through the theme); navy, orange and blue from the logo (`BrandColors`, `context.brand`), light and dark.
- **Dashboard kit** (`dashboard_kit.dart`): `ConsoleCard`, `ConsoleKpi` (numbers count up), `ConsoleLineChart` (draws itself in), `ConsoleBarChart` (bars grow in; tap and tooltips), `ConsoleRing` (sweeps round), `ConsoleShareRow`, `ConsoleRangePicker`.
- **Motion** (`motion.dart`): `AnimatedCount`, `HoverLift` (cards rise under the mouse), `FadeSlideIn` / `staggered` (cards arrive one after another), `LoadingSkeleton` (the shape of the page, shimmering, instead of a spinner; `AsyncValueView` uses it). Pages fade and rise in (`SoftRiseTransitionsBuilder`). It all stands still when the device asks for less motion.
- **Feedback**: `runAction` / `showFeedback` show a tick or a warning in a floating bar; `EmptyState` says what to do next.
- **Service cards** (`service_cards.dart`): `ServiceCard`, `ServiceStat(s)`, `QuickActionTile`.

### Organisations

An **organisation** is the business that runs one or more venues (its branches): `organisations`, and `venues.organisation_id`. Every venue belongs to one. A new venue gets one of its own, named after it, so nothing changes for a single gym. The Health Pro team (`organisations.manage`, Admin → Organisations) renames them, makes new ones, and moves venues between them, so a business with several gyms is one organisation and its roles are the same at all of them.

### Roles and permissions

A **permission** is something the database checks (`permissions`; the keys are fixed in the migrations). A **role** is a named set of permissions (`roles`, `role_permissions`), made and changed under Admin → Roles and permissions.

| Scope | Permissions | Roles that come with Health Pro |
|---|---|---|
| Health Pro team (`user_roles`) | `users.manage`, `roles.manage`, `masters.manage`, `venues.verify`, `modules.manage`, `organisations.manage` | Administrator (all six) |
| A venue (`venue_staff.role`) | `venue.edit`, `venue.staff`, `venue.roles`, `venue.income`, and the gym's `gym.members`, `gym.payments`, `gym.check_in`, `gym.plans`, `gym.register` | Owner (always everything), Manager, Front desk (`staff`), Trainer |

**Venue roles are Health Pro-wide or one organisation's own** (`roles.organisation_id`):

- **Health Pro-wide** (`organisation_id` null): every organisation has them, with the same permissions: the generic setup that applies the same everywhere.
- **Changed for one organisation**: an organisation can change what a Health Pro-wide role allows at its venues, or turn it off there (`organisation_role_settings`, `organisation_role_permissions`). Other organisations keep it as it is. Without a change, the organisation follows Health Pro's role, including the team's later changes to it; "Use Health Pro's" goes back to that.
- **An organisation's own** (`organisation_id` set): made by or for the organisation, given only at its venues, and seen only by its people and the team.
- Owner always has everything, everywhere. The team's own roles are always Health Pro-wide.

**Who configures them.** The team (`roles.manage`) manages Health Pro-wide roles and any organisation's: Admin → Roles and permissions, then "Whose roles". An organisation's own people manage its roles from a venue's **Roles & permissions** page (the gym's menu → Manage), if they have `venue.roles` at **every** one of its venues (an Owner of all of them does). They add or take away only permissions they have at all of its venues themselves.

The database works out what a role allows at a venue (`has_venue_permission`, `role_permission_keys`); the app reads it through `my_venues()` and `organisation_roles()`.

- **Super admins** (`profiles.role = 'admin'`) can do everything. Only another super admin makes or unmakes one, and nobody can unmake themselves.
- **Nobody can give a permission they don't have.** Team roles and venue roles can only be given, changed or taken away by someone holding every permission in them. Only super admins and user managers make someone a venue's Owner, and a venue always keeps one.
- **Turning things off.** A role that is turned off gives nobody anything. An account that is turned off (Admin → Users) loses every role, and the `admin-users` Edge Function blocks its sign-in until it's turned on again. Memberships and history stay.
- **Making accounts.** Admin → Users → New user, or a venue's Staff → Add staff → Make their account. They sign in with their email and the emailed code. The `admin-users` Edge Function makes the account; the role changes run as the person asking, so the database rules above still decide.
- One person can own a gym and be a member at another.

### Master data

`dzongkhags` → `gewogs` (and thromdes) → `villages`: 20, 216 and 4,499 rows, from the BRECSA service's `tbl_dzongkhag`, `tbl_gewog` and `tbl_chiwog` (`20261108000002_master_locations_data.sql` says what was cleaned). Everyone reads the rows that are on. People with `masters.manage` add, rename and turn rows off under Admin → Master data. Rows are never deleted, so addresses keep pointing at them. Forms use `LocationFields` (dzongkhag, then gewog, then village).

### Security

Row Level Security is on for every table. Members see only their own memberships, check-ins and payments; a gym's staff see only what their role's permissions allow at that gym. Money, membership status, roles and master data change only through `security definer` functions that check the caller's permissions (`has_permission`, `has_venue_permission`). Unverified venues are hidden from everyone but their staff, admins and venue verifiers. The service-role key lives only in Edge Functions.

### Gym membership

Members walk in (they need no account), or ask to join in the app. Either way each person has **one Health Pro QR code that works at every gym** (see [One QR code, every gym](#one-qr-code-every-gym)).

1. **Register** (Register member, `gym.register`): the front desk fills in the client's form (name, phone, email, dzongkhag, gewog and village, occupation, emergency contact, blood group, date of birth, date of joining, medical issues), snaps their photo with the webcam (the camera on a phone; Retake before saving, or Upload), and sells a package (`gym.payments`): the package, how many months (1 to 24), and what they paid. The **expiry date** is worked out, not typed: the same date, months later (joining 8 Nov 2026 for 3 months expires on 8 Feb 2027, and they can still come in that day). `gym_register_member` saves it all in `gym_members`, `gym_subscriptions` and `payments`.
2. **Card**: the page after registering shows the package, its expiry date, their details and their **QR card**: Download card (in a browser) or Share card (on a phone, WhatsApp is in the share sheet), and WhatsApp, which opens their chat with a message ready. The card holds only `sportshub:gym-member:<random token>`: no phone, birthday or medical notes. New card (on their page) makes the old one stop working.
3. **Check in** (`gym.check_in`): scan the card with the camera, a USB QR scanner (it types into the member code box, which keeps the cursor on a computer), or type the 6-character member code (`gym_check_in_member`, `gym_check_in_by_code`). It's recorded only if a package at that gym covers today. The desk sees **Checked in** with their photo, days left and medical notes, or **Not checked in** with why ("…'s package ended on …") and a button to renew.
4. **Renew**: on their page. A renewal starts on the day the current package expires, so the dates don't drift (8 Feb, 8 May, 8 Aug), or today once it has ended (`gym_renew_member`).
5. **Owner**: a dashboard (today's numbers, shortcuts, what needs attention, a getting-started checklist for a new gym), packages and prices (members on each, times sold), the members register (search, status filters with counts, sort, table or cards), income (12 months, by method, every payment), **reports & analytics** (new members, visits by day and hour, renewal rate, package mix, most regular members, and what it all says) and staff with their roles.

6. **Ask AI** (every staff member; the floating Ask AI button on the gym's pages): questions in their own words, in English or Dzongkha. Questions about the gym ("busiest hours this month?", "who hasn't come in two weeks?", "when did Pema last come?", "revenue by payment method this year?") are answered with a chart or a list of members. How-to questions ("how do I renew a member?") get a short answer and a button to the page that does it. See [Ask AI](#ask-ai-cloudflare-workers-ai).

Members with an account membership from before (`gym_subscriptions.member_id`) still work underneath: `gym_activate_subscription` runs their memberships by the plan's days, and their old account QR code (`sportshub:member:<account id>`) still checks them in.

Dates are Bhutan dates (Asia/Thimphu), both ends included.

### One QR code, every gym

The client's "Health Pro – QR Code Flow" (migration `20261115000001_people_and_join_requests.sql`, checks in `tests/database/people_test.sql`).

- **People** (`people`): everyone Health Pro knows, with an account or not. Each has one personal QR code, `healthpro:member:<random token>`, nothing else in it. A gym's registered member (`gym_members`) is a person at that gym (`person_id`); a person can be at several gyms, each package running to its own end. Members registered before this got a person each whose QR code is their card's, so printed cards keep working.
- **My QR code** (`/my-qr`, under Me in the menu, where members start): the person's code, big, on white. "Get a new QR code" makes the old one stop working at every gym, as "New card" on a member's page does.
- **Accounts join their person by email.** The first time an account needs its QR code (`my_person`), it takes in the people the desk registered with the same email, once the account has **confirmed** that email. Never by phone: nobody has proved a phone number is theirs, so matching on it would let anyone claim someone's card, details and medical notes.
- **At the desk**, any QR code (the personal one, a gym's old card, an old account code) checks the person in where they're registered (`gym_check_in_member`, `gym_check_in_account`). At a gym where they aren't, Check-in says **Not a member here yet** with **Add to this gym**: Register member opens filled in with the details they gave their last gym, or their account (`gym_person_details`), and saving adds the same person, so the same QR code works here from then on. Their photo is taken again (each gym's photos are private to it).
- **Joining by the gym's QR code.** Gym QR code (Front desk, in the gym's menu) shows the gym's code to print: it opens the gym's public page with `?join=1`, where someone signed in taps **Ask to join**, with the package they'd like and a note (`gym_request_to_join`). The front desk, managers and owner are told; the request waits under **Join requests** (a count in the menu) until the desk **adds** them (the filled-in form; saving approves it) or **declines** with a note (`gym_decline_join_request`). The member is told either way, and the gym shows in **My gyms** (`/gyms/my`: their gyms and packages, requests, visits; `my_gyms`).
- **Notifications** are under Me for everyone now (members, trainers and staff get them), not only the super admin. Overview and My services are still the super admin's.

### Paying online, and a gym's membership settings

Migration `20261115000002_gym_payments_and_settings.sql`, checks in `tests/database/payments_test.sql`.

- **Membership settings** (Manage, for those who edit the gym; `gym_settings`, `gym_save_settings`): the bank's **payment QR code** (an image in the public `gym-payment-qr` bucket, shown with the gym's payment details from Gym settings), **reminders** (any of 1, 3, 7, 14 or 30 days before a package ends; 3 by default) and who answers **requests to join**: the front desk (whoever registers members) or **the owner and managers only**. With managers only, the desk isn't told of requests, doesn't see Join requests in its menu, and the database refuses its answers (a trigger on `gym_join_requests`).
- **Paying online** (`gym_payment_claims`): in My gyms a member taps **Pay online**, chooses the package and months, scans the gym's payment QR in their bank app, pays, and enters the **journal number (JRN)** (`gym_claim_payment`). One payment waits at a time, and a journal number pays once at a gym (nor one the desk already recorded). Those who take payments (`gym.payments`) are told, and find it under **Payments to confirm** (Front desk, with a count), on the member's page, and on Check-in when the member is refused. They check it with the bank, then **Confirm** (`gym_confirm_payment_claim`: the package starts as a desk renewal would, from the day the current one ends or today, recorded as a bank payment with the JRN) or **Not found** with a note (`gym_reject_payment_claim`). The member is told either way. Cash is still sold at the desk as before. A package that has ended can't check in until a payment is confirmed.

### A gym's profile, and finding a gym

Migration `20261115000003_venue_profile.sql`, checks in `tests/database/profile_test.sql`.

- **The profile** (Gym settings, the venue form; `register_venue`, `update_venue`): besides name, place, phone and WhatsApp, an **email**, a **contact person**, **its place on the map** (tap the map at the entrance, or "Use where I'm standing"; it must be in Bhutan), **opening hours** day by day (closed, or one or two opening times, e.g. 6–10 am and 4–9 pm), **facilities** (the kind's usual ones as ticks, `VenueKind.facilities`, a gym's in `gymFacilities`, plus any of its own), **video links** (YouTube or Facebook, up to 10: posted there, shown as pictures that open the video) and up to **30 photos**. Changing photos, videos, facilities or hours doesn't send a venue that was sent back for checking again.
- **Price range**: worked out from the packages on sale (lowest and highest price), never typed, so it can't go stale: `gym_price_ranges()` for the list (visitors too), the packages on the gym's page.
- **The list of gyms** (`/gyms`; Gyms near me on the Welcome page is `/gyms?near=1`): each gym with its cover photo, price range, whether it's open now (Bhutan time) and, with Near me, how far. **Near me** asks for the location (browser or phone) and puts the nearest first; without it, the list stays as it comes. Anyone can sort by price and keep to a **budget** (gyms with a package at or under it), or a dzongkhag.
- **A gym's page**: prices, open now, contact person and email, facilities, videos, the week's hours, and a small **OpenStreetMap** map with **Directions** (Google Maps) and Bigger map. The map uses OpenStreetMap's free tiles (no key); they ask apps not to send heavy traffic, so for many daily visitors move to a tile service (e.g. MapTiler or Stadia, free tiers) by changing `MapTiles` in `venue_map.dart`.
- **Reviews**: a gym's members can review it (`has_used_venue` now counts anyone the gym registered, with their account), not only those who paid with their account.
- **Location permission**: the phone apps ask for it (`AndroidManifest.xml`, `Info.plist`); the website asks in the browser.

### Trainers

Migration `20261115000004_trainers.sql`, checks in `tests/database/trainers_test.sql`.

- **Their profile** (Trainer profile, under Me; `/gyms/trainer`): anyone with an account makes one (name as members see it, what they do, about them, specialties, years of experience, photo) and adds **certificates** (a photo of each, in the public `trainer-media` bucket). It's public (`/trainers/<id>`) once a gym has verified them.
- **Each gym verifies them** (`gym_trainers`): the trainer asks a gym (Train at a gym); its staff who check trainers (`gym.trainers`, new; the Owner, Manager and Front desk roles have it) are told, check the certificates under **Trainers** (Front desk, with a count) and **Verify** or **Don't verify** with a note (`gym_decide_trainer`); the trainer is told. One gym saying no doesn't touch the others. A trainer can leave a gym (their times and members there go).
- **Their week** (`trainer_slots`): days and times at each gym, never overlapping across gyms. A gym (its page, its Trainers list) sees its own times and the trainer's others only as **Not available**, never the other gym's name (`trainer_timings`, `gym_trainers_overview`). On the trainer's own public profile, each verified gym's times are shown.
- **Attendance** (`trainer_check_ins`), as the client asked on 15 Nov (instead of working it out from members' check-ins): the front desk scans the trainer's Health Pro QR code at **Check-in** when they arrive, as for members. A trainer verified there is recorded as **Trainer arrived** (with their times there today), not checked in as a member; a trainer who is also a member there gets "check in as a member" instead. Each gym sees only its own record (Trainers: days here in the last 30, last arrivals); the trainer sees all of them, gym by gym, on their own page.
- **Members and trainers** (`trainer_links`, with history): a member chooses a trainer at each of their gyms (My gyms → Choose / Change), or the front desk assigns one (under a member's check-in, or on their page). The old and the new trainer are told (Trainer changed / New member), and the member when the desk chose.
- **Reviews** (`trainer_reviews`): only members who have had them as their trainer review a trainer (stars and a comment), on the trainer's profile; the trainer is told; no replies.

### Push notifications

Migration `20261115000005_push_notifications.sql`, the `send-push` Edge Function, checks in `tests/database/push_test.sql` and `tests/functions/web_push_test.ts`.

- **What goes out**: every notification Health Pro makes (new join request; join approved or declined; payment to confirm; payment confirmed; package ending on the gym's reminder days and on its last day; trainer request; trainer verified or not; new review; trainer changed) also arrives as a push on each phone or browser where the person turned them on. Tapping it opens the page it's about. Notifications are still kept in the app under **Notifications** (under Me), for anyone who said no.
- **Asking**: after signing in (not on first opening), once a session, Health Pro asks "Turn on notifications?"; "Not now" waits two weeks. The **Notifications** page shows push on this device and turns it on or off. Signing out turns it off on that device, so a shared phone doesn't get the last person's notifications.
- **iPhone and iPad**: web push works only in the installed app (Install app on the sign-in page; iOS 16.4 or later). In Safari, the Notifications page says to install it first.
- **How it's sent**: a trigger on `notifications` asks `send-push` (through pg_net, after the insert commits) to send the new one. The function sends each notification once, only one made in the last 15 minutes, only to its own person's devices (`push_claim_notification`), so anyone calling it can't send anything else. Devices whose push service says they're gone are forgotten. Web Push is done with WebCrypto alone (VAPID signing, aes128gcm encryption), checked against RFC 8291's own example. Push failing never stops a notification.
- **The website's service worker** is now Health Pro's own (`web/push_sw.js`; `web/flutter_bootstrap.js` loads the app without Flutter's). It shows notifications and has no offline cache, so every visit gets the newest app.

**Turn it on** (once):

1. Make the keys: `deno run scripts/make_push_keys.ts`. Keep both in a password manager, and never change them (every device would have to turn notifications on again).
2. Deploy with them; this stores them as `send-push`'s secrets, puts the public key in `env.json`, and tells the database where `send-push` is:

```sh
VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... \
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

3. Build the website with the public key: from `env.json` on your computer, or add `VAPID_PUBLIC_KEY` to the host's build variables (Cloudflare Pages).

Without the keys, nothing changes: notifications stay inside the app and nobody is asked.

### Install app (a web app on the home screen)

Health Pro ships as a web app people install, not a store app. The sign-in page has **Install app**: on Android, and Chrome or Edge on a computer, it opens the browser's own install window (`web/index.html` keeps the browser's `beforeinstallprompt` offer for it); on an iPhone or iPad it shows the steps (Share, Add to Home Screen, Add), since Safari can't be asked. Once installed (opened full screen), the button hides. On an iPhone, notifications from the web need it installed (iOS 16.4 or later).

### Ask AI (Cloudflare Workers AI)

A floating **Ask AI** button sits in the bottom-right corner of every page, for visitors too ("Ask AI" on a computer, its icon on a phone). It opens a chat beside the page (the whole screen on a phone), and the conversation is still there when it's opened again. It isn't in the menus. Which assistant it opens depends on the page:

| Where | Assistant | Who | Edge Function |
|---|---|---|---|
| A gym's staff pages | **Ask AI** for that gym: questions about its members, visits, packages and money, and how-tos. Its expand button opens it full size (`/gyms/<id>/manage/ask`). | That gym's staff | `ask-ai` |
| Everywhere else | **Health Pro assistant**: what Health Pro is, finding and joining a gym, checking in, putting a gym on Health Pro, accounts. "Gyms in Paro?" lists the verified gyms there. | Anyone, no account needed | `ask-sportshub` |

The button stays off pages it would get in the way of: the full Ask AI page, and pages with a Save bar along the bottom (the member form, the role editors). A module chooses this through `buildAssistant`, `hidesAssistantButton`, `assistantLinks` and `publicVenueRoute` on `HealthProModule`.

The AI never sees the gym's records. It only decides **which of the app's reports** answers a question (and for how long a period, or whose name to look for), or writes a short how-to from a guide written into the function (`supabase/functions/*/reply.ts`). The app then works the answer out itself, so the numbers are always Health Pro's own and follow the person's role (no money for the front desk). Gym lists come from Health Pro's public list of verified venues.

1. The app sends the question, with the conversation's last three questions, to the Edge Function.
2. The database counts it before the AI is asked:
   - `ai_take_question` (gym staff, as the person asking): they must work at that gym, 25 questions a person a Bhutan day. It keeps who asked, where and when (not what) for 90 days.
   - `ai_take_public_question` (anyone, called by `ask-sportshub` with the service role): 15 a day from one address and 150 a day from everyone (about half the free allowance), so visitors can't use up the gyms' share. Addresses are kept only as a hash keyed with a secret, for 30 days.
3. The function asks Cloudflare Workers AI (`@cf/meta/llama-3.3-70b-instruct-fp8-fast`, in JSON mode) and checks the reply against its lists of reports, pages and dzongkhags before passing it on.
4. The app draws the chart or list from Health Pro's data.

The suggestions in each chat have their answers written into the app: they skip the AI, don't count, and work even when Ask AI isn't set up.

**Cost: free, within limits.** Workers AI gives every Cloudflare account 10,000 "neurons" a day, shared by both assistants and every gym on Health Pro. It resets at 00:00 UTC (6 am in Bhutan). A question uses a few dozen neurons, so a few hundred questions a day fit. On the free plan, going over is never charged; questions fail with "Today's free AI questions are used up" until the reset. For many gyms, move to Workers Paid ($0.011 per 1,000 neurons above the free 10,000).

**Privacy.** Only the question text leaves Health Pro (to Cloudflare); members' details, medical notes and photos never do. Questions can contain a member's name when staff type one; the public chat asks people not to type personal details.

**Turn it on** (once):

1. Cloudflare dashboard → AI → Workers AI → Use REST API: **Create a Workers AI API Token**, and copy the **Account ID** from the same page.
2. Deploy with them. This applies the migrations, deploys both functions and stores both values as their secrets:

```sh
CLOUDFLARE_ACCOUNT_ID=... CLOUDFLARE_AI_TOKEN=... \
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

Without them, both chats still work: the suggestions answer, and typed questions say it isn't set up yet. To try another Workers AI model (it must support JSON mode), set `CLOUDFLARE_AI_MODEL` the same way with `supabase secrets set`. The functions log each question's token use (Supabase → Edge Functions → ask-ai or ask-sportshub → Logs).

### Logo, splash and loader

- **Logo** (`HealthProLogo`): the Health Pro logo, blue lettering for light backgrounds (`logo.png`), and white lettering for dark ones (`logo_on_dark.png`); `markOnly` is the cross with the runner (`mark.png`, `mark_on_dark.png`). It follows the theme. Places that are navy in both themes (the side menu, the welcome page's footer, the splash) pass `onDark: true`.
- **Splash** (`HealthProSplash`): the white logo in the middle of the navy, 240 wide on a phone and 320 on anything bigger, with a green bar (the logo's green) under it. It shows while the modules load at start (`SplashGate` fades it into the page). The launch screens draw the same logo at the same size and place, so the handover doesn't jump. If you change one, change them all: `web/index.html` and `web/splash/`, Android's `res/drawable*/launch_background.xml`, `splash_logo.png`, `splash_icon.png` and `values*-v31/styles.xml` (Android 12+ shows the mark in a circle), and iOS's `LaunchScreen.storyboard`, `LaunchImage` and `LaunchBackground`. iOS caches its launch screen, so delete the app and reinstall it to see a change.
- **Loader** (`HealthProLoader`): the orange-and-blue spinner, for the few places that wait without a shape to show. Pages and lists waiting on data show `LoadingSkeleton` (through `AsyncValueView`). Spinners inside buttons stay Flutter's plain one.

## Adding a module (e.g. coaching)

1. `packages/coaching`, depending on `health_pro_core`; add it to the root `pubspec.yaml` workspace list and to the app's `pubspec.yaml`.
2. `class CoachingModule extends HealthProModule`, with its `color`, `navigation` (its menu section) and, if it wants one, `buildOverviewCard`; and one line in `apps/health_pro_app/lib/main.dart`. The side menu, Overview and My services pick it up: nothing else in the app changes.
3. A migration: `coaching_*` tables (linked to `venues`), RLS, functions, and
   `insert into public.app_modules (key, name, is_enabled, sort_order) values ('coaching', 'Coaching', false, 30);`
4. Test it as an admin, then turn it on.

## Bringing ground booking in (one domain)

All modules are meant to run from one domain. Ground booking already owns its paths in Health Pro (`/grounds`, `/grounds/venue/:id`, `/tournaments`, `/tournaments/:id`, `/register-ground`, the same hash URLs the booking website uses). For now those paths hand over to the website. To bring it in:

1. Move its screens into `packages/ground_booking` behind those same routes, so shared links keep working.
2. Add a migration with its tables (`ground_*`, linked to `venues`), its venue types (futsal, football...), and its deposits written to `payments`.
3. Remove `externalUrl`/`externalRegisterUrl` from `GroundBookingModule`.
4. Point the old domain at the Health Pro website.

## Website on Cloudflare

The website is a Cloudflare Pages project named `sporthubs` that serves the Flutter web build as static files: https://sporthubs.pages.dev. Every push to `main` builds and publishes it; other branches get a preview address of their own.

It was set up once in Cloudflare: Workers & Pages → Create application → "Continue to Pages" (the link at the bottom) → Import an existing Git repository → `sporthubs`, with:

- Production branch: `main`
- Framework preset: None
- Build command: `bash scripts/build_web.sh`
- Build output directory: `apps/health_pro_app/build/web`
- Environment variables: `SUPABASE_URL` = `https://iagqntjaywpdxvoxgfhl.supabase.co`, `SUPABASE_ANON_KEY` = the anon (publishable) key. It's public: it ships inside the website anyway, and the database rules protect the data.

To publish from your computer instead (after `scripts/deploy_supabase.sh` has written `env.json`):

```sh
CLOUDFLARE_API_TOKEN=... scripts/deploy_web.sh
```

Make the token at dash.cloudflare.com/profile/api-tokens → Create Token → Custom token, permission Account → Cloudflare Pages → Edit. Alternatively, run `npx wrangler login` once and leave the token out.

When it moves to its own domain, add the domain to the Pages project (Custom domains) and to `site_url` and `additional_redirect_urls` in `supabase/config.toml`, then run the Supabase deploy again.

## Releasing

- **Website**: see [Website on Cloudflare](#website-on-cloudflare). `scripts/build_web.sh` builds `apps/health_pro_app/build/web`, which any static host can serve; URLs use `/#/`, so no rewrites are needed.
- **Android**: application id `bt.sportshub.app`. Add a release signing key before uploading to Google Play.
- **iOS**: bundle id `bt.sportshub.app`. Set your team in Xcode (`ios/Runner.xcworkspace`).
- App icons, launch screens and in-app logos are all made from the brand files in `packages/health_pro_core/tool/brand/` (kept out of `assets/` so they don't ship in the app): `logo-dark-new.png`, the transparent logo, and `logo-white-small.png`, the app icon (the mark on a white tile); `logo-white-new.png`, the logo on white, is for reference. To change the logo, replace those files and run `cd packages/health_pro_core && flutter test tool/brand_images.dart`; it makes the white-lettered version, lifts the mark off the icon's tile, and writes every image. If the logo's shape changes, update `HealthProLogo.aspectRatio`, `web/index.html` and `LaunchScreen.storyboard` to the size it prints.

## Tests

```sh
(cd packages/health_pro_core && flutter test)
(cd packages/gym_membership && flutter test)
(cd packages/ground_booking && flutter test)
(cd apps/health_pro_app && flutter test)
scripts/test_database.sh      # needs a local PostgreSQL (brew install postgresql)
deno test tests/functions/    # the Edge Functions' own logic (brew install deno)
```

`scripts/test_database.sh` runs `tests/database/scenario_test.sql` (memberships end to end), `access_test.sql` (master data, roles and permissions), and the organisations, registration and Ask AI (`ai_test.sql`: the daily question allowance) checks.
