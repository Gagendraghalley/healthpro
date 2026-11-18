-- Inventory: what a gym keeps (equipment, supplements, towels...) and how
-- many it has, for its owner and managers ('gym.inventory'); and the other
-- systems connected here, whose items and stock the Suppliers page shows.
--
-- - gym_inventory_items: the gym's things and their count now;
-- - gym_inventory_moves: every change to a count (stock in, used, sold,
--   damaged, a recount) with who made it; counts only change through
--   gym_move_stock, so the history always adds up;
-- - inventory_suppliers: connected systems. The supplier-catalog Edge
--   Function reads their items through their API ([api_kind] picks the
--   adapter). Health Pro only shows them: buying and paying happen in the
--   supplier's own system ([website_url]).
--
-- Safe to re-run.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.inventory_suppliers (
  key         text primary key check (key ~ '^[a-z0-9-]{2,40}$'),
  name        text not null check (char_length(trim(name)) between 2 and 80),
  description text check (char_length(description) <= 300),
  website_url text not null check (website_url ~ '^https://'),
  api_kind    text not null check (api_kind in ('dummyjson')),
  api_url     text not null check (api_url ~ '^https://'),
  category    text check (char_length(category) <= 60), -- the part of their catalogue to show; null for all
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.gym_inventory_items (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  name          text not null check (char_length(trim(name)) between 2 and 80),
  category      text check (char_length(category) <= 40),
  unit          text not null default 'pcs' check (char_length(trim(unit)) between 1 and 20),
  quantity      int not null default 0 check (quantity between 0 and 1000000),
  reorder_level int not null default 0 check (reorder_level between 0 and 1000000), -- low stock at or below this
  unit_cost     int check (unit_cost between 0 and 1000000), -- Ngultrum, optional
  notes         text check (char_length(notes) <= 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists gym_inventory_items_venue_idx on public.gym_inventory_items (venue_id);
create unique index if not exists gym_inventory_items_one_name on public.gym_inventory_items (venue_id, lower(trim(name)));

create table if not exists public.gym_inventory_moves (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references public.gym_inventory_items (id) on delete cascade,
  venue_id       uuid not null references public.venues (id) on delete cascade,
  reason         text not null check (reason in ('opening', 'stock_in', 'used', 'sold', 'damaged', 'recount')),
  change         int not null check (change <> 0),
  quantity_after int not null check (quantity_after >= 0),
  note           text check (char_length(note) <= 200),
  made_by        uuid constraint gym_inventory_moves_made_by_fkey references public.profiles (id) on delete set null,
  made_at        timestamptz not null default now()
);
create index if not exists gym_inventory_moves_item_idx on public.gym_inventory_moves (item_id, made_at desc);

drop trigger if exists gym_inventory_items_updated_at on public.gym_inventory_items;
create trigger gym_inventory_items_updated_at before update on public.gym_inventory_items
  for each row execute function public.set_updated_at();

-- The test supplier until the real one is ready: sports items from the
-- public DummyJSON API. Turn it off (is_active) when the real one is added.
insert into public.inventory_suppliers (key, name, description, website_url, api_kind, api_url, category, sort_order)
values ('test-store', 'Test supplier',
        'Sample sports items from a public test API, until the real supplier is connected.',
        'https://dummyjson.com', 'dummyjson', 'https://dummyjson.com', 'sports-accessories', 0)
on conflict (key) do nothing;

-- 'gym.inventory': the gym's stock and the connected suppliers. Owners and
-- managers have it to start with.
do $$
declare
  v_new boolean;
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order)
    values ('gym.inventory', 'venue', 'gym_membership', 'Inventory',
            'Keep the gym''s stock and see items from connected suppliers', 107)
    on conflict (key) do update
      set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order
    returning (xmax = 0) as inserted
  )
  select inserted into v_new from saved;
  if v_new then
    insert into public.role_permissions (role_id, permission_key)
    select r.id, 'gym.inventory' from public.roles r where r.key in ('owner', 'manager')
    on conflict do nothing;
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Who can read what (changes go through the functions below)
-- ---------------------------------------------------------------------

alter table public.inventory_suppliers enable row level security;
alter table public.gym_inventory_items enable row level security;
alter table public.gym_inventory_moves enable row level security;
revoke all on public.inventory_suppliers, public.gym_inventory_items, public.gym_inventory_moves from anon, authenticated;
grant select on public.inventory_suppliers, public.gym_inventory_items, public.gym_inventory_moves to authenticated;

drop policy if exists "inventory_suppliers: connected ones, signed in" on public.inventory_suppliers;
create policy "inventory_suppliers: connected ones, signed in" on public.inventory_suppliers for select to authenticated
  using (is_active or (select public.is_admin()));

drop policy if exists "gym_inventory_items: the gym's inventory staff" on public.gym_inventory_items;
create policy "gym_inventory_items: the gym's inventory staff" on public.gym_inventory_items for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.inventory'));

drop policy if exists "gym_inventory_moves: the gym's inventory staff" on public.gym_inventory_moves;
create policy "gym_inventory_moves: the gym's inventory staff" on public.gym_inventory_moves for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.inventory'));


-- ---------------------------------------------------------------------
-- 3. Functions
-- ---------------------------------------------------------------------

-- Adds an item (item_id null; details.quantity is its opening count) or
-- changes one's details (its count only through gym_move_stock). Returns
-- its id. details: name, category, unit, reorder_level, unit_cost, notes,
-- quantity.
create or replace function public.gym_save_inventory_item(venue_id uuid, item_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_inventory_item.venue_id;
  p_item uuid := gym_save_inventory_item.item_id;
  d jsonb := coalesce(gym_save_inventory_item.details, '{}'::jsonb);
  v_name text := regexp_replace(trim(coalesce(d ->> 'name', '')), '\s+', ' ', 'g');
  v_category text := nullif(regexp_replace(trim(coalesce(d ->> 'category', '')), '\s+', ' ', 'g'), '');
  v_unit text := coalesce(nullif(trim(coalesce(d ->> 'unit', '')), ''), 'pcs');
  v_notes text := nullif(trim(coalesce(d ->> 'notes', '')), '');
  v_reorder int;
  v_cost int;
  v_quantity int;
  v_id uuid;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.inventory') then
    raise exception 'Only the gym''s owner and managers can change its inventory.';
  end if;
  if char_length(v_name) < 2 then
    raise exception 'Give the item a name.';
  end if;
  begin
    v_reorder := coalesce((d ->> 'reorder_level')::int, 0);
    v_cost := (d ->> 'unit_cost')::int;
    v_quantity := coalesce((d ->> 'quantity')::int, 0);
  exception when others then
    raise exception 'Counts and prices are whole numbers.';
  end;
  if v_reorder < 0 or v_quantity < 0 or coalesce(v_cost, 0) < 0 then
    raise exception 'Counts and prices can''t be below zero.';
  end if;
  if exists (select 1 from public.gym_inventory_items i
             where i.venue_id = p_venue and lower(trim(i.name)) = lower(v_name) and i.id is distinct from p_item) then
    raise exception 'There''s already an item called %.', v_name;
  end if;

  if p_item is null then
    insert into public.gym_inventory_items (venue_id, name, category, unit, quantity, reorder_level, unit_cost, notes)
    values (p_venue, v_name, v_category, v_unit, v_quantity, v_reorder, v_cost, v_notes)
    returning gym_inventory_items.id into v_id;
    if v_quantity > 0 then
      insert into public.gym_inventory_moves (item_id, venue_id, reason, change, quantity_after, made_by)
      values (v_id, p_venue, 'opening', v_quantity, v_quantity, (select auth.uid()));
    end if;
  else
    update public.gym_inventory_items i set
      name = v_name, category = v_category, unit = v_unit, reorder_level = v_reorder, unit_cost = v_cost, notes = v_notes
    where i.id = p_item and i.venue_id = p_venue
    returning i.id into v_id;
    if v_id is null then
      raise exception 'This item no longer exists.';
    end if;
  end if;
  return v_id;
end;
$$;

-- Changes [item_id]'s count: stock_in adds [amount]; used, sold and damaged
-- take it away (never below zero); recount sets the count to [amount].
-- Returns the new count.
create or replace function public.gym_move_stock(item_id uuid, reason text, amount int, note text default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  p_reason text := gym_move_stock.reason;
  p_amount int := gym_move_stock.amount;
  p_note text := nullif(trim(coalesce(gym_move_stock.note, '')), '');
  v_item public.gym_inventory_items;
  v_after int;
begin
  select * into v_item from public.gym_inventory_items i where i.id = gym_move_stock.item_id for update;
  if v_item.id is null or not public.has_venue_permission(v_item.venue_id, 'gym.inventory') then
    raise exception 'This item no longer exists.';
  end if;
  if p_reason is null or p_reason not in ('stock_in', 'used', 'sold', 'damaged', 'recount') then
    raise exception 'Choose stock in, used, sold, damaged or recount.';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 or (p_amount = 0 and p_reason <> 'recount') then
    raise exception 'Enter how many.';
  end if;
  if char_length(p_note) > 200 then
    raise exception 'Keep the note under 200 characters.';
  end if;

  v_after := case p_reason
    when 'stock_in' then v_item.quantity + p_amount
    when 'recount' then p_amount
    else v_item.quantity - p_amount
  end;
  if v_after < 0 then
    raise exception 'Only % % in stock.', v_item.quantity, v_item.unit;
  end if;
  if v_after > 1000000 then
    raise exception 'That''s more than the inventory can count.';
  end if;
  if v_after = v_item.quantity then
    return v_after; -- a recount that matches: nothing to record
  end if;

  update public.gym_inventory_items i set quantity = v_after where i.id = v_item.id;
  insert into public.gym_inventory_moves (item_id, venue_id, reason, change, quantity_after, note, made_by)
  values (v_item.id, v_item.venue_id, p_reason, v_after - v_item.quantity, v_after, p_note, (select auth.uid()));
  return v_after;
end;
$$;

-- Removes [item_id] and its history.
create or replace function public.gym_delete_inventory_item(item_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  select i.venue_id into v_venue from public.gym_inventory_items i where i.id = gym_delete_inventory_item.item_id;
  if v_venue is null or not public.has_venue_permission(v_venue, 'gym.inventory') then
    raise exception 'This item no longer exists.';
  end if;
  delete from public.gym_inventory_items i where i.id = gym_delete_inventory_item.item_id;
end;
$$;

revoke execute on function public.gym_save_inventory_item(uuid, uuid, jsonb), public.gym_move_stock(uuid, text, int, text),
  public.gym_delete_inventory_item(uuid)
  from public, anon;
grant execute on function public.gym_save_inventory_item(uuid, uuid, jsonb), public.gym_move_stock(uuid, text, int, text),
  public.gym_delete_inventory_item(uuid)
  to authenticated;
