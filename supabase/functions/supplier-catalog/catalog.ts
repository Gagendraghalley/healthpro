// Reading a connected supplier's catalogue (inventory_suppliers), one
// adapter per kind of API, into the one shape the app shows. Pure: the
// fetching is in index.ts, so this is tested without the network.

export type Supplier = {
  key: string;
  name: string;
  description: string | null;
  website_url: string;
  api_kind: string;
  api_url: string;
  category: string | null;
};

export type SupplierItem = {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  brand: string | null;
  price: number | null;
  currency: string | null;
  stock: number | null;
  availability: string | null;
  image: string | null;
  url: string; // the item in the supplier's own system, where it's bought
};

export const PAGE = 30;

const text = (value: unknown, max: number): string | null => {
  if (typeof value !== 'string') return null;
  const t = value.replace(/\s+/g, ' ').trim();
  return t.length === 0 ? null : t.slice(0, max);
};
const count = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : null;
const https = (value: unknown): string | null =>
  typeof value === 'string' && /^https:\/\/\S+$/.test(value) ? value : null;

export function cleanQuery(value: unknown): string | null {
  return text(value, 60);
}

export function cleanSkip(value: unknown): number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 ? Math.min(value, 10000) : 0;
}

/// The request for [supplier]'s items matching [query]. With a category,
/// the whole category comes back and [read] filters it, since DummyJSON's
/// search covers every category.
export function catalogUrl(supplier: Supplier, query: string | null, skip: number): string {
  const base = supplier.api_url.replace(/\/+$/, '');
  const fields = 'select=title,description,category,brand,price,stock,availabilityStatus,thumbnail';
  switch (supplier.api_kind) {
    case 'dummyjson':
      if (supplier.category) return `${base}/products/category/${encodeURIComponent(supplier.category)}?limit=100&${fields}`;
      if (query) return `${base}/products/search?q=${encodeURIComponent(query)}&limit=${PAGE}&skip=${skip}&${fields}`;
      return `${base}/products?limit=${PAGE}&skip=${skip}&${fields}`;
    default:
      throw new Error(`No adapter for ${supplier.api_kind}`);
  }
}

/// [body] from [catalogUrl], as the app's items: [query] and [skip] applied
/// here when the API returned a whole category.
export function read(supplier: Supplier, body: unknown, query: string | null, skip: number): { items: SupplierItem[]; total: number } {
  switch (supplier.api_kind) {
    case 'dummyjson': {
      const raw = (body as { products?: unknown })?.products;
      const all = (Array.isArray(raw) ? raw : []).map((p) => fromDummyjson(supplier, p)).filter((p): p is SupplierItem => p !== null);
      if (!supplier.category) {
        const total = count((body as { total?: unknown })?.total) ?? all.length;
        return { items: all, total };
      }
      const q = query?.toLowerCase();
      const matching = q
        ? all.filter((i) => [i.name, i.brand, i.description].some((f) => f?.toLowerCase().includes(q)))
        : all;
      return { items: matching.slice(skip, skip + PAGE), total: matching.length };
    }
    default:
      throw new Error(`No adapter for ${supplier.api_kind}`);
  }
}

function fromDummyjson(supplier: Supplier, raw: unknown): SupplierItem | null {
  if (raw === null || typeof raw !== 'object') return null;
  const p = raw as Record<string, unknown>;
  const id = typeof p.id === 'number' || typeof p.id === 'string' ? String(p.id) : null;
  const name = text(p.title, 120);
  if (!id || !name) return null;
  const price = typeof p.price === 'number' && Number.isFinite(p.price) && p.price >= 0 ? p.price : null;
  const base = supplier.website_url.replace(/\/+$/, '');
  return {
    id,
    name,
    description: text(p.description, 400),
    category: text(p.category, 60),
    brand: text(p.brand, 60),
    price,
    currency: price === null ? null : 'USD',
    stock: count(p.stock),
    availability: text(p.availabilityStatus, 30),
    image: https(p.thumbnail),
    url: `${base}/products/${encodeURIComponent(id)}`,
  };
}

/// What the app may show of a supplier (never its API address).
export function publicSupplier(s: Supplier) {
  return { key: s.key, name: s.name, description: s.description, website_url: s.website_url };
}
