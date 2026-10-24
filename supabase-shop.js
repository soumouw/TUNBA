/* Accès à Supabase : comptes, catalogue, commandes, administration.
   La vraie sécurité est dans la base (RLS, voir les fichiers .sql) : masquer un
   bouton ou une page en JavaScript ne protège rien. */
const Shop = (function () {
  const MILLIMES = 1000; // 1 DT = 1000 millimes (la base stocke des entiers)

  function need() {
    if (!sb) throw new Error('Supabase n\'est pas configuré : renseigne supabase-client.js (voir SUPABASE.md).');
    return sb;
  }
  function friendly(error, fallback) {
    console.error(error);
    const m = error.message || '';
    if (m.includes('Failed to fetch') || m.includes('NetworkError')) return 'Connexion impossible : vérifie ta connexion internet puis réessaie.';
    if (error.code === '23505') return 'Cet identifiant existe déjà.';
    if (error.code === '42501' || error.code === 'PGRST301') return 'Accès refusé.';
    if (error.code === 'PGRST205' || error.code === '42P01') return 'Table introuvable : exécute les scripts SQL (voir SUPABASE.md).';
    if (error.code === 'P0001') return m; // messages écrits dans nos fonctions SQL
    return fallback;
  }
  async function run(query, fallback) {
    const r = await query;
    if (r.error) throw new Error(friendly(r.error, fallback));
    return r.data;
  }
  const dt = n => n / MILLIMES;
  function toOrder(r) {
    return { id: r.id, ref: r.reference, date: r.created_at, status: r.status, payment: r.payment, delivery: r.delivery,
      items: (r.items || []).map(i => ({ id: i.id, name: i.name, price: dt(i.price_millimes), qty: i.qty })),
      subtotal: dt(r.subtotal_millimes), shipping: dt(r.shipping_millimes), total: dt(r.total_millimes) };
  }
  function toProduct(r) {
    return { id: r.id, name: r.name, category: r.category, description: r.description, features: r.features,
      price: dt(r.price_millimes), image: r.image, available: r.available };
  }

  /* ----- Comptes (Supabase Auth) ----- */
  async function getUser() {
    if (!sb) return null;
    const { data } = await sb.auth.getSession();
    const u = data.session && data.session.user;
    return u ? { id: u.id, email: u.email, firstName: (u.user_metadata || {}).first_name || '', lastName: (u.user_metadata || {}).last_name || '', confirmed: !!u.email_confirmed_at } : null;
  }
  async function signUp(p) {
    const { data, error } = await need().auth.signUp({ email: p.email, password: p.password,
      options: { data: { first_name: p.firstName, last_name: p.lastName }, emailRedirectTo: new URL('verification.html', location.href).href } });
    if (error) throw new Error(error.message.includes('Password') ? 'Mot de passe refusé : ' + error.message : friendly(error, 'Inscription impossible.'));
    return { loggedIn: !!data.session };
  }
  async function resendConfirmation(email) {
    const { error } = await need().auth.resend({ type: 'signup', email: email, options: { emailRedirectTo: new URL('verification.html', location.href).href } });
    if (error) throw new Error(friendly(error, 'Envoi impossible pour le moment.'));
  }
  async function signIn(email, password) {
    const { error } = await need().auth.signInWithPassword({ email: email, password: password });
    if (error) {
      if (/not confirmed/i.test(error.message)) throw new Error('Adresse e-mail non confirmée : ouvre le lien reçu par e-mail.');
      if (/invalid login/i.test(error.message)) throw new Error('E-mail ou mot de passe incorrect.');
      throw new Error(friendly(error, 'Connexion impossible.'));
    }
  }
  async function signOut() { if (sb) await sb.auth.signOut(); }
  async function isAdmin(userId) { // lit SA propre ligne (RLS) ; la vraie protection est dans la base
    const d = await run(need().from('user_roles').select('role').eq('user_id', userId).maybeSingle(), 'Rôle illisible.');
    return !!d && d.role === 'admin';
  }

  /* ----- Catalogue ----- */
  async function fetchProducts() {
    const d = await run(need().from('products').select('*').eq('available', true).order('created_at'), 'Catalogue indisponible.');
    return d.map(toProduct);
  }

  /* ----- Commandes ----- */
  async function createOrder(attemptId, items, delivery, payment, expectedTotal) {
    const d = await run(need().rpc('create_demo_order', { p_attempt_id: attemptId, p_items: items, p_delivery: delivery, p_payment: payment, p_expected_total: Math.round(expectedTotal * MILLIMES) }), 'Commande impossible.');
    return toOrder(d);
  }
  async function myOrders(limit) {
    const d = await run(need().from('orders').select('*').order('created_at', { ascending: false }).limit(limit), 'Commandes illisibles.');
    return d.map(toOrder);
  }
  async function orderByRef(ref) {
    const d = await run(need().from('orders').select('*').eq('reference', ref).maybeSingle(), 'Commande illisible.');
    return d ? toOrder(d) : null;
  }

  /* ----- Administration (autorisée par RLS seulement pour les admins) ----- */
  async function adminOrders(status, offset, size) {
    let q = need().from('orders').select('*').order('created_at', { ascending: false }).range(offset, offset + size - 1);
    if (status) q = q.eq('status', status);
    return (await run(q, 'Commandes illisibles.')).map(toOrder);
  }
  async function setOrderStatus(id, oldStatus, newStatus) { // échoue si quelqu'un d'autre l'a déjà modifiée
    const d = await run(need().from('orders').update({ status: newStatus }).eq('id', id).eq('status', oldStatus).select('id'), 'Mise à jour impossible.');
    return d.length === 1;
  }
  async function adminProducts() {
    return (await run(need().from('products').select('*').order('created_at'), 'Produits illisibles.')).map(toProduct);
  }
  async function saveProduct(p, isNew) {
    const row = { name: p.name, category: p.category, description: p.description, features: p.features,
      price_millimes: Math.round(p.price * MILLIMES), image: p.image, available: p.available };
    if (isNew) await run(need().from('products').insert(Object.assign({ id: p.id }, row)), 'Enregistrement impossible.');
    else await run(need().from('products').update(row).eq('id', p.id), 'Enregistrement impossible.');
  }
  async function deleteProduct(id) { await run(need().from('products').delete().eq('id', id), 'Suppression impossible.'); }

  return { getUser, signUp, resendConfirmation, signIn, signOut, isAdmin, fetchProducts, createOrder, myOrders, orderByRef,
    adminOrders, setOrderStatus, adminProducts, saveProduct, deleteProduct };
})();
