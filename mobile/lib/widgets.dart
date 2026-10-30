// Composants reutilisables
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';

// ============================================================
// THEME
// ============================================================
class Couleurs {
  static const primaire = Color(0xFF6C4A2E);
  static const accent = Color(0xFFC8963E);
  static const succes = Color(0xFF2E7D32);
  static const danger = Color(0xFFC62828);
  static const attention = Color(0xFFEF8F00);
  static const info = Color(0xFF1565C0);
}

ThemeData construireTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: Couleurs.primaire, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
  );
}

// ============================================================
// UTILITAIRES
// ============================================================
String formaterDate(DateTime? d) => d == null ? '-' : DateFormat('d MMM y', 'fr_FR').format(d);
String formaterEuros(double v) => NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(v);

void toast(BuildContext context, String message, {bool erreur = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: erreur ? Couleurs.danger : Couleurs.succes,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirmer(BuildContext context, String message, {String ok = 'Confirmer', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Couleurs.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Execute une action API et affiche le resultat (ou l'erreur) dans un toast.
Future<bool> executer(BuildContext context, Future<void> Function() action, {String? succes}) async {
  try {
    await action();
    if (context.mounted && succes != null) toast(context, succes);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), erreur: true);
    return false;
  }
}

// ============================================================
// LIVE BUILDER : charge des donnees et se recharge en temps reel
// ============================================================
class LiveBuilder<T> extends StatefulWidget {
  final Future<T> Function() charger;
  final Set<String> ecoute;
  final Widget Function(BuildContext context, T data) builder;

  const LiveBuilder({super.key, required this.charger, required this.ecoute, required this.builder});

  @override
  State<LiveBuilder<T>> createState() => LiveBuilderState<T>();
}

class LiveBuilderState<T> extends State<LiveBuilder<T>> {
  T? _data;
  Object? _erreur;
  bool _charge = false;
  StreamSubscription? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    recharger();
    _sub = Realtime.instance.changements.listen((entites) {
      if (entites.contains('*') || entites.any(widget.ecoute.contains)) {
        // Regroupe les rafales d'evenements
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), recharger);
      }
    });
  }

  Future<void> recharger() async {
    try {
      final d = await widget.charger();
      if (!mounted) return;
      setState(() {
        _data = d;
        _erreur = null;
        _charge = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e;
        _charge = true;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!_charge) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_data == null) {
      child = ListView(children: [
        EtatVide(icone: Icons.cloud_off, message: '$_erreur'),
        Center(child: OutlinedButton.icon(onPressed: recharger, icon: const Icon(Icons.refresh), label: const Text('Reessayer'))),
      ]);
    } else {
      child = widget.builder(context, _data as T);
    }
    return RefreshIndicator(onRefresh: recharger, child: child);
  }
}

// ============================================================
// WIDGETS
// ============================================================
class EtatVide extends StatelessWidget {
  final IconData icone;
  final String message;
  const EtatVide({super.key, required this.icone, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(children: [
        Icon(icone, size: 56, color: c),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: TextStyle(color: c)),
      ]),
    );
  }
}

/// Liste scrollable (compatible pull-to-refresh) avec etat vide.
class ListeOuVide extends StatelessWidget {
  final List<Widget> enfants;
  final IconData icone;
  final String vide;
  final Widget? entete;
  const ListeOuVide({super.key, required this.enfants, required this.icone, required this.vide, this.entete});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        ?entete,
        if (enfants.isEmpty) EtatVide(icone: icone, message: vide),
        for (final e in enfants) Padding(padding: const EdgeInsets.only(bottom: 10), child: e),
      ],
    );
  }
}

class Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;
  const Pastille(this.texte, this.couleur, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(texte, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  static Pastille disponibilite(bool dispo) =>
      dispo ? const Pastille('Disponible', Couleurs.succes) : const Pastille('Emprunte', Couleurs.attention);

  static Pastille statutDemande(String statut) => switch (statut) {
        'en_attente' => const Pastille('En attente', Couleurs.attention),
        'approuvee' => const Pastille('Approuvee', Couleurs.succes),
        _ => const Pastille('Refusee', Couleurs.danger),
      };
}

class Couverture extends StatelessWidget {
  final String? url;
  final double largeur;
  final double hauteur;
  const Couverture(this.url, {super.key, this.largeur = 48, this.hauteur = 68});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: largeur,
      height: hauteur,
      color: Couleurs.primaire.withValues(alpha: 0.12),
      child: Icon(Icons.menu_book, color: Couleurs.primaire, size: largeur * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: (url == null || url!.isEmpty)
          ? fallback
          : Image.network(
              url!,
              width: largeur,
              height: hauteur,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (context, child, frame, _) => frame == null ? fallback : child,
            ),
    );
  }
}

/// Indicateur "En direct" dans l'AppBar
class IndicateurDirect extends StatelessWidget {
  const IndicateurDirect({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Realtime.instance.connecte,
      builder: (context, ok, _) => Tooltip(
        message: ok ? 'Synchronise en temps reel' : 'Hors ligne - reconnexion...',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 10, color: ok ? Colors.greenAccent.shade700 : Colors.grey),
            const SizedBox(width: 4),
            Text(ok ? 'Direct' : 'Hors ligne', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// Carte de statistique (tableau de bord / accueil)
class CarteStat extends StatelessWidget {
  final String titre;
  final String valeur;
  final String? sousTitre;
  final IconData icone;
  final Color couleur;
  const CarteStat({super.key, required this.titre, required this.valeur, this.sousTitre, required this.icone, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(titre, style: Theme.of(context).textTheme.labelMedium)),
            CircleAvatar(radius: 16, backgroundColor: couleur.withValues(alpha: 0.15), child: Icon(icone, size: 18, color: couleur)),
          ]),
          const SizedBox(height: 8),
          FittedBox(child: Text(valeur, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
          if (sousTitre != null) Text(sousTitre!, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

const genres = [
  'Roman', 'Conte', 'Poesie', 'Theatre', 'Science-fiction', 'Fantasy', 'Policier',
  'Biographie', 'Histoire', 'Sciences', 'Philosophie', "Roman d'aventure", 'Autre',
];
