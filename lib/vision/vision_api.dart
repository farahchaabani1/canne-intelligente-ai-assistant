
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// Réutilise l'adresse du backend et la clé d'accès
// déjà définies pour l'assistant vocal.
import '../assistant_api.dart';

// Représente la réponse reçue après analyse de l'image.
class VisionReply {
  final String reply;
  final bool needsHelp;

  VisionReply({
    required this.reply,
    required this.needsHelp,
  });
}

// Service responsable de l'envoi des images au backend.
class VisionApi {

  Future<VisionReply> analyzeImage(
    String imagePath, {
    String question = 'Décris ce que tu vois sur cette image.',
  }) async {

    // 1. Ouvre l'image capturée par la caméra.
    final imageFile = File(imagePath);

    // 2. Lit les octets de l'image.
    final imageBytes = await imageFile.readAsBytes();

    // 3. Convertit l'image en Base64.
    // Le backend attend une image sous cette forme.
    final imageBase64 = base64Encode(imageBytes);

    // 4. Prépare les données à envoyer à Node.js.
    final requestBody = {
      'imageBase64': imageBase64,
      'mimeType': 'image/jpeg',
      'question': question,
    };

    // 5. Envoie la requête HTTP POST à /vision.
    final response = await http.post(
      Uri.parse('$kBaseUrl/vision'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': kApiKey,
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 50));

    // 6. Vérifie si le backend a accepté la requête.
    if (response.statusCode >= 300) {
      throw Exception(
        'Erreur Vision HTTP ${response.statusCode}',
      );
    }

    // 7. Convertit la réponse JSON en objet Dart.
    final data = jsonDecode(
      utf8.decode(response.bodyBytes),
    ) as Map<String, dynamic>;

    // 8. Retourne la description produite par Gemini.
    return VisionReply(
      reply: data['reply'] as String,
      needsHelp: (data['needsHelp'] as bool?) ?? false,
    );
  }
}
