# Health Pro: features by role

Health Pro is a gym membership platform for Bhutan, on the website (installable on a phone) and the Android and iOS apps. This document lists every feature that is built today, grouped by who uses it. For each feature: where to find it, what it does, and what to check when testing.

Gym roles below show the default rights. An organisation can change what each role allows, and the Owner always has everything.

Last updated: 23 November 2026

## Before you start testing
- **Website:** https://myhealthpro.pages.dev (works on a computer and in a phone's browser).
- **Test accounts** (sign in with the email and its 6-digit code; they exist once `supabase/test_users.sql` has been run):
  - **Super admin** (can do everything): test.superadmin@example.com, code **123456**
  - **Health Pro administrator:** test.admin@example.com, code **123456**
  - **Owner** of "Health Pro Test Gym": test.owner@example.com, code **123456**
  - **Manager:** test.manager@example.com, code **123456**
  - **Front desk:** test.frontdesk@example.com, code **123456**
  - **Trainer:** test.trainer@example.com, code **123456**
  - **Member** with 3 months of the Monthly package: test.member@example.com, code **123456**
- **Gym membership switch:** while the gym service is turned off (Admin → Services on/off), only the super admin and the administrator see the gym pages.
- **Needs setting up first:** Continue with Google, push notifications, emails and Ask AI only work once they're switched on for the project. A missing Google button, or "Ask AI isn't set up yet", isn't a bug.
- **Dates** are Bhutan time. A package that ends on a day still lets the member in on that day.
- **Reporting a problem:** say which account, which page, the steps, what you expected and what happened, phone or computer, and add a screenshot.

## Everyone (no account needed)

### Welcome page
**Where:** open the website.
- What Health Pro is, Gyms near me, Find a gym, Sign in and Sign up.

### Find a gym
**Where:** Welcome page → Find a gym.
- Each gym with its cover photo, price range (from its packages), Open now (Bhutan time) and, with Near me, how far it is.
- Near me asks for your location and puts the nearest gym first.
- Sort by price, set a budget (only gyms with a package at or under it), or choose a dzongkhag.
- **Check:** only verified gyms are listed; Open now matches the gym's hours.

### A gym's page
**Where:** tap any gym in the list.
- Photos, video links and a promotional video, facilities, opening hours for the week, contact person, phone, WhatsApp and email.
- Packages and prices, trainers, classes with places left, and reviews.
- A map with Directions (opens Google Maps) and Bigger map.

### Trainer profile
**Where:** a trainer on a gym's page.
- About them, specialties, years of experience, photo, certificates, the gyms they train at with their weekly times, and reviews.
- **Check:** only trainers verified by at least one gym are public.

### Health Pro assistant (Ask AI)
**Where:** the Ask AI button, bottom right of every page.
- Answers questions about Health Pro: finding and joining a gym, checking in, putting a gym on Health Pro, accounts.
- "Gyms in Paro?" lists the verified gyms there.
- The suggested questions answer straight away. Typed questions: 15 a day per account (or per network without an account).
- **Check:** the button is hidden on pages with a Save bar at the bottom.

### Sign up and sign in
**Where:** Sign up / Sign in on the Welcome page.
- **Sign up:** Join as Member or Join as Trainer, then email; a 6-digit code is emailed to confirm it.
- **Choose your 6-digit code** to sign in with from then on, or skip and sign in with emailed codes.
- **Sign in:** email and your code; "Email me a code instead"; "Forgot code?" to set a new one.
- **Continue with Google** (when switched on): asks for a phone number once (can be skipped).
- **Install app:** on Android, Chrome or Edge it opens the install window; on iPhone it shows the steps (Share → Add to Home Screen). It hides once installed.

## Every signed-in person
- **Notifications:** the bell at the top of every page. Health Pro asks "Turn on notifications?" once a session after sign-in ("Not now" waits two weeks). The Notifications page turns push on or off for this device. Signing out turns it off on that device. On iPhone, push needs the installed app (iOS 16.4 or later).
- **Search** ("Search anything…" in the top bar): pages, shortcuts and records such as members and packages, as your role allows.
- **Account menu:** My details (edit), Light or Dark theme, Delete account, Sign out.
- **Side menu:** folds to icons on a computer, a drawer on a phone. Each service shows your role in it; with several gyms, a switcher picks the gym.

