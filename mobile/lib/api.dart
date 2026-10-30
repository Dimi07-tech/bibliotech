// Session, client HTTP et temps reel (WebSocket)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

// Ordre de priorite : --dart-define=API_URL, puis
//  - navigateur : le serveur qui a servi la page (l'API et l'app web sont sur le meme domaine)
//  - Android    : 10.0.2.2 = la machine hote vue depuis l'emulateur
// Sur un vrai telephone, mettre l'IP du PC (ex: http://192.168.1.20:3000) ou l'URL du serveur en ligne.
const String _apiUrl = String.fromEnvironment('API_URL');
final String urlServeurParDefaut =
    _apiUrl.isNotEmpty ? _apiUrl : (kIsWeb ? Uri.base.origin : 'http://10.0.2.2:3000');

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

// ============================================================
// SESSION
// ============================================================
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  late SharedPreferences _prefs;
  String baseUrl = urlServeurParDefaut;
  String? token;
  Utilisateur? utilisateur;

  bool get connecte => token != null && utilisateur != null;

  Future<void> charger() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? urlServeurParDefaut;
    token = _prefs.getString('token');
    final u = _prefs.getString('utilisateur');
    if (u != null) utilisateur = Utilisateur.fromJson(jsonDecode(u));
    Realtime.instance.connecter();
  }

  Future<void> definirServeur(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString('baseUrl', baseUrl);
    Realtime.instance.connecter();
    notifyListeners();
  }

  Future<void> ouvrir(String tok, Utilisateur u) async {
    token = tok;
    utilisateur = u;
    await _prefs.setString('token', tok);
    await _prefs.setString('utilisateur', jsonEncode(u.toJson()));
    Realtime.instance.connecter();
    notifyListeners();
  }

  Future<void> fermer() async {
    token = null;
    utilisateur = null;
    await _prefs.remove('token');
    await _prefs.remove('utilisateur');
    Realtime.instance.connecter();
    notifyListeners();
  }
}

// ============================================================
// CLIENT HTTP
// ============================================================
class Api {
  static Session get _s => Session.instance;

  static Future<dynamic> _req(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('${_s.baseUrl}/api$path');
    final headers = {
      'Content-Type': 'application/json',
      if (_s.token != null) 'Authorization': 'Bearer ${_s.token}',
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    } on TimeoutException {
      throw ApiException('Le serveur ne repond pas');
    } catch (_) {
      throw ApiException('Impossible de joindre le serveur (${_s.baseUrl})');
    }

    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    // Jeton invalide/expire : on deconnecte proprement
    if (res.statusCode == 401 && _s.token != null && !path.startsWith('/auth/')) {
      await _s.fermer();
    }
    final msg = data is Map && data['erreur'] != null ? data['erreur'] as String : 'Erreur ${res.statusCode}';
    throw ApiException(msg, res.statusCode);
  }

  static List<T> _list<T>(dynamic d, T Function(Map<String, dynamic>) f) =>
      (d as List).map((e) => f(e as Map<String, dynamic>)).toList();

  // ---------- Auth ----------
  static Future<void> connexion(String email, String motDePasse) async {
    final r = await _req('POST', '/auth/connexion', {'email': email, 'motDePasse': motDePasse});
    await _s.ouvrir(r['token'], Utilisateur.fromJson(r['utilisateur']));
  }

  static Future<void> inscription(String nom, String email, String motDePasse) async {
    final r = await _req('POST', '/auth/inscription', {'nom': nom, 'email': email, 'motDePasse': motDePasse});
    await _s.ouvrir(r['token'], Utilisateur.fromJson(r['utilisateur']));
  }

  // ---------- Stats / livres ----------
  static Future<Stats> stats() async => Stats.fromJson(await _req('GET', '/stats'));

  static Future<List<Livre>> livres([String recherche = '']) async {
    final q = recherche.trim();
    final path = q.isEmpty ? '/livres' : '/livres/recherche?q=${Uri.encodeQueryComponent(q)}';
    return _list(await _req('GET', path), Livre.fromJson);
  }

  static Future<void> ajouterLivre(Map<String, dynamic> livre) => _req('POST', '/livres', livre);
  static Future<void> modifierLivre(int id, Map<String, dynamic> livre) => _req('PUT', '/livres/$id', livre);
  static Future<void> supprimerLivre(int id) => _req('DELETE', '/livres/$id');

