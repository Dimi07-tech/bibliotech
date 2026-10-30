// Ecrans administrateur : tableau de bord, livres, demandes, emprunts, retours, amendes
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';

// ============================================================
// TABLEAU DE BORD
// ============================================================
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<(Stats, List<Emprunt>)>(
      ecoute: const {'livres', 'emprunts', 'demandes', 'amendes', 'stats'},
      charger: () async => (await Api.stats(), await Api.emprunts(enCours: true)),
      builder: (context, data) {
        final (s, enCours) = data;
        return ListeOuVide(
          icone: Icons.check_circle_outline,
          vide: 'Aucun emprunt en cours',
          entete: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                CarteStat(titre: 'Total livres', valeur: '${s.totalLivres}', sousTitre: '${s.livresDisponibles} disponible(s)',
                    icone: Icons.menu_book, couleur: Couleurs.primaire),
                CarteStat(titre: 'Emprunts en cours', valeur: '${s.empruntsEnCours}', sousTitre: '${s.empruntsEnRetard} en retard',
                    icone: Icons.back_hand_outlined, couleur: Couleurs.info),
                CarteStat(titre: 'Demandes en attente', valeur: '${s.demandesEnAttente}', sousTitre: 'a traiter',
                    icone: Icons.inbox, couleur: Couleurs.attention),
                CarteStat(titre: 'Amendes', valeur: formaterEuros(s.montantTotalAmendes),
                    sousTitre: '${formaterEuros(s.montantImpaye)} impaye', icone: Icons.payments_outlined, couleur: Couleurs.danger),
              ],
            ),
            const SizedBox(height: 20),
            Text('Emprunts en cours', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ]),
          enfants: [for (final e in enCours) TuileEmprunt(emprunt: e)],
        );
      },
    );
  }
}

class TuileEmprunt extends StatelessWidget {
  final Emprunt emprunt;
  final Widget? action;
  const TuileEmprunt({super.key, required this.emprunt, this.action});

  @override
  Widget build(BuildContext context) {
    final e = emprunt;
    final Pastille statut;
    if (!e.enCours) {
      statut = Pastille('Retourne le ${formaterDate(e.dateRetourEffective)}', Couleurs.succes);
    } else if (e.enRetard) {
      statut = const Pastille('En retard', Couleurs.danger);
    } else {
      statut = const Pastille('En cours', Couleurs.info);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Couverture(e.imageLivre),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.titreLivre, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('#${e.id} · ${e.emprunteur}', style: Theme.of(context).textTheme.bodySmall),
              Text('${formaterDate(e.dateEmprunt)} → ${formaterDate(e.dateRetourPrevue)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                statut,
                if (e.enCours && e.retourSignale) const Pastille('Retour signale', Couleurs.attention),
              ]),
            ]),
          ),
          ?action,
        ]),
      ),
    );
  }
}

// ============================================================
// LIVRES
// ============================================================
class LivresScreen extends StatefulWidget {
  const LivresScreen({super.key});

  @override
  State<LivresScreen> createState() => _LivresScreenState();
}

