import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:finestar_mail/core/constants/app_strings.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';

import '../../../app/router/app_route.dart';
import 'auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccountAsync = ref.watch(activeAccountProvider);
    activeAccountAsync.whenData((account) {
      final target = account == null
          ? AppRoute.login.path
          : AppRoute.inbox.path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(target);
        }
      });
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7EEE3), Color(0xFFE9D6C6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const SectionCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mail_lock_outlined, size: 56),
                  SizedBox(height: 16),
                  Text(
                    AppStrings.appName,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
