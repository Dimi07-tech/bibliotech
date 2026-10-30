// Accueil public (catalogue + stats), connexion / inscription, reglage serveur
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';

class AccueilScreen extends StatelessWidget {
  const AccueilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.auto_stories), SizedBox(width: 8), Text('BiblioTech')]),
        actions: [
          const IndicateurDirect(),
          IconButton(icon: const Icon(Icons.dns_outlined), tooltip: 'Serveur', onPressed: () => reglerServeur(context)),
        ],
      ),
      body: LiveBuilder<(Stats, List<Livre>)>(
        ecoute: const {'livres', 'stats'},
        charger: () async => (await Api.stats(), await Api.livres()),
        builder: (context, data) {
          final (stats, livres) = data;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Hero(stats: stats)),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                sliver: SliverToBoxAdapter(child: Text('Catalogue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200, childAspectRatio: 0.52, mainAxisSpacing: 12, crossAxisSpacing: 12),
                  itemCount: livres.length,
                  itemBuilder: (_, i) => CarteLivre(livre: livres[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Stats stats;
  const _Hero({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Couleurs.primaire, Color(0xFF3E2A1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Votre bibliotheque numerique', style: TextStyle(color: Couleurs.accent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Decouvrez, Empruntez,\nExplorez le Savoir',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1.2)),
        const SizedBox(height: 20),
        Row(children: [
          _chiffre('${stats.totalLivres}', 'Livres'),
          _chiffre('${stats.livresDisponibles}', 'Disponibles'),
          _chiffre('${stats.totalUtilisateurs}', 'Membres'),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Couleurs.accent),
              onPressed: () => ouvrirAuth(context, inscription: false),
              icon: const Icon(Icons.login),
              label: const Text('Connexion'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: () => ouvrirAuth(context, inscription: true),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Inscription'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _chiffre(String v, String l) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}

/// Carte de livre en grille (accueil public et catalogue membre)
class CarteLivre extends StatelessWidget {
  final Livre livre;
  final Widget? action;
  const CarteLivre({super.key, required this.livre, this.action});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: LayoutBuilder(builder: (_, c) => Couverture(livre.image, largeur: c.maxWidth, hauteur: c.maxHeight))),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(livre.titre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${livre.auteur}${livre.annee != null ? ' (${livre.annee})' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(livre.genre, style: const TextStyle(fontSize: 11, color: Couleurs.primaire)),
            const SizedBox(height: 6),
            action ?? Pastille.disponibilite(livre.disponible),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================
// AUTH
// ============================================================
void ouvrirAuth(BuildContext context, {required bool inscription}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _FormAuth(inscription: inscription),
    ),
  );
}

class _FormAuth extends StatefulWidget {
  final bool inscription;
  const _FormAuth({required this.inscription});

  @override
  State<_FormAuth> createState() => _FormAuthState();
}

class _FormAuthState extends State<_FormAuth> {
  final _form = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  late bool _inscription = widget.inscription;
  bool _envoi = false;
  bool _masquer = true;

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _envoi = true);
    try {
      if (_inscription) {
        await Api.inscription(_nom.text.trim(), _email.text.trim(), _mdp.text);
      } else {
        await Api.connexion(_email.text.trim(), _mdp.text);
      }
      if (!mounted) return;
      final nom = Session.instance.utilisateur!.nom;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(_inscription ? 'Inscription reussie ! Bienvenue $nom' : 'Connexion reussie !'),
        backgroundColor: Couleurs.succes,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) toast(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_inscription ? 'Creer un compte' : 'Connexion',
              style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (_inscription) ...[
            TextFormField(
              controller: _nom,
              decoration: const InputDecoration(labelText: 'Nom complet', prefixIcon: Icon(Icons.person_outline)),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v!.trim().isEmpty ? 'Nom obligatoire' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            validator: (v) => v!.contains('@') ? null : 'Email invalide',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _mdp,
            obscureText: _masquer,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_masquer ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _masquer = !_masquer),
              ),
            ),
            validator: (v) => _inscription && v!.length < 6 ? '6 caracteres minimum' : (v!.isEmpty ? 'Obligatoire' : null),
            onFieldSubmitted: (_) => _valider(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _envoi ? null : _valider,
            child: _envoi
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_inscription ? "S'inscrire" : 'Se connecter'),
          ),
          TextButton(
            onPressed: () => setState(() => _inscription = !_inscription),
            child: Text(_inscription ? 'Deja un compte ? Se connecter' : "Pas de compte ? S'inscrire"),
          ),
        ]),
      ),
    );
  }
}

// ============================================================
// REGLAGE DU SERVEUR
// ============================================================
Future<void> reglerServeur(BuildContext context) async {
  final ctrl = TextEditingController(text: Session.instance.baseUrl);
  final url = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Adresse du serveur'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, keyboardType: TextInputType.url, autocorrect: false,
            decoration: const InputDecoration(hintText: 'http://192.168.1.20:3000')),
        const SizedBox(height: 8),
        const Text('Emulateur Android : http://10.0.2.2:3000\nTelephone : IP du PC sur le meme Wi-Fi',
            style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Enregistrer')),
      ],
    ),
  );
  if (url != null && url.trim().isNotEmpty) await Session.instance.definirServeur(url);
}
