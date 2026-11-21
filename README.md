# Health Pro

Your Health. Our Priority. One app for sport in Bhutan, on the web, Android and iOS, built from a shared **core** and one package per **module**:

| Module | Status | What it does |
|---|---|---|
| Gym membership (`gym_membership`) | Built, off until you turn it on | The front desk registers members (details, webcam photo, package and its expiry date), sends them a QR card on WhatsApp, and checks them in with it. Owners set packages and prices, see income and choose their staff's roles. |

The backend is Supabase: database, security rules, server functions, the daily job and the account-deletion Edge Function. There is no other server.

## Layout

```
pubspec.yaml                  Dart pub workspace: run `flutter pub get` here
apps/health_pro_app/           the one Flutter app (web, Android, iOS); lib/main.dart lists the modules
packages/health_pro_core/      accounts, profiles, venues and staff, payments, notifications,
                              the module contract, router, home page, admin, theme
packages/gym_membership/      the gym module: gym plans, memberships, check-in, staff and owner pages
supabase/migrations/          core, then one migration per module
supabase/functions/           Edge Functions (delete-account, admin-users, ask-ai, ask-health-pro; _shared)
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

Rules for database changes: every change is a new file in `supabase/migrations/` (never edit one that's applied). Try it on a development project or with `scripts/test_database.sh` first, and back up before applying to the live project ([Backups](#backups)).

### Email: set up SMTP before real users sign up

There are no passwords: people sign in with their email and a 6-digit code they choose. Signing up, and choosing a new one ("Forgot code?"), use a 6-digit code sent by email. An account an admin or a gym owner makes for someone starts with the code `123456`; they must choose their own the first time they sign in. Accounts from before sign-in codes have no code: run `supabase/default_code_for_old_users.sql` once in the SQL Editor to start them on `123456` the same way. Supabase's built-in email sender is only for trying things out: it sends a few emails an hour, and only to your team's addresses. Before launch, add an email provider (Resend, Brevo, Amazon SES...) under Authentication → Emails → SMTP Settings, sending from your Health Pro domain.

Check it on the live project (reads the settings, never prints the password):

```sh
SUPABASE_ACCESS_TOKEN=sbp_... scripts/check_email.sh                     # how it sends: test sender or your SMTP
SUPABASE_ACCESS_TOKEN=sbp_... scripts/check_email.sh someone@example.com # and sends that account a real code
```

The address needs an account already (nothing is made). Send it to an account outside the Supabase team, then look in that inbox and its spam folder: a code that arrives there is the real test.

### Sign in with Google

The website's sign-in and sign-up pages show **Continue with Google** once Google is on for the project (the button stays hidden until then; not in the apps yet). It's the same account as email + code: a Gmail that already has an account signs in to it, and a new one gets an account and profile with Google's name (no phone; they can add it). Google users have no 6-digit code until they choose one with "Forgot code?".

1. [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → **OAuth consent screen**: External, app name Health Pro, the logo, support email, and the privacy policy and terms pages of the website. Scopes: only `email`, `profile`, `openid`.
2. **Credentials** → Create credentials → OAuth client ID → **Web application**.
   - Authorized JavaScript origins: `https://sporthubs.pages.dev` (and `http://localhost:3000` to try it locally).
   - Authorized redirect URIs: `https://iagqntjaywpdxvoxgfhl.supabase.co/auth/v1/callback`
3. Deploy with the client ID and secret (every deploy needs them, or the auth settings step is skipped):

```sh
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... \
GOOGLE_CLIENT_ID=....apps.googleusercontent.com GOOGLE_CLIENT_SECRET=GOCSPX-... scripts/deploy_supabase.sh
```

Coming back from Google lands on `/#/sign-in?next=...`, which sends them on; `additional_redirect_urls` in `supabase/config.toml` allows that address (the `/**` entries).

### Backups

On Supabase's free plan you can't download or restore a backup yourself; Pro keeps 7 days of daily ones (Database → Backups). Either way, keep a copy of your own somewhere else, at least weekly and before every migration:

```sh
SUPABASE_DB_PASSWORD=... SUPABASE_ACCESS_TOKEN=sbp_... scripts/backup_supabase.sh [folder]
```

