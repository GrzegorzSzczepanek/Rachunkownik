import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';
import 'theme.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    required this.downloadUrl,
  });

  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String downloadUrl;
}

abstract class AppUpdateClient {
  Future<AppUpdateInfo?> checkForUpdate();
}

class GitHubUpdateClient implements AppUpdateClient {
  GitHubUpdateClient({
    this.repo = githubRepo,
    this.currentSha = buildCommitSha,
    this.currentVersion = appVersion,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {'Accept': 'application/vnd.github.v3+json'},
            ));

  final String repo;
  final String currentSha;
  final String currentVersion;
  final Dio _dio;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      // 1. Check GitHub Releases first (for published APK assets or release tags)
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          'https://api.github.com/repos/$repo/releases/latest',
        );
        if (res.statusCode == 200 && res.data != null) {
          final data = res.data!;
          final tag = data['tag_name']?.toString() ?? '';
          final htmlUrl = data['html_url']?.toString() ?? 'https://github.com/$repo/releases';
          final body = data['body']?.toString();

          String? apkUrl;
          final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final a in assets) {
            final name = a['name']?.toString().toLowerCase() ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = a['browser_download_url']?.toString();
              break;
            }
          }

          final cleanTag = tag.replaceFirst(RegExp(r'^v'), '');
          if (cleanTag.isNotEmpty && cleanTag != currentVersion) {
            return AppUpdateInfo(
              hasUpdate: true,
              currentVersion: currentVersion,
              latestVersion: tag,
              releaseNotes: body,
              downloadUrl: apkUrl ?? htmlUrl,
            );
          }
        }
      } catch (_) {
        // Releases endpoint returns 404 when no releases are published yet; continue to commits check
      }

      // 2. Check latest commit on repo
      try {
        final commitRes = await _dio.get<List<dynamic>>(
          'https://api.github.com/repos/$repo/commits',
          queryParameters: {'per_page': 1},
        );
        if (commitRes.statusCode == 200 && commitRes.data != null && commitRes.data!.isNotEmpty) {
          final first = commitRes.data!.first as Map<String, dynamic>;
          final sha = first['sha']?.toString() ?? '';
          final shortSha = sha.length > 7 ? sha.substring(0, 7) : sha;
          final commitObj = first['commit'] as Map<String, dynamic>?;
          final message = (commitObj?['message']?.toString() ?? '').trim().split('\n').first;

          final curShort = currentSha.length > 7 ? currentSha.substring(0, 7) : currentSha;
          final isDifferentCommit = currentSha.isNotEmpty &&
              sha.isNotEmpty &&
              !sha.startsWith(currentSha) &&
              !currentSha.startsWith(sha);

          if (isDifferentCommit) {
            return AppUpdateInfo(
              hasUpdate: true,
              currentVersion: curShort.isEmpty ? currentVersion : curShort,
              latestVersion: shortSha.isEmpty ? 'Nowa wersja' : '$shortSha: $message',
              releaseNotes: message,
              downloadUrl: 'https://github.com/$repo/releases',
            );
          }
        }
      } catch (_) {
        // Fall through
      }

      return AppUpdateInfo(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        downloadUrl: 'https://github.com/$repo/releases',
      );
    } catch (_) {
      return null;
    }
  }
}

Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo update) async {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.system_update_rounded, color: AppColors.green),
        SizedBox(width: 10),
        Text('Nowa wersja'),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wykryto nowszą wersję w repozytorium Rachunkownik:'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.chip,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              update.latestVersion,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          if (update.releaseNotes != null && update.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              update.releaseNotes!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Czy chcesz pobrać najnowszą wersję?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Później'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          onPressed: () async {
            Navigator.pop(ctx);
            final uri = Uri.parse(update.downloadUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: const Text('Pobierz'),
        ),
      ],
    ),
  );
}
