// Suppliers connected to Health Pro (a gym's Suppliers page, for staff with
// 'gym.inventory' there): their items and stock, live from their API.
//
//   { venue_id, supplier?, query?, skip? }
//     -> { suppliers: [{ key, name, description, website_url }], supplier,
//          items: [{ id, name, ..., stock, url }], total }
//
// Health Pro only shows them. Buying and paying happen in the supplier's own
// system: each item's url opens it there.
//
// A supplier's API key, when one needs it, goes in a secret named
// SUPPLIER_<KEY>_TOKEN (e.g. SUPPLIER_TEST_STORE_TOKEN), never in the app.
// Deploy: supabase functions deploy supplier-catalog
import { createClient } from 'npm:@supabase/supabase-js@2';

import { cors, reply } from '../_shared/workers_ai.ts';
import { catalogUrl, cleanQuery, cleanSkip, publicSupplier, read, type Supplier } from './catalog.ts';

const uuid = (value: unknown): string | null =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) ? value : null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply({ error: 'Please sign in again.' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: 'Send JSON' }, 400);
  }
  const venueId = uuid(body.venue_id);
  if (!venueId) return reply({ error: 'Which gym?' }, 400);

  const asCaller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: allowed, error: allowedError } = await asCaller.rpc('has_venue_permission', {
    venue: venueId,
    perm: 'gym.inventory',
  });
  if (allowedError) return reply({ error: 'Please sign in again.' }, 401);
  if (allowed !== true) return reply({ error: "Only the gym's owner and managers can see suppliers." }, 403);

  const { data: rows, error: suppliersError } = await asCaller
    .from('inventory_suppliers')
    .select('key, name, description, website_url, api_kind, api_url, category')
    .eq('is_active', true)
    .order('sort_order')
    .order('name');
  if (suppliersError) return reply({ error: suppliersError.message }, 500);
  const suppliers = (rows ?? []) as Supplier[];
  if (suppliers.length === 0) return reply({ suppliers: [], supplier: null, items: [], total: 0 }, 200);

  const supplier = suppliers.find((s) => s.key === body.supplier) ?? suppliers[0];
  const query = cleanQuery(body.query);
  const skip = cleanSkip(body.skip);
  const token = Deno.env.get(`SUPPLIER_${supplier.key.toUpperCase().replace(/-/g, '_')}_TOKEN`);
  const list = suppliers.map(publicSupplier);

  try {
    const response = await fetch(catalogUrl(supplier, query, skip), {
      headers: { Accept: 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(`${supplier.key} answered ${response.status}`);
    const { items, total } = read(supplier, await response.json(), query, skip);
    return reply({ suppliers: list, supplier: supplier.key, items, total }, 200);
  } catch (e) {
    console.error('supplier-catalog failed', e);
    return reply({
      suppliers: list,
      supplier: supplier.key,
      error: `${supplier.name} isn't answering just now. Please try again, or open their website.`,
    }, 502);
  }
});
