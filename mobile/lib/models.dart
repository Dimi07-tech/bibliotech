// Modeles de donnees (miroir des reponses JSON de l'API)

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

class Utilisateur {
  final int id;
  final String nom;
  final String email;
  final String role;

  Utilisateur({required this.id, required this.nom, required this.email, required this.role});

  bool get estAdmin => role == 'admin';

  String get initiales {
    final parts = nom.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final init = parts.take(2).map((p) => p[0]).join().toUpperCase();
    return init.isEmpty ? '?' : init;
  }

  factory Utilisateur.fromJson(Map<String, dynamic> j) =>
      Utilisateur(id: j['id'], nom: j['nom'], email: j['email'] ?? '', role: j['role'] ?? 'membre');

  Map<String, dynamic> toJson() => {'id': id, 'nom': nom, 'email': email, 'role': role};
}

class Livre {
  final int id;
  final String titre;
  final String auteur;
  final String isbn;
  final int? annee;
  final String genre;
  final String? image;
  final bool disponible;

  Livre({
    required this.id,
    required this.titre,
    required this.auteur,
    required this.isbn,
    this.annee,
    required this.genre,
    this.image,
    required this.disponible,
  });

  factory Livre.fromJson(Map<String, dynamic> j) => Livre(
        id: j['id'],
        titre: j['titre'],
        auteur: j['auteur'],
        isbn: j['isbn'] ?? '',
        annee: j['annee'],
        genre: j['genre'] ?? 'Non classe',
        image: j['image'],
        disponible: j['disponible'] == true,
      );
}

class Emprunt {
  final int id;
  final int livreId;
  final int? utilisateurId;
  final String emprunteur;
  final String titreLivre;
  final String? auteurLivre;
  final String? imageLivre;
  final DateTime dateEmprunt;
  final DateTime dateRetourPrevue;
  final DateTime? dateRetourEffective;
  final bool retourSignale;

  Emprunt({
    required this.id,
    required this.livreId,
    this.utilisateurId,
    required this.emprunteur,
    required this.titreLivre,
    this.auteurLivre,
    this.imageLivre,
    required this.dateEmprunt,
    required this.dateRetourPrevue,
    this.dateRetourEffective,
    required this.retourSignale,
  });

  bool get enCours => dateRetourEffective == null;
  bool get enRetard => enCours && DateTime.now().isAfter(dateRetourPrevue);

  factory Emprunt.fromJson(Map<String, dynamic> j) => Emprunt(
        id: j['id'],
        livreId: j['livreId'],
        utilisateurId: j['utilisateurId'],
        emprunteur: j['emprunteur'] ?? '',
        titreLivre: j['titreLivre'] ?? '',
        auteurLivre: j['auteurLivre'],
        imageLivre: j['imageLivre'],
        dateEmprunt: _date(j['dateEmprunt'])!,
        dateRetourPrevue: _date(j['dateRetourPrevue'])!,
        dateRetourEffective: _date(j['dateRetourEffective']),
        retourSignale: j['retourSignale'] == true,
      );
}

class Demande {
  final int id;
  final int livreId;
  final int? empruntId;
  final String type; // emprunt | retour
  final String statut; // en_attente | approuvee | refusee
  final int dureeJours;
  final DateTime dateDemande;
  final String? commentaireAdmin;
  final String titreLivre;
  final String? imageLivre;
  final String nomUtilisateur;
  final bool livreDisponible;

  Demande({
    required this.id,
    required this.livreId,
    this.empruntId,
    required this.type,
    required this.statut,
    required this.dureeJours,
    required this.dateDemande,
    this.commentaireAdmin,
    required this.titreLivre,
    this.imageLivre,
    required this.nomUtilisateur,
    required this.livreDisponible,
  });

  bool get enAttente => statut == 'en_attente';
  bool get estRetour => type == 'retour';

  factory Demande.fromJson(Map<String, dynamic> j) => Demande(
        id: j['id'],
        livreId: j['livreId'],
        empruntId: j['empruntId'],
        type: j['type'] ?? 'emprunt',
        statut: j['statut'],
        dureeJours: j['dureeJours'] ?? 14,
        dateDemande: _date(j['dateDemande'])!,
        commentaireAdmin: j['commentaireAdmin'],
        titreLivre: j['titreLivre'] ?? '',
        imageLivre: j['imageLivre'],
        nomUtilisateur: j['nomUtilisateur'] ?? '',
        livreDisponible: j['livreDisponible'] == true,
      );
}

class Amende {
  final int id;
  final String titreLivre;
  final String emprunteur;
  final int joursRetard;
  final double montant;
  final bool payee;
  final DateTime? datePaiement;

  Amende({
    required this.id,
    required this.titreLivre,
    required this.emprunteur,
    required this.joursRetard,
    required this.montant,
    required this.payee,
    this.datePaiement,
  });

  factory Amende.fromJson(Map<String, dynamic> j) => Amende(
        id: j['id'],
        titreLivre: j['titreLivre'] ?? '',
        emprunteur: j['emprunteur'] ?? '',
        joursRetard: j['joursRetard'] ?? 0,
        montant: _num(j['montant']),
        payee: j['payee'] == true,
        datePaiement: _date(j['datePaiement']),
      );
}

class Stats {
  final int totalLivres;
  final int livresDisponibles;
  final int totalUtilisateurs;
  final int totalEmprunts;
  final int empruntsEnCours;
  final int empruntsEnRetard;
  final int demandesEnAttente;
  final int totalAmendes;
  final double montantTotalAmendes;
  final double montantImpaye;

  Stats.fromJson(Map<String, dynamic> j)
      : totalLivres = j['totalLivres'] ?? 0,
        livresDisponibles = j['livresDisponibles'] ?? 0,
        totalUtilisateurs = j['totalUtilisateurs'] ?? 0,
        totalEmprunts = j['totalEmprunts'] ?? 0,
        empruntsEnCours = j['empruntsEnCours'] ?? 0,
        empruntsEnRetard = j['empruntsEnRetard'] ?? 0,
        demandesEnAttente = j['demandesEnAttente'] ?? 0,
        totalAmendes = j['totalAmendes'] ?? 0,
        montantTotalAmendes = _num(j['montantTotalAmendes']),
        montantImpaye = _num(j['montantImpaye']);
}
