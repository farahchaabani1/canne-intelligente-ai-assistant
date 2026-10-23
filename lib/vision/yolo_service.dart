//import 'dart:typed_data';

//import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:flutter/foundation.dart';

/// Service de détection d'objets avec YOLO.
///
/// Il utilise un modèle préentraîné exécuté sur le téléphone.
class YoloService {
  // Modèle léger de détection d'objets.
  final YOLO _yolo = YOLO(modelPath: 'yolo26n', task: YOLOTask.detect);

  // Indique si le modèle a été chargé.
  bool _isLoaded = false;

  /// Charge le modèle YOLO en mémoire.
  Future<void> loadModel() async {
    if (_isLoaded) return;

    //await _yolo.loadModel();
    //_isLoaded = true;

    debugPrint('YOLO : début du chargement du modèle');

    await _yolo.loadModel();

    _isLoaded = true;

    debugPrint('YOLO : modèle chargé avec succès');

  }

  /// Analyse une image et retourne les objets détectés.
  ///
  /// imageBytes contient les octets de l'image JPEG ou PNG.
  //Future<List<YOLOResult>> detectObjects(
  //  Uint8List imageBytes,
  //) async {
  //  if (!_isLoaded) {
  //    await loadModel();
  //  }

  // Exécute YOLO sur l'image.
  //  final results = await _yolo.predict(imageBytes);

  //  return results;
  //}

  /// Analyse une image et retourne les résultats bruts de YOLO.
  Future<Map<String, dynamic>> detectObjects(Uint8List imageBytes) async {
    // Charge le modèle s'il n'est pas encore prêt.
    if (!_isLoaded) {
      await loadModel();
    }

    // Analyse l'image.
    final results = await _yolo.predict(imageBytes);

    // Retourne les résultats de la prédiction.
    return results;
  }
}
