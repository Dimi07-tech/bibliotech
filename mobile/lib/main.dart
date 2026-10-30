import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api.dart';
import 'models.dart';
import 'screens/accueil.dart';
import 'screens/admin.dart';
import 'screens/membre.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await Session.instance.charger();
  runApp(const BiblioTechApp());
}

class BiblioTechApp extends StatelessWidget {
  const BiblioTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiblioTech',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => kIsWeb ? CadreTelephone(child: child!) : child!,
      theme: construireTheme(Brightness.light),
      darkTheme: construireTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: Session.instance,
        builder: (_, _) => Session.instance.connecte
            ? EspacePrincipal(key: ValueKey(Session.instance.utilisateur!.id))
            : const AccueilScreen(),
      ),
    );
  }
}

class _Page {
  final String titre;
  final IconData icone;
  final Widget ecran;
  final bool badgeDemandes;
  const _Page(this.titre, this.icone, this.ecran, {this.badgeDemandes = false});
}

const _pagesAdmin = [
  _Page('Tableau de bord', Icons.pie_chart_outline, DashboardScreen()),
  _Page('Livres', Icons.menu_book_outlined, LivresScreen()),
  _Page('Demandes', Icons.inbox_outlined, DemandesAdminScreen(), badgeDemandes: true),
  _Page('Emprunts', Icons.back_hand_outlined, EmpruntsScreen()),
  _Page('Retours', Icons.assignment_return_outlined, RetoursScreen()),
  _Page('Amendes', Icons.payments_outlined, AmendesScreen()),
];

const _pagesMembre = [
  _Page('Catalogue', Icons.auto_stories_outlined, CatalogueScreen()),
  _Page('Mes demandes', Icons.send_outlined, MesDemandesScreen()),
  _Page('Mes emprunts', Icons.back_hand_outlined, MesEmpruntsScreen()),
];

class EspacePrincipal extends StatefulWidget {
  const EspacePrincipal({super.key});

  @override
  State<EspacePrincipal> createState() => _EspacePrincipalState();
}

class _EspacePrincipalState extends State<EspacePrincipal> {
  int _index = 0;
  int _demandesEnAttente = 0;
  StreamSubscription? _sub;

  bool get _admin => Session.instance.utilisateur!.estAdmin;
  List<_Page> get _pages => _admin ? _pagesAdmin : _pagesMembre;

  @override
  void initState() {
    super.initState();
    if (_admin) {
      _majBadge();
      _sub = Realtime.instance.changements.listen((e) {
        if (e.contains('*') || e.contains('stats') || e.contains('demandes')) _majBadge();
      });
    }
  }

  Future<void> _majBadge() async {
    try {
      final s = await Api.stats();
      if (mounted) setState(() => _demandesEnAttente = s.demandesEnAttente);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Widget _icone(_Page p) {
    final icon = Icon(p.icone);
    if (!p.badgeDemandes || _demandesEnAttente == 0) return icon;
    return Badge(label: Text('$_demandesEnAttente'), child: icon);
  }

  Future<void> _deconnecter() async {
    if (!await confirmer(context, 'Se deconnecter ?', ok: 'Deconnexion') || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await Session.instance.fermer();
    messenger.showSnackBar(const SnackBar(content: Text('Deconnexion reussie'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.utilisateur!;
    final page = _pages[_index];

    final appBar = AppBar(
      title: Text(page.titre),
      actions: const [IndicateurDirect(), SizedBox(width: 8)],
    );
    // IndexedStack garde l'etat (recherche, onglet) de chaque page
    final corps = IndexedStack(index: _index, children: [for (final p in _pages) p.ecran]);

    // Membre : 3 pages -> barre de navigation en bas
    if (!_admin) {
      return Scaffold(
        appBar: appBar,
        drawer: _tiroir(u),
        body: corps,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [for (final p in _pages) NavigationDestination(icon: _icone(p), label: p.titre)],
        ),
      );
    }
    // Admin : 6 pages -> menu lateral
    return Scaffold(appBar: appBar, drawer: _tiroir(u), body: corps);
  }

  Widget _tiroir(Utilisateur u) {
    return NavigationDrawer(
      selectedIndex: _index,
      onDestinationSelected: (i) {
        if (i < _pages.length) setState(() => _index = i);
        Navigator.pop(context);
      },
      children: [
        UserAccountsDrawerHeader(
          decoration: const BoxDecoration(color: Couleurs.primaire),
          currentAccountPicture: CircleAvatar(
            backgroundColor: Couleurs.accent,
            child: Text(u.initiales, style: const TextStyle(fontSize: 22, color: Colors.white)),
          ),
          accountName: Text(u.nom),
          accountEmail: Text('${u.email} · ${u.estAdmin ? 'Administrateur' : 'Membre'}'),
        ),
        for (final p in _pages) NavigationDrawerDestination(icon: _icone(p), label: Text(p.titre)),
        const Divider(indent: 24, endIndent: 24),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Serveur'),
          subtitle: Text(Session.instance.baseUrl, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.pop(context);
            reglerServeur(context);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.logout, color: Couleurs.danger),
          title: const Text('Deconnexion'),
          onTap: () {
            Navigator.pop(context);
            _deconnecter();
          },
        ),
      ],
    );
  }
}

/// Dans un navigateur d'ordinateur, affiche l'app dans un cadre de telephone
/// (sur un vrai mobile ou une fenetre etroite, elle occupe tout l'ecran).
class CadreTelephone extends StatelessWidget {
  final Widget child;
  const CadreTelephone({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    if (taille.width < 600) return child;
    const largeur = 412.0;
    final hauteur = (taille.height - 48).clamp(600.0, 915.0);
    return ColoredBox(
      color: const Color(0xFF2B211A),
      child: Center(
        child: Container(
          width: largeur + 24,
          height: hauteur + 24,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(48),
            boxShadow: const [BoxShadow(blurRadius: 40, color: Colors.black54)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(largeur, hauteur)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
