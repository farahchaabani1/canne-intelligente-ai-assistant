import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'yolo_service.dart';

class YoloTestScreen extends StatefulWidget {
  const YoloTestScreen({super.key});

  @override
  State<YoloTestScreen> createState() => _YoloTestScreenState();
}

class _YoloTestScreenState extends State<YoloTestScreen> {
  final YoloService _yoloService = YoloService();
  final ImagePicker _imagePicker = ImagePicker();

  String _message = 'Prêt à tester YOLO.';
  bool _isLoading = false;

  // Charge le modèle puis analyse une photo de la galerie.
  Future<void> _testDetection() async {
    if (_isLoading) return;

    try {
      // 1. Sélectionne une image.
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      if (!mounted) return;

      setState(() {
        _isLoading = true;
        _message = 'Analyse de l’image en cours...';
      });

      // 2. Lit les octets de l'image.
      final imageBytes = await image.readAsBytes();

      debugPrint('YOLO TEST : image sélectionnée');

      // 3. Charge le modèle et lance la détection.
      final results = await _yoloService.detectObjects(imageBytes);

      //debugPrint('YOLO TEST : résultats = $results');
      final boxes = results['boxes'] as List<dynamic>? ?? [];

      final descriptions = boxes.map((box) {
        final objet = box as Map;
        final nom = objet['className'] ?? 'Objet inconnu';
        final confiance = (objet['confidence'] as num).toDouble() * 100;

        return '$nom : ${confiance.toStringAsFixed(1)} %';
      }).toList();

      final message = descriptions.isEmpty
          ? 'Aucun objet détecté.'
          : descriptions.join('\n');

      debugPrint('YOLO TEST : $message');

      if (!mounted) return;

      // 4. Affiche les résultats bruts pour le premier test.
      setState(() {
        //_message = 'Résultats YOLO :\n$results';
        _message = 'Objets détectés :\n$message';
      });
    } catch (e, stackTrace) {
      debugPrint('YOLO TEST : erreur = $e');
      debugPrint('YOLO TEST : stackTrace = $stackTrace');

      if (!mounted) return;

      setState(() {
        _message = 'Erreur de détection : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test détection YOLO')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.image_search, size: 70),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isLoading ? null : _testDetection,
              child: Text(
                _isLoading
                    ? 'Analyse en cours...'
                    : 'Choisir une photo et détecter',
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoading) const CircularProgressIndicator(),

            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_message, textAlign: TextAlign.left),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
