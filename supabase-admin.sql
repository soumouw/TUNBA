-- =====================================================================
-- TUNBA — 2/3 : donner le rôle admin à UN utilisateur existant.
-- Dans SQL Editor uniquement, jamais depuis le navigateur.
-- 1) Crée d'abord le compte sur le site, confirme son e-mail.
-- 2) Supabase > Authentication > Users : copie l'UUID de l'utilisateur.
-- 3) Remplace VOTRE-UUID ci-dessous (garde les apostrophes), puis exécute.
-- =====================================================================
insert into public.user_roles (user_id, role)
values ('VOTRE-UUID', 'admin')
on conflict (user_id) do update set role = 'admin';
