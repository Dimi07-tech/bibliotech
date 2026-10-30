// ============================================================
// server.js — API BiblioTech + temps reel (WebSocket) + app web
// ============================================================
const http = require('http');
const path = require('path');
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { WebSocketServer } = require('ws');
const { db, transaction, couvertureParIsbn, initialiser } = require('./db');

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'change-moi-en-production';
const AMENDE_PAR_JOUR = parseFloat(process.env.AMENDE_PAR_JOUR || '0.5');
const JOUR_MS = 24 * 60 * 60 * 1000;

const app = express();
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json());

app.get('/healthz', (req, res) => res.json({ ok: true }));

// ============================================================
// TEMPS REEL
// ============================================================
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    ws.send(JSON.stringify({ type: 'hello' }));
});

// Ping pour detecter les connexions mortes (reseau mobile, proxy Render)
setInterval(() => {
    for (const ws of wss.clients) {
        if (!ws.isAlive) { ws.terminate(); continue; }
        ws.isAlive = false;
        ws.ping();
    }
}, 30000);

// Notifie tous les clients qu'une ressource a change ; ils rechargent ce qui les concerne
function diffuser(...entites) {
    const msg = JSON.stringify({ type: 'change', entites });
    for (const ws of wss.clients) {
        if (ws.readyState === ws.OPEN) ws.send(msg);
    }
}

// ============================================================
// AUTH
// ============================================================
function signer(u) {
    return jwt.sign({ id: u.id, role: u.role }, JWT_SECRET, { expiresIn: '30d' });
}

function publicUser(u) {
    return { id: u.id, nom: u.nom, email: u.email, role: u.role };
}

async function auth(req, res, next) {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) return res.status(401).json({ erreur: 'Authentification requise' });
    let payload;
    try {
        payload = jwt.verify(token, JWT_SECRET);
    } catch {
        return res.status(401).json({ erreur: 'Session expiree, reconnectez-vous' });
    }
    const u = await db.one('SELECT * FROM utilisateurs WHERE id = $1', [payload.id]);
    if (!u) return res.status(401).json({ erreur: 'Utilisateur introuvable' });
    req.user = publicUser(u);
    next();
}

function admin(req, res, next) {
    if (req.user?.role !== 'admin') return res.status(403).json({ erreur: 'Acces reserve a l\'administrateur' });
    next();
}

app.post('/api/auth/inscription', async (req, res) => {
    const { nom, email, motDePasse } = req.body || {};
    if (!nom?.trim() || !email?.trim() || !motDePasse) return res.status(400).json({ erreur: 'Tous les champs sont obligatoires' });
    if (motDePasse.length < 6) return res.status(400).json({ erreur: 'Mot de passe : 6 caracteres minimum' });
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ erreur: 'Email invalide' });
    if (await db.one('SELECT 1 FROM utilisateurs WHERE lower(email) = lower($1)', [email.trim()])) {
        return res.status(409).json({ erreur: 'Cet email est deja utilise' });
    }
    const u = await db.one('INSERT INTO utilisateurs (nom, email, mot_de_passe) VALUES ($1, $2, $3) RETURNING *',
        [nom.trim(), email.trim(), bcrypt.hashSync(motDePasse, 10)]);
    diffuser('stats');
    res.status(201).json({ token: signer(u), utilisateur: publicUser(u) });
});

app.post('/api/auth/connexion', async (req, res) => {
    const { email, motDePasse } = req.body || {};
    const u = await db.one('SELECT * FROM utilisateurs WHERE lower(email) = lower($1)', [(email || '').trim()]);
    if (!u || !bcrypt.compareSync(motDePasse || '', u.mot_de_passe)) {
        return res.status(401).json({ erreur: 'Email ou mot de passe incorrect' });
    }
    res.json({ token: signer(u), utilisateur: publicUser(u) });
});

app.get('/api/auth/moi', auth, (req, res) => res.json(req.user));

