-- =====================================================================
-- TUNBA — 3/3 : commandes simulées.  À exécuter APRÈS supabase-setup.sql.
-- Relançable sans supprimer les commandes (create if not exists / or replace).
-- Paiement simulé : aucune donnée bancaire n'est stockée.
-- =====================================================================

create table if not exists public.orders (
  id                uuid primary key default gen_random_uuid(),
  reference         text not null unique,
  user_id           uuid not null references auth.users(id),
  attempt_id        uuid not null,
  created_at        timestamptz not null default now(),
  items             jsonb not null,          -- instantané : id, nom, prix (millimes), quantité
  delivery          jsonb not null,          -- prenom, nom, email, tel, adresse, ville, cp, pays
  payment           text not null check (payment in ('Carte bancaire — Démonstration','D17 — Démonstration','Paiement à la livraison — Démonstration')),
  subtotal_millimes integer not null check (subtotal_millimes >= 0),
  shipping_millimes integer not null check (shipping_millimes >= 0),
  total_millimes    integer not null check (total_millimes >= 0),
  status            text not null default 'Nouvelle' check (status in ('Nouvelle','En préparation','Terminée','Annulée')),
  unique (user_id, attempt_id)               -- une même tentative ne crée jamais deux commandes
);
create index if not exists orders_user_created_idx on public.orders (user_id, created_at desc);

alter table public.orders enable row level security;
revoke all on public.orders from anon, authenticated;
grant select on public.orders to authenticated;
grant update (status) on public.orders to authenticated;   -- seul le statut est modifiable (et seulement par un admin, voir RLS)

drop policy if exists orders_read_own on public.orders;
create policy orders_read_own on public.orders for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists orders_admin_read on public.orders;
create policy orders_admin_read on public.orders for select to authenticated using (public.is_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update to authenticated using (public.is_admin()) with check (public.is_admin());
-- Pas de politique INSERT : on ne crée une commande que via la fonction ci-dessous.

create or replace function public.create_demo_order(
  p_attempt_id uuid, p_items jsonb, p_delivery jsonb, p_payment text, p_expected_total integer default null)
returns public.orders
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  o public.orders; lines jsonb; d jsonb := '{}'::jsonb;
  n_ids int; n_found int; sub int; ship int; k text; v text; i int;
begin
  if uid is null then raise exception 'Connexion requise.'; end if;
  if p_attempt_id is null then raise exception 'Tentative invalide.'; end if;

  -- Même tentative déjà enregistrée (nouvel essai après une coupure réseau) : on renvoie la commande existante.
  select * into o from public.orders where user_id = uid and attempt_id = p_attempt_id;
  if found then return o; end if;

  if p_payment not in ('Carte bancaire — Démonstration','D17 — Démonstration','Paiement à la livraison — Démonstration') then
    raise exception 'Moyen de paiement invalide.'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Panier invalide.'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) e
             where coalesce(e->>'id','') = ''
                or case when (e->>'qty') ~ '^[0-9]{1,2}$' then (e->>'qty')::int else 0 end not between 1 and 20) then
    raise exception 'Quantité invalide (1 à 20 par produit).'; end if;

  -- Coordonnées : on reconstruit un objet propre (aucune clé inattendue)
  if jsonb_typeof(p_delivery) is distinct from 'object' then raise exception 'Livraison invalide.'; end if;
  foreach k in array array['prenom','nom','email','tel','adresse','ville','cp','pays'] loop
    v := btrim(coalesce(p_delivery ->> k, ''));
    if v = '' or char_length(v) > 200 then raise exception 'Livraison invalide : champ « % ».', k; end if;
    d := d || jsonb_build_object(k, v);
  end loop;

  -- Prix et noms lus dans le catalogue (jamais envoyés par le navigateur)
  select count(*), coalesce(sum(p.price_millimes * g.qty), 0),
         jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'price_millimes', p.price_millimes, 'qty', g.qty) order by p.id)
    into n_found, sub, lines
    from (select e->>'id' as id, sum((e->>'qty')::int) as qty from jsonb_array_elements(p_items) e group by 1) g
    join public.products p on p.id = g.id and p.available;
  select count(distinct e->>'id') into n_ids from jsonb_array_elements(p_items) e;
  if n_found <> n_ids then raise exception 'Un produit du panier n''est plus disponible.'; end if;

  ship := case when sub >= 350000 then 0 else 7000 end;   -- 7 DT, offerts dès 350 DT
  if p_expected_total is not null and p_expected_total <> sub + ship then
    raise exception 'PRIX_MODIFIES : les prix ont changé, vérifie ton panier.'; end if;

  for i in 1..5 loop
    begin
      insert into public.orders (reference, user_id, attempt_id, items, delivery, payment, subtotal_millimes, shipping_millimes, total_millimes)
      values ('TUNBA-' || to_char(now(), 'YYYYMMDD') || '-' || substr(upper(replace(gen_random_uuid()::text, '-', '')), 1, 6),
              uid, p_attempt_id, lines, d, p_payment, sub, ship, sub + ship)
      returning * into o;
      return o;
    exception when unique_violation then
      select * into o from public.orders where user_id = uid and attempt_id = p_attempt_id;
      if found then return o; end if;      -- sinon : référence déjà prise, on réessaie
    end;
  end loop;
  raise exception 'Impossible de créer la commande, réessaie.';
end;
$$;
revoke all on function public.create_demo_order(uuid, jsonb, jsonb, text, integer) from public, anon;
grant execute on function public.create_demo_order(uuid, jsonb, jsonb, text, integer) to authenticated;
