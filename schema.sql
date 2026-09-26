-- ============================================================
-- NŌMA / BIGULL DIGITAL — schema base (multi-restaurante)
-- Corre este ficheiro completo no Supabase: Project > SQL Editor > New query > Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- RESTAURANTS ----------
create table restaurants (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,               -- usado no URL, ex: 'noma'
  name text not null,
  logo_url text,
  description text,
  address text,
  phone text,
  opening_hours text,
  primary_color text default '#9C7A3C',
  secondary_color text default '#18150F',
  created_at timestamptz default now()
);

-- liga utilizadores autenticados (Supabase Auth) a um restaurante = o "admin" desse restaurante
create table restaurant_staff (
  user_id uuid references auth.users(id) on delete cascade,
  restaurant_id uuid references restaurants(id) on delete cascade,
  role text default 'admin',
  created_at timestamptz default now(),
  primary key (user_id, restaurant_id)
);

-- ---------- CATEGORIES ----------
create table categories (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  name text not null,
  description text,
  display_order int default 0,
  active boolean default true,
  created_at timestamptz default now()
);

-- ---------- PRODUCTS ----------
create table products (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  category_id uuid references categories(id) on delete set null,
  name text not null,
  description text,
  price numeric(10,2) not null,
  image_url text,
  available boolean default true,
  display_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- TABLES ----------
create table tables (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  table_number int not null,
  qr_code_url text,
  active boolean default true,
  created_at timestamptz default now(),
  unique (restaurant_id, table_number)
);

-- ---------- ORDERS ----------
create table orders (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  table_id uuid references tables(id),
  order_number int generated always as identity,  -- numeração global sequencial (simples para o MVP)
  status text not null default 'new'
    check (status in ('new','accepted','preparing','ready','completed','cancelled')),
  total numeric(10,2) not null default 0,
  customer_notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- ORDER_ITEMS ----------
-- product_name e unit_price são copiados do produto no momento do pedido:
-- alterar o preço do produto depois NÃO altera pedidos já feitos.
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  quantity int not null default 1,
  unit_price numeric(10,2) not null,
  notes text,
  subtotal numeric(10,2) not null
);

-- ---------- updated_at automático ----------
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

create trigger trg_products_updated before update on products
  for each row execute function set_updated_at();
create trigger trg_orders_updated before update on orders
  for each row execute function set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- Regra geral: qualquer pessoa (cliente anónimo) pode LER menu ativo/disponível
-- e CRIAR pedidos. Só quem está em restaurant_staff para esse restaurante
-- pode escrever em products/categories/tables/restaurants ou mudar o estado de um pedido.
-- ============================================================
alter table restaurants enable row level security;
alter table restaurant_staff enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table tables enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;

-- leitura pública
create policy "public read restaurants" on restaurants for select using (true);
create policy "public read categories" on categories for select using (active = true);
create policy "public read products" on products for select using (available = true);
create policy "public read tables" on tables for select using (active = true);

-- pedidos: qualquer pessoa cria; leitura pública por id (o UUID não é adivinhável,
-- suficiente para o MVP acompanhar o próprio pedido — não é uma conta de cliente)
create policy "public insert orders" on orders for insert with check (true);
create policy "public insert order_items" on order_items for insert with check (true);
create policy "public read orders" on orders for select using (true);
create policy "public read order_items" on order_items for select using (true);

-- staff: pode gerir tudo do seu próprio restaurante
create policy "staff manage categories" on categories for all using (
  exists (select 1 from restaurant_staff s where s.restaurant_id = categories.restaurant_id and s.user_id = auth.uid())
);
create policy "staff manage products" on products for all using (
  exists (select 1 from restaurant_staff s where s.restaurant_id = products.restaurant_id and s.user_id = auth.uid())
);
create policy "staff manage tables" on tables for all using (
  exists (select 1 from restaurant_staff s where s.restaurant_id = tables.restaurant_id and s.user_id = auth.uid())
);
create policy "staff update restaurant" on restaurants for update using (
  exists (select 1 from restaurant_staff s where s.restaurant_id = restaurants.id and s.user_id = auth.uid())
);
create policy "staff update orders" on orders for update using (
  exists (select 1 from restaurant_staff s where s.restaurant_id = orders.restaurant_id and s.user_id = auth.uid())
);
create policy "staff read own staff row" on restaurant_staff for select using (user_id = auth.uid());

-- ============================================================
-- DADOS DE DEMONSTRAÇÃO — NŌMA
-- ============================================================
insert into restaurants (slug, name, description, address, phone, opening_hours, primary_color, secondary_color)
values ('noma','NŌMA','Cozinha contemporânea num ambiente elegante e acolhedor.',
        'Rua das Flores 42, 1200-195 Lisboa','+351 21 000 0000',
        'Terça a Domingo · 12h00–15h00 e 19h00–23h00','#9C7A3C','#18150F');

-- categorias (usa o id do restaurante acima)
insert into categories (restaurant_id, name, display_order)
select id, c.name, c.ord from restaurants, (values
 ('Entradas',1),('Sopas',2),('Carne',3),('Peixe',4),
 ('Acompanhamentos',5),('Sobremesas',6),('Bebidas',7)
) as c(name,ord) where restaurants.slug='noma';

-- mesas 1 a 12
insert into tables (restaurant_id, table_number, active)
select id, n, true from restaurants, generate_series(1,12) as n where slug='noma';

-- produtos (associados por nome de categoria)
insert into products (restaurant_id, category_id, name, description, price, display_order)
select r.id, c.id, p.name, p.desc, p.price, p.ord
from restaurants r
join categories c on c.restaurant_id = r.id
join (values
 ('Entradas','Pão artesanal','Pão da casa, manteiga com ervas',2.50,1),
 ('Entradas','Tábua de queijos','Seleção de queijos nacionais, compota',9.50,2),
 ('Entradas','Croquetes de carne','Croquetes caseiros, maionese de mostarda',6.50,3),
 ('Entradas','Camarão ao alho','Camarão salteado em azeite e alho',10.50,4),
 ('Sopas','Sopa do dia','Receita tradicional, atualizada diariamente',3.50,1),
 ('Sopas','Creme de legumes','Legumes da época, fio de azeite',4.00,2),
 ('Carne','Bife da casa','Bife de novilho grelhado, molho da casa e batata',18.50,1),
 ('Carne','Bife com molho de cogumelos','Novilho grelhado, molho cremoso de cogumelos',20.50,2),
 ('Carne','Entrecôte grelhado','Entrecôte maturado, grelhado no ponto',23.00,3),
 ('Carne','Hambúrguer NŌMA','Blend da casa, queijo, molho especial, batata',15.50,4),
 ('Peixe','Bacalhau à Brás','Bacalhau desfiado, batata palha, ovo',16.50,1),
 ('Peixe','Dourada grelhada','Dourada fresca grelhada, legumes salteados',17.50,2),
 ('Peixe','Salmão grelhado','Salmão grelhado, legumes da época',18.50,3),
 ('Peixe','Polvo à lagareiro','Polvo assado, batata a murro, azeite',21.00,4),
 ('Acompanhamentos','Batata frita','Batata frita crocante',3.00,1),
 ('Acompanhamentos','Batata doce','Batata doce assada',3.50,2),
 ('Acompanhamentos','Arroz','Arroz branco solto',2.50,3),
 ('Acompanhamentos','Salada','Salada verde da época',3.00,4),
 ('Acompanhamentos','Legumes grelhados','Legumes grelhados no momento',3.50,5),
 ('Sobremesas','Cheesecake','Cremoso, coulis de frutos vermelhos',5.50,1),
 ('Sobremesas','Mousse de chocolate','Chocolate negro 70%',5.00,2),
 ('Sobremesas','Brownie com gelado','Brownie quente, gelado de baunilha',6.00,3),
 ('Sobremesas','Fruta da época','Seleção de fruta fresca',4.00,4),
 ('Bebidas','Água','Água mineral natural, 33cl',1.50,1),
 ('Bebidas','Água com gás','Água mineral com gás, 33cl',1.80,2),
 ('Bebidas','Coca-Cola','Lata, 33cl',2.00,3),
 ('Bebidas','Coca-Cola Zero','Lata, 33cl',2.00,4),
 ('Bebidas','Ice Tea','Lata, 33cl',2.00,5),
 ('Bebidas','Limonada','Limonada natural da casa',3.00,6)
) as p(cat,name,"desc",price,ord) on p.cat = c.name
where r.slug='noma';

-- ============================================================
-- CRIAR O TEU UTILIZADOR ADMIN (faz isto manualmente, não por SQL):
-- 1. Supabase > Authentication > Users > Add user (email + password)
-- 2. Copia o UUID desse utilizador
-- 3. Corre (substitui o UUID e mantém o slug 'noma'):
--
-- insert into restaurant_staff (user_id, restaurant_id)
-- select 'COLA-AQUI-O-UUID-DO-UTILIZADOR', id from restaurants where slug='noma';
-- ============================================================
