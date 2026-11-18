// How the supplier-catalog Edge Function reads a connected supplier.
//
//   deno test tests/functions/
import { catalogUrl, cleanQuery, cleanSkip, publicSupplier, read, type Supplier } from '../../supabase/functions/supplier-catalog/catalog.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

const store: Supplier = {
  key: 'test-store',
  name: 'Test supplier',
  description: null,
  website_url: 'https://dummyjson.com/',
  api_kind: 'dummyjson',
  api_url: 'https://dummyjson.com/',
  category: 'sports-accessories',
};
const everything: Supplier = { ...store, category: null };

const ball = {
  id: 101,
  title: '  Football ',
  description: 'Size 5',
  category: 'sports-accessories',
  brand: 'Kicks',
  price: 19.99,
  stock: 40,
  availabilityStatus: 'In Stock',
  thumbnail: 'https://cdn.dummyjson.com/ball.png',
};
const gloves = { id: 102, title: 'Boxing gloves', price: 30, stock: 3, availabilityStatus: 'Low Stock', thumbnail: 'http://x/a.png' };

Deno.test('a category comes back whole', () => {
  same(catalogUrl(store, 'ball', 30),
    'https://dummyjson.com/products/category/sports-accessories?limit=100&select=title,description,category,brand,price,stock,availabilityStatus,thumbnail');
});

Deno.test('without a category: search, a page at a time', () => {
  same(catalogUrl(everything, 'mat', 30).split('&select')[0], 'https://dummyjson.com/products/search?q=mat&limit=30&skip=30');
  same(catalogUrl(everything, null, 0).split('&select')[0], 'https://dummyjson.com/products?limit=30&skip=0');
});

Deno.test('an unknown kind of API is refused', () => {
  let failed = false;
  try {
    catalogUrl({ ...store, api_kind: 'other' }, null, 0);
  } catch {
    failed = true;
  }
  same(failed, true);
});

Deno.test('items in the app\'s shape, linking to the supplier', () => {
  const { items, total } = read(store, { products: [ball, gloves, { id: 103 }, 'junk'] }, null, 0);
  same(total, 2);
  same(items[0], {
    id: '101',
    name: 'Football',
    description: 'Size 5',
    category: 'sports-accessories',
    brand: 'Kicks',
    price: 19.99,
    currency: 'USD',
    stock: 40,
    availability: 'In Stock',
    image: 'https://cdn.dummyjson.com/ball.png',
    url: 'https://dummyjson.com/products/101',
  });
  same(items[1].image, null); // only https pictures
  same(items[1].description, null);
});

Deno.test('a category is searched and paged here', () => {
  same(read(store, { products: [ball, gloves] }, 'BOX', 0).items.map((i) => i.name), ['Boxing gloves']);
  same(read(store, { products: [ball, gloves] }, 'kicks', 0).items.map((i) => i.name), ['Football']);
  same(read(store, { products: [ball, gloves] }, null, 1), { items: [read(store, { products: [gloves] }, null, 0).items[0]], total: 2 });
});

Deno.test('a search keeps the API\'s total', () => {
  same(read(everything, { products: [ball], total: 57 }, 'ball', 0).total, 57);
  same(read(everything, { nothing: true }, null, 0), { items: [], total: 0 });
});

Deno.test('what comes in from the app is tidied', () => {
  same(cleanQuery('   yoga    mat  '), 'yoga mat');
  same(cleanQuery(''), null);
  same(cleanQuery(42), null);
  same(cleanSkip(-5), 0);
  same(cleanSkip(2.5), 0);
  same(cleanSkip(60), 60);
});

Deno.test('the app never sees the API address', () => {
  same(Object.keys(publicSupplier(store)), ['key', 'name', 'description', 'website_url']);
});
