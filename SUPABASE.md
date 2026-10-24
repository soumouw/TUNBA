# TUNBA × Supabase — guide pas à pas

Le site reste en HTML/CSS/JavaScript natif. Supabase fournit les comptes (Auth), le catalogue, les commandes et les rôles. Le paiement reste **simulé**.

## 1. Créer le projet Supabase
1. Va sur supabase.com, connecte-toi, clique **New project**.
2. Choisis un nom (ex. `tunba`), un mot de passe de base de données (garde-le pour toi, il n'est jamais mis dans le site) et la région la plus proche. Attends la fin de la création.

## 2. Récupérer l'URL et la clé publique
1. Menu **Project Settings → API Keys** (et **Data API** pour l'URL).
2. Copie la **Project URL** (`https://xxxx.supabase.co`) et la clé **Publishable** (`sb_publishable_...`). Si ton projet n'a que des clés « anon », utilise la clé `anon public`.
3. Colle-les dans `supabase-client.js`. **Ne colle jamais** une clé `secret` ou `service_role`.

## 3. Exécuter les scripts SQL (dans cet ordre)
Menu **SQL Editor → New query**, colle le contenu du fichier, puis **Run**.
1. `supabase-setup.sql` : catalogue, rôles, RLS (projet neuf uniquement : si tu as déjà des tables `products` ou `user_roles`, ne l'exécute pas tel quel).
2. `supabase-orders.sql` : commandes et fonction `create_demo_order`.
3. `supabase-admin.sql` : à faire **après l'étape 5** (il faut un compte).
Les scripts 1 et 2 peuvent être relancés sans rien supprimer.

## 4. Configurer l'authentification
**Authentication → URL Configuration** :
- **Site URL** : `http://localhost:8000` pour tester en local (remplace-la par l'URL Vercel après le déploiement).
- **Redirect URLs** : ajoute `http://localhost:8000/**`, `http://127.0.0.1:5500/**` (Live Server) et `https://TON-PROJET.vercel.app/**`.

**Authentication → Providers → Email** : laisse **Confirm email** activé. L'envoi d'e-mails par défaut de Supabase est limité (quelques e-mails par heure) et peut finir dans les courriers indésirables.

## 5. Créer un compte et le confirmer
1. Lance le site (`python -m http.server 8000`, puis `http://localhost:8000`).
2. Ouvre `inscription.html`, crée un compte avec une vraie adresse e-mail.
3. Ouvre le lien reçu par e-mail. Si rien n'arrive : bouton « Renvoyer l'e-mail », ou, pour un test seulement, **Authentication → Users → ⋯ → Confirm user** dans Supabase.

## 6. Devenir administrateur
1. **Authentication → Users** : copie l'**UUID** de ton utilisateur.
2. Ouvre `supabase-admin.sql`, remplace `VOTRE-UUID` (garde les apostrophes), puis exécute-le dans SQL Editor.
3. Reconnecte-toi : le lien **Admin** apparaît dans le menu (`admin.html`).

## 7. Tests à faire (avec de vraies sessions)
Ne teste pas les droits dans SQL Editor : il contourne RLS.
- **Visiteur** (déconnecté) : voit les produits ; `admin.html` et `compte.html` le renvoient vers la connexion.
- **Client A** : commande 2 articles → commande visible dans son compte, panier vidé seulement après succès. Coupe internet pendant « Simuler le paiement » puis réessaie : une seule commande doit exister.
- **Client B** : ne voit pas les commandes de A ; `admin.html` affiche « Accès réservé ».
- **Admin** : voit toutes les commandes, change un statut, ajoute/modifie/supprime un produit.
- Modifie un prix en admin pendant qu'un client est sur le checkout : il doit voir « Les prix ont changé ».

## 8. Erreurs fréquentes
| Message | Cause / solution |
|---|---|
| « Supabase n'est pas configuré » | `supabase-client.js` contient encore `VOTRE-...`. |
| « Table introuvable » | Les scripts SQL n'ont pas été exécutés (étape 3). |
| « Adresse e-mail non confirmée » | Ouvre le lien de l'e-mail (étape 5). |
| Le lien de l'e-mail pointe vers `localhost` en ligne | Mets l'URL Vercel dans **Site URL** (étape 4). |
| « Accès refusé » | Pas le bon rôle, ou session expirée : reconnecte-toi. |
| Admin : « modifiée entre-temps » | Quelqu'un a changé le statut : clique sur Actualiser. |
| Images cassées | Copie `TUNBAlogo.png`, `sac1.jpg`, `sac2_2.jpg`, `sac2_3.jpg` dans `images/`. |

## 9. Déployer sur Vercel (adresse `vercel.app`)
1. Mets le dossier du site dans un dépôt **GitHub** (`index.html` à la racine du dépôt, ou note le sous-dossier). Ne mets jamais de clé secret dans le dépôt.
2. Sur vercel.com : **Add New → Project**, importe le dépôt.
3. **Framework Preset : Other**. **Root Directory** : le dossier qui contient `index.html`.
4. **Build Command** : vide (laisse « Override » activé et vide). **Output Directory** : `.` (ou vide). Pas d'install command.
5. Clique **Deploy** puis note l'URL `https://xxx.vercel.app`.
6. Dans Supabase **Authentication → URL Configuration** : mets cette URL dans **Site URL** et ajoute `https://xxx.vercel.app/**` aux **Redirect URLs**.
7. Reteste sur l'URL HTTPS finale : inscription (e-mail), connexion, commande, admin.