// ============================================================
// STATS (public)
// ============================================================
app.get('/api/stats', async (req, res) => {
    res.json(await db.one(`SELECT
        (SELECT COUNT(*)::int FROM livres) AS "totalLivres",
        (SELECT COUNT(*)::int FROM livres WHERE disponible) AS "livresDisponibles",
        (SELECT COUNT(*)::int FROM utilisateurs WHERE role = 'membre') AS "totalUtilisateurs",
        (SELECT COUNT(*)::int FROM emprunts) AS "totalEmprunts",
        (SELECT COUNT(*)::int FROM emprunts WHERE date_retour_effective IS NULL) AS "empruntsEnCours",
        (SELECT COUNT(*)::int FROM emprunts WHERE date_retour_effective IS NULL AND date_retour_prevue < now()) AS "empruntsEnRetard",
        (SELECT COUNT(*)::int FROM demandes WHERE statut = 'en_attente') AS "demandesEnAttente",
        (SELECT COUNT(*)::int FROM amendes) AS "totalAmendes",
        (SELECT COALESCE(SUM(montant), 0)::float FROM amendes) AS "montantTotalAmendes",
        (SELECT COALESCE(SUM(montant), 0)::float FROM amendes WHERE NOT payee) AS "montantImpaye"`));
});

// ============================================================
// LIVRES
// ============================================================
app.get('/api/livres', async (req, res) => {
    res.json(await db.q('SELECT * FROM livres ORDER BY titre'));
});

app.get('/api/livres/recherche', async (req, res) => {
    const q = `%${(req.query.q || '').trim()}%`;
    res.json(await db.q('SELECT * FROM livres WHERE titre ILIKE $1 OR auteur ILIKE $1 OR isbn ILIKE $1 OR genre ILIKE $1 ORDER BY titre', [q]));
});

app.get('/api/livres/:id', async (req, res) => {
    const l = await db.one('SELECT * FROM livres WHERE id = $1', [req.params.id]);
    if (!l) return res.status(404).json({ erreur: 'Livre introuvable' });
    res.json(l);
});

function validerLivre(body) {
    const { titre, auteur, isbn } = body || {};
    if (!titre?.trim() || !auteur?.trim() || !isbn?.trim()) return 'Titre, auteur et ISBN sont obligatoires';
    if (body.annee != null && body.annee !== '' && !Number.isInteger(Number(body.annee))) return 'Annee invalide';
    return null;
}

app.post('/api/livres', auth, admin, async (req, res) => {
    const err = validerLivre(req.body);
    if (err) return res.status(400).json({ erreur: err });
    const { titre, auteur, isbn, annee, genre, image } = req.body;
    if (await db.one('SELECT 1 FROM livres WHERE isbn = $1', [isbn.trim()])) return res.status(409).json({ erreur: 'Un livre avec cet ISBN existe deja' });
    const l = await db.one('INSERT INTO livres (titre, auteur, isbn, annee, genre, image) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
        [titre.trim(), auteur.trim(), isbn.trim(), annee ? Number(annee) : null, genre || 'Non classe', image?.trim() || couvertureParIsbn(isbn)]);
    diffuser('livres', 'stats');
    res.status(201).json(l);
});

app.put('/api/livres/:id', auth, admin, async (req, res) => {
    const l = await db.one('SELECT * FROM livres WHERE id = $1', [req.params.id]);
    if (!l) return res.status(404).json({ erreur: 'Livre introuvable' });
    const err = validerLivre(req.body);
    if (err) return res.status(400).json({ erreur: err });
    const { titre, auteur, isbn, annee, genre, image } = req.body;
    if (await db.one('SELECT 1 FROM livres WHERE isbn = $1 AND id != $2', [isbn.trim(), l.id])) return res.status(409).json({ erreur: 'Un livre avec cet ISBN existe deja' });
    const maj = await db.one('UPDATE livres SET titre = $1, auteur = $2, isbn = $3, annee = $4, genre = $5, image = $6 WHERE id = $7 RETURNING *',
        [titre.trim(), auteur.trim(), isbn.trim(), annee ? Number(annee) : null, genre || l.genre,
            image === undefined ? l.image : (image?.trim() || couvertureParIsbn(isbn)), l.id]);
    diffuser('livres', 'emprunts', 'demandes', 'amendes');
    res.json(maj);
});

