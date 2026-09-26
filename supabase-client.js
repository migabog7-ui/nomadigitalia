// ============================================================
// NŌMA / BIGULL DIGITAL — camada de dados Supabase
// Usado por menu.html (cliente) e admin.html (painel).
// Requer o script https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2
// carregado ANTES deste ficheiro (define window.supabase).
// ============================================================

// >>> PREENCHE ESTES DOIS VALORES <<<
// Supabase > Project Settings > API > Project URL / anon public key
const SUPABASE_URL = 'https://swjeqjndrwsgxgzrotot.supabase.co/rest/v1/';
const SUPABASE_ANON_KEY = 'sb_publishable_b5o36f7hxSyBOdQEYpgqrA_rMSoplM9';

// slug por omissão quando o URL não indica ?restaurant=
const DEFAULT_RESTAURANT_SLUG = 'noma';

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

function must(result) {
  if (result.error) throw result.error;
  return result.data;
}

const Noma = {
  sb, // acesso direto se precisares de algo fora deste módulo

  // ---------- leitura pública (cliente) ----------
  async getRestaurantBySlug(slug) {
    return must(await sb.from('restaurants').select('*').eq('slug', slug).single());
  },
  async getCategories(restaurantId) {
    return must(await sb.from('categories').select('*')
      .eq('restaurant_id', restaurantId).eq('active', true).order('display_order'));
  },
  async getProducts(restaurantId) {
    return must(await sb.from('products').select('*')
      .eq('restaurant_id', restaurantId).eq('available', true).order('display_order'));
  },
  async getTableByNumber(restaurantId, number) {
    const { data, error } = await sb.from('tables').select('*')
      .eq('restaurant_id', restaurantId).eq('table_number', number).eq('active', true).single();
    if (error) return null; // mesa inexistente/inativa -> null, não erro fatal
    return data;
  },

  // ---------- pedidos (cliente cria, ambos leem/ouvem) ----------
  async createOrder({ restaurant_id, table_id, items, total, customer_notes }) {
    const order = must(await sb.from('orders')
      .insert({ restaurant_id, table_id, total, customer_notes, status: 'new' })
      .select().single());
    const rows = items.map(it => ({
      order_id: order.id,
      product_id: it.product_id,
      product_name: it.product_name,
      quantity: it.quantity,
      unit_price: it.unit_price,
      notes: it.notes || '',
      subtotal: +(it.unit_price * it.quantity).toFixed(2),
    }));
    await sb.from('order_items').insert(rows).then(r => { if (r.error) throw r.error; });
    return order;
  },
  async getOrder(orderId) {
    return must(await sb.from('orders').select('*, order_items(*)').eq('id', orderId).single());
  },
  // chama cb sempre que este pedido mudar (ex: admin altera o estado)
  subscribeOrder(orderId, cb) {
    return sb.channel('order-' + orderId)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders', filter: `id=eq.${orderId}` },
        payload => cb(payload.new))
      .subscribe();
  },

  // ---------- autenticação (admin) ----------
  async signIn(email, password) {
    return must(await sb.auth.signInWithPassword({ email, password }));
  },
  async signOut() { await sb.auth.signOut(); },
  async getSession() { const { data } = await sb.auth.getSession(); return data.session; },
  onAuthChange(cb) { sb.auth.onAuthStateChange((_e, session) => cb(session)); },

  // restaurante(s) que este utilizador administra
  async getStaffRestaurants(userId) {
    const rows = must(await sb.from('restaurant_staff').select('restaurant_id, restaurants(*)').eq('user_id', userId));
    return rows.map(r => r.restaurants);
  },

  // ---------- pedidos (admin) ----------
  async getOrders(restaurantId) {
    return must(await sb.from('orders')
      .select('*, order_items(*), tables(table_number)')
      .eq('restaurant_id', restaurantId).order('created_at', { ascending: false }));
  },
  subscribeOrders(restaurantId, cb) {
    return sb.channel('orders-' + restaurantId)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `restaurant_id=eq.${restaurantId}` }, cb)
      .subscribe();
  },
  async updateOrderStatus(orderId, status) {
    await sb.from('orders').update({ status }).eq('id', orderId).then(r => { if (r.error) throw r.error; });
  },

  // ---------- CRUD produtos ----------
  async getAllProducts(restaurantId) { // inclui indisponíveis, para o admin
    return must(await sb.from('products').select('*').eq('restaurant_id', restaurantId).order('display_order'));
  },
  async createProduct(p) { return must(await sb.from('products').insert(p).select().single()); },
  async updateProduct(id, p) { await sb.from('products').update(p).eq('id', id).then(r => { if (r.error) throw r.error; }); },
  async deleteProduct(id) { await sb.from('products').delete().eq('id', id).then(r => { if (r.error) throw r.error; }); },

  // ---------- CRUD categorias ----------
  async getAllCategories(restaurantId) {
    return must(await sb.from('categories').select('*').eq('restaurant_id', restaurantId).order('display_order'));
  },
  async createCategory(c) { return must(await sb.from('categories').insert(c).select().single()); },
  async updateCategory(id, c) { await sb.from('categories').update(c).eq('id', id).then(r => { if (r.error) throw r.error; }); },
  async deleteCategory(id) { await sb.from('categories').delete().eq('id', id).then(r => { if (r.error) throw r.error; }); },

  // ---------- CRUD mesas ----------
  async getAllTables(restaurantId) {
    return must(await sb.from('tables').select('*').eq('restaurant_id', restaurantId).order('table_number'));
  },
  async createTable(t) { return must(await sb.from('tables').insert(t).select().single()); },
  async updateTable(id, t) { await sb.from('tables').update(t).eq('id', id).then(r => { if (r.error) throw r.error; }); },
  async deleteTable(id) { await sb.from('tables').delete().eq('id', id).then(r => { if (r.error) throw r.error; }); },

  // ---------- configurações do restaurante ----------
  async updateRestaurant(id, r) { await sb.from('restaurants').update(r).eq('id', id).then(res => { if (res.error) throw res.error; }); },
};

window.Noma = Noma;
window.NOMA_DEFAULT_SLUG = DEFAULT_RESTAURANT_SLUG;
