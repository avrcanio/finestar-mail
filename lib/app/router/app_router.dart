import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/compose/domain/entities/reply_context.dart';
import '../../features/compose/domain/entities/share_compose_args.dart';
import '../../features/compose/presentation/compose_screen.dart';
import '../../features/compose/presentation/share_compose_entry_screen.dart';
import '../../features/mailbox/presentation/mailbox_screen.dart';
import '../../features/mailbox/presentation/message_detail_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../core/platform/share_intent_service.dart';
import 'app_route.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.splash.path,
    routes: [
      GoRoute(
        path: AppRoute.splash.path,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.login.path,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.inbox.path,
        builder: (context, state) => const MailboxScreen(),
      ),
      GoRoute(
        path: AppRoute.messageDetail.path,
        builder: (context, state) =>
            MessageDetailScreen(messageId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoute.shareCompose.path,
        builder: (context, state) => ShareComposeEntryScreen(
          files: state.extra is List<SharedFile>
              ? state.extra! as List<SharedFile>
              : const [],
        ),
      ),
      GoRoute(
        path: AppRoute.compose.path,
        builder: (context, state) {
          final extra = state.extra;
          return ComposeScreen(
            replyContext: extra is ReplyContext ? extra : null,
            shareArgs: extra is ShareComposeArgs ? extra : null,
          );
        },
      ),
      GoRoute(
        path: AppRoute.settings.path,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