class _LivresScreenState extends State<LivresScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => formulaireLivre(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: Column(children: [
        BarreRecherche(onChanged: (v) => setState(() => _q = v)),
        Expanded(
          child: LiveBuilder<List<Livre>>(
            key: ValueKey(_q),
            ecoute: const {'livres'},
            charger: () => Api.livres(_q),
            builder: (context, livres) => ListeOuVide(
              icone: Icons.menu_book,
              vide: 'Aucun livre trouve',
              enfants: [
                for (final l in livres)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      leading: Couverture(l.image, largeur: 40, hauteur: 56),
                      title: Text(l.titre, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l.auteur}${l.annee != null ? ' · ${l.annee}' : ''} · ${l.genre}'),
                        Text('ISBN ${l.isbn}', style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        Pastille.disponibilite(l.disponible),
                      ]),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) async {
                          if (a == 'edit') formulaireLivre(context, livre: l);
                          if (a == 'del' && await confirmer(context, 'Supprimer « ${l.titre} » ?', ok: 'Supprimer', danger: true)) {
                            if (context.mounted) await executer(context, () => Api.supprimerLivre(l.id), succes: 'Livre supprime !');
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Modifier'))),
                          PopupMenuItem(value: 'del', child: ListTile(leading: Icon(Icons.delete, color: Couleurs.danger), title: Text('Supprimer'))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class BarreRecherche extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String indice;
  const BarreRecherche({super.key, required this.onChanged, this.indice = 'Rechercher un livre, auteur, ISBN...'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SearchBar(
        hintText: indice,
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(1),
        onChanged: onChanged,
      ),
    );
  }
}

Future<void> formulaireLivre(BuildContext context, {Livre? livre}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _FormLivre(livre: livre),
    ),
  );
}

class _FormLivre extends StatefulWidget {
  final Livre? livre;
  const _FormLivre({this.livre});

  @override
  State<_FormLivre> createState() => _FormLivreState();
}

class _FormLivreState extends State<_FormLivre> {
  final _form = GlobalKey<FormState>();
  late final _titre = TextEditingController(text: widget.livre?.titre);
  late final _auteur = TextEditingController(text: widget.livre?.auteur);
  late final _isbn = TextEditingController(text: widget.livre?.isbn);
  late final _annee = TextEditingController(text: widget.livre?.annee?.toString());
  late final _image = TextEditingController(text: widget.livre?.image);
  late String? _genre = widget.livre?.genre;
  bool _envoi = false;

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _envoi = true);
    final data = {
      'titre': _titre.text.trim(),
      'auteur': _auteur.text.trim(),
      'isbn': _isbn.text.trim(),
      'annee': int.tryParse(_annee.text.trim()),
      'genre': _genre ?? 'Non classe',
      'image': _image.text.trim(),
    };
    final edition = widget.livre != null;
    final ok = await executer(
      context,
      () => edition ? Api.modifierLivre(widget.livre!.id, data) : Api.ajouterLivre(data),
      succes: edition ? 'Livre modifie !' : 'Livre ajoute !',
    );
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    String? obligatoire(String? v) => v!.trim().isEmpty ? 'Obligatoire' : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.livre == null ? 'Ajouter un livre' : 'Modifier le livre', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(controller: _titre, decoration: const InputDecoration(labelText: 'Titre *'), validator: obligatoire),
          const SizedBox(height: 10),
          TextFormField(controller: _auteur, decoration: const InputDecoration(labelText: 'Auteur *'), validator: obligatoire),
          const SizedBox(height: 10),
          TextFormField(controller: _isbn, decoration: const InputDecoration(labelText: 'ISBN *'), validator: obligatoire),
          const SizedBox(height: 10),
          TextFormField(
            controller: _annee,
            decoration: const InputDecoration(labelText: 'Annee'),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v!.trim().isEmpty) return null;
              final n = int.tryParse(v.trim());
              return (n == null || n < 1000 || n > 2100) ? 'Annee invalide' : null;
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: genres.contains(_genre) ? _genre : null,
            decoration: const InputDecoration(labelText: 'Genre'),
            items: [for (final g in genres) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) => _genre = v,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _image,
            decoration: const InputDecoration(labelText: 'URL de la couverture', helperText: 'Vide = couverture trouvee via l\'ISBN'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _envoi ? null : _valider,
            icon: Icon(widget.livre == null ? Icons.add : Icons.save),
            label: Text(widget.livre == null ? 'Ajouter' : 'Enregistrer'),
          ),
        ]),
      ),
    );
  }
}

