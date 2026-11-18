-- Inventory and connected suppliers: runs after scenario_test.sql (it uses
-- its t.* helpers and super admin A). Owner Ola runs Stock Gym with manager
-- Mani (has gym.inventory) and desk Dema (staff: doesn't); Xo runs another
-- gym and must see none of Stock Gym's.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000ab001', 'stock.owner@gym.bt', '{"full_name":"Ola Owner"}'),
  ('00000000-0000-0000-0000-0000000ab002', 'stock.manager@gym.bt', '{"full_name":"Mani Manager"}'),
  ('00000000-0000-0000-0000-0000000ab003', 'stock.desk@gym.bt', '{"full_name":"Dema Desk"}'),
  ('00000000-0000-0000-0000-0000000ab004', 'stock.other@gym.bt', '{"full_name":"Xo Other"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000ab001');
select public.register_venue('{"type":"gym","name":"Stock Gym","dzongkhag":"Thimphu","phone":"+97517200001"}') as gym \gset
select public.add_venue_staff(:'gym', 'stock.manager@gym.bt', 'manager');
select public.add_venue_staff(:'gym', 'stock.desk@gym.bt', 'staff');
select t.as_user('00000000-0000-0000-0000-0000000ab004');
select public.register_venue('{"type":"gym","name":"Other Stock Gym","dzongkhag":"Thimphu","phone":"+97517200002"}') as other \gset

-- ---- Connected suppliers ---------------------------------------------------
select t.eq((select string_agg(key, ',' order by sort_order) from public.inventory_suppliers where is_active),
            'sample-equipment,sample-nutrition,sample-accessories', 'the dummy gym suppliers are connected');
select t.eq((select count(*)::int from public.inventory_suppliers where key = 'test-store'), 0, 'the other-sports test supplier is gone');
set role anon;
select t.as_user(null);
select t.fails('select count(*) from public.inventory_suppliers', 'permission denied');
select t.fails('select count(*) from public.gym_inventory_items', 'permission denied');
set role authenticated;

-- ---- The owner adds items ----------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000ab001');
select public.gym_save_inventory_item(:'gym', null,
  '{"name":"  Yoga   mat ","category":"Equipment","quantity":10,"reorder_level":3,"unit_cost":800}') as mat \gset
select t.eq((select name || '|' || unit || '|' || quantity from public.gym_inventory_items where id = :'mat'),
            'Yoga mat|pcs|10', 'an item, tidied, with its opening count');
select t.eq((select reason || ' ' || change from public.gym_inventory_moves where item_id = :'mat'), 'opening 10',
            'the opening count is in its history');
select t.fails(format($$select public.gym_save_inventory_item(%L, null, '{"name":"yoga mat"}')$$, :'gym'), 'already an item');
select t.fails(format($$select public.gym_save_inventory_item(%L, null, '{"name":"X"}')$$, :'gym'), 'Give the item a name');
select t.fails(format($$select public.gym_save_inventory_item(%L, null, '{"name":"Towel","quantity":"lots"}')$$, :'gym'),
               'whole numbers');
select t.fails(format($$select public.gym_save_inventory_item(%L, null, '{"name":"Towel","quantity":-1}')$$, :'gym'),
               'below zero');
select public.gym_save_inventory_item(:'gym', null, '{"name":"Protein shake","unit":"tubs"}') as shake \gset
select t.eq((select count(*) from public.gym_inventory_moves where item_id = :'shake')::int, 0, 'no history for an empty item');

-- ---- The manager moves stock ---------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000ab002');
select t.eq(public.gym_move_stock(:'mat', 'stock_in', 5, 'From the supplier'), 15, 'stock in adds');
select t.eq(public.gym_move_stock(:'mat', 'used', 2), 13, 'used takes away');
select t.eq(public.gym_move_stock(:'mat', 'damaged', 1, 'Torn'), 12, 'so does damaged');
select t.fails(format($$select public.gym_move_stock(%L, 'sold', 50)$$, :'mat'), 'Only 12 pcs in stock');
select t.fails(format($$select public.gym_move_stock(%L, 'stolen', 1)$$, :'mat'), 'Choose stock in');
select t.fails(format($$select public.gym_move_stock(%L, 'used', 0)$$, :'mat'), 'Enter how many');
select t.eq(public.gym_move_stock(:'mat', 'recount', 12), 12, 'a recount that matches');
select t.eq(public.gym_move_stock(:'mat', 'recount', 9, 'Counted on Friday'), 9, 'a recount sets the count');
select t.eq((select string_agg(reason || ' ' || change || '=' || quantity_after, ', ' order by made_at, quantity_after desc)
             from public.gym_inventory_moves where item_id = :'mat'),
            'opening 10=10, stock_in 5=15, used -2=13, damaged -1=12, recount -3=9', 'every change is in the history');
select t.eq((select count(*) from public.gym_inventory_moves
             where item_id = :'mat' and made_by = '00000000-0000-0000-0000-0000000ab002')::int, 4, 'with who made it');
select public.gym_save_inventory_item(:'gym', :'mat', '{"name":"Yoga mat","reorder_level":10,"quantity":500}');
select t.eq((select quantity || '/' || reorder_level from public.gym_inventory_items where id = :'mat'), '9/10',
            'editing details never changes the count');

-- ---- Staff without the permission, and other gyms ---------------------------------
select t.as_user('00000000-0000-0000-0000-0000000ab003');
select t.eq((select count(*) from public.gym_inventory_items where venue_id = :'gym')::int, 0, 'desk staff see no inventory');
select t.fails(format($$select public.gym_move_stock(%L, 'used', 1)$$, :'mat'), 'no longer exists');
select t.fails(format($$select public.gym_save_inventory_item(%L, null, '{"name":"Towel"}')$$, :'gym'), 'owner and managers');
select t.as_user('00000000-0000-0000-0000-0000000ab004');
select t.eq((select count(*) from public.gym_inventory_items)::int, 0, 'another gym sees none of it');
select t.eq((select count(*) from public.gym_inventory_moves)::int, 0, 'nor its history');
select t.fails(format($$select public.gym_delete_inventory_item(%L)$$, :'mat'), 'no longer exists');
select t.fails(format($$select public.gym_save_inventory_item(%L, %L, '{"name":"Mine now"}')$$, :'other', :'mat'),
               'no longer exists');

-- ---- Removing an item ----------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000ab001');
select public.gym_delete_inventory_item(:'mat');
select t.eq((select count(*) from public.gym_inventory_moves where item_id = :'mat')::int, 0, 'removed with its history');

reset role;
do $$ begin raise notice 'ALL INVENTORY CHECKS PASSED'; end $$;
