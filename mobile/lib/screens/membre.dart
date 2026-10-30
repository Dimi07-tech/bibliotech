// Ecrans membre : catalogue (reservation), mes demandes, mes emprunts (+ amendes)
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'accueil.dart' show CarteLivre;
import 'admin.dart' show BarreRecherche, TuileAmende, TuileEmprunt;

// ============================================================
// CATALOGUE
// ============================================================
class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      BarreRecherche(onChanged: (v) => setState(() => _q = v), indice: 'Rechercher...'),
      Expanded(
        child: LiveBuilder<(List<Livre>, List<Demande>)>(
          key: ValueKey(_q),
          ecoute: const {'livres', 'demandes'},
          charger: () async => (await Api.livres(_q), await Api.mesDemandes()),
          builder: (context, data) {
            final (livres, demandes) = data;
            final dejaDemandes = {for (final d in demandes) if (d.enAttente && !d.estRetour) d.livreId};
            if (livres.isEmpty) {
              return ListView(children: const [EtatVide(icone: Icons.search_off, message: 'Aucun livre trouve')]);
            }
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200, childAspectRatio: 0.5, mainAxisSpacing: 12, crossAxisSpacing: 12),
              itemCount: livres.length,
              itemBuilder: (context, i) {
                final l = livres[i];
                final Widget action;
                if (dejaDemandes.contains(l.id)) {
                  action = const Pastille('Demande envoyee', Couleurs.attention);
                } else if (l.disponible) {
                  action = SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => demanderEmprunt(context, l),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Reserver'),
                    ),
                  );
                } else {
                  action = const Pastille('Indisponible', Couleurs.attention);
                }
                return CarteLivre(livre: l, action: action);
              },
            );
          },
        ),
      ),
    ]);
  }
}

Future<void> demanderEmprunt(BuildContext context, Livre livre) async {
  var duree = 14.0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Demande d\'emprunt'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(livre.titre, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('Duree souhaitee : ${duree.round()} jours'),
          Slider(value: duree, min: 1, max: 90, divisions: 89, label: '${duree.round()} j', onChanged: (v) => setState(() => duree = v)),
          const Text('Votre demande sera envoyee a l\'administrateur pour validation.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send), label: const Text('Envoyer')),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) {
    await executer(context, () => Api.demanderEmprunt(livre.id, duree.round()),
        succes: 'Demande envoyee ! L\'administrateur va la traiter.');
  }
}

// ============================================================
// MES DEMANDES
// ============================================================
class MesDemandesScreen extends StatelessWidget {
  const MesDemandesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Demande>>(
      ecoute: const {'demandes'},
      charger: Api.mesDemandes,
      builder: (context, demandes) => ListeOuVide(
        icone: Icons.send_outlined,
        vide: 'Aucune demande. Parcourez le catalogue pour emprunter un livre.',
        enfants: [
          for (final d in demandes.where((d) => !d.estRetour))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Couverture(d.imageLivre),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.titreLivre, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${formaterDate(d.dateDemande)} · ${d.dureeJours} jours', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Pastille.statutDemande(d.statut),
                      if (d.commentaireAdmin != null && d.commentaireAdmin!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(d.commentaireAdmin!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                        ),
                    ]),
                  ),
                  if (d.enAttente)
                    IconButton(
                      tooltip: 'Annuler la demande',
                      icon: const Icon(Icons.cancel_outlined, color: Couleurs.danger),
                      onPressed: () async {
                        if (await confirmer(context, 'Annuler cette demande ?', ok: 'Oui, annuler', danger: true) && context.mounted) {
                          await executer(context, () => Api.annulerDemande(d.id), succes: 'Demande annulee');
                        }
                      },
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// MES EMPRUNTS (+ mes amendes)
// ============================================================
class MesEmpruntsScreen extends StatelessWidget {
  const MesEmpruntsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<(List<Emprunt>, List<Amende>)>(
      ecoute: const {'emprunts', 'amendes'},
      charger: () async => (await Api.mesEmprunts(), await Api.mesAmendes()),
      builder: (context, data) {
        final (emprunts, amendes) = data;
        final impayees = amendes.where((a) => !a.payee).toList();
        final total = impayees.fold<double>(0, (s, a) => s + a.montant);
        return ListeOuVide(
          icone: Icons.menu_book,
          vide: 'Aucun emprunt. Faites une demande depuis le catalogue.',
          entete: impayees.isEmpty
              ? null
              : Card(
                  color: Couleurs.danger.withValues(alpha: 0.08),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: const Icon(Icons.warning_amber, color: Couleurs.danger),
                    title: Text('Amendes impayees : ${formaterEuros(total)}'),
                    subtitle: const Text('A regler aupres de la bibliotheque'),
                    children: [for (final a in impayees) TuileAmende(amende: a)],
                  ),
                ),
          enfants: [
            for (final e in emprunts)
              TuileEmprunt(
                emprunt: e,
                action: e.enCours && !e.retourSignale
                    ? IconButton.outlined(
                        tooltip: 'Signaler le retour',
                        icon: const Icon(Icons.assignment_return),
                        onPressed: () async {
                          if (await confirmer(context, 'Signaler le retour de ce livre ? L\'administrateur confirmera le retour.') &&
                              context.mounted) {
                            await executer(context, () => Api.signalerRetour(e.id), succes: 'Demande de retour envoyee !');
                          }
                        },
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}