// ============================================================
// DEMANDES (reservations + retours signales)
// ============================================================
class DemandesAdminScreen extends StatelessWidget {
  const DemandesAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Demande>>(
      ecoute: const {'demandes'},
      charger: Api.demandes,
      builder: (context, demandes) {
        final attente = demandes.where((d) => d.enAttente).toList();
        final traitees = demandes.where((d) => !d.enAttente).toList();
        return DefaultTabController(
          length: 2,
          child: Column(children: [
            TabBar(tabs: [Tab(text: 'En attente (${attente.length})'), Tab(text: 'Traitees (${traitees.length})')]),
            Expanded(
              child: TabBarView(children: [
                ListeOuVide(
                  icone: Icons.inbox,
                  vide: 'Aucune demande en attente',
                  enfants: [for (final d in attente) _CarteDemande(demande: d)],
                ),
                ListeOuVide(
                  icone: Icons.folder_open,
                  vide: 'Aucune demande traitee',
                  enfants: [for (final d in traitees) _CarteDemande(demande: d)],
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _CarteDemande extends StatelessWidget {
  final Demande demande;
  const _CarteDemande({required this.demande});

  Future<void> _refuser(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Refuser la demande'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Raison du refus (optionnel)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Couleurs.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await executer(context, () => Api.refuserDemande(demande.id, ctrl.text.trim()), succes: 'Demande refusee');
    }
  }

  Future<void> _confirmerRetour(BuildContext context) async {
    try {
      final r = await Api.confirmerRetour(demande.id);
      if (!context.mounted) return;
      if (r['enRetard'] == true) {
        toast(context, 'Retour confirme avec ${r['joursRetard']} jour(s) de retard. Amende : ${formaterEuros((r['amende']['montant'] as num).toDouble())}',
            erreur: true);
      } else {
        toast(context, 'Retour confirme !');
      }
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = demande;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Couverture(d.imageLivre),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.titreLivre, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(d.nomUtilisateur),
                Text(
                  '${formaterDate(d.dateDemande)}${d.estRetour ? '' : ' · ${d.dureeJours} jours'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  if (d.estRetour) const Pastille('Retour', Couleurs.info) else const Pastille('Reservation', Couleurs.primaire),
                  Pastille.statutDemande(d.statut),
                  if (d.enAttente && !d.estRetour && !d.livreDisponible) const Pastille('Livre indisponible', Couleurs.danger),
                ]),
                if (d.commentaireAdmin != null && d.commentaireAdmin!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(d.commentaireAdmin!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                  ),
              ]),
            ),
          ]),
          if (d.enAttente) ...[
            const SizedBox(height: 10),
            if (d.estRetour)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Couleurs.succes),
                onPressed: () => _confirmerRetour(context),
                icon: const Icon(Icons.check),
                label: const Text('Confirmer le retour'),
              )
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Couleurs.danger),
                    onPressed: () => _refuser(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Couleurs.succes),
                    onPressed: () => executer(context, () => Api.approuverDemande(d.id), succes: 'Demande approuvee !'),
                    icon: const Icon(Icons.check),
                    label: const Text('Approuver'),
                  ),
                ),
              ]),
          ],
        ]),
      ),
    );
  }
}

// ============================================================
// EMPRUNTS
// ============================================================
class EmpruntsScreen extends StatefulWidget {
  const EmpruntsScreen({super.key});

  @override
  State<EmpruntsScreen> createState() => _EmpruntsScreenState();
}

enum _Filtre { tous, enCours, enRetard, termines }

class _EmpruntsScreenState extends State<EmpruntsScreen> {
  _Filtre _filtre = _Filtre.tous;

  bool _garder(Emprunt e) => switch (_filtre) {
        _Filtre.tous => true,
        _Filtre.enCours => e.enCours,
        _Filtre.enRetard => e.enRetard,
        _Filtre.termines => !e.enCours,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => nouvelEmprunt(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel emprunt'),
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_Filtre>(
            segments: const [
              ButtonSegment(value: _Filtre.tous, label: Text('Tous')),
              ButtonSegment(value: _Filtre.enCours, label: Text('En cours')),
              ButtonSegment(value: _Filtre.enRetard, label: Text('En retard')),
              ButtonSegment(value: _Filtre.termines, label: Text('Termines')),
            ],
            selected: {_filtre},
            onSelectionChanged: (s) => setState(() => _filtre = s.first),
          ),
        ),
        Expanded(
          child: LiveBuilder<List<Emprunt>>(
            ecoute: const {'emprunts'},
            charger: Api.emprunts,
            builder: (context, emprunts) => ListeOuVide(
              icone: Icons.back_hand_outlined,
              vide: 'Aucun emprunt',
              enfants: [for (final e in emprunts.where(_garder)) TuileEmprunt(emprunt: e)],
            ),
          ),
        ),
      ]),
    );
  }
}

Future<void> nouvelEmprunt(BuildContext context) async {
  List<Livre> dispo;
  List<Utilisateur> membres;
  try {
    dispo = (await Api.livres()).where((l) => l.disponible).toList();
    membres = (await Api.utilisateurs()).where((u) => !u.estAdmin).toList();
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), erreur: true);
    return;
  }
  if (!context.mounted) return;
  if (dispo.isEmpty) {
    toast(context, 'Aucun livre disponible', erreur: true);
    return;
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _FormEmprunt(livres: dispo, membres: membres),
    ),
  );
}

class _FormEmprunt extends StatefulWidget {
  final List<Livre> livres;
  final List<Utilisateur> membres;
  const _FormEmprunt({required this.livres, required this.membres});

  @override
  State<_FormEmprunt> createState() => _FormEmpruntState();
}

