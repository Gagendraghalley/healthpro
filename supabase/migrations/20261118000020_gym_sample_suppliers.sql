-- Dummy gym suppliers for trying the Suppliers page until a real one is
-- connected: gym equipment, nutrition and accessories, priced in Ngultrum.
-- Their items are built into the supplier-catalog Edge Function (sample.ts,
-- api_kind 'sample'), so nothing is fetched and no outside site is shown.
--
-- The DummyJSON test supplier showed other sports (cricket, football,
-- tennis...), so it goes. Turn these off (is_active) when the real supplier
-- is added.
--
-- Safe to re-run.

alter table public.inventory_suppliers drop constraint if exists inventory_suppliers_api_kind_check;
alter table public.inventory_suppliers
  add constraint inventory_suppliers_api_kind_check check (api_kind in ('dummyjson', 'sample'));

delete from public.inventory_suppliers where key = 'test-store';

insert into public.inventory_suppliers (key, name, description, website_url, api_kind, api_url, category, sort_order)
values ('sample-equipment', 'Iron & Cardio (sample)',
        'Dummy gym equipment supplier (weights, benches, cardio machines, floor mats) for trying this page. Not a real shop.',
        'https://example.com', 'sample', 'https://example.com', 'equipment', 1),
       ('sample-nutrition', 'Fuel Nutrition (sample)',
        'Dummy sports nutrition supplier (protein, supplements, snacks) for trying this page. Not a real shop.',
        'https://example.com', 'sample', 'https://example.com', 'nutrition', 2),
       ('sample-accessories', 'Gym Basics (sample)',
        'Dummy gym accessories supplier (mats, ropes, medicine balls, bottles, towels, cleaning) for trying this page. Not a real shop.',
        'https://example.com', 'sample', 'https://example.com', 'accessories', 3)
on conflict (key) do nothing;
