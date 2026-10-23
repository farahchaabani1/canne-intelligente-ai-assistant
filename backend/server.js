// Mini serveur de l'assistant (version Gemini, offre gratuite de Google AI Studio).
// La clé de l'IA reste côté serveur : elle n'est jamais dans l'application.
import express from 'express';

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.APP_API_KEY;

if (!API_KEY) {
  console.error('APP_API_KEY manquante.');
  process.exit(1);
}
const GEMINI_KEY = process.env.GEMINI_API_KEY;
// Modèle : vérifiez dans Google AI Studio lesquels sont disponibles gratuitement pour votre compte,
// puis changez-le avec la variable GEMINI_MODEL (ex. gemini-3.5-flash-lite).
//const MODEL = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
const MODEL = process.env.GEMINI_MODEL || 'gemini-3.5-flash-lite';

if (!GEMINI_KEY) {
  console.error('GEMINI_API_KEY manquante. Créez une clé gratuite sur https://aistudio.google.com');
  process.exit(1);
}

const SYSTEM_PROMPT = `Tu es l'assistant vocal d'une application pour personnes aveugles.
Tes réponses sont LUES À VOIX HAUTE : phrases courtes et simples, en français, sans listes,
sans symboles, sans markdown, sans émojis. Maximum 5 phrases.
Règles :
- Donne UNE seule étape à la fois, puis demande si la personne est prête pour la suite.
- Utilise des repères concrets : sons, toucher, gauche et droite, nombre de pas.
- Si la question est floue, pose UNE question courte pour préciser.
- Si tu ne sais pas ou si tu n'es pas sûr, dis-le clairement ; n'invente jamais.
- Ne donne jamais de diagnostic médical ni de dose de médicament.
- Si la personne est blessée, en danger, perdue sans solution, ou si le problème est grave,
  mets needsHelp à true et conseille calmement d'appeler le 190.
- Reste calme et rassurant.
Réponds UNIQUEMENT avec un objet JSON : {"reply": "texte à lire", "needsHelp": true|false}`;


const VISION_PROMPT = `Tu es un assistant de vision destiné aux personnes
aveugles ou malvoyantes.

Analyse uniquement ce qui est réellement visible sur la photo.

Règles :
- Décris les objets principaux avec des phrases courtes et simples.
- Si des titres de livres, des étiquettes ou des prix sont lisibles,
  tu peux les lire.
- Si un texte est illisible, indique-le sans inventer.
- Si l'utilisateur recherche un produit, indique s'il est visible.
- Ne prétends pas connaître la distance exacte des objets.
- Ne donne pas d'instructions de déplacement risquées.
- Ne suppose pas qu'un passage est libre ou sans danger.
- Réponds en français, sans markdown, en 3 à 5 phrases maximum.

Réponds uniquement avec un objet JSON :
{"reply":"description à lire","needsHelp":false}`;


