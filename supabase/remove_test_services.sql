-- =====================================================================
-- Remove the test services (not a migration)
-- =====================================================================
-- Takes away the 39 test places of 20261128000002_test_services.sql (the
-- ones named "... (Test)"), with everything members did there: their
-- memberships, payments, check-ins, class bookings and requests to join,
-- and the staff, packages and classes. Then the organisations made for
-- them, unless a real place has since been put in one. The service types
-- stay. Members keep their accounts and their QR codes.
--
-- Paste it into the Supabase SQL editor of the live project when testing is
-- done. All or nothing; running it again does nothing.
-- =====================================================================

begin;

create temp table test_venues on commit drop as
select id, organisation_id from public.venues where id::text like '5a000000-0000-0000-0000-0000000000%';

-- Payments keep a place from being deleted, so they go first; the rest goes with the place.
delete from public.payments where venue_id in (select id from test_venues);
delete from public.venues where id in (select id from test_venues);
delete from public.organisations o
where (o.id in (select organisation_id from test_venues) or o.id::text like '5b000000-0000-0000-0000-0000000000%')
  and not exists (select 1 from public.venues v where v.organisation_id = o.id);

commit;
