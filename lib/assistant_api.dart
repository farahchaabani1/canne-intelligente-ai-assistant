import 'dart:convert';

import 'package:http/http.dart' as http;

/// 10.0.2.2 = localhost de votre PC depuis l'émulateur Android.
/// Sur un vrai téléphone : l'adresse IP de votre PC (ex. http://192.168.1.20:3000)
/// ou l'URL HTTPS de votre serveur déployé.
const String kBaseUrl = 'http://127.0.0.1:3000';
const String kApiKey = 'change-me'; // même valeur que APP_API_KEY côté serveur

class AssistantReply {
  final String reply;

  /// true si la situation semble grave : l'app propose alors d'appeler le 190.
  final bool needsHelp;
  AssistantReply(this.reply, this.needsHelp);
}

class AssistantApi {
  Future<AssistantReply> ask(String message, List<Map<String, String>> history) async {
    final res = await http
        .post(
          Uri.parse('$kBaseUrl/assistant'),
          headers: {'Content-Type': 'application/json', 'x-api-key': kApiKey},
          body: jsonEncode({'message': message, 'history': history}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return AssistantReply(j['reply'] as String, (j['needsHelp'] as bool?) ?? false);
  }
}