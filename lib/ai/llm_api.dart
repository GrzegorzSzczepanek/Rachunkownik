import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ai_settings.dart';

class LlmResult {
  LlmResult(this.text, {this.inputTokens = 0, this.outputTokens = 0});
  final String text;
  final int inputTokens;
  final int outputTokens;
  int get totalTokens => inputTokens + outputTokens;
}

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// One call to a hosted (or LAN) model. Images are optional so the same client
/// serves OCR-from-photo, categorisation and chat.
abstract class LlmApi {
  Future<LlmResult> complete({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 2048,
  });
}

LlmApi buildLlmApi(ApiConfig cfg, String? apiKey, {Dio? dio}) {
  final d = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120)));
  return switch (cfg.format) {
    ApiFormat.openai => OpenAiCompatibleApi(cfg, apiKey, d),
    ApiFormat.anthropic => AnthropicApi(cfg, apiKey, d),
  };
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

LlmException _wrap(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  String? detail;
  if (data is Map) {
    final err = data['error'];
    detail = err is Map ? err['message']?.toString() : err?.toString();
  }
  if (status == 401 || status == 403) {
    return LlmException('Odrzucono klucz API (${status ?? ''}). ${detail ?? ''}'.trim(),
        statusCode: status);
  }
  if (status != null) {
    return LlmException('Błąd dostawcy ($status). ${detail ?? ''}'.trim(), statusCode: status);
  }
  return LlmException('Brak połączenia z ${e.requestOptions.uri.host}: ${e.message}');
}

class OpenAiCompatibleApi implements LlmApi {
  OpenAiCompatibleApi(this.cfg, this.key, this.dio);
  final ApiConfig cfg;
  final String? key;
  final Dio dio;

  @override
  Future<LlmResult> complete({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 2048,
  }) async {
    final content = image == null
        ? user
        : [
            {'type': 'text', 'text': user},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$imageMime;base64,${base64Encode(image)}'},
            },
          ];
    Future<Response> send(bool withJsonMode) => dio.post(
          '${_trimSlash(cfg.baseUrl)}/chat/completions',
          options: Options(headers: {
            if (key != null && key!.isNotEmpty) 'Authorization': 'Bearer $key',
          }),
          data: {
            'model': cfg.model,
            'temperature': 0,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': content},
            ],
            if (withJsonMode) 'response_format': {'type': 'json_object'},
          },
        );
    try {
      Response r;
      try {
        r = await send(json);
      } on DioException catch (e) {
        // Some OpenAI-compatible servers reject response_format; retry plain.
        if (json && e.response?.statusCode == 400) {
          r = await send(false);
        } else {
          rethrow;
        }
      }
      final data = r.data as Map;
      final text = (data['choices'] as List).first['message']['content'] as String? ?? '';
      final usage = data['usage'] as Map?;
      return LlmResult(text,
          inputTokens: (usage?['prompt_tokens'] as int?) ?? 0,
          outputTokens: (usage?['completion_tokens'] as int?) ?? 0);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
}

class AnthropicApi implements LlmApi {
  AnthropicApi(this.cfg, this.key, this.dio);
  final ApiConfig cfg;
  final String? key;
  final Dio dio;

  @override
  Future<LlmResult> complete({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 2048,
  }) async {
    try {
      final r = await dio.post(
        '${_trimSlash(cfg.baseUrl)}/v1/messages',
        options: Options(headers: {
          'x-api-key': key ?? '',
          'anthropic-version': '2023-06-01',
        }),
        data: {
          'model': cfg.model,
          'max_tokens': maxTokens,
          'temperature': 0,
          'system': system,
          'messages': [
            {
              'role': 'user',
              'content': [
                if (image != null)
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': imageMime,
                      'data': base64Encode(image),
                    },
                  },
                {'type': 'text', 'text': user},
              ],
            },
          ],
        },
      );
      final data = r.data as Map;
      final text = (data['content'] as List)
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'])
          .join();
      final usage = data['usage'] as Map?;
      return LlmResult(text,
          inputTokens: (usage?['input_tokens'] as int?) ?? 0,
          outputTokens: (usage?['output_tokens'] as int?) ?? 0);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
}
