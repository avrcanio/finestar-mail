import 'package:finestar_mail/features/mailbox/domain/archive_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_conversation.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectableArchiveFolderPath', () {
    test('returns null when no selectable folders', () {
      expect(
        selectableArchiveFolderPath([
          const MailFolder(
            id: 'a',
            name: 'Archive',
            path: 'INBOX/Archive',
            isInbox: false,
            selectable: false,
          ),
        ]),
        isNull,
      );
    });

    test('prefers exact path Archive (case-insensitive)', () {
      expect(
        selectableArchiveFolderPath([
          const MailFolder(
            id: '1',
            name: 'Nested',
            path: 'INBOX/Archive',
            isInbox: false,
          ),
          const MailFolder(
            id: '2',
            name: 'Archive',
            path: 'Archive',
            isInbox: false,
          ),
        ]),
        'Archive',
      );
    });

    test('picks shortest path among Archive suffix candidates', () {
      expect(
        selectableArchiveFolderPath([
          const MailFolder(
            id: '1',
            name: 'Deep',
            path: 'INBOX/Projects/Archive',
            isInbox: false,
          ),
          const MailFolder(
            id: '2',
            name: 'Shallow',
            path: 'INBOX/Archive',
            isInbox: false,
          ),
        ]),
        'INBOX/Archive',
      );
    });
  });

  group('messageIdsInConversationForFolder', () {
    test('yields only messages matching folder id', () {
      final conv = MailConversation(
        id: 'c1',
        messageCount: 2,
        replyCount: 1,
        hasUnread: false,
        hasAttachments: false,
        hasVisibleAttachments: false,
        participants: const [],
        rootMessage: MailMessageSummary(
          id: 'm1',
          folderId: 'inbox-id',
          subject: 'a',
          sender: 'a@b.c',
          preview: '',
          receivedAt: DateTime.now(),
          isRead: true,
          hasAttachments: false,
          sequence: 1,
        ),
        replies: [
          MailMessageSummary(
            id: 'm2',
            folderId: 'sent-id',
            subject: 'b',
            sender: 'a@b.c',
            preview: '',
            receivedAt: DateTime.now(),
            isRead: true,
            hasAttachments: false,
            sequence: 2,
          ),
        ],
        latestDate: DateTime.now(),
      );
      expect(
        messageIdsInConversationForFolder(
          conv,
          const MailFolder(
            id: 'inbox-id',
            name: 'INBOX',
            path: 'INBOX',
            isInbox: true,
          ),
        ).toList(),
        ['m1'],
      );
    });
  });

  group('isArchiveFolderPath', () {
    test('detects archive by path or name', () {
      expect(isArchiveFolderPath('Archive', ''), isTrue);
      expect(isArchiveFolderPath('INBOX/Archive', 'Nested'), isTrue);
      expect(isArchiveFolderPath('INBOX', 'Inbox'), isFalse);
    });
  });
}