app.delete('/api/livres/:id', auth, admin, async (req, res) => {
    const l = await db.one('SELECT * FROM livres WHERE id = $1', [req.params.id]);
    if (!l) return res.status(404).json({ erreur: 'Livre introuvable' });
    if (!l.disponible) return res.status(409).json({ erreur: 'Impossible : ce livre est actuellement emprunte' });
    const historique = await db.one('SELECT 1 FROM emprunts WHERE livre_id = $1 UNION SELECT 1 FROM demandes WHERE livre_id = $1', [l.id]);
    if (historique) return res.status(409).json({ erreur: 'Impossible : ce livre a un historique d\'emprunts/demandes' });
    await db.q('DELETE FROM livres WHERE id = $1', [l.id]);
    diffuser('livres', 'stats');
    res.json({ ok: true });
});

// ============================================================
// EMPRUNTS
// ============================================================
const SELECT_EMPRUNT = `
    SELECT e.id, e.livre_id AS "livreId", e.utilisateur_id AS "utilisateurId", e.emprunteur,
           e.date_emprunt AS "dateEmprunt", e.date_retour_prevue AS "dateRetourPrevue",
           e.date_retour_effective AS "dateRetourEffective",
           l.titre AS "titreLivre", l.auteur AS "auteurLivre", l.image AS "imageLivre",
           EXISTS (SELECT 1 FROM demandes d WHERE d.emprunt_id = e.id AND d.type = 'retour' AND d.statut = 'en_attente') AS "retourSignale"
    FROM emprunts e JOIN livres l ON l.id = e.livre_id`;

app.get('/api/emprunts', auth, admin, async (req, res) => {
    res.json(await db.q(`${SELECT_EMPRUNT} ORDER BY e.id DESC`));
});

app.get('/api/emprunts/en-cours', auth, admin, async (req, res) => {
    res.json(await db.q(`${SELECT_EMPRUNT} WHERE e.date_retour_effective IS NULL ORDER BY e.date_retour_prevue`));
});

app.get('/api/emprunts/moi', auth, async (req, res) => {
    res.json(await db.q(`${SELECT_EMPRUNT} WHERE e.utilisateur_id = $1 ORDER BY e.id DESC`, [req.user.id]));
});

// `t` = executeur de la transaction en cours
async function creerEmprunt(t, livreId, utilisateurId, emprunteur, dureeJours) {
    // FOR UPDATE : deux approbations simultanees ne peuvent pas preter le meme livre
    const livre = await t.one('SELECT * FROM livres WHERE id = $1 FOR UPDATE', [livreId]);
    if (!livre) throw httpErr(404, 'Livre introuvable');
    if (!livre.disponible) throw httpErr(409, 'Ce livre n\'est pas disponible');
    const duree = Math.min(Math.max(parseInt(dureeJours) || 14, 1), 90);
    const now = new Date();
    const e = await t.one('INSERT INTO emprunts (livre_id, utilisateur_id, emprunteur, date_emprunt, date_retour_prevue) VALUES ($1, $2, $3, $4, $5) RETURNING id',
        [livre.id, utilisateurId, emprunteur, now, new Date(now.getTime() + duree * JOUR_MS)]);
    await t.q('UPDATE livres SET disponible = FALSE WHERE id = $1', [livre.id]);
    return e.id;
}

app.post('/api/emprunts', auth, admin, async (req, res) => {
    const { livreId, utilisateurId, emprunteur, dureeJours } = req.body || {};
    let nom = emprunteur?.trim();
    let uid = null;
    if (utilisateurId) {
        const u = await db.one('SELECT * FROM utilisateurs WHERE id = $1', [utilisateurId]);
        if (!u) return res.status(404).json({ erreur: 'Membre introuvable' });
        uid = u.id; nom = u.nom;
    }
    if (!livreId || !nom) return res.status(400).json({ erreur: 'Livre et emprunteur obligatoires' });
    const id = await transaction((t) => creerEmprunt(t, livreId, uid, nom, dureeJours));
    diffuser('livres', 'emprunts', 'stats');
    res.status(201).json(await db.one(`${SELECT_EMPRUNT} WHERE e.id = $1`, [id]));
});

