import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// Notre service de communication avec Gemini Vision.
import 'vision_api.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen>
    with WidgetsBindingObserver {
  // Contrôle la caméra du téléphone.
  CameraController? _controller;

  // Service permettant d'envoyer une photo à Gemini.
  final VisionApi _visionApi = VisionApi();
  // Synthèse vocale utilisée pour lire les descriptions.
  final FlutterTts _tts = FlutterTts();

  // Reconnaissance vocale pour les questions sur l'image.
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Indique si le microphone écoute une question.
  bool _isListening = false;

  // Question prononcée par l'utilisateur.
  String _spokenQuestion = '';

  // États de l'interface.
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String? _errorMessage;

  // Description retournée par Gemini.
  String _description = 'Appuyez sur le bouton pour analyser une image.';

  // Identifiant utilisé pour éviter les initialisations obsolètes.
  int _generation = 0;

  @override
  void initState() {
    super.initState();

    // Surveille les changements d'état de l'application.
    WidgetsBinding.instance.addObserver(this);

    // Configure la synthèse vocale française.
    _configureTts();

    // Initialise la caméra.
    _initializeCamera();
  }

  Future<void> _configureTts() async {
    // Sélectionne le français.
    await _tts.setLanguage('fr-FR');

    // Vitesse légèrement réduite pour faciliter la compréhension.
    await _tts.setSpeechRate(0.45);

    // Volume maximal.
    await _tts.setVolume(1.0);
  }

  // Démarre la caméra arrière.
  Future<void> _initializeCamera() async {
    final generation = ++_generation;
    CameraController? newController;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Récupère les caméras disponibles.
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('Aucune caméra disponible.');
      }

      // Sélectionne la caméra arrière.
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Configure la caméra.
      newController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      // Attend que la caméra soit prête.
      await newController.initialize();

      if (!mounted || generation != _generation) {
        await newController.dispose();
        return;
      }

      // Affiche la caméra dans l'interface.
      setState(() {
        _controller = newController;
        _isLoading = false;
      });
    } catch (e) {
      await newController?.dispose();

      if (!mounted || generation != _generation) return;

      setState(() {
        _errorMessage = 'Impossible de démarrer la caméra : $e';
        _isLoading = false;
      });
    }
  }

  // Écoute une question orale, puis analyse une image.
  Future<void> _askQuestionByVoice() async {
    if (_isListening || _isAnalyzing || _isLoading) return;

    try {
      // Arrête la réponse vocale précédente.
      await _tts.stop();

      // Vérifie que la reconnaissance vocale est disponible.
      final available = await _speech.initialize(
        onError: (error) {
          debugPrint('VISION STT : erreur = $error');

          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        },
      );

      if (!mounted) return;

      if (!available) {
        setState(() {
          _description = 'Reconnaissance vocale indisponible.';
        });
        return;
      }

      setState(() {
        _isListening = true;
        _spokenQuestion = '';
        _description = 'Je vous écoute. Posez votre question.';
      });

      // Écoute la question en français.
      await _speech.listen(
        localeId: 'fr_FR',
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _spokenQuestion = result.recognizedWords;
          });
        },
      );
    } catch (e) {
      debugPrint('VISION STT : $e');

      if (!mounted) return;

      setState(() {
        _isListening = false;
        _description = 'Impossible de démarrer le microphone.';
      });
    }
  }

  // Termine l'écoute et envoie la question avec une photo.
  Future<void> _finishVoiceQuestion() async {
    if (!_isListening) return;

    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });

    final question = _spokenQuestion.trim();

    if (question.isEmpty) {
      setState(() {
        _description = 'Aucune question détectée. Réessayez.';
      });
      return;
    }

    debugPrint('VISION : question = $question');

    // Analyse une nouvelle image avec la question prononcée.
    await _analyzeCurrentImage(question: question);
  }

  // Capture une photo et l'envoie à Gemini Vision.
  Future<void> _analyzeCurrentImage({String? question}) async {
    debugPrint('VISION : bouton analyse activé');
    final controller = _controller;

    // Vérifie que la caméra est disponible.
    if (controller == null ||
        !controller.value.isInitialized ||
        _isAnalyzing ||
        controller.value.isTakingPicture) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _description = 'Analyse de l’image en cours...';
    });

    try {
      debugPrint('VISION : début capture photo');
      // 1. Capture une image avec la caméra arrière.
      final photo = await controller.takePicture();
      debugPrint('VISION : photo capturée : ${photo.path}');

      debugPrint('VISION : envoi de la photo à Gemini');
      // 2. Envoie la photo au backend Node.js.
      // Le backend transmet l'image à Gemini.
      final result = await _visionApi.analyzeImage(
        photo.path,
        question:
            question ??
            'Décris les objets visibles devant moi. '
                'Lis les textes clairement visibles sur les objets.',
      );

      debugPrint('VISION : réponse Gemini reçue');
      debugPrint('VISION : ${result.reply}');

      if (!mounted) return;

      // 3. Affiche la réponse reçue de Gemini.
      setState(() {
        _description = result.reply;
      });

      // Arrête une éventuelle lecture précédente.
      await _tts.stop();

      // Lit la description générée par Gemini.
      if (mounted) {
        debugPrint('VISION : début lecture vocale');
        await _tts.speak(result.reply);
      }
      //} catch (e) {
      //  debugPrint('Erreur analyse image : $e');

      debugPrint('VISION : lecture vocale demandée');
    } catch (e, stackTrace) {
      debugPrint('VISION : ERREUR = $e');
      debugPrint('VISION : STACKTRACE = $stackTrace');

      if (!mounted) return;

      setState(() {
        _description =
            'Impossible d’analyser cette image. Vérifiez le serveur et réessayez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // Gère les changements d'état de l'application Android.
  //@override
  //void didChangeAppLifecycleState(AppLifecycleState state) {
  //  if (state == AppLifecycleState.inactive) {
  // Libère la caméra lorsque l'application est interrompue.
  //    _generation++;

  //    final oldController = _controller;
  //    _controller = null;
  //    oldController?.dispose();
  //  } else if (state == AppLifecycleState.resumed && _controller == null) {
  // Réactive la caméra au retour dans l'application.
  //    _initializeCamera();
  //  }
  //}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('VISION : état Android = $state');
  }

  @override
  void dispose() {
    _generation++;

    // Libère la caméra et arrête l'observation Android.
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();

    _speech.cancel();

    _tts.stop();

    super.dispose();
  }

  // Construit l'interface graphique de l'écran caméra.
  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Vision intelligente')),

      body: Column(
        children: [
          // Partie supérieure : affichage de la caméra.
          Expanded(
            flex: 5,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!))
                : controller != null && controller.value.isInitialized
                ? Center(child: CameraPreview(controller))
                : const Center(child: Text('Caméra indisponible')),
          ),

          // Partie inférieure : bouton et description.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Bouton de capture et d'analyse.
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton.icon(
                    //onPressed: _isAnalyzing ? null : _analyzeCurrentImage,
                    onPressed: _isAnalyzing || _isListening || _isLoading
                        ? null
                        : () => _analyzeCurrentImage(),
                    icon: const Icon(Icons.visibility),
                    label: Text(
                      _isAnalyzing
                          ? 'Analyse en cours...'
                          : 'Décrire ce que je vois',
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Bouton permettant de poser une question orale.
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing || _isLoading
                        ? null
                        : _isListening
                        ? _finishVoiceQuestion
                        : _askQuestionByVoice,
                    icon: Icon(_isListening ? Icons.stop : Icons.mic),
                    label: Text(
                      _isListening
                          ? 'Terminer ma question'
                          : 'Poser une question',
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Indicateur de chargement pendant l'analyse.
                if (_isAnalyzing) const CircularProgressIndicator(),

                const SizedBox(height: 16),

                // Texte de la description générée par Gemini.
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
