import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/mail_translation_languages.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_message_translation.dart';

final messageTranslationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<MessageTranslationController, MessageTranslationState, String>(
      MessageTranslationController.new,
    );

class MessageTranslationState {
  const MessageTranslationState({
    required this.targetLanguage,
    required this.showTranslated,
    this.translation,
  });

  final String targetLanguage;
  final bool showTranslated;
  final MailMessageTranslation? translation;

  MessageTranslationState copyWith({
    String? targetLanguage,
    bool? showTranslated,
    MailMessageTranslation? translation,
  }) {
    return MessageTranslationState(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      showTranslated: showTranslated ?? this.showTranslated,
      translation: translation ?? this.translation,
    );
  }
}

class MessageTranslationController extends AsyncNotifier<MessageTranslationState> {
  MessageTranslationController(this.messageId);

  final String messageId;

  static const fallbackLanguage = kMailTranslationDefaultLanguageCode;

  @override
  Future<MessageTranslationState> build() async {
    final storage = ref.read(secureStorageServiceProvider);
    final stored = await storage.readMailTranslationTargetLanguage();
    final normalized = stored?.trim();
    final target =
        (normalized == null || normalized.isEmpty) ? fallbackLanguage : stored!;
    return MessageTranslationState(
      targetLanguage: target,
      showTranslated: false,
      translation: null,
    );
  }

  Future<void> setTargetLanguage(String languageCode) async {
    final normalized = languageCode.trim();
    if (normalized.isEmpty) {
      return;
    }
    final storage = ref.read(secureStorageServiceProvider);
    await storage.saveMailTranslationTargetLanguage(normalized);
    state = AsyncData(
      (state.asData?.value ?? MessageTranslationState(
            targetLanguage: normalized,
            showTranslated: false,
          ))
          .copyWith(targetLanguage: normalized),
    );
  }

  Future<void> translate() async {
    final current = state.asData?.value;
    final targetLanguage = current?.targetLanguage ?? fallbackLanguage;
    final existing = current?.translation;

    if (existing != null &&
        existing.targetLanguage.trim().toLowerCase() ==
            targetLanguage.trim().toLowerCase()) {
      state = AsyncData(
        current!.copyWith(showTranslated: true),
      );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final account = await ref.read(activeAccountProvider.future);
      if (account == null) {
        throw StateError('Active account session is missing.');
      }
      final logger = ref.read(loggerProvider);
      final watch = Stopwatch()..start();
      try {
        final result = await ref
            .read(mailboxRepositoryProvider)
            .translateMessage(
              accountId: account.id,
              messageId: messageId,
              targetLanguage: targetLanguage,
            );
        watch.stop();
        logger.i(
          'mail.translate: messageId=$messageId target=$targetLanguage '
          'took=${watch.elapsedMilliseconds}ms cached=${result.cached} '
          'truncated=${result.truncated} folder=${result.folder} uid=${result.uid} '
          'htmlLen=${result.translatedHtml.length} textLen=${result.translatedText.length}',
        );
        return MessageTranslationState(
          targetLanguage: targetLanguage,
          showTranslated: true,
          translation: result,
        );
      } catch (error, stack) {
        watch.stop();
        logger.e(
          'mail.translate: failed messageId=$messageId target=$targetLanguage '
          'took=${watch.elapsedMilliseconds}ms',
          error: error,
          stackTrace: stack,
        );
        rethrow;
      }
    });
  }

  void toggleShowTranslated() {
    final current = state.asData?.value;
    final translation = current?.translation;
    if (current == null || translation == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(showTranslated: !current.showTranslated),
    );
  }
}