// ============================================================
// RETOURS
// ============================================================
async function retournerEmprunt(t, empruntId) {
    const e = await t.one('SELECT * FROM emprunts WHERE id = $1 FOR UPDATE', [empruntId]);
    if (!e) throw httpErr(404, 'Emprunt introuvable');
    if (e.date_retour_effective) throw httpErr(409, 'Ce livre a deja ete retourne');
    const now = new Date();
    await t.q('UPDATE emprunts SET date_retour_effective = $1 WHERE id = $2', [now, e.id]);
    await t.q('UPDATE livres SET disponible = TRUE WHERE id = $1', [e.livre_id]);
    // Toute demande de retour en attente sur cet emprunt est cloturee
    await t.q(`UPDATE demandes SET statut = 'approuvee', date_traitement = $1 WHERE emprunt_id = $2 AND type = 'retour' AND statut = 'en_attente'`,
        [now, e.id]);

    const retardMs = now - new Date(e.date_retour_prevue);
    const joursRetard = retardMs > 0 ? Math.ceil(retardMs / JOUR_MS) : 0;
    let amende = null;
    if (joursRetard > 0) {
        const montant = Math.round(joursRetard * AMENDE_PAR_JOUR * 100) / 100;
        const a = await t.one('INSERT INTO amendes (emprunt_id, jours_retard, montant) VALUES ($1, $2, $3) RETURNING id', [e.id, joursRetard, montant]);
        amende = { id: a.id, joursRetard, montant, payee: false };
    }
    return { enRetard: joursRetard > 0, joursRetard, amende };
}

app.post('/api/retours/:empruntId', auth, admin, async (req, res) => {
    const result = await transaction((t) => retournerEmprunt(t, req.params.empruntId));
    diffuser('livres', 'emprunts', 'demandes', 'amendes', 'stats');
    res.json(result);
});

// ============================================================
// AMENDES
// ============================================================
const SELECT_AMENDE = `
    SELECT a.id, a.emprunt_id AS "empruntId", a.jours_retard AS "joursRetard", a.montant, a.payee, a.date_paiement AS "datePaiement",
           e.emprunteur, e.utilisateur_id AS "utilisateurId", l.titre AS "titreLivre"
    FROM amendes a JOIN emprunts e ON e.id = a.emprunt_id JOIN livres l ON l.id = e.livre_id`;

app.get('/api/amendes', auth, admin, async (req, res) => {
    res.json(await db.q(`${SELECT_AMENDE} ORDER BY a.payee, a.id DESC`));
});

app.get('/api/amendes/moi', auth, async (req, res) => {
    res.json(await db.q(`${SELECT_AMENDE} WHERE e.utilisateur_id = $1 ORDER BY a.payee, a.id DESC`, [req.user.id]));
});

app.put('/api/amendes/:id/payer', auth, admin, async (req, res) => {
    const a = await db.one('SELECT * FROM amendes WHERE id = $1', [req.params.id]);
    if (!a) return res.status(404).json({ erreur: 'Amende introuvable' });
    if (a.payee) return res.status(409).json({ erreur: 'Amende deja payee' });
    await db.q('UPDATE amendes SET payee = TRUE, date_paiement = now() WHERE id = $1', [a.id]);
    diffuser('amendes', 'stats');
    res.json({ ok: true });
});

// ============================================================
// DEMANDES (reservations / retours)
// ============================================================
const SELECT_DEMANDE = `
    SELECT d.id, d.livre_id AS "livreId", d.utilisateur_id AS "utilisateurId", d.emprunt_id AS "empruntId",
           d.type, d.statut, d.duree_jours AS "dureeJours", d.date_demande AS "dateDemande",
           d.date_traitement AS "dateTraitement", d.commentaire_admin AS "commentaireAdmin",
           l.titre AS "titreLivre", l.auteur AS "auteurLivre", l.image AS "imageLivre", l.disponible AS "livreDisponible",
           u.nom AS "nomUtilisateur"
    FROM demandes d JOIN livres l ON l.id = d.livre_id JOIN utilisateurs u ON u.id = d.utilisateur_id`;

