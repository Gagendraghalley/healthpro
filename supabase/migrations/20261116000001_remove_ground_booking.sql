-- =====================================================================
-- Ground booking is no longer part of Health Pro: its module row goes.
-- It never had tables, venue types or payments of its own here.
-- =====================================================================

delete from public.app_modules where key = 'ground_booking';