// Appel à l'API Gemini (generateContent). Retourne le texte brut de la réponse.
async function askGemini(contents) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_KEY },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents,
      generationConfig: {
        maxOutputTokens: 1024, // marge : certains modèles « réfléchissent » avant de répondre
        temperature: 0.4,
        responseMimeType: 'application/json',
      },
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) {
    const err = new Error(`Gemini HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    err.status = res.status;
    throw err;
  }
  const j = await res.json();
  return (j.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? '').join('');
}


async function analyzeImageWithGemini(imageBase64, mimeType, question) {
  // Adresse de l'API Gemini.
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

  // Prépare la requête contenant le texte et l'image.
  const body = {
    systemInstruction: {
      parts: [{ text: VISION_PROMPT }],
    },

    contents: [
      {
        role: 'user',
        parts: [
          {
            text: question ||
              'Décris ce que tu vois sur cette image.',
          },
          {
            inlineData: {
              mimeType: mimeType,
              data: imageBase64,
            },
          },
        ],
      },
    ],

    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
      responseMimeType: 'application/json',
    },
  };

  // Envoie l'image à Gemini.
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': GEMINI_KEY,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(40_000),
  });

  // Détecte les erreurs de l'API Gemini.
  if (!response.ok) {
    const errorText = await response.text();

    const error = new Error(
      `Gemini Vision HTTP ${response.status}: ` +
      errorText.slice(0, 300)
    );

    error.status = response.status;
    throw error;
  }

  // Récupère la réponse générée.
  const result = await response.json();

  const text = (result.candidates?.[0]?.content?.parts ?? [])
    .map(part => part.text ?? '')
    .join('');

  if (!text.trim()) {
    throw new Error('Réponse Gemini Vision vide');
  }

  // Convertit la réponse JSON en objet JavaScript.
  const parsed = JSON.parse(text);

  return {
    reply: String(parsed.reply ?? 'Description indisponible.'),
    needsHelp: parsed.needsHelp === true,
  };
}


// Limite simple : 30 requêtes par minute et par adresse IP.
const hits = new Map();
function rateLimit(req, res, next) {
  const now = Date.now();
  const recent = (hits.get(req.ip) || []).filter((t) => now - t < 60_000);
  if (recent.length >= 30) return res.status(429).json({ error: 'too many requests' });
  recent.push(now);
  hits.set(req.ip, recent);
  next();
}

const app = express();
//app.use(express.json({ limit: '50kb' }));
// Autorise l'envoi d'images encodées en Base64.
// Limite volontaire pour éviter les fichiers trop volumineux.
app.use(express.json({ limit: '5mb' }));

app.get('/health', (_req, res) => res.json({ ok: true, model: MODEL }));

app.use((req, res, next) => {
  if (req.get('x-api-key') !== API_KEY) return res.status(401).json({ error: 'unauthorized' });
  next();
});

app.post('/assistant', rateLimit, async (req, res) => {
  const { message, history = [] } = req.body;
  if (!message || String(message).length > 500) {
    return res.status(400).json({ error: 'message required (max 500 caractères)' });
  }

  // Gemini appelle « model » le rôle que l'app appelle « assistant ».
  const contents = [
    ...history
      .filter((h) => ['user', 'assistant'].includes(h.role) && h.content)
      .slice(-12)
      .map((h) => ({
        role: h.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: String(h.content).slice(0, 1000) }],
      })),
    { role: 'user', parts: [{ text: String(message) }] },
  ];
  while (contents.length > 1 && contents[0].role !== 'user') contents.shift();

  try {
    const text = await askGemini(contents);
    if (!text.trim()) {
      return res.json({
        reply: 'Je ne peux pas répondre à cette question. Pouvez-vous la reformuler autrement ?',
        needsHelp: false,
      });
    }
    let reply = text;
    let needsHelp = false;
    const m = text.match(/\{[\s\S]*\}/);
    if (m) {
      try {
        const j = JSON.parse(m[0]);
        reply = String(j.reply ?? text);
        needsHelp = j.needsHelp === true;
      } catch {/* on garde le texte brut */ }
    }
    res.json({ reply, needsHelp });
  } catch (e) {
    console.error(e.message);
    // 429 = quota gratuit atteint : l'app dit à la personne de réessayer plus tard.
    res.status(e.status === 429 ? 429 : 502).json({ error: 'assistant unavailable' });
  }
});


/**
 * POST /vision
 *
 * Reçoit une image depuis Flutter et demande
 * à Gemini de décrire son contenu.
 */
app.post('/vision', rateLimit, async (req, res) => {
  const {
    imageBase64,
    mimeType = 'image/jpeg',
    question = 'Décris ce que tu vois.',
  } = req.body ?? {};

  // Vérifie la présence de l'image.
  if (
    typeof imageBase64 !== 'string' ||
    imageBase64.length === 0
  ) {
    return res.status(400).json({
      error: 'imageBase64 required',
    });
  }

  // Accepte uniquement JPEG et PNG.
  if (!['image/jpeg', 'image/png'].includes(mimeType)) {
    return res.status(400).json({
      error: 'unsupported image type',
    });
  }

  // Limite la taille de l'image encodée.
  if (imageBase64.length > 4_000_000) {
    return res.status(413).json({
      error: 'image too large',
    });
  }

  if (
    typeof question !== 'string' ||
    question.length > 500
  ) {
    return res.status(400).json({
      error: 'invalid question',
    });
  }

  try {
    // Analyse l'image avec Gemini Vision.
    const result = await analyzeImageWithGemini(
      imageBase64,
      mimeType,
      question
    );

    // Retourne la description à Flutter.
    res.json(result);

  } catch (error) {
    console.error('Erreur Gemini Vision:', error.message);

    res.status(error.status === 429 ? 429 : 502).json({
      error: 'vision unavailable',
    });
  }
});


app.listen(PORT, () => console.log(`Assistant prêt sur le port ${PORT} (modèle ${MODEL})`));