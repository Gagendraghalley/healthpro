# Health Pro

Gym membership platform for Bhutan (renamed from SportsHub; the repo folder is still `sporthubs`).
Flutter app for web, Android and iOS. Supabase is the only backend. Gym is the only module.

Dart pub workspace (`flutter pub get` once, at the root):
- `apps/health_pro_app`: thin shell; `lib/main.dart` lists the modules.
- `packages/health_pro_core`: the platform (auth, shell and menu, roles, venues, theme, widgets).
- `packages/gym_membership`: the gym module. Imports only `health_pro_core`.

## Keep token use low
- Don't explore to get oriented. Use the map below, `grep -rn` for the symbol, then Read only those lines (`offset`/`limit`).
- Never read these whole: `gym_welcome_page.dart` (3.5k lines), `members_screens.dart` (1.6k), and the ~1k-line files
  `dashboard_kit.dart`, `platform_shell.dart`, `auth_layout.dart`, `role_screens.dart`, `user_screens.dart`,
  `my_gyms_screen.dart`, `staff_screens.dart`, `trainer_screens.dart`, `payment_screens.dart`, `gym_repository.dart`.
- Never open: `supabase/migrations/20261108000002_master_locations_data.sql` (village data), `pubspec.lock`, `*.docx`,
  `build/`, `.dart_tool/`, `.wrangler/`, `.github/` (unrelated).
- `README.md` is long: `grep -n '^#' README.md`, then read only the section you need.
- Test only what you changed, quietly: `flutter test -r failures-only test/<name>_test.dart` inside that package.
  Run the full suites only before saying a feature is done.
- Trim command output (`| tail -20`, `| grep -E 'FAIL|ERROR'`). Don't re-read a file you just edited.
- No subagents for searches a grep can answer. Screenshots only for visual work or when asked.
- Short replies: what changed and what's left. No recap of the diff.

## Commands (from the repo root)
- Analyze everything (currently 0 issues): `flutter analyze`
- Dart tests: `(cd packages/gym_membership && flutter test -r failures-only)`; same for `packages/health_pro_core`, `apps/health_pro_app`
- Database rules (throwaway local Postgres, applies every migration twice): `scripts/test_database.sh 2>&1 | grep -E 'FAIL|ERROR|PASSED'`
- Edge Functions: `deno test tests/functions/`
- Run the website: `./scripts/run_web.sh` (localhost:3000; needs `apps/health_pro_app/env.json`)
- Release build: `bash scripts/build_web.sh` (PWA install only works on this or the live site, not on `flutter run`)
- Deploys need the user's tokens, so the user runs them: `scripts/deploy_supabase.sh`, `scripts/deploy_web.sh`.

## Map
```
apps/health_pro_app/web/            index.html (PWA install), push_sw.js, flutter_bootstrap.js
packages/health_pro_core/lib/src/
  shell/          platform_shell (side menu), service_nav, start_page (assignedStart), home/services screens
  module/         health_pro_module.dart: the module contract
  router/         app_router, core_routes, route_guard
  auth/           sign-in (email + own 6-digit code), install_app_button
  access/         roles, permissions (access.can), users, organisations
  venues/         venue model/repository/screens, profile fields, OSM map, opening hours
  people/         my_qr_screen (My dashboard, /my-qr), person_qr
  theme/          brand.dart (BrandColors, LightColors, Brand.pick), app_theme, theme_mode, phone_size
  widgets/        dashboard_kit, motion (Motion, reduceMotion), common (AsyncValueView), feedback (runAction),
                  data_grid, app_page, form_fields, searchable_dropdown, art3d (Art3D: the menu's 3D icons,
                  assets/icons3d/, Fluent Emoji 3D, MIT; every menu entry, ServiceAction and SearchHit gets an `art:`)
  assistant/ push/ pwa/ masters/ notifications/ payments/ admin/ profiles/ utils/
packages/gym_membership/lib/src/
  gym_routes.dart (every /gyms path), gym_module.dart, gym_permissions.dart
  data/           gym_repository (all Supabase calls), gym_models, member_qr, registered_member (packageEnd,
                  renewalStart), joining, online_payments, trainers, inventory, reports/dashboard/ask data
  screens/        members_screens (Members, RegisterMember, GymMember), check_in, staff_screens (Plans, Income),
                  payment_screens, join_screens (JoinRequests, GymQr), my_gyms_screen (MyGym), trainer_screens,
                  gym_trainer_screens, public_screens (GymList, GymDetails), reports, ask_screen,
                  inventory_screens (Inventory, Suppliers: shown only, bought in the supplier's own system)
  shell/          gym_navigation (the gym's menu section), current_gym
  dashboard/ welcome/ (public landing page) widgets/
supabase/migrations/    YYYYMMDDNNNNNN_name.sql, one per change
supabase/functions/     admin-users, ask-ai, ask-health-pro, delete-account, send-push, supplier-catalog, _shared/
tests/database/         *_test.sql, run by scripts/test_database.sh
tests/functions/        Deno tests for the Edge Functions
```

## Rules
- Never run `dart format` on folders or on files you didn't create. The code is hand-formatted with long lines
  (~120-150 columns); match the surrounding style by hand. Lints: single quotes, declared return types, no `print`.
- Never edit an applied migration; add a new one with the next timestamp. Migrations must be safe to re-run.
  Cover DB changes in `tests/database/*_test.sql` (a new test file also goes into `scripts/test_database.sh`).
- Membership expiry is the same date N months later. Keep `packageEnd`/`renewalStart` (Dart) in step with
  `gym_add_membership`/`gym_renew_member` (SQL).
- Kept as "sportshub" on purpose, never rename: the `sportshub:` QR prefixes (member_qr.dart; cards are printed),
  the Cloudflare project `sporthubs`, Supabase `project_id`, `@sportshub.bt` test emails.
- User-facing name is "Health Pro". Ground booking was removed: don't mention grounds or tournaments.
- The menu is service-driven: gym pages go in `gym_navigation.dart`, never straight into the core sidebar.
  Gate pages and actions with `access.can(...)`.
- Keep the top bar clear: a page's own buttons go in `PageActions` at the top of its content, never
  `AppPage(actions:)`. The gym's New menu shows only on Members and Check-in (`ServiceNav.actionsInBar`).
- Light theme is the default. Light-only colours go through `LightColors` / `Brand.pick(light, dark)`; never change
  dark-mode values. Animations use `Motion` timings and stand still when `reduceMotion(context)`.
  Phone sizing is global (`PhoneSized`); don't shrink sizes per screen.
- No mock data in the app. Don't change routes, permissions, API or database unless asked.
- Mockups from the user are style only: copy the look, keep the existing fields and flow.
- When new logos or assets replace old ones, delete the old files. Brand sources are in
  `packages/health_pro_core/tool/brand/`; regenerate with `cd packages/health_pro_core && flutter test tool/brand_images.dart`.
- Never read or print `deploy.local.sh` or `env.json` (secrets).
- Commit or push only when asked. A push to `main` publishes the website (Cloudflare Pages).
