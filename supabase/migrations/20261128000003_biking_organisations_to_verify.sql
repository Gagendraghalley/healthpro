-- =====================================================================
-- Real biking organisations, waiting in Venues to verify
-- =====================================================================
-- Four businesses in Bhutan that hire out bikes or run cycling trips, found
-- on the web (28 Nov 2026). They are not on Health Pro yet, so each waits,
-- unpublished, in Admin -> Venues to verify, as a lead for the team: call
-- or email it, and verify it only once it agrees to join (then it adds its
-- own packages and staff). Decline it otherwise.
--
-- Only what each one's own website says: its name, town, what it offers,
-- and its public phone and email. No packages, prices, classes, opening
-- hours or map pin are made up. Sources:
--   Firefox Tours            https://www.firefoxtours.com/mountain-bikes-e-bikes, /contact
--   Xplore Bhutan            https://bhutanxplore.com/activities/mountain-biking/, /about-us/, /contact-us/
--   Heavenly Bhutan Travels  https://www.heavenlybhutan.com/?p=8985, /contact-us/
--   Wind Horse Tours         https://www.windhorsetours.com/bhutan/mountain-biking-in-bhutan/, /contact/
-- Each gets its own organisation, as a registered place does.
--
-- Safe to re-run: fixed ids; one the team has verified or declined keeps
-- that.
-- =====================================================================

insert into public.venues (id, type, name, description, dzongkhag, town, address, phone, email, facilities,
                           verification_status)
values
  ('5c000000-0000-0000-0000-000000000001', 'cycling', 'Firefox Tours',
   'A Bhutanese tour operator that hires out mountain bikes and e-bikes from Thimphu, with half-day, full-day and '
   'longer rides, a guide and a support vehicle. Its bikes are only for guests on its package tours. '
   'Website: firefoxtours.com. Found on the web; not on Health Pro yet.',
   'Thimphu', 'Thimphu', null, '+97517883262', 'info@firefoxtours.com',
   array['Bike hire', 'Helmets', 'Guided trails'],
   'pending'),
  ('5c000000-0000-0000-0000-000000000002', 'cycling', 'Xplore Bhutan',
   'A tour operator in Thimphu with fully supported mountain-biking trips: Bhutan Biking Adventure, Bike across '
   'Bhutan (9 days) and Tour of the Dragon (9 days). Website: bhutanxplore.com. Found on the web; not on Health Pro yet.',
   'Thimphu', 'Chubachu', 'RTA Building, Suite 105, Chubachu', '+97517474180', 'info@bhutanxplore.com',
   array['Guided trails', 'Group rides'],
   'pending'),
  ('5c000000-0000-0000-0000-000000000003', 'cycling', 'Heavenly Bhutan Travels',
   'A tour operator in Thimphu, since 2009, with cycling tours of 4 to 17 days, among them Cycling Tours in Bhutan '
   '(9 days) and Tour of the Dragon Holidays (15 days). Website: heavenlybhutan.com. Found on the web; not on '
   'Health Pro yet.',
   'Thimphu', 'Samteling', 'Samteling Zur Lam 14, Bebena', '+97517617107', 'heavenlybhutan@gmail.com',
   array['Guided trails', 'Group rides'],
   'pending'),
  ('5c000000-0000-0000-0000-000000000004', 'cycling', 'Wind Horse Tours',
   'An adventure travel company based in the USA, with offices in Thimphu and Phuentsholing. In Bhutan it hires '
   'out Trek and Giant bikes with helmets, runs guided rides with a support vehicle from a day to 17 days, and '
   'gives race-day support for the Tour of the Dragon. Website: windhorsetours.com. Found on the web; not on '
   'Health Pro yet.',
   'Thimphu', 'Thimphu', null, '+16128694949', null,
   array['Bike hire', 'Helmets', 'Guided trails', 'Group rides'],
   'pending')
on conflict (id) do nothing;