It reads only, and writes `<folder>/<date-time>/` (`backups/` by default, which git ignores; a synced Google Drive folder is a good place): `database.dump` (the `public` and `private` schemas: tables, data, functions and rules), `accounts.sql` (sign-in accounts) and `files/` (every photo, certificate and payment QR code; skipped without `SUPABASE_ACCESS_TOKEN`). It needs `pg_dump` as new as the database: `brew install postgresql@17`. These are real people's details: keep them private.

To restore into a new, empty Supabase project (with its Session pooler string as `$DB`; `pg_restore` and `psql` from `postgresql@17`):

1. `psql "$DB" -f accounts.sql`: the accounts first.
2. `pg_restore --no-owner --no-privileges -d "$DB" database.dump`: the app's tables and data. "schema public already exists" is expected.
3. `SUPABASE_PROJECT_REF=<new ref> SUPABASE_DB_URL=... scripts/deploy_supabase.sh`: the migrations again (safe to re-run; they put back the triggers, storage rules, buckets and the daily job), the Edge Functions and the auth settings.
4. Upload each `files/<bucket>/` folder's contents to the bucket of that name, keeping the folders inside (Storage in the dashboard takes folders, or the CLI's `storage cp -r`).
5. Point the app at the new project (`env.json`) and rebuild the website.

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

`gym_birthday_wishes()` runs every day at 08:05 Bhutan time: members with the app and a package running get a birthday wish from their gym (born on 29 February: the 28th in other years), once a year. If it isn't scheduled:

```sql
select cron.schedule('gym-birthday-wishes', '5 2 * * *', 'select public.gym_birthday_wishes()');
```

## How it fits together

### A platform of services

Health Pro is a multi-service platform: gym management is the first service, and others (coaching...) plug in the same way. Each service is a module. The platform owns the frame; a service only describes itself.

**The side menu is service-driven, not feature-driven** (`PlatformShell`, in health_pro_core):

