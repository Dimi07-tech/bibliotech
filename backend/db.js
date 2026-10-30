// ============================================================
// db.js — Base de donnees PostgreSQL (Supabase en production)
// ============================================================
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');

if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL manquant (chaine de connexion PostgreSQL / Supabase)');
    process.exit(1);
}

// Supabase (et la plupart des hebergeurs) exigent SSL ; desactivable en local avec DB_SSL=false
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false },
    max: 5,
});

// Executeur commun au pool et aux transactions : .q() -> lignes, .one() -> premiere ligne
function executeur(client) {
    return {
        q: async (sql, params = []) => (await client.query(sql, params)).rows,
        one: async (sql, params = []) => (await client.query(sql, params)).rows[0],
    };
}

const db = executeur(pool);

async function transaction(fn) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const r = await fn(executeur(client));
        await client.query('COMMIT');
        return r;
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS utilisateurs (
    id SERIAL PRIMARY KEY,
    nom TEXT NOT NULL,
    email TEXT NOT NULL,
    mot_de_passe TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'membre' CHECK (role IN ('admin', 'membre')),
    date_inscription TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS utilisateurs_email_unique ON utilisateurs (lower(email));

CREATE TABLE IF NOT EXISTS livres (
    id SERIAL PRIMARY KEY,
    titre TEXT NOT NULL,
    auteur TEXT NOT NULL,
    isbn TEXT NOT NULL UNIQUE,
    annee INTEGER,
    genre TEXT NOT NULL DEFAULT 'Non classe',
    image TEXT,
    disponible BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS emprunts (
    id SERIAL PRIMARY KEY,
    livre_id INTEGER NOT NULL REFERENCES livres(id),
    utilisateur_id INTEGER REFERENCES utilisateurs(id),
    emprunteur TEXT NOT NULL,
    date_emprunt TIMESTAMPTZ NOT NULL,
    date_retour_prevue TIMESTAMPTZ NOT NULL,
    date_retour_effective TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS demandes (
    id SERIAL PRIMARY KEY,
    livre_id INTEGER NOT NULL REFERENCES livres(id),
    utilisateur_id INTEGER NOT NULL REFERENCES utilisateurs(id),
    emprunt_id INTEGER REFERENCES emprunts(id),
    type TEXT NOT NULL DEFAULT 'emprunt' CHECK (type IN ('emprunt', 'retour')),
    statut TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'approuvee', 'refusee')),
    duree_jours INTEGER NOT NULL DEFAULT 14,
    date_demande TIMESTAMPTZ NOT NULL,
    date_traitement TIMESTAMPTZ,
    commentaire_admin TEXT
);

CREATE TABLE IF NOT EXISTS amendes (
    id SERIAL PRIMARY KEY,
    emprunt_id INTEGER NOT NULL UNIQUE REFERENCES emprunts(id),
    jours_retard INTEGER NOT NULL,
    montant DOUBLE PRECISION NOT NULL,
    payee BOOLEAN NOT NULL DEFAULT FALSE,
    date_paiement TIMESTAMPTZ
);
`;

function couvertureParIsbn(isbn) {
    const clean = String(isbn || '').replace(/[^0-9Xx]/g, '');
    return clean ? `https://covers.openlibrary.org/b/isbn/${clean}-M.jpg?default=false` : null;
}

// ---------- Schema + donnees initiales ----------
async function initialiser() {
    await pool.query(SCHEMA);

    const { n: nbUsers } = await db.one('SELECT COUNT(*)::int AS n FROM utilisateurs');
    if (nbUsers === 0) {
        const email = process.env.ADMIN_EMAIL || 'admin@bibliotech.local';
        const mdp = process.env.ADMIN_PASSWORD || 'admin123';
        await db.q('INSERT INTO utilisateurs (nom, email, mot_de_passe, role) VALUES ($1, $2, $3, $4)',
            ['Administrateur', email, bcrypt.hashSync(mdp, 10), 'admin']);
        console.log(`[seed] Compte admin cree : ${email}${process.env.ADMIN_PASSWORD ? '' : ' / admin123  (changez-le !)'}`);
    }

    const { n: nbLivres } = await db.one('SELECT COUNT(*)::int AS n FROM livres');
    if (nbLivres === 0) {
        const livres = [
            ['Le Petit Prince', 'Antoine de Saint-Exupery', '9782070612758', 1943, 'Conte'],
            ['Les Miserables', 'Victor Hugo', '9782253096344', 1862, 'Roman'],
            ['L\'Etranger', 'Albert Camus', '9782070360024', 1942, 'Roman'],
            ['Vingt mille lieues sous les mers', 'Jules Verne', '9782253006329', 1870, 'Roman d\'aventure'],
            ['1984', 'George Orwell', '9782070368228', 1949, 'Science-fiction'],
            ['Le Comte de Monte-Cristo', 'Alexandre Dumas', '9782253098058', 1844, 'Roman d\'aventure'],
            ['Les Fleurs du mal', 'Charles Baudelaire', '9782253007104', 1857, 'Poesie'],
            ['Germinal', 'Emile Zola', '9782253004226', 1885, 'Roman'],
        ];
        for (const [titre, auteur, isbn, annee, genre] of livres) {
            await db.q('INSERT INTO livres (titre, auteur, isbn, annee, genre, image) VALUES ($1, $2, $3, $4, $5, $6)',
                [titre, auteur, isbn, annee, genre, couvertureParIsbn(isbn)]);
        }
        console.log(`[seed] ${livres.length} livres ajoutes`);
    }
}

module.exports = { db, transaction, couvertureParIsbn, initialiser };
