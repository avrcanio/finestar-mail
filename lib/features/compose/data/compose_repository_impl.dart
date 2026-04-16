import 'package:logger/logger.dart';

import '../../../core/result/result.dart';
import '../domain/entities/outgoing_message.dart';
import '../domain/repositories/compose_repository.dart';

class ComposeRepositoryImpl implements ComposeRepository {
  ComposeRepositoryImpl({required Logger logger}) : _logger = logger;

  final Logger _logger;

  @override
  Future<Result<void>> send(OutgoingMessage message) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (message.to.isEmpty || message.subject.trim().isEmpty) {
      return const Failure<void>('Recipient and subject are required.');
    }

    _logger.i('Queued SMTP send for ${message.to.join(', ')}');
    return const Success<void>(null);
  }
}
