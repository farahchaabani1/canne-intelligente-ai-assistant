import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'vision/vision_screen.dart';
import 'vision/yolo_live_test_screen.dart';

import 'assistant_api.dart';
import 'voice_service.dart';

enum AssistantState { idle, speaking, listening, thinking }

/// Écran unique : tout se fait à la voix.
/// L'écran sert aux personnes malvoyantes et aux accompagnants :
/// un grand cercle d'état et deux grands boutons (Répéter, Appeler le 190).
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _voice =
      VoiceService(); // 'ar-TN' pour l'arabe : VoiceService(locale: 'ar-TN')
  final _api = AssistantApi();
  final List<Map<String, String>> _history = [];

  AssistantState _state = AssistantState.idle;
  String _caption = 'Démarrage…';
  String _lastReply = '';
  bool _running = true;
  bool _awaitingCall = false;
  int _silent = 0;

  static const _sosWords = [
    'au secours',
    'urgence',
    'danger',
    'aidez-moi',
    'aidez moi',
    'je suis blessé',
    'je suis blessée',
    'j\'ai besoin d\'aide',
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    WakelockPlus.enable(); // garde l'écran allumé pendant l'utilisation
    await _voice.init();
    //await _say(
    //  'Bonjour, je suis votre assistant. Posez-moi vos questions. '
    //  'Dites répète pour réentendre ma réponse, nouvelle conversation pour recommencer, '
    //  'ou au secours en cas de danger.',
    //);
    await _say(
      'Bonjour, je suis votre assistant intelligent. '
      'Vous pouvez me poser des questions, '
      'dire ouvre la détection pour reconnaître les objets autour de vous, '
      'ou dire ouvre la caméra pour obtenir une description détaillée. '
      'Dites répète pour réécouter ma réponse, '
      'nouvelle conversation pour recommencer, '
      'ou au secours pour demander de l’aide.',
    );
    _loop();
  }

  // ───────────────────────── boucle de conversation ─────────────────────────

  Future<void> _loop() async {
    while (mounted && _running) {
      _set(AssistantState.listening, 'Je vous écoute…');
      final heard = await _voice.listen();
      if (!mounted) return;

      if (heard == null || heard.trim().isEmpty) {
        _silent++;
        if (_silent >= 4) {
          _silent = 0;
          await _say('Je suis toujours là. Parlez quand vous voulez.');
        } else {
          await Future.delayed(const Duration(milliseconds: 600));
        }
        continue;
      }
      _silent = 0;
      await _handle(heard.trim());
    }
  }

  Future<void> _handle(String raw) async {
    final t = raw.toLowerCase();
    _set(AssistantState.thinking, '« $raw »');

    // Commande vocale : ouvrir YOLO.
    if (RegExp(
      r"(ouvre|ouvrir|lance|démarre|active).*(détection|yolo)",
    ).hasMatch(t)) {
      await _openYolo();
      return;
    }

    // Commande vocale : ouvrir Gemini Vision.
    if (RegExp(
      r"(ouvre|ouvrir|lance|démarre|active).*(caméra|vision)",
    ).hasMatch(t)) {
      await _openVision();
      return;
    }

    // Réponse oui / non à la proposition d'appeler le 190.
    if (_awaitingCall) {
      _awaitingCall = false;
      if (_isYes(t)) {
        await _callEmergency();
        return;
      }
      if (_isNo(t)) {
        await _say('D\'accord. Je reste avec vous.');
        return;
      }
    }

    // Commandes locales (sans Internet).
    if (RegExp(r"\b(répète|repete|répéter|repeter|redis)\b").hasMatch(t)) {
      await _say(_lastReply.isEmpty ? 'Je n\'ai encore rien dit.' : _lastReply);
      return;
    }
    if (RegExp(r"(nouvelle conversation|recommence|efface tout)").hasMatch(t)) {
      _history.clear();
      _lastReply = '';
      await _say('C\'est fait. Nous repartons de zéro.');
      return;
    }
    if (_sosWords.any(t.contains)) {
      await _offerCall();
      return;
    }

    // Question normale : on demande à l'IA.
    _set(AssistantState.thinking, 'Je réfléchis…');
    try {
      final r = await _api.ask(raw, _history);
      _history
        ..add({'role': 'user', 'content': raw})
        ..add({'role': 'assistant', 'content': r.reply});
      if (_history.length > 12) _history.removeRange(0, _history.length - 12);

      await _say(r.reply, remember: true);
      if (r.needsHelp) await _offerCall();
      //} catch (_) {
    } catch (e, stackTrace) {
      debugPrint('ERREUR ASSISTANT API : $e');
      debugPrintStack(stackTrace: stackTrace);
      await _say(
        'Désolé, je n\'ai pas pu joindre le service. '
        'Vérifiez la connexion Internet, puis répétez votre question.',
      );
    }
  }

  // ───────────────────────────── actions ─────────────────────────────

  Future<void> _offerCall() async {
    _awaitingCall = true;
    await _say(
      'Je suis là. Voulez-vous que j\'ouvre le numéro du SAMU, le 190 ? '
      'Dites oui ou non.',
    );
  }

  Future<void> _callEmergency() async {
    await _say(
      'J\'ouvre le numéro 190. Appuyez sur le bouton vert pour appeler.',
    );
    await launchUrl(Uri(scheme: 'tel', path: '190'));
  }

  Future<void> _onTapRepeat() async {
    HapticFeedback.mediumImpact();
    _voice.stopSpeaking();
    _voice.cancelListening();
    await _say(_lastReply.isEmpty ? 'Je n\'ai encore rien dit.' : _lastReply);
  }

  Future<void> _onTapCall() async {
    HapticFeedback.heavyImpact();
    _voice.stopSpeaking();
    _voice.cancelListening();
    _awaitingCall = false;
    await _callEmergency();
  }

  /// Toucher le cercle = interrompre l'assistant et parler.
  void _onTapOrb() {
    HapticFeedback.mediumImpact();
    _voice.stopSpeaking();
    _voice.cancelListening();
  }

  // Ouvre l'écran de vision intelligente.
  Future<void> _openVision() async {
    // Arrête temporairement l'assistant vocal
    // pour éviter qu'il continue à écouter pendant la caméra.
    _running = false;
    _voice.cancelListening();
    _voice.stopSpeaking();

    // Ouvre la page caméra et attend sa fermeture.
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VisionScreen()),
    );

    if (!mounted) return;

    // Relance la conversation après le retour.
    if (!_running) {
      _running = true;
      _loop();
    }
  }

  // Ouvre la détection YOLO en direct.
  Future<void> _openYolo() async {
    // Suspend l'assistant vocal pendant l'utilisation de YOLO.
    _running = false;
    await _voice.cancelListening();
    await _voice.stopSpeaking();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const YoloLiveTestScreen()),
    );

    if (!mounted) return;

    // Reprend l'assistant vocal après la fermeture de YOLO.
    if (!_running) {
      _running = true;
      _loop();
    }
  }

  // ───────────────────────────── utilitaires ─────────────────────────────

  bool _isYes(String t) => RegExp(
    r"\b(oui|ouais|d'accord|ok|vas-y|allez-y|appelle|appelez)\b",
  ).hasMatch(t);
  bool _isNo(String t) =>
      RegExp(r"\b(non|annule|annuler|laisse|stop)\b").hasMatch(t);

  Future<void> _say(String text, {bool remember = false}) async {
    if (!mounted) return;
    if (remember) _lastReply = text;
    _set(AssistantState.speaking, text);
    await _voice.speak(text);
  }

  void _set(AssistantState s, String caption) {
    if (!mounted) return;
    setState(() {
      _state = s;
      _caption = caption;
    });
  }

  @override
  void dispose() {
    _running = false;
    _voice.stopSpeaking();
    _voice.cancelListening();
    WakelockPlus.disable();
    super.dispose();
  }

  // ───────────────────────────────────── UI ─────────────────────────────────────

  Color get _orbColor => switch (_state) {
    AssistantState.listening => const Color(
      0xFFFFD54F,
    ), // jaune : je vous écoute
    AssistantState.speaking => const Color(0xFF81D4FA), // bleu clair : je parle
    AssistantState.thinking => const Color(
      0xFFC5E1A5,
    ), // vert clair : je réfléchis
    AssistantState.idle => const Color(0xFFE0E0E0),
  };

  IconData get _orbIcon => switch (_state) {
    AssistantState.listening => Icons.mic,
    AssistantState.speaking => Icons.volume_up,
    AssistantState.thinking => Icons.hourglass_top,
    AssistantState.idle => Icons.mic_none,
  };

  Widget _bigButton({
    required String label,
    required String semantics,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: semantics,
        child: SizedBox.expand(
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 44),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: Semantics(
                  button: true,
                  label:
                      'Assistant vocal. Touchez pour l\'interrompre et parler.',
                  child: GestureDetector(
                    onTap: _onTapOrb,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final orbSize = (constraints.maxHeight * 0.58).clamp(
                          90.0,
                          220.0,
                        );
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: orbSize,
                              height: orbSize,
                              decoration: BoxDecoration(
                                color: _orbColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF1A237E),
                                  width: 6,
                                ),
                              ),
                              child: Icon(
                                _orbIcon,
                                size: orbSize * 0.5,
                                color: const Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: SingleChildScrollView(
                                  child: Text(
                                    _caption,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A237E),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Bouton permettant d'ouvrir la caméra.
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _openVision,
                  icon: const Icon(Icons.camera_alt, size: 30),
                  label: const Text(
                    'Vision intelligente',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              // Bouton permettant d'ouvrir YOLO en direct.
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _openYolo,
                  icon: const Icon(Icons.visibility, size: 30),
                  label: const Text(
                    'Détection en direct',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    _bigButton(
                      label: 'Répéter',
                      semantics:
                          'Bouton répéter. Réécouter la dernière réponse.',
                      icon: Icons.replay,
                      color: const Color(0xFF1A237E),
                      onPressed: _onTapRepeat,
                    ),
                    const SizedBox(width: 16),
                    _bigButton(
                      label: 'Appeler\nle 190',
                      semantics: 'Bouton appeler le 190, le SAMU.',
                      icon: Icons.call,
                      color: const Color(0xFFD32F2F),
                      onPressed: _onTapCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