app.get('/api/demandes', auth, admin, async (req, res) => {
    res.json(await db.q(`${SELECT_DEMANDE} ORDER BY d.statut != 'en_attente', d.id DESC`));
});

app.get('/api/demandes/moi', auth, async (req, res) => {
    res.json(await db.q(`${SELECT_DEMANDE} WHERE d.utilisateur_id = $1 ORDER BY d.id DESC`, [req.user.id]));
});

// Un membre reserve un livre (demande d'emprunt)
app.post('/api/demandes', auth, async (req, res) => {
    const { livreId, dureeJours } = req.body || {};
    const livre = await db.one('SELECT * FROM livres WHERE id = $1', [livreId]);
    if (!livre) return res.status(404).json({ erreur: 'Livre introuvable' });
    if (!livre.disponible) return res.status(409).json({ erreur: 'Ce livre n\'est pas disponible' });
    const dejaDemande = await db.one(`SELECT 1 FROM demandes WHERE livre_id = $1 AND utilisateur_id = $2 AND type = 'emprunt' AND statut = 'en_attente'`,
        [livre.id, req.user.id]);
    if (dejaDemande) return res.status(409).json({ erreur: 'Vous avez deja une demande en attente pour ce livre' });
    const duree = Math.min(Math.max(parseInt(dureeJours) || 14, 1), 90);
    const d = await db.one(`INSERT INTO demandes (livre_id, utilisateur_id, type, duree_jours, date_demande) VALUES ($1, $2, 'emprunt', $3, now()) RETURNING id`,
        [livre.id, req.user.id, duree]);
    diffuser('demandes', 'stats');
    res.status(201).json(await db.one(`${SELECT_DEMANDE} WHERE d.id = $1`, [d.id]));
});

// Un membre annule sa propre demande en attente
app.delete('/api/demandes/:id', auth, async (req, res) => {
    const d = await db.one('SELECT * FROM demandes WHERE id = $1', [req.params.id]);
    if (!d || (d.utilisateur_id !== req.user.id && req.user.role !== 'admin')) return res.status(404).json({ erreur: 'Demande introuvable' });
    if (d.statut !== 'en_attente') return res.status(409).json({ erreur: 'Cette demande a deja ete traitee' });
    await db.q('DELETE FROM demandes WHERE id = $1', [d.id]);
    diffuser('demandes', 'emprunts', 'stats');
    res.json({ ok: true });
});

async function demandeEnAttente(t, id, type) {
    const d = await t.one('SELECT * FROM demandes WHERE id = $1 FOR UPDATE', [id]);
    if (!d) throw httpErr(404, 'Demande introuvable');
    if (d.statut !== 'en_attente') throw httpErr(409, 'Cette demande a deja ete traitee');
    if (d.type !== type) throw httpErr(400, 'Type de demande incorrect');
    return d;
}

app.put('/api/demandes/:id/approuver', auth, admin, async (req, res) => {
    await transaction(async (t) => {
        const d = await demandeEnAttente(t, req.params.id, 'emprunt');
        const u = await t.one('SELECT * FROM utilisateurs WHERE id = $1', [d.utilisateur_id]);
        const empruntId = await creerEmprunt(t, d.livre_id, u.id, u.nom, d.duree_jours);
        await t.q(`UPDATE demandes SET statut = 'approuvee', emprunt_id = $1, date_traitement = now(), commentaire_admin = $2 WHERE id = $3`,
            [empruntId, req.body?.commentaire || null, d.id]);
        // Les autres demandes en attente sur ce livre deviennent impossibles
        await t.q(`UPDATE demandes SET statut = 'refusee', date_traitement = now(), commentaire_admin = 'Livre emprunte par un autre membre'
                   WHERE livre_id = $1 AND type = 'emprunt' AND statut = 'en_attente' AND id != $2`, [d.livre_id, d.id]);
    });
    diffuser('livres', 'emprunts', 'demandes', 'stats');
    res.json({ ok: true });
});

