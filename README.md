# BiblioTech — application mobile Flutter + API temps réel

```
bibliotheque/
├── backend/          API Node.js/Express + PostgreSQL (Supabase) + WebSocket
│   └── public/       Version navigateur de l'app (build Flutter web)
├── mobile/           Application Flutter (Android / iOS / navigateur)
└── render.yaml       Déploiement Render (Blueprint)
```

**En ligne :** https://bibliotech-api-0n19.onrender.com (app web + API) — base Supabase `bibliotech` (Frankfurt).
APK Android : `BiblioTech.apk` (non versionné, se recompile avec la commande de la section 3).

**Base de données : PostgreSQL hébergé sur Supabase.** 5 tables : `utilisateurs`,
`livres`, `emprunts`, `demandes`, `amendes`. Elles sont créées automatiquement
au premier démarrage du serveur, avec 8 livres et le compte administrateur.

---

## 1. Supabase (base de données)

1. https://supabase.com → **New project** (notez le mot de passe de la base).
2. Bouton **Connect** (en haut) → onglet **Connection string** → **Session pooler**
   (compatible IPv4, obligatoire pour Render). Copiez l'URI :
   `postgresql://postgres.<ref>:<MOT_DE_PASSE>@aws-0-<region>.pooler.supabase.com:5432/postgres`
3. Remplacez `<MOT_DE_PASSE>`. S'il contient `@ : / ? #`, encodez-le
   (ex. `@` → `%40`).

Les tables sont visibles dans Supabase → **Table Editor**.

## 2. Render (serveur en ligne)

1. Poussez ce dossier sur GitHub.
2. https://dashboard.render.com → **New → Blueprint** → choisissez le dépôt.
   Render lit `render.yaml`.
3. Renseignez les variables demandées :
   - `DATABASE_URL` : l'URI Supabase de l'étape 1
   - `ADMIN_EMAIL` / `ADMIN_PASSWORD` : le compte administrateur créé au 1er démarrage
   (`JWT_SECRET` est généré automatiquement.)
4. **Apply**. Une fois déployé : `https://bibliotech-api-0n19.onrender.com`
   - l'app dans le navigateur : cette URL
   - l'API : `…/api/stats`

Offre gratuite Render : le serveur s'endort après 15 min sans visite ; la
première requête suivante prend ~30-60 s. Les données sont dans Supabase, rien n'est perdu.

## 3. L'application

**Dans le navigateur** : ouvrez l'URL Render (affichage en format téléphone).

**APK Android pointant sur Render :**
```bash
cd mobile
flutter build apk --release --dart-define=API_URL=https://bibliotech-api-0n19.onrender.com
# -> build/app/outputs/flutter-apk/app-release.apk
```
(L'adresse reste modifiable dans l'app via l'icône « Serveur ».)

**Mettre à jour la version navigateur** après une modification de l'app :
```bash
cd mobile && flutter build web --release
rm -rf ../backend/public && cp -r build/web ../backend/public
git add -A && git commit -m "Mise a jour app web" && git push   # Render redéploie
```

## 4. Développement local

```bash
cd backend
cp .env.example .env        # mettre l'URI Supabase dans DATABASE_URL
npm install
npm run dev                 # http://localhost:3000 (app web + API)

cd ../mobile
flutter run -d chrome       # ou un téléphone / émulateur
```

| Variable          | Défaut                     | Rôle                                   |
|-------------------|----------------------------|----------------------------------------|
| `DATABASE_URL`    | (obligatoire)              | Connexion PostgreSQL / Supabase        |
| `JWT_SECRET`      | `change-moi-en-production` | Signature des sessions — **à changer** |
| `ADMIN_EMAIL`     | `admin@bibliotech.local`   | Admin créé si la base est vide         |
| `ADMIN_PASSWORD`  | `admin123`                 | idem — **à changer**                   |
| `AMENDE_PAR_JOUR` | 0.5                        | Montant (€) par jour de retard         |
| `PORT`            | 3000                       | Port HTTP (fourni par Render)          |
| `DB_SSL`          | activé                     | `false` pour un PostgreSQL local       |

## Fonctionnalités

**Public** : statistiques, catalogue, connexion / inscription.

**Membre** : catalogue + recherche, réservation d'un livre (1–90 jours),
suivi / annulation de ses demandes, ses emprunts, signalement de retour, ses amendes.

**Administrateur** : tableau de bord, ajout / modification / suppression de
livres, validation / refus des réservations (avec motif), confirmation des
retours, emprunt direct (membre ou personne externe), retours, amendes
automatiques en cas de retard, paiement des amendes.

**Temps réel** : chaque modification est poussée par WebSocket à toutes les
apps ouvertes (indicateur « Direct » ; reconnexion automatique).

## Sécurité

- Mots de passe hachés (bcrypt), sessions par jeton JWT (30 jours).
- Les routes d'administration vérifient le rôle **côté serveur**.
- Un membre ne voit / modifie que ses propres demandes, emprunts et amendes.
- Transactions + verrous (`FOR UPDATE`) : un livre ne peut pas être prêté deux fois.