class _FormEmpruntState extends State<_FormEmprunt> {
  final _form = GlobalKey<FormState>();
  final _emprunteur = TextEditingController();
  final _duree = TextEditingController(text: '14');
  int? _livreId;
  int? _membreId; // null = emprunteur externe (nom libre)

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    final ok = await executer(
      context,
      () => Api.creerEmprunt(
        livreId: _livreId!,
        utilisateurId: _membreId,
        emprunteur: _membreId == null ? _emprunteur.text.trim() : null,
        dureeJours: int.tryParse(_duree.text) ?? 14,
      ),
      succes: 'Emprunt enregistre !',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Nouvel emprunt', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Livre *'),
            items: [
              for (final l in widget.livres)
                DropdownMenuItem(value: l.id, child: Text('${l.titre} - ${l.auteur}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _livreId = v,
            validator: (v) => v == null ? 'Choisissez un livre' : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            isExpanded: true,
            initialValue: null,
            decoration: const InputDecoration(labelText: 'Membre'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Personne externe (saisir le nom)')),
              for (final u in widget.membres) DropdownMenuItem<int?>(value: u.id, child: Text('${u.nom} (${u.email})')),
            ],
            onChanged: (v) => setState(() => _membreId = v),
          ),
          if (_membreId == null) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _emprunteur,
              decoration: const InputDecoration(labelText: 'Nom de l\'emprunteur *', hintText: 'Jean Dupont'),
              validator: (v) => v!.trim().isEmpty ? 'Obligatoire' : null,
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            controller: _duree,
            decoration: const InputDecoration(labelText: 'Duree (jours)'),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return (n == null || n < 1 || n > 90) ? 'Entre 1 et 90' : null;
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _valider, icon: const Icon(Icons.back_hand), label: const Text('Enregistrer')),
        ]),
      ),
    );
  }
}

// ============================================================
// RETOURS
// ============================================================
class RetoursScreen extends StatelessWidget {
  const RetoursScreen({super.key});

  Future<void> _retourner(BuildContext context, Emprunt e) async {
    if (!await confirmer(context, 'Confirmer le retour de « ${e.titreLivre} » ?')) return;
    try {
      final r = await Api.enregistrerRetour(e.id);
      if (!context.mounted) return;
      if (r['enRetard'] == true) {
        toast(context, 'Retourne avec ${r['joursRetard']} jour(s) de retard. Amende : ${formaterEuros((r['amende']['montant'] as num).toDouble())}',
            erreur: true);
      } else {
        toast(context, 'Livre retourne !');
      }
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Emprunt>>(
      ecoute: const {'emprunts'},
      charger: () => Api.emprunts(enCours: true),
      builder: (context, emprunts) => ListeOuVide(
        icone: Icons.check_circle_outline,
        vide: 'Tous les livres ont ete retournes !',
        entete: const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Enregistrez le retour d\'un livre. Une amende est generee automatiquement en cas de retard.'),
        ),
        enfants: [
          for (final e in emprunts)
            TuileEmprunt(
              emprunt: e,
              action: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Couleurs.succes),
                tooltip: 'Retourner',
                onPressed: () => _retourner(context, e),
                icon: const Icon(Icons.assignment_return),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// AMENDES
// ============================================================
class AmendesScreen extends StatelessWidget {
  const AmendesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Amende>>(
      ecoute: const {'amendes'},
      charger: Api.amendes,
      builder: (context, amendes) => ListeOuVide(
        icone: Icons.check_circle_outline,
        vide: 'Aucune amende',
        enfants: [
          for (final a in amendes)
            TuileAmende(
              amende: a,
              action: a.payee
                  ? null
                  : FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Couleurs.succes),
                      onPressed: () async {
                        if (await confirmer(context, 'Marquer l\'amende de ${formaterEuros(a.montant)} comme payee ?') && context.mounted) {
                          await executer(context, () => Api.payerAmende(a.id), succes: 'Amende marquee comme payee');
                        }
                      },
                      child: const Text('Payer'),
                    ),
            ),
        ],
      ),
    );
  }
}

class TuileAmende extends StatelessWidget {
  final Amende amende;
  final Widget? action;
  const TuileAmende({super.key, required this.amende, this.action});

  @override
  Widget build(BuildContext context) {
    final a = amende;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (a.payee ? Couleurs.succes : Couleurs.danger).withValues(alpha: 0.15),
          child: Icon(a.payee ? Icons.check : Icons.warning_amber, color: a.payee ? Couleurs.succes : Couleurs.danger),
        ),
        title: Text('${formaterEuros(a.montant)} · ${a.titreLivre}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${a.emprunteur} · ${a.joursRetard} jour(s) de retard'
            '${a.payee ? '\nPayee le ${formaterDate(a.datePaiement)}' : ''}'),
        isThreeLine: a.payee,
        trailing: action ?? Pastille(a.payee ? 'Payee' : 'Impayee', a.payee ? Couleurs.succes : Couleurs.danger),
      ),
    );
  }
}
