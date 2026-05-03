import 'dart:convert';

import 'package:http/http.dart' as http;

/// Load at build/run time, e.g. `flutter run --dart-define=OPENAI_API_KEY=sk-...`
const String kOpenAiApiKeyFromEnvironment = String.fromEnvironment(
  'OPENAI_API_KEY',
);

String _composeTranslationModel() {
  const raw = String.fromEnvironment(
    'OPENAI_TRANSLATION_MODEL',
    defaultValue: 'gpt-4o-mini',
  );
  final t = raw.trim();
  return t.isEmpty ? 'gpt-4o-mini' : t;
}

Duration _composeTranslationTimeout() {
  const seconds = int.fromEnvironment(
    'OPENAI_TRANSLATION_TIMEOUT_SECONDS',
    defaultValue: 60,
  );
  return Duration(seconds: seconds <= 0 ? 60 : seconds);
}

int _composeTranslationMaxInputChars() {
  const n = int.fromEnvironment(
    'MAIL_TRANSLATION_MAX_INPUT_CHARS',
    defaultValue: 12000,
  );
  return n <= 0 ? 12000 : n;
}

enum OpenAiComposeAssistKind {
  fixGrammar,
  improveBody,
  suggestSubject,
}

class OpenAiComposeAssistException implements Exception {
  OpenAiComposeAssistException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OpenAiComposeTranslationResult {
  const OpenAiComposeTranslationResult({
    required this.subject,
    required this.body,
  });

  final String subject;
  final String body;
}

/// Minimal Chat Completions client for compose assist actions.
class OpenAiComposeAssistService {
  OpenAiComposeAssistService({
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;

  static final _endpoint =
      Uri.parse('https://api.openai.com/v1/chat/completions');
  static const _model = 'gpt-4o-mini';

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Future<String> run({
    required OpenAiComposeAssistKind kind,
    required String bodyText,
    required String subjectText,
  }) async {
    if (!isConfigured) {
      throw OpenAiComposeAssistException(
        'OpenAI is not configured. Run the app with '
        '--dart-define=OPENAI_API_KEY=your_key',
      );
    }

    final (system, user) = _prompts(
      kind: kind,
      bodyText: bodyText,
      subjectText: subjectText,
    );

    final payload = <String, dynamic>{
      'model': _model,
      'temperature': switch (kind) {
        OpenAiComposeAssistKind.fixGrammar => 0.2,
        OpenAiComposeAssistKind.improveBody => 0.5,
        OpenAiComposeAssistKind.suggestSubject => 0.4,
      },
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    };

    return _postChatCompletion(
      payload: payload,
      timeout: const Duration(seconds: 60),
    );
  }

  /// Translates draft subject + body into [targetLanguageEnglishLabel] (e.g. Croatian).
  Future<OpenAiComposeTranslationResult> translateDraft({
    required String subject,
    required String body,
    required String targetLanguageCode,
    required String targetLanguageEnglishLabel,
  }) async {
    if (!isConfigured) {
      throw OpenAiComposeAssistException(
        'OpenAI is not configured. Run the app with '
        '--dart-define=OPENAI_API_KEY=your_key',
      );
    }

    final maxChars = _composeTranslationMaxInputChars();
    var subjectPart = subject;
    var bodyPart = body;
    final overhead = 64;
    var total = subjectPart.length + bodyPart.length;
    if (total + overhead > maxChars) {
      final budget = maxChars - overhead - subjectPart.length;
      if (budget < 256 && subjectPart.length > 256) {
        subjectPart = subjectPart.substring(0, 256);
        total = subjectPart.length + bodyPart.length;
      }
      final bodyBudget = maxChars - overhead - subjectPart.length;
      if (bodyBudget < 1) {
        throw OpenAiComposeAssistException(
          'Draft is too long to translate (max ~$maxChars characters).',
        );
      }
      if (bodyPart.length > bodyBudget) {
        bodyPart = bodyPart.substring(0, bodyBudget);
      }
    }

    final system =
        'You translate email subject and body into $targetLanguageEnglishLabel '
        '(BCP-47 style language code: $targetLanguageCode). '
        'Preserve line breaks in the body where sensible. '
        'Do not add explanations. '
        'Reply with a single JSON object only, keys "subject" and "body" (strings). '
        'If the subject is empty in the input, use an empty string for "subject".';

    final user = '---SUBJECT---\n$subjectPart\n---BODY---\n$bodyPart';

    final model = _composeTranslationModel();
    final payload = <String, dynamic>{
      'model': model,
      'temperature': 0.25,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    };

    final raw = await _postChatCompletion(
      payload: payload,
      timeout: _composeTranslationTimeout(),
    );
    return _parseTranslationJson(raw);
  }

  Future<String> _postChatCompletion({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final response = await _http
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final snippet = response.body.length > 200
          ? '${response.body.substring(0, 200)}…'
          : response.body;
      throw OpenAiComposeAssistException(
        'OpenAI request failed (${response.statusCode}): $snippet',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw OpenAiComposeAssistException('Unexpected OpenAI response shape.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw OpenAiComposeAssistException('OpenAI returned no choices.');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw OpenAiComposeAssistException('Unexpected OpenAI choice shape.');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw OpenAiComposeAssistException('Unexpected OpenAI message shape.');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw OpenAiComposeAssistException('OpenAI returned empty content.');
    }
    return content.trim();
  }

  OpenAiComposeTranslationResult _parseTranslationJson(String raw) {
    final stripped = _stripJsonFence(raw);
    final decoded = jsonDecode(stripped);
    if (decoded is! Map<String, dynamic>) {
      throw OpenAiComposeAssistException('Translation was not valid JSON.');
    }
    final sub = decoded['subject'];
    final bod = decoded['body'];
    return OpenAiComposeTranslationResult(
      subject: sub is String ? sub : '',
      body: bod is String ? bod : '',
    );
  }

  (String system, String user) _prompts({
    required OpenAiComposeAssistKind kind,
    required String bodyText,
    required String subjectText,
  }) {
    switch (kind) {
      case OpenAiComposeAssistKind.fixGrammar:
        return (
          'You correct grammar and spelling in the user email draft. '
          'Preserve the original language (e.g. Croatian or English). '
          'Do not change meaning or add commentary. '
          'Reply with the corrected body text only, no quotes or markdown fences.',
          bodyText,
        );
      case OpenAiComposeAssistKind.improveBody:
        return (
          'You improve clarity and flow of the user email draft while keeping '
          'the same meaning, tone, and language. Do not add a greeting unless '
          'already present. Do not add commentary. '
          'Reply with the improved body text only, no quotes or markdown fences.',
          bodyText,
        );
      case OpenAiComposeAssistKind.suggestSubject:
        return (
          'You write one short email subject line based on the draft body. '
          'Use the same language as the body. Max about 78 characters when reasonable. '
          'Reply with the subject line only — no quotes, no prefixes like Subject:.',
          'Current subject (may be empty): $subjectText\n\n---\n\nDraft body:\n$bodyText',
        );
    }
  }
}

String _stripJsonFence(String s) {
  var t = s.trim();
  if (t.startsWith('```')) {
    final firstNl = t.indexOf('\n');
    if (firstNl != -1) {
      t = t.substring(firstNl + 1);
    }
    final end = t.lastIndexOf('```');
    if (end != -1) {
      t = t.substring(0, end).trim();
    }
  }
  return t;
}
