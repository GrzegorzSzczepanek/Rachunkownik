import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/core/app_update.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }
}

void main() {
  group('GitHubUpdateClient', () {
    test('detects update from GitHub release with APK asset', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) {
        if (options.path.contains('/releases/latest')) {
          return ResponseBody.fromString(
            '''{
              "tag_name": "v1.1.0",
              "html_url": "https://github.com/GrzegorzSzczepanek/Rachunkownik/releases/tag/v1.1.0",
              "body": "Nowe funkcje i poprawki",
              "assets": [
                {
                  "name": "rachunkownik-release.apk",
                  "browser_download_url": "https://github.com/GrzegorzSzczepanek/Rachunkownik/releases/download/v1.1.0/app.apk"
                }
              ]
            }''',
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        return ResponseBody.fromString('Not found', 404);
      });

      final client = GitHubUpdateClient(
        currentVersion: '1.0.0',
        dio: dio,
      );

      final update = await client.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.hasUpdate, isTrue);
      expect(update.latestVersion, 'v1.1.0');
      expect(update.releaseNotes, 'Nowe funkcje i poprawki');
      expect(update.downloadUrl, contains('app.apk'));
    });

    test('detects update from commits when no releases published', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) {
        if (options.path.contains('/releases/latest')) {
          return ResponseBody.fromString('{"message":"Not Found"}', 404);
        }
        if (options.path.contains('/commits')) {
          return ResponseBody.fromString(
            '''[
              {
                "sha": "abcdef1234567890",
                "html_url": "https://github.com/GrzegorzSzczepanek/Rachunkownik/commit/abcdef1",
                "commit": {
                  "message": "Dodano nowe wykresy\\n\\nOpis"
                }
              }
            ]''',
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        return ResponseBody.fromString('Not found', 404);
      });

      final client = GitHubUpdateClient(
        currentSha: '0000000000',
        currentVersion: '1.0.0',
        dio: dio,
      );

      final update = await client.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.hasUpdate, isTrue);
      expect(update.latestVersion, contains('abcdef1'));
      expect(update.latestVersion, contains('Dodano nowe wykresy'));
    });

    test('reports no update when version and commit match', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) {
        if (options.path.contains('/releases/latest')) {
          return ResponseBody.fromString(
            '{"tag_name": "v1.0.0", "html_url": "https://github.com/test"}',
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        return ResponseBody.fromString('[]', 200);
      });

      final client = GitHubUpdateClient(
        currentSha: 'abcdef12',
        currentVersion: '1.0.0',
        dio: dio,
      );

      final update = await client.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.hasUpdate, isFalse);
    });
  });

  group('showUpdateDialog', () {
    testWidgets('renders update dialog with version, notes and buttons', (tester) async {
      const update = AppUpdateInfo(
        hasUpdate: true,
        currentVersion: '1.0.0',
        latestVersion: 'v1.1.0',
        releaseNotes: 'Szybkie skanowanie',
        downloadUrl: 'https://github.com/GrzegorzSzczepanek/Rachunkownik/releases',
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showUpdateDialog(context, update),
            child: const Text('Sprawdź'),
          ),
        ),
      ));

      await tester.tap(find.text('Sprawdź'));
      await tester.pumpAndSettle();

      expect(find.text('Nowa wersja'), findsOneWidget);
      expect(find.text('v1.1.0'), findsOneWidget);
      expect(find.text('Szybkie skanowanie'), findsOneWidget);
      expect(find.text('Pobierz'), findsOneWidget);
      expect(find.text('Później'), findsOneWidget);

      await tester.tap(find.text('Później'));
      await tester.pumpAndSettle();
      expect(find.text('Nowa wersja'), findsNothing);
    });
  });
}