  // ---------- Emprunts / retours ----------
  static Future<List<Emprunt>> emprunts({bool enCours = false}) async =>
      _list(await _req('GET', enCours ? '/emprunts/en-cours' : '/emprunts'), Emprunt.fromJson);
  static Future<List<Emprunt>> mesEmprunts() async => _list(await _req('GET', '/emprunts/moi'), Emprunt.fromJson);

  static Future<void> creerEmprunt({required int livreId, int? utilisateurId, String? emprunteur, required int dureeJours}) =>
      _req('POST', '/emprunts', {
        'livreId': livreId,
        'utilisateurId': ?utilisateurId,
        'emprunteur': ?emprunteur,
        'dureeJours': dureeJours,
      });

  /// Retourne {enRetard, joursRetard, amende}
  static Future<Map<String, dynamic>> enregistrerRetour(int empruntId) async =>
      Map<String, dynamic>.from(await _req('POST', '/retours/$empruntId'));

  // ---------- Amendes ----------
  static Future<List<Amende>> amendes() async => _list(await _req('GET', '/amendes'), Amende.fromJson);
  static Future<List<Amende>> mesAmendes() async => _list(await _req('GET', '/amendes/moi'), Amende.fromJson);
  static Future<void> payerAmende(int id) => _req('PUT', '/amendes/$id/payer');

  // ---------- Demandes ----------
  static Future<List<Demande>> demandes() async => _list(await _req('GET', '/demandes'), Demande.fromJson);
  static Future<List<Demande>> mesDemandes() async => _list(await _req('GET', '/demandes/moi'), Demande.fromJson);
  static Future<void> demanderEmprunt(int livreId, int dureeJours) =>
      _req('POST', '/demandes', {'livreId': livreId, 'dureeJours': dureeJours});
  static Future<void> annulerDemande(int id) => _req('DELETE', '/demandes/$id');
  static Future<void> approuverDemande(int id) => _req('PUT', '/demandes/$id/approuver', {});
  static Future<void> refuserDemande(int id, String? commentaire) =>
      _req('PUT', '/demandes/$id/refuser', {'commentaire': commentaire});
  static Future<void> signalerRetour(int empruntId) => _req('POST', '/demandes/signaler-retour/$empruntId');
  static Future<Map<String, dynamic>> confirmerRetour(int id) async =>
      Map<String, dynamic>.from(await _req('PUT', '/demandes/$id/confirmer-retour'));

  // ---------- Utilisateurs ----------
  static Future<List<Utilisateur>> utilisateurs() async => _list(await _req('GET', '/utilisateurs'), Utilisateur.fromJson);
}

// ============================================================
// TEMPS REEL
// ============================================================
/// Ecoute le serveur et emet la liste des entites modifiees
/// ('livres', 'emprunts', 'demandes', 'amendes', 'stats').
/// A la (re)connexion, emet {'*'} pour que tous les ecrans se resynchronisent.
class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  final _controller = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get changements => _controller.stream;
  final ValueNotifier<bool> connecte = ValueNotifier(false);

  WebSocketChannel? _canal;
  StreamSubscription? _sub;
  Timer? _retry;
  int _tentatives = 0;
  int _generation = 0;

  void connecter() {
    _fermerCanal();
    final gen = ++_generation;
    final s = Session.instance;
    final base = Uri.parse(s.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {if (s.token != null) 'token': s.token!},
    );
    try {
      final canal = WebSocketChannel.connect(uri);
      _canal = canal;
      // L'echec de connexion est deja gere par onError ; on evite l'exception non capturee de `ready`
      canal.ready.catchError((_) {});
      _sub = canal.stream.listen(
        (msg) {
          if (gen != _generation) return;
          final data = jsonDecode(msg as String);
          if (data['type'] == 'hello') {
            _tentatives = 0;
            connecte.value = true;
            _controller.add({'*'});
          } else if (data['type'] == 'change') {
            _controller.add(Set<String>.from(data['entites'] as List));
          }
        },
        onDone: () => _planifierReconnexion(gen),
        onError: (_) => _planifierReconnexion(gen),
        cancelOnError: true,
      );
    } catch (_) {
      _planifierReconnexion(gen);
    }
  }

  void _planifierReconnexion(int gen) {
    if (gen != _generation) return;
    connecte.value = false;
    _retry?.cancel();
    final delai = Duration(seconds: (1 << _tentatives.clamp(0, 5))); // 1s -> 32s
    _tentatives++;
    _retry = Timer(delai, () {
      if (gen == _generation) connecter();
    });
  }

  void _fermerCanal() {
    _retry?.cancel();
    _sub?.cancel();
    _canal?.sink.close();
    _canal = null;
    connecte.value = false;
  }
}