app.put('/api/demandes/:id/refuser', auth, admin, async (req, res) => {
    await transaction(async (t) => {
        const d = await demandeEnAttente(t, req.params.id, 'emprunt');
        await t.q(`UPDATE demandes SET statut = 'refusee', date_traitement = now(), commentaire_admin = $1 WHERE id = $2`,
            [req.body?.commentaire?.trim() || null, d.id]);
    });
    diffuser('demandes', 'stats');
    res.json({ ok: true });
});

// Un membre signale qu'il a rendu le livre ; l'admin confirme ensuite
app.post('/api/demandes/signaler-retour/:empruntId', auth, async (req, res) => {
    const e = await db.one('SELECT * FROM emprunts WHERE id = $1', [req.params.empruntId]);
    if (!e || e.utilisateur_id !== req.user.id) return res.status(404).json({ erreur: 'Emprunt introuvable' });
    if (e.date_retour_effective) return res.status(409).json({ erreur: 'Ce livre a deja ete retourne' });
    if (await db.one(`SELECT 1 FROM demandes WHERE emprunt_id = $1 AND type = 'retour' AND statut = 'en_attente'`, [e.id])) {
        return res.status(409).json({ erreur: 'Retour deja signale, en attente de confirmation' });
    }
    await db.q(`INSERT INTO demandes (livre_id, utilisateur_id, emprunt_id, type, duree_jours, date_demande) VALUES ($1, $2, $3, 'retour', 0, now())`,
        [e.livre_id, req.user.id, e.id]);
    diffuser('demandes', 'emprunts', 'stats');
    res.status(201).json({ ok: true });
});

app.put('/api/demandes/:id/confirmer-retour', auth, admin, async (req, res) => {
    const result = await transaction(async (t) => {
        const d = await demandeEnAttente(t, req.params.id, 'retour');
        return retournerEmprunt(t, d.emprunt_id);
    });
    diffuser('livres', 'emprunts', 'demandes', 'amendes', 'stats');
    res.json(result);
});

// ============================================================
// UTILISATEURS (admin) — pour choisir un membre lors d'un emprunt direct
// ============================================================
app.get('/api/utilisateurs', auth, admin, async (req, res) => {
    res.json(await db.q('SELECT id, nom, email, role, date_inscription AS "dateInscription" FROM utilisateurs ORDER BY nom'));
});

// ============================================================
// APPLICATION WEB (build Flutter web copie dans backend/public)
// ============================================================
const PUBLIC_DIR = path.join(__dirname, 'public');
app.use(express.static(PUBLIC_DIR));
app.get(/^(?!\/api\/|\/ws).*/, (req, res, next) => {
    res.sendFile(path.join(PUBLIC_DIR, 'index.html'), (err) => err && next());
});

// ============================================================
// ERREURS
// ============================================================
function httpErr(status, message) {
    const e = new Error(message);
    e.status = status;
    return e;
}

app.use((req, res) => res.status(404).json({ erreur: 'Route introuvable' }));
app.use((err, req, res, next) => {
    // 22P02 = identifiant non numerique (ex: /api/livres/abc)
    if (err.code === '22P02') return res.status(400).json({ erreur: 'Identifiant invalide' });
    if (err.code === '23505') return res.status(409).json({ erreur: 'Cette valeur existe deja' });
    if (!err.status) console.error(err);
    res.status(err.status || 500).json({ erreur: err.status ? err.message : 'Erreur serveur' });
});

initialiser()
    .then(() => server.listen(PORT, '0.0.0.0', () => {
        console.log(`BiblioTech API sur http://0.0.0.0:${PORT}  (WebSocket: /ws)`);
    }))
    .catch((e) => {
        console.error('Impossible d\'initialiser la base de donnees :', e.message);
        process.exit(1);
    });