## Member

### My dashboard
**Where:** menu → My Health Pro → My dashboard (where members start).
- Your personal QR code, which works at every gym: Enlarge (for the scanner), Copy, Share, Save picture.
- My details (with Edit), Latest updates, and your gyms: package, days left, visits in the last 7 days, requests.
- What needs your attention: a package ended or ending within a week, a payment waiting or not found.
- **Get a new QR code** makes the old one stop working at every gym.

### Join a gym
**Where:** scan the gym's QR code, or open the gym's page → Ask to join.
- Choose the package you'd like and add a note. The gym is told and the request waits for them.
- You're told when they add you or decline (with their note). Requests left for 30 days close by themselves.
- If the desk registered you with the same email, your account picks up that membership once your email is confirmed.

### My gym
**Where:** menu → My gym.
- The gym in full (photos, contact, facilities, trainers, videos, hours, map) beside your membership: package, days left, member code, trainer.
- With several gyms, chips at the top choose one.
- When paused: "Paused until …", when you can check in again and until when your package runs.

### Pay online
**Where:** My dashboard → My gyms → Pay online.
- Choose the package and months, scan the gym's bank QR code in your bank app, pay, then enter the journal number (JRN).
- The gym confirms it (the package starts) or marks it Not found with a note. You're told either way.
- **Check:** only one payment can wait at a time; the same journal number is refused a second time at a gym.

### Receipts
**Where:** My gym → Receipts.
- Your last 10 receipts, to print or share.

### Classes
**Where:** My gym → classes; or a gym's page.
- Book a class up to two weeks ahead, before it starts. Cancel your own place before it starts.
- Members-only classes need a package that covers that day and no pause. Classes open to everyone can be booked by anyone signed in.
- You get an email and a notification when you book, when the class changes, and when the gym cancels your place.
- **Check:** a full class can't be booked; a cancelled date shows "Cancelled" and can't be booked.

### My trainer
**Where:** My dashboard → My gyms → Choose / Change trainer.
- Choose a trainer at each gym. The old and new trainer are told.
- Review a trainer (stars and a comment) once they've been your trainer.

### Progress, goals and plans
**Where:** My gym.
- **Log my weight** and other measurements (height, body fat, chest, waist, hips, arm, thigh).
- **My progress:** weight now, change since the first entry, BMI with its band, and a weight chart.
- **Goal:** what you're after, target weight and day, how active you are; it works out daily calories and protein.
- **My plans:** workout and diet plans from your trainer or the gym. You're told when a plan is given or changed.
- Suggestions on what to do next, and a reminder to log your weight after 30 days without.

