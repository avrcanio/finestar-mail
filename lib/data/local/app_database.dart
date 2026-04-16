import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get displayName => text()();
  TextColumn get imapHost => text()();
  IntColumn get imapPort => integer()();
  TextColumn get imapSecurity => text()();
  TextColumn get smtpHost => text()();
  IntColumn get smtpPort => integer()();
  TextColumn get smtpSecurity => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MailFolders extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get name => text()();
  TextColumn get path => text()();
  BoolColumn get isInbox => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MessageSummaries extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text()();
  TextColumn get subject => text()();
  TextColumn get sender => text()();
  TextColumn get preview => text()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get isRead => boolean()();
  BoolColumn get hasAttachments => boolean()();
  IntColumn get sequence => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MessageDetails extends Table {
  TextColumn get id => text()();
  TextColumn get subject => text()();
  TextColumn get sender => text()();
  TextColumn get recipients => text()();
  TextColumn get bodyPlain => text()();
  TextColumn get bodyHtml => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AttachmentMetadata extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text()();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get mimeType => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final file = File(p.join(documentsDirectory.path, 'finestar_mail.sqlite'));
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [
    Accounts,
    MailFolders,
    MessageSummaries,
    MessageDetails,
    AttachmentMetadata,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}
