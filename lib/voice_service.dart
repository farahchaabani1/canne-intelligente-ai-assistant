import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Reconnaissance vocale + synthèse vocale.
/// Changez [locale] en 'ar-TN' ou 'ar-SA' pour l'arabe.
class VoiceService {
  VoiceService({this.locale = 'fr-FR'});

  final String locale;
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init() async {
    _ready = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.45); // lent et clair
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    await _stt.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() => _tts.stop();

  /// Écoute une phrase. Retourne null en cas de silence.
  Future<String?> listen() async {
    if (!_ready) {
      await Future.delayed(const Duration(seconds: 1));
      return null;
    }
    final done = Completer<String?>();
    var words = '';

    await _stt.listen(
      localeId: locale.replaceAll('-', '_'),
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
      onResult: (r) {
        words = r.recognizedWords;
        if (r.finalResult && !done.isCompleted) done.complete(words);
      },
    );

    // Filet de sécurité si aucun résultat final n'arrive.
    return done.future.timeout(const Duration(seconds: 25), onTimeout: () async {
      await _stt.stop();
      return words.isEmpty ? null : words;
    });
  }

  Future<void> cancelListening() => _stt.cancel();
}