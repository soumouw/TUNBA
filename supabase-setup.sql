-- =====================================================================
-- TUNBA — 1/3 : catalogue, rôles, RLS.   ORDRE : setup -> admin -> orders
-- À exécuter dans Supabase > SQL Editor.
-- RÉSERVÉ À UN PROJET NEUF (ou sans tables "products" / "user_roles").
-- Si ces tables existent déjà : ne l'exécute pas tel quel, écris une migration
-- adaptée à ton schéma. Ce script ne supprime aucune table ni donnée ;
-- il peut être relancé (create if not exists / on conflict do nothing).
-- Prix en MILLIMES (1 DT = 1000 millimes) : 65 DT = 65000.
-- =====================================================================

create table if not exists public.products (
  id             text primary key check (id ~ '^[a-z0-9_-]{1,40}$'),
  name           text not null check (char_length(name) between 1 and 120),
  category       text not null check (category in ('Homme','Femme','Unisex','Enfants')),
  description    text not null default '' check (char_length(description) <= 1000),
  price_millimes integer not null check (price_millimes > 0),
  image          text not null check (image ~ '^(images/[A-Za-z0-9_.-]+|https://[^[:space:]]+)$'),
  features       text not null default '' check (char_length(features) <= 500),
  available      boolean not null default true,
  created_at     timestamptz not null default now()
);

-- Seuls les administrateurs ont une ligne ici. Pas de ligne = compte client.
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role    text not null check (role = 'admin')
);

-- Vrai si l'utilisateur connecté est admin. SECURITY DEFINER pour que les
-- politiques RLS puissent lire user_roles sans récursion.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_roles r where r.user_id = (select auth.uid()) and r.role = 'admin');
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Droits SQL (en plus de RLS)
alter table public.products   enable row level security;
alter table public.user_roles enable row level security;
revoke all on public.products, public.user_roles from anon, authenticated;
grant select on public.products to anon;
grant select, insert, update, delete on public.products to authenticated;
grant select on public.user_roles to authenticated;   -- aucun insert/update/delete : impossible depuis le navigateur

-- Politiques
drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products for select to anon, authenticated using (available);
drop policy if exists products_admin_read on public.products;
create policy products_admin_read on public.products for select to authenticated using (public.is_admin());
drop policy if exists products_admin_insert on public.products;
create policy products_admin_insert on public.products for insert to authenticated with check (public.is_admin());
drop policy if exists products_admin_update on public.products;
create policy products_admin_update on public.products for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists products_admin_delete on public.products;
create policy products_admin_delete on public.products for delete to authenticated using (public.is_admin());
drop policy if exists roles_read_own on public.user_roles;
create policy roles_read_own on public.user_roles for select to authenticated using (user_id = (select auth.uid()));

-- Données initiales (celles du site). Catégorie « Unisex » : choix par défaut, modifiable dans la page admin.
insert into public.products (id, name, category, description, price_millimes, image, features) values
  ('p1', 'Sac à dos Nike',                          'Unisex', 'Sac à dos Nike',                65000, 'images/sac1.jpg',   'Trendy'),
  ('p2', 'Sac à dos The North Face',                'Unisex', 'Sac à dos The North Face',      80000, 'images/sac2_2.jpg', 'Cool'),
  ('p3', 'Sac à dos The North Face (grand espace)', 'Unisex', 'Sac à dos The North Face',      95000, 'images/sac2_3.jpg', 'Grand espace, pour le camping')
on conflict (id) do nothing;
