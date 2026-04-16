import '../../../../core/result/result.dart';
import '../entities/outgoing_message.dart';

abstract class ComposeRepository {
  Future<Result<void>> send(OutgoingMessage message);
}
