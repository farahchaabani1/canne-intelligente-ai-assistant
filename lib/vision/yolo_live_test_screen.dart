
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class YoloLiveTestScreen extends StatefulWidget {
  const YoloLiveTestScreen({super.key});

  @override
  State<YoloLiveTestScreen> createState() =>
      _YoloLiveTestScreenState();
}

class _YoloLiveTestScreenState
    extends State<YoloLiveTestScreen> {
  final FlutterTts _tts = FlutterTts();

  String _message = 'Place un objet devant la caméra.';
  int _nombreObjets = 0;

  bool _voixActive = true;
  bool _voixPrete = false;
  bool _annonceEnCours = false;

  DateTime _dernierAffichage =
      DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, DateTime> _dernieresAnnonces = {};

  // Nombre de résultats consécutifs pour chaque classe.
  final Map<String, int> _detectionsConsecutives = {};

  // Objets actuellement détectés.
  List<String> _objetsVisibles = [];

  static const Duration _delaiRepetition =
      Duration(seconds: 15);

  // Traduction des classes YOLO.
  static const Map<String, String> _traductions = {
    'person': 'personne',
    'chair': 'chaise',
    'bottle': 'bouteille',
    'cup': 'tasse',
    'car': 'voiture',
    'bus': 'bus',
    'truck': 'camion',
    'bicycle': 'vélo',
    'motorcycle': 'moto',
    'dog': 'chien',
    'cat': 'chat',
    'backpack': 'sac à dos',
    'handbag': 'sac à main',
    'umbrella': 'parapluie',
    'bench': 'banc',
    'dining table': 'table',
    'couch': 'canapé',
    'bed': 'lit',
    'door': 'porte',
    'book': 'livre',
    'cell phone': 'téléphone',
    'laptop': 'ordinateur portable',
    'tv': 'télévision',
    'clock': 'horloge',
    'traffic light': 'feu de circulation',
    'stop sign': 'panneau stop',
  };

  // Priorité 1 : objets mobiles ou personnes.
  // Priorité 2 : objets courants dans l'environnement.
  // Priorité 3 : autres objets.
  static const Map<String, int> _priorites = {
    'person': 1,
    'car': 1,
    'bus': 1,
    'truck': 1,
    'motorcycle': 1,
    'bicycle': 1,
    'dog': 2,
    'chair': 2,
    'bench': 2,
    'dining table': 2,
  };

  @override
  void initState() {
    super.initState();
    _initialiserVoix();
  }

  // Initialise la synthèse vocale en français.
  Future<void> _initialiserVoix() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);

      // Attend la fin d'une annonce avant d'en lancer une autre.
      await _tts.awaitSpeakCompletion(true);

      if (!mounted) return;

      setState(() {
        _voixPrete = true;
      });
    } catch (e) {
      debugPrint(
        'YOLO TTS : initialisation impossible : $e',
      );
    }
  }

  // Traduit le nom d'un objet.
  String _traduire(String nom) {
    return _traductions[nom] ?? nom;
  }

  // Reçoit les résultats de YOLO en temps réel.
  void _onResults(List<YOLOResult> results) {
    if (!mounted) return;

    // Ignore les prédictions trop incertaines.
    final objets = results
        .where((result) => result.confidence >= 0.50)
        .toList();

    // Trie d'abord par priorité, puis par confiance.
    objets.sort((a, b) {
      final prioriteA = _priorites[a.className] ?? 3;
      final prioriteB = _priorites[b.className] ?? 3;

      final comparaison =
          prioriteA.compareTo(prioriteB);

      if (comparaison != 0) {
        return comparaison;
      }

      return b.confidence.compareTo(a.confidence);
    });

    final maintenant = DateTime.now();

    // Ensemble des classes présentes dans cette prédiction.
    final classesPresentes = objets
        .map((objet) => objet.className)
        .toSet();

    // Incrémente les détections consécutives.
    for (final nom in classesPresentes) {
      _detectionsConsecutives[nom] =
          (_detectionsConsecutives[nom] ?? 0) + 1;
    }

    // Supprime les classes absentes de cette prédiction.
    _detectionsConsecutives.removeWhere(
      (nom, _) => !classesPresentes.contains(nom),
    );

    // Prépare la liste des objets visibles.
    final descriptions = objets.map((objet) {
      final nom = _traduire(objet.className);

      final confiance =
          (objet.confidence * 100).toStringAsFixed(1);

      return '$nom : $confiance %';
    }).toList();

    final message = descriptions.isEmpty
        ? 'Aucun objet détecté.'
        : descriptions.join('\n');

    _objetsVisibles = objets
        .map((objet) => _traduire(objet.className))
        .toSet()
        .toList();

    // Actualise l'affichage au maximum deux fois par seconde.
    if (maintenant.difference(_dernierAffichage) >=
        const Duration(milliseconds: 500)) {
      _dernierAffichage = maintenant;

      setState(() {
        _nombreObjets = objets.length;
        _message = message;
      });
    }

    // Arrête ici si les annonces sont désactivées
    // ou si la voix est déjà occupée.
    if (!_voixActive ||
        !_voixPrete ||
        _annonceEnCours) {
      return;
    }

    // Sélectionne un seul objet à annoncer.
    for (final objet in objets) {
      // Seuil plus strict pour les annonces vocales.
      if (objet.confidence < 0.65) {
        continue;
      }

      final nomOriginal = objet.className;

      // Attend au moins trois résultats consécutifs.
      if ((_detectionsConsecutives[nomOriginal] ?? 0) <
          3) {
        continue;
      }

      // Évite de répéter le même objet trop souvent.
      final derniereAnnonce =
          _dernieresAnnonces[nomOriginal];

      if (derniereAnnonce != null &&
          maintenant.difference(derniereAnnonce) <
              _delaiRepetition) {
        continue;
      }

      _dernieresAnnonces[nomOriginal] = maintenant;

      _annoncerObjet(_traduire(nomOriginal));
      break;
    }
  }

  // Annonce automatiquement un objet.
  Future<void> _annoncerObjet(String nom) async {
    if (_annonceEnCours ||
        !_voixActive ||
        !_voixPrete ||
        !mounted) {
      return;
    }

    _annonceEnCours = true;

    try {
      await _tts.speak('$nom détecté');
    } catch (e) {
      debugPrint('YOLO TTS : erreur : $e');
    } finally {
      _annonceEnCours = false;
    }
  }

  // Annonce les objets visibles à la demande.
  Future<void> _decrireObjetsVisibles() async {
    if (!_voixPrete || !mounted) return;

    // Prend une copie des objets détectés.
    final objets = List<String>.from(_objetsVisibles);

    final message = objets.isEmpty
        ? 'Je ne détecte aucun objet pour le moment.'
        : 'Je détecte : ${objets.join(', ')}.';

    // Réserve la voix pour la description demandée.
    _annonceEnCours = true;

    try {
      // Interrompt l'annonce automatique précédente.
      await _tts.stop();

      // Lit la liste des objets.
      await _tts.speak(message);
    } catch (e) {
      debugPrint(
        'YOLO TTS : erreur description : $e',
      );
    } finally {
      _annonceEnCours = false;
    }
  }

  // Active ou désactive les annonces automatiques.
  Future<void> _changerVoix(bool active) async {
    if (!mounted) return;

    setState(() {
      _voixActive = active;
    });

    if (!active) {
      await _tts.stop();
    } else {
      // Autorise de nouvelles annonces à la réactivation.
      _dernieresAnnonces.clear();
    }
  }

  @override
  void dispose() {
    _voixActive = false;
    _voixPrete = false;

    _tts.stop();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'YOLO - Détection en direct',
        ),
      ),
      body: Column(
        children: [
          // Caméra et détection YOLO.
          Expanded(
            flex: 5,
            child: YOLOView(
              modelPath: 'yolo26n',
              task: YOLOTask.detect,
              onResult: _onResults,
            ),
          ),

          // Interface de contrôle.
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Activation des annonces automatiques.
                  SwitchListTile(
                    title: const Text(
                      'Annonces vocales',
                    ),
                    subtitle: Text(
                      _voixPrete
                          ? 'Voix française disponible'
                          : 'Initialisation de la voix...',
                    ),
                    value: _voixActive,
                    onChanged: _changerVoix,
                  ),

                  // Bouton de description à la demande.
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _voixPrete
                          ? _decrireObjetsVisibles
                          : null,
                      icon: const Icon(
                        Icons.record_voice_over,
                      ),
                      label: const Text(
                        'Que vois-tu ?',
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Objets détectés : $_nombreObjets',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Semantics(
                        liveRegion: false,
                        child: Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