1. The platform's own pages: **Overview** (`/home`: a welcome, every service's shortcuts and card, what needs attention), **My services** (`/services`: every service, in use or not yet set up). Notifications are the bell at the top of every page, not a menu entry.
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
4. **Renew**: on their page. A renewal starts on the day the current package expires, so the dates don't drift (8 Feb, 8 May, 8 Aug), or today once it has ended (`gym_renew_member`). Its receipt opens straight after.
   - **Pause** (`gym.payments`, on their page): travel, illness or an injury, from today or a later day, 1 to 180 days, with a reason. The running package ends that many days later and any renewal after it moves too, so nothing paid for is lost (`gym_pause_member`, `gym_membership_pauses`). While paused, check-in refuses them ("…'s membership is paused until …"). Back early, **Resume** gives the unused days back off the dates; before it begins, **Take back** undoes it (`gym_resume_member`). One pause at a time; a member with an account is told both times, and sees it on My dashboard and My gym ("Paused until …", when they can check in again, until when their package runs).
   - **Receipts**: every payment gets the gym's next receipt number (1, 2, 3… per gym, `payments.receipt_no`; older payments were numbered oldest first). Open one from the payment's package on the member's page, any row of Payments & income, or the page after registering: **Print** (website), **Save picture** / **Share** (phone), and **WhatsApp** with the receipt as a message (`gym_payment_receipt`, for staff who see members, payments or income, and the member who paid). Members find their last 10 under Receipts on My gym, to print or keep (`my_gyms()` lists them).
   - **Export to Excel** (.xlsx): Members (everyone: details, package, until when, standing), Payments & income (the month, day or dates on screen, with receipt numbers and packages) and Reports (every visit in the range). A download in a browser, the share sheet on a phone.
   - **Reminders on WhatsApp** (`gym.members`): a chat button on the dashboard's Ending soon list, on Members under "Ending in 7 days" and "Ended", and on the member's page opens WhatsApp on the desk's phone with a renewal reminder ready to send. It's free and reaches members without the app. The app notes each one (`gym_note_message`, `gym_member_messages`), so the button shows "Reminded yesterday" for a week.
   - **Birthdays**: the dashboard lists birthdays in the next 7 days (members with a package now or in the last 90 days); today's have a wish on WhatsApp, as does the member's page on the day. Members with the app also get a wish by notification (see [Daily job](#daily-job)).
   - **Enquiries & trials** (`gym.register`, Front desk menu): walk-ins, calls and messages from people who haven't joined: how they heard of the gym, what they're after, a free trial (first day, 1 to 30 days), the day to follow up, and notes (`gym_enquiries`, `gym_save_enquiry`). The menu counts those due today (a follow-up today or missed, or a trial that has ended). **Register** opens Register member with their name and phone filled in. Registering anyone with the same phone number marks the enquiry joined.
   - **Activity log** (`gym.activity`: owners, and managers by default; Manage menu): who registered, edited or gave a new card to whom, sold or renewed what, took which payment (with its journal number and receipt), confirmed or turned down online payments, paused, resumed or cancelled, changed a package's price, or added staff. Triggers write it (`gym_audit_log`, 20261118000006), so every function's changes are in. One action is one line (registering with a package and cash is one entry). Nobody can change or delete it, the owner included. The daily job's changes aren't in it. Filter by kind, by who, or by a name. A member's page shows their own history.
   - **Offers & discounts** (`gym.plans`, Business menu): the gym's offers, a percentage or an amount off ('Student', 10%; 'Couple', Nu. 500), kept with `gym_save_offer` (`gym_offers`). Selling a package, the desk picks one (the amount follows), or takes less and must say why ('Referred by Sonam'). Every package sold at the desk now keeps its full price (`gym_subscriptions.list_price`, the plan's price for those months as `gym_package_price` works it out, the same as the form), with the offer and reason (`gym_add_membership`'s `discount`: `gym_register_member` takes it in its details, `gym_renew_member` as a last argument). The receipt shows the full price and the discount; the activity log says what was taken off and why, or "no reason given". The page lists the month's discounts with totals, and flags any without a reason. Online payments aren't offered discounts.
   - **Expenses & profit** (`venue.income`, Business menu): the gym's expenses (rent, salaries, equipment, repairs, utilities, supplies, marketing, other), each with its day, amount, how it was paid, to whom and a note (`gym_expenses`, `gym_save_expense`). The page shows the month's payments in, expenses out and profit (or loss), the last 12 months side by side, and what the money went on. Every change is in the activity log. Export to Excel.
   - **Body progress** (`gym_body_measurements`, `gym_save_measurement`): weight, height, body fat and tape measurements (chest, waist, hips, arm, thigh) on a day. Recorded by the gym's staff who see members, the member's trainer (`trainer_links`), or the member on My gym ("Log my weight"; they change only their own). Shown on the member's page, My gym and the trainer's page: weight now, the change since the first, BMI from the latest height (WHO bands), a line of their weight and the latest entries.
   - **Workout & diet plans** (`gym_member_plans`, `gym_save_member_plan`): a title and the plan in words, written for one member by their trainer or the gym's staff. The member reads them on My gym ("My plans") and is told when one is given or its words change. Old ones are put away, not lost.
   - **Trainers' members**: a trainer verified at a gym gets **My members** in their menu (`trainer_my_members()`): each member's package, latest weight and plans, and each one's page to record progress and write plans.
   - **Group classes** (Classes on the Front desk menu; `gym_classes`, `gym_class_bookings`): a weekly timetable (day, time, length, trainer, places) kept by who sets packages (`gym.plans`; `gym_save_class`), public to read. Members book on My gym up to two weeks ahead, before the class starts, when a package covers that day and they're not paused (`gym_book_class`); never more than the places (counted under a lock). The desk sees who's booked each day, books anyone in and takes them out (`gym_cancel_class_booking`); members cancel their own before it starts. Taking a class off the timetable, or moving its day, cancels its bookings to come and tells members with the app.
5. **Owner**: a dashboard (today's numbers, shortcuts, what needs attention, a getting-started checklist for a new gym), packages and prices (members on each, times sold), the members register (search, status filters with counts, sort, table or cards), income (12 months, by method, every payment), **reports & analytics** (new members, visits by day and hour, renewal rate, package mix, most regular members, and what it all says) and staff with their roles.

6. **Ask AI** (every staff member; the floating Ask AI button on the gym's pages): questions in their own words (English works best; the model has little Dzongkha). Questions about the gym ("busiest hours this month?", "who hasn't come in two weeks?", "when did Pema last come?", "revenue by payment method this year?") are answered with a chart or a list of members. How-to questions ("how do I renew a member?") get a short answer and a button to the page that does it. See [Ask AI](#ask-ai-cloudflare-workers-ai).

Members with an account membership from before (`gym_subscriptions.member_id`) still work underneath: `gym_activate_subscription` runs their memberships by the plan's days, and their old account QR code (`sportshub:member:<account id>`) still checks them in. Migration 20261118000015 moved them into the desk's register (`gym_register_account_members()`): a registration per account and gym, as their Health Pro person, with a new member code, their packages, visits and class bookings moved onto it. Accounts with no phone number were left as they were (the register needs one); run `select public.gym_register_account_members();` again once they've added one.

Dates are Bhutan dates (Asia/Thimphu), both ends included.

### One QR code, every gym

The client's "Health Pro – QR Code Flow" (migration `20261115000001_people_and_join_requests.sql`, checks in `tests/database/people_test.sql`).

- **People** (`people`): everyone Health Pro knows, with an account or not. Each has one personal QR code, `healthpro:member:<random token>`, nothing else in it. A gym's registered member (`gym_members`) is a person at that gym (`person_id`); a person can be at several gyms, each package running to its own end. Members registered before this got a person each whose QR code is their card's, so printed cards keep working.
- **My dashboard** (`/my-qr`, the one entry under My Health Pro in the menu, where members start): the person's QR code as a small white pass (Enlarge for the scanner, Copy, Share and Save its picture), their details (My details, with Edit), their latest notifications (Latest updates), and what each service keeps for them (`HealthProModule.buildMemberDashboard`; the gym module gives their gyms, packages, days left, what needs their attention (a package ended or ending within a week, a payment waiting or not found), their visits over the last 7 days, requests and recent visits, and each gym card opens My gym).
- **My gym** (`/gyms/my`, in the menu under My dashboard): the gym the member belongs to, in full: photos, contact, about, facilities, trainers, videos, opening hours and a map, beside their membership there (package, days left, member code, trainer, paying). With several gyms, chips at the top choose one (`/gyms/my?gym=<id>` opens on it). "Get a new QR code" makes the old one stop working at every gym, as "New card" on a member's page does.
- **Accounts join their person by email.** The first time an account needs its QR code (`my_person`), it takes in the people the desk registered with the same email, once the account has **confirmed** that email. Never by phone: nobody has proved a phone number is theirs, so matching on it would let anyone claim someone's card, details and medical notes.
- **At the desk**, any QR code (the personal one, a gym's old card, an old account code) checks the person in where they're registered (`gym_check_in_member`, `gym_check_in_account`). At a gym where they aren't, Check-in says **Not a member here yet** with **Add to this gym**: Register member opens filled in with the details they gave their last gym, or their account (`gym_person_details`), and saving adds the same person, so the same QR code works here from then on. Their photo is taken again (each gym's photos are private to it).
- **Joining by the gym's QR code.** Gym QR code (Front desk, in the gym's menu) shows the gym's code to print: it opens the gym's public page with `?join=1`, where someone signed in taps **Ask to join**, with the package they'd like and a note (`gym_request_to_join`). The front desk, managers and owner are told; the request waits under **Join requests** (a count in the menu) until the desk **adds** them (the filled-in form; saving approves it) or **declines** with a note (`gym_decline_join_request`). The member is told either way, and the gym shows in **My gyms** (`/gyms/my`: their gyms and packages, requests, visits; `my_gyms`).
- **Notifications** are for everyone (members, trainers and staff get them), from the bell at the top of every page; there is no menu entry. Overview and My services are still the super admin's.

### Paying online, and a gym's membership settings

Migration `20261115000002_gym_payments_and_settings.sql`, checks in `tests/database/payments_test.sql`.

- **Membership settings** (Manage, for those who edit the gym; `gym_settings`, `gym_save_settings`): the bank's **payment QR code** (an image in the public `gym-payment-qr` bucket, shown with the gym's payment details from Gym settings), **reminders** (any of 1, 3, 7, 14 or 30 days before a package ends; 3 by default) and who answers **requests to join**: the front desk (whoever registers members) or **the owner and managers only**. With managers only, the desk isn't told of requests, doesn't see Join requests in its menu, and the database refuses its answers (a trigger on `gym_join_requests`).
- **Paying online** (`gym_payment_claims`): on their dashboard, under My gyms, a member taps **Pay online**, chooses the package and months, scans the gym's payment QR in their bank app, pays, and enters the **journal number (JRN)** (`gym_claim_payment`). One payment waits at a time, and a journal number pays once at a gym (nor one the desk already recorded). Those who take payments (`gym.payments`) are told, and find it under **Payments to confirm** (Front desk, with a count), on the member's page, and on Check-in when the member is refused. They check it with the bank, then **Confirm** (`gym_confirm_payment_claim`: the package starts as a desk renewal would, from the day the current one ends or today, recorded as a bank payment with the JRN) or **Not found** with a note (`gym_reject_payment_claim`). The member is told either way. Cash is still sold at the desk as before. A package that has ended can't check in until a payment is confirmed.

### A gym's profile, and finding a gym

Migration `20261115000003_venue_profile.sql`, checks in `tests/database/profile_test.sql`.

- **The profile** (Gym settings, the venue form; `register_venue`, `update_venue`): besides name, place, phone and WhatsApp, an **email**, a **contact person**, **its place on the map** (tap the map at the entrance, or "Use where I'm standing"; it must be in Bhutan), **opening hours** day by day (closed, or one or two opening times, e.g. 6–10 am and 4–9 pm), **facilities** (the kind's usual ones as ticks, `VenueKind.facilities`, a gym's in `gymFacilities`, plus any of its own), **video links** (YouTube or Facebook, up to 10: posted there, shown as pictures that open the video), one optional **promotional video** (MP4, MOV or WebM, up to 20 MB; shown on the public venue page and My gym), and up to **30 photos**. Changing photos, videos, facilities or hours doesn't send a venue that was sent back for checking again.
- **Price range**: worked out from the packages on sale (lowest and highest price), never typed, so it can't go stale: `gym_price_ranges()` for the list (visitors too), the packages on the gym's page.
- **The list of gyms** (`/gyms`; Gyms near me on the Welcome page is `/gyms?near=1`): each gym with its cover photo, price range, whether it's open now (Bhutan time) and, with Near me, how far. **Near me** asks for the location (browser or phone) and puts the nearest first; without it, the list stays as it comes. Anyone can sort by price and keep to a **budget** (gyms with a package at or under it), or a dzongkhag.
- **A gym's page**: prices, open now, contact person and email, facilities, video links and the promotional video, the week's hours, and a small **OpenStreetMap** map with **Directions** (Google Maps) and Bigger map. The map uses OpenStreetMap's free tiles (no key); they ask apps not to send heavy traffic, so for many daily visitors move to a tile service (e.g. MapTiler or Stadia, free tiers) by changing `MapTiles` in `venue_map.dart`.
- **Reviews**: a gym's members can review it (`has_used_venue` now counts anyone the gym registered, with their account), not only those who paid with their account.
- **Location permission**: the phone apps ask for it (`AndroidManifest.xml`, `Info.plist`); the website asks in the browser.

### Trainers

Migration `20261115000004_trainers.sql`, checks in `tests/database/trainers_test.sql`.

- **Their profile** (Trainer profile, under Me; `/gyms/trainer`): anyone with an account makes one (name as members see it, what they do, about them, specialties, years of experience, photo) and adds **certificates** (a photo of each, in the public `trainer-media` bucket). It's public (`/trainers/<id>`) once a gym has verified them, whether the trainer applied or the gym added them.
- **Each gym verifies them** (`gym_trainers`): the trainer asks a gym (Train at a gym); its staff who check trainers (`gym.trainers`, new; the Owner, Manager and Front desk roles have it) are told, check the certificates under **Trainers** (Front desk, with a count) and **Verify** or **Don't verify** with a note (`gym_decide_trainer`); the trainer is told. One gym saying no doesn't touch the others. Either the gym or the trainer can make the trainer inactive at that gym: the public listing, schedule and active member assignments are removed, and the gym, trainer and affected members are notified. The gym may reactivate them later.
- **Their week** (`trainer_slots`): days and times at each gym, never overlapping across gyms. A gym (its page, its Trainers list) sees its own times and the trainer's others only as **Not available**, never the other gym's name (`trainer_timings`, `gym_trainers_overview`). On the trainer's own public profile, each verified gym's times are shown.
- **Attendance** (`trainer_check_ins`), as the client asked on 15 Nov (instead of working it out from members' check-ins): the front desk scans the trainer's Health Pro QR code at **Check-in** when they arrive, as for members, or uses **Mark arrived**. A trainer gets at most one attendance record per gym per Bhutan day; a repeat scan says **Already marked today**, and the staff button disables after the first record. A trainer verified there is recorded as **Trainer arrived** (with their times there today), not checked in as a member; a trainer who is also a member there gets "check in as a member" instead. Each gym sees only its own record (Trainers: days here in the last 30, recent arrivals); the trainer sees all of them, gym by gym, on their own page.
- **Members and trainers** (`trainer_links`, with history): a member chooses a trainer at each of their gyms (My dashboard → My gyms → Choose / Change), or the front desk assigns one (under a member's check-in, or on their page). The old and the new trainer are told (Trainer changed / New member), and the member when the desk chose.
- **Reviews** (`trainer_reviews`): only members who have had them as their trainer review a trainer (stars and a comment), on the trainer's profile; the trainer is told; no replies.

### Inventory and suppliers

Migration `20261118000009_gym_inventory.sql`, the `supplier-catalog` Edge Function, checks in `tests/database/inventory_test.sql` and `tests/functions/supplier_catalog_test.ts`.

- **Who**: staff with `gym.inventory` (new; the Owner and Manager roles have it). Both pages are under **Business** in the gym's menu; Inventory shows a count of items low or out.
- **Inventory** (`/gyms/<id>/manage/inventory`): what the gym keeps (equipment, supplements, towels...), how many, a low-stock level and an optional cost each (stock value). Counts change only through **Stock in**, **Take out** (used, sold, damaged) and **Recount** (`gym_move_stock`), each kept in the item's **History** with who and when (`gym_inventory_moves`).
- **Suppliers** (`/gyms/<id>/manage/inventory/suppliers`): items and live stock from systems connected to Health Pro (`inventory_suppliers`). Health Pro only shows them: **View in <supplier>** opens the item in the supplier's own system, where it's ordered and paid for. Nothing is bought or paid here.
- **For now** the one connected supplier is a test: the public DummyJSON API (its sports-accessories items, prices in USD).

**Connecting the real supplier** (when their API is ready):

1. Add an adapter for their API in `supabase/functions/supplier-catalog/catalog.ts` (`catalogUrl` and `read`, into the same item shape), with tests in `tests/functions/supplier_catalog_test.ts`, and allow its `api_kind` in a new migration.
2. In that migration, add their row to `inventory_suppliers` (name, website, API address, kind) and set the test one's `is_active` to false.
3. If their API needs a key, store it as the secret `SUPPLIER_<KEY>_TOKEN` (e.g. `supabase secrets set SUPPLIER_SPORTS_BT_TOKEN=...`); it is sent as a Bearer token and never reaches the app.
4. Deploy (`scripts/deploy_supabase.sh`). The app doesn't change.

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

### Class emails

Migrations `20261119000001_class_emails.sql` and `20261119000002_class_change_notices.sql`, the `send-email` Edge Function (`_shared/smtp.ts`, `send-email/class_emails.ts`), checks in `tests/database/class_emails_test.sql`, `tests/functions/smtp_test.ts` and `tests/functions/class_emails_test.ts`.

- **What goes out**: whoever has a place in a class is emailed when they book it (or the desk books it for them): the class, day, time and length, the trainer, the gym, where it is (with a map link) and its phone. Any change the gym makes to the class (name, time, length, trainer, description, places, open to everyone or members only) reaches everyone booked on a day still to come: one email with what changed, and a notification in the app (bell and push), which goes out even before email is set up. When the gym cancels their place (class taken off the timetable, moved to another day, or cancelled by the desk), they're told why, by email and in the app. Cancelling your own place sends nothing.
- **To whom**: the email of their Health Pro account, or else the one the desk keeps for the member. Members with neither get no email.
- **How it's sent**: triggers put each email in `private.email_outbox` (out of the app's reach) and ask `send-email` (pg_net, after the commit) to send what's waiting over one SMTP connection. It takes nothing from the caller, sends each email once, and tries a failed one again with the next ones (3 tries, 2 days). Emails over a month old are cleared away.
- **SMTP**: TLS on port 465 (Supabase's Edge Functions can't reach 587 or 25, so those become 465). Gmail works with an app password; for more than ~500 emails a day use a provider (Brevo, Resend, Amazon SES) and send from your own domain.

**Turn it on** (once; the same mail account as sign-in's SMTP is fine):

```sh
SMTP_HOST=smtp.gmail.com SMTP_USER=you@gmail.com SMTP_PASS=your-app-password \
SMTP_FROM='Health Pro <you@gmail.com>' SITE_URL=https://sporthubs.pages.dev \
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

This stores them as `send-email`'s secrets and tells the database where `send-email` is. Without SMTP, nothing is queued and the app works as before.

### Install app (a web app on the home screen)

Health Pro ships as a web app people install, not a store app. The sign-in page has **Install app**: on Android, and Chrome or Edge on a computer, it opens the browser's own install window (`web/index.html` keeps the browser's `beforeinstallprompt` offer for it); on an iPhone or iPad it shows the steps (Share, Add to Home Screen, Add), since Safari can't be asked. Once installed (opened full screen), the button hides. On an iPhone, notifications from the web need it installed (iOS 16.4 or later).

### Ask AI (Cloudflare Workers AI)

A floating **Ask AI** button sits in the bottom-right corner of every page, for visitors too ("Ask AI" on a computer, its icon on a phone). It opens a chat beside the page (the whole screen on a phone), and the conversation is still there when it's opened again. It isn't in the menus. Which assistant it opens depends on the page:

| Where | Assistant | Who | Edge Function |
|---|---|---|---|
| A gym's staff pages | **Ask AI** for that gym: questions about its members, visits, packages and money, and how-tos. Its expand button opens it full size (`/gyms/<id>/manage/ask`). | That gym's staff | `ask-ai` |
| Everywhere else | **Health Pro assistant**: what Health Pro is, finding and joining a gym, checking in, putting a gym on Health Pro, accounts. "Gyms in Paro?" lists the verified gyms there. | Anyone, no account needed | `ask-health-pro` |

The button stays off pages it would get in the way of: the full Ask AI page, and pages with a Save bar along the bottom (the member form, the role editors). A module chooses this through `buildAssistant`, `hidesAssistantButton`, `assistantLinks` and `publicVenueRoute` on `HealthProModule`.

The AI never sees the gym's records. It only decides **which of the app's reports** answers a question (and for how long a period, or whose name to look for), or writes a short how-to from a guide written into the function (`supabase/functions/*/reply.ts`). The app then works the answer out itself, so the numbers are always Health Pro's own and follow the person's role (no money for the front desk). Gym lists come from Health Pro's public list of verified venues.

1. The app sends the question, with the conversation's last three questions, to the Edge Function.
2. The database counts it before the AI is asked:
   - `ai_take_question` (gym staff, as the person asking): they must work at that gym, 25 questions a person a Bhutan day. It keeps who asked, where and when (not what) for 90 days.
   - `ai_take_public_question` (anyone, called by `ask-health-pro` with the service role): 15 a day for each signed-in account, or for each address when nobody is signed in (people on one mobile network or office Wi-Fi share an address). 150 a day from all visitors together (about half the free allowance), so visitors can't use up the gyms' share; signed-in members don't count towards it, so they can still ask when it runs out. Addresses are kept only as a hash keyed with a secret, for 30 days.
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

Without them, both chats still work: the suggestions answer, and typed questions say it isn't set up yet. To try another Workers AI model (it must support JSON mode), set `CLOUDFLARE_AI_MODEL` the same way with `supabase secrets set`. The functions log each question's token use (Supabase → Edge Functions → ask-ai or ask-health-pro → Logs).

### Logo, splash and loader

- **Logo** (`HealthProLogo`): the Health Pro logo, blue lettering for light backgrounds (`logo.webp`), and white lettering for dark ones (`logo_on_dark.webp`); `markOnly` is the cross with the runner (`mark.webp`, `mark_on_dark.webp`). They're WebP (a quarter of the PNGs' size), made by `tool/brand_images.dart`, which needs `cwebp` (`brew install webp`). It follows the theme. Places that are navy in both themes (the side menu, the welcome page's footer, the splash) pass `onDark: true`.
- **Splash** (`HealthProSplash`): the white logo in the middle of the navy, 240 wide on a phone and 320 on anything bigger, with a green bar (the logo's green) under it. It shows while the modules load at start (`SplashGate` fades it into the page). The launch screens draw the same logo at the same size and place, so the handover doesn't jump. If you change one, change them all: `web/index.html` and `web/splash/`, Android's `res/drawable*/launch_background.xml`, `splash_logo.png`, `splash_icon.png` and `values*-v31/styles.xml` (Android 12+ shows the mark in a circle), and iOS's `LaunchScreen.storyboard`, `LaunchImage` and `LaunchBackground`. iOS caches its launch screen, so delete the app and reinstall it to see a change.
- **Loader** (`HealthProLoader`): the orange-and-blue spinner, for the few places that wait without a shape to show. Pages and lists waiting on data show `LoadingSkeleton` (through `AsyncValueView`). Spinners inside buttons stay Flutter's plain one.

## Adding a module (e.g. coaching)

1. `packages/coaching`, depending on `health_pro_core`; add it to the root `pubspec.yaml` workspace list and to the app's `pubspec.yaml`.
2. `class CoachingModule extends HealthProModule`, with its `color`, `navigation` (its menu section) and, if it wants one, `buildOverviewCard`; and one line in `apps/health_pro_app/lib/main.dart`. The side menu, Overview and My services pick it up: nothing else in the app changes.
3. A migration: `coaching_*` tables (linked to `venues`), RLS, functions, and
   `insert into public.app_modules (key, name, is_enabled, sort_order) values ('coaching', 'Coaching', false, 30);`
4. Test it as an admin, then turn it on.

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

- **Privacy policy and terms**: `/#/privacy` and `/#/terms`, open to everyone and linked from the landing page's footer, the sign-up form and Account. Google Play and the App Store ask for the privacy policy's address. Set `LegalInfo.contactEmail` in `packages/health_pro_core/lib/src/legal/legal_pages.dart` before publishing (until then the pages say an address is coming), and change the pages (and `LegalInfo.updated`) whenever what the app collects or who it's shared with changes. Have them checked by someone who knows Bhutan's law.
- **App errors**: release builds send errors the app didn't handle to the database (`app_errors`, through `report_app_error`); the team sees them under Admin → App errors (permission `errors.view`, which the Administrator role has). A lost connection isn't sent; each kind goes once per run, ten at most; one not seen for 90 days is cleared. On the web the stack is the compiled JavaScript's, so the message and the page say most.
- **Website**: see [Website on Cloudflare](#website-on-cloudflare). `scripts/build_web.sh` builds `apps/health_pro_app/build/web`, which any static host can serve; URLs use `/#/`, so no rewrites are needed.
- **Android**: application id `bt.healthpro.app`. Add a release signing key before uploading to Google Play.
- **iOS**: bundle id `bt.healthpro.app`. Set your team in Xcode (`ios/Runner.xcworkspace`).
- App icons, launch screens and in-app logos are all made from the brand files in `packages/health_pro_core/tool/brand/` (kept out of `assets/` so they don't ship in the app): `logo-dark-new.png`, the transparent logo, and `logo-white-small.png`, the app icon (the mark on a white tile); `logo-white-new.png`, the logo on white, is for reference. To change the logo, replace those files and run `cd packages/health_pro_core && flutter test tool/brand_images.dart`; it makes the white-lettered version, lifts the mark off the icon's tile, and writes every image. If the logo's shape changes, update `HealthProLogo.aspectRatio`, `web/index.html` and `LaunchScreen.storyboard` to the size it prints.

## Tests

```sh
(cd packages/health_pro_core && flutter test)
(cd packages/gym_membership && flutter test)
(cd apps/health_pro_app && flutter test)
scripts/test_database.sh      # needs a local PostgreSQL (brew install postgresql)
deno test tests/functions/    # the Edge Functions' own logic (brew install deno)
```

`scripts/test_database.sh` runs `tests/database/scenario_test.sql` (memberships end to end), `access_test.sql` (master data, roles and permissions), and the organisations, registration, Ask AI (`ai_test.sql`: the daily question allowance) and app errors (`app_errors_test.sql`) checks, among others.