### Reviews and notifications
- Review your gym on its page.
- Notifications you get: join request answered, payment confirmed or not found, package ending (on the gym's reminder days and the last day), pause and resume, removed from a gym, class bookings and changes, plans, trainer changes, a birthday wish.

## Trainer

### Trainer profile
**Where:** menu → Me → Trainer profile.
- Name as members see it, what you do, about you, specialties, years of experience, photo, and certificates (a photo of each).

### Train at a gym
**Where:** Trainer profile → Train at a gym.
- Ask a gym to verify you. The gym checks your certificates and verifies or declines with a note; you're told.
- One gym declining doesn't affect the others. You or the gym can make you inactive there; the gym can make you active again.

### My week
**Where:** Trainer profile → My week.
- Your days and times at each gym. Times can't overlap across gyms.
- **Check:** a gym sees your times elsewhere only as "Not available", never the other gym's name.

### Attendance
- The front desk scans your QR code at Check-in, or taps Mark arrived. One record per gym per day ("Already marked today" after that).
- You see your attendance at every gym on your own page; each gym sees only its own.

### My members
**Where:** menu → My members.
- Each member you train: package, latest weight and plans; open one to:
  - record measurements and set their goal;
  - give a workout or diet plan (meals and foods from the shared food list), start from a gym template, or keep a plan as a template for the gym;
  - **Draft with AI** fills the plan form from the member's numbers and goal for you to check (10 drafts a day).
- You're told when you get a new member, when a member changes trainer, and when a member's weight hasn't moved toward their goal for 3 weeks.
- Members who've trained with you can review you; you're told.

## Front desk (gym staff)
Default rights: Check-in, Members, Register member, payments at the desk, Classes, Trainers. No income, expenses, packages, stock, staff or settings.

### Dashboard
**Where:** the gym's menu → Dashboard.
- Today's numbers, what needs attention, packages ending soon (with a WhatsApp reminder button), and birthdays in the next 7 days (with a WhatsApp wish on the day).

### Check-in
**Where:** Front desk → Check-in.
- Scan the member's QR code with the camera or a USB scanner, or type their 6-character member code.
- **Checked in:** photo, days left and medical notes. **Not checked in:** the reason ("…'s package ended on …") and a Renew button.
- A paused member is refused ("…'s membership is paused until …").
- A person who isn't a member here yet: **Add to this gym** opens Register member filled in with their details.
- A verified trainer's QR code records **Trainer arrived** instead.
- **Check:** an ended package is refused; one ending today is let in; a member with an online payment waiting shows it here.

### Register member
**Where:** Front desk → Register member.
- The member's form: name, phone, email, dzongkhag, gewog, village, occupation, emergency contact, blood group, date of birth, date of joining, medical issues.
- Photo with the webcam or phone camera (Retake), or Upload.
- Package, months (1 to 24), amount paid, and an offer or a lower price with a reason.
- The expiry date is worked out, not typed: the same date N months later.
- After saving: the QR card (Download, Share, WhatsApp) and the receipt.
- **Check:** joining 8 Nov 2026 for 3 months expires on 8 Feb 2027.

### Members
**Where:** Front desk → Members.
- Search, status filters with counts, sort, table or cards, Export to Excel.
- "Ending in 7 days" and "Ended" lists with a WhatsApp reminder button; it shows "Reminded yesterday" for a week.

### A member's page
**Where:** tap a member.
- Edit details, New card (the old card stops working), receipts, history, progress and plans, assign a trainer, birthday wish.
- **Renew:** starts on the day the current package ends (so dates don't drift), or today if it has already ended. The receipt opens straight after.
- **Pause:** 1 to 180 days, from today or later, with a reason; the package end moves by that many days. **Resume** early gives the unused days back; **Take back** undoes a pause that hasn't started.
- **Delete member:** takes them off this gym; their account and other gyms stay, and payments stay in income. An active membership shows a red warning and needs a tick before Delete anyway. An online payment waiting must be confirmed or rejected first.
- **Receipts:** every payment has the gym's next receipt number. Print, Save picture, Share or WhatsApp.

### Requests
**Where:** the gym's menu → Requests (each with a count).
- **Join requests:** Add (opens the filled-in form; saving approves it) or Decline with a note.
- **Payments to confirm:** check the journal number with the bank, then Confirm (the package starts) or Not found with a note.
- **Enquiries & trials:** walk-ins and calls: how they heard of the gym, what they're after, a free trial (1 to 30 days), a follow-up day and notes. The count shows follow-ups due today and ended trials. Register fills in their name and phone; registering that phone marks the enquiry joined.

### Classes (bookings)
**Where:** Training → Classes.
- Who's booked each day; book members in, take them out (not once a class is over), register a newcomer from a class.

### Trainers
**Where:** Training → Trainers.
- Trainers asking to join: check certificates, then Verify or Don't verify with a note.
- Each trainer's times here, days here in the last 30, recent arrivals, Mark arrived, make inactive.

### Gym QR code, reports and Ask AI
- **Gym QR code** (Front desk): print it; scanning it opens the gym's page to Ask to join.
- **Reports & analytics:** new members, visits by day and hour, renewal rate, package mix, most regular members, and a summary; Export to Excel.
- **Ask AI** (on the gym's pages): "busiest hours this month?", "who hasn't come in two weeks?", "how do I renew a member?". Answers come as a chart, a list or a link to the page. Front desk gets no money answers. 25 questions a day.

## Trainer (gym staff role)
- Default rights: Check-in, Members, Reports & analytics and Classes, as for the front desk.
- A trainer verified at the gym also gets My members (see Trainer above).

## Manager
Everything the front desk does, plus:

### Memberships & packages
**Where:** Sales & money → Memberships & packages.
- Make and change packages and prices; members on each and times sold. The gym's price range on Find a gym follows them.

### Offers & discounts
**Where:** Sales & money → Offers & discounts.
- Offers as a percentage or an amount off (e.g. Student 10%). The desk picks one when selling.
- The month's discounts with totals; discounts without a reason are flagged. Receipts show the full price and the discount.

### Class timetable
**Where:** Training → Classes.
- Add, change or remove weekly classes: day, time, length, trainer, places, open to everyone or members only.
- **One date only:** change the time, trainer or places for one day, or cancel that day, with a note; Back to the timetable undoes it.
- **Check:** members booked are told by notification and email; removing a class or moving its day cancels the bookings to come.

### Money
- **Payments & income:** 12 months, by payment method, every payment with its receipt; Export to Excel.
- **Expenses & profit:** rent, salaries, equipment, repairs, utilities, supplies, marketing, other; the month's money in, money out and profit, the last 12 months; Export to Excel.

### Inventory and suppliers
**Where:** Stock.
- **Inventory:** items, counts, low-stock level and cost. Counts change only by Stock in, Take out or Recount, each kept in the item's History. The menu shows how many items are low or out.
- **Suppliers:** items and stock from connected suppliers (for now a test supplier); View in the supplier's own system. Nothing is bought here.

### Team and settings
- **Staff:** Add staff, choose their role, Make their account.
- **Gym settings:** name, place, phone, WhatsApp, email, contact person, map location, opening hours, facilities, video links, promotional video (up to 20 MB), up to 30 photos.
- **Membership settings:** the bank payment QR code, reminder days (1, 3, 7, 14 or 30 days before a package ends) and who answers join requests (front desk, or owner and managers only).
- **Activity log:** who registered, edited, sold, renewed, took payments, paused, deleted or added staff. Filter by kind, person or name. Nobody can change it.
- **Ask AI** also answers money questions ("revenue by payment method this year?").

## Owner
Everything above, always, plus:
- **Set up your gym / Register another gym:** register the gym; it shows "Being verified" until Health Pro approves it. A new gym gets a getting-started checklist on its dashboard.
- **Roles & permissions** (Team & settings): change what each role allows at the organisation's gyms, turn a role off, or make the organisation's own roles.
- **Check:** nobody can give a permission they don't have themselves; a gym always keeps an owner.

## Health Pro admin
**Where:** menu → Administration.
- **Admin home**, plus Overview and My services (every service and its numbers).
- **Users:** New user, give team roles, turn an account off (it can't sign in until turned on again).
- **Roles & permissions:** Health Pro-wide roles and, under "Whose roles", each organisation's.
- **Organisations:** rename, make new, move gyms between organisations (branches of one business).
- **Venues to verify:** approve new gyms or send them back.
- **Master data:** dzongkhags, gewogs and villages: add, rename, turn off.
- **Services on/off:** turn the gym membership service on or off.
- **App errors:** errors people hit, with the page, how many times and when last seen.
- **Check:** only a super admin can make another super admin; nobody can remove their own super admin.

## Runs by itself every day
- **00:05:** ends packages past their date, sends package-ending reminders (on the gym's reminder days and the last day) and closes requests left for 30 days.
- **08:05:** birthday wishes to members with the app and a package running.
- **08:15:** reminds members to log their weight (after 30 days) and tells trainers when a member's weight hasn't moved toward their goal for 3 weeks.
