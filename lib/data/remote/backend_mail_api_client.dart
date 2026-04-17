import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

typedef BackendBaseUrlLoader = Future<String> Function();

class BackendMailApiClient {
  BackendMailApiClient({
    required http.Client httpClient,
    required BackendBaseUrlLoader baseUrlLoader,
    this.timeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient,
       _baseUrlLoader = baseUrlLoader;

  final http.Client _httpClient;
  final BackendBaseUrlLoader _baseUrlLoader;
  final Duration timeout;

  Future<BackendLoginResponse> login({
    required String email,
    required String password,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/login',
      body: {'email': email, 'password': password},
    );
    return BackendLoginResponse.fromJson(json);
  }

  Future<BackendIdentityResponse> me({required String token}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/auth/me',
      token: token,
    );
    return BackendIdentityResponse.fromJson(json);
  }

  Future<BackendAccountSummariesResponse> accountSummaries({
    required String token,
    required String fcmToken,
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/accounts/summaries',
      queryParameters: {'fcm_token': fcmToken.trim()},
      token: token,
    );
    return BackendAccountSummariesResponse.fromJson(json);
  }

  Future<BackendFoldersResponse> folders({required String token}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/mail/folders',
      token: token,
    );
    return BackendFoldersResponse.fromJson(json);
  }

  Future<BackendMessagesResponse> messages({
    required String token,
    required String folder,
    required int limit,
    String? beforeUid,
  }) async {
    final trimmedBeforeUid = beforeUid?.trim();
    final json = await _requestJson(
      method: 'GET',
      path: '/api/mail/messages',
      queryParameters: {
        'folder': folder,
        'limit': '$limit',
        if (trimmedBeforeUid != null && trimmedBeforeUid.isNotEmpty)
          'before_uid': trimmedBeforeUid,
      },
      token: token,
    );
    return BackendMessagesResponse.fromJson(json);
  }

  Future<BackendConversationsResponse> conversations({
    required String token,
    required String folder,
    required int limit,
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/mail/conversations',
      queryParameters: {'folder': folder, 'limit': '$limit'},
      token: token,
    );
    return BackendConversationsResponse.fromJson(json);
  }

  Future<BackendUnifiedConversationsResponse> unifiedConversations({
    required String token,
    required int limit,
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/mail/unified-conversations',
      queryParameters: {'limit': '$limit'},
      token: token,
    );
    return BackendUnifiedConversationsResponse.fromJson(json);
  }

  Future<BackendMessageDetailResponse> messageDetail({
    required String token,
    required String folder,
    required String uid,
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/mail/messages/${Uri.encodeComponent(uid)}',
      queryParameters: {'folder': folder},
      token: token,
    );
    return BackendMessageDetailResponse.fromJson(json);
  }

  Future<BackendSendResponse> send({
    required String token,
    required BackendSendRequest request,
    List<BackendSendAttachment> attachments = const [],
  }) async {
    if (attachments.isNotEmpty) {
      return _sendMultipart(
        token: token,
        request: request,
        attachments: attachments,
      );
    }
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/send',
      token: token,
      body: request.toJson(),
    );
    return BackendSendResponse.fromJson(json);
  }

  Future<BackendAttachmentDownload> downloadAttachment({
    required String token,
    required String folder,
    required String uid,
    required String attachmentId,
  }) async {
    final uri = await _uri(
      '/api/mail/messages/${Uri.encodeComponent(uid)}/attachments/${Uri.encodeComponent(attachmentId)}',
      {'folder': folder},
    );
    final response = await _httpClient
        .get(
          uri,
          headers: {'Accept': '*/*', 'Authorization': 'Token ${token.trim()}'},
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _tryDecodeObject(utf8.decode(response.bodyBytes));
      throw BackendMailApiException(
        statusCode: response.statusCode,
        code: decoded['error'] as String?,
        detail: decoded['detail'] as String?,
      );
    }

    final contentDisposition = response.headers['content-disposition'];
    return BackendAttachmentDownload(
      bytes: response.bodyBytes,
      filename: _filenameFromContentDisposition(contentDisposition),
      contentType: response.headers['content-type'],
    );
  }

  Future<BackendDeleteResponse> deleteMessages({
    required String token,
    required String folder,
    required List<String> uids,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/messages/delete',
      token: token,
      body: {'folder': folder, 'uids': uids},
    );
    return BackendDeleteResponse.fromJson(json);
  }

  Future<BackendDeleteResponse> deleteMessage({
    required String token,
    required String folder,
    required String uid,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/messages/${Uri.encodeComponent(uid)}/delete',
      queryParameters: {'folder': folder},
      token: token,
    );
    return BackendDeleteResponse.fromJson(json);
  }

  Future<BackendRestoreResponse> restoreMessages({
    required String token,
    required String folder,
    required List<String> uids,
    required String targetFolder,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/messages/restore',
      token: token,
      body: {'folder': folder, 'uids': uids, 'target_folder': targetFolder},
    );
    return BackendRestoreResponse.fromJson(json);
  }

  Future<BackendRestoreResponse> restoreMessage({
    required String token,
    required String folder,
    required String uid,
    required String targetFolder,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/messages/${Uri.encodeComponent(uid)}/restore',
      queryParameters: {'folder': folder, 'target_folder': targetFolder},
      token: token,
    );
    return BackendRestoreResponse.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final uri = await _uri(path, queryParameters);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Token ${token.trim()}',
    };

    final response = await _send(
      method: method,
      uri: uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(timeout);

    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendMailApiException(
        statusCode: response.statusCode,
        code: decoded['error'] as String?,
        detail: decoded['detail'] as String?,
      );
    }
    return decoded;
  }

  Future<BackendSendResponse> _sendMultipart({
    required String token,
    required BackendSendRequest request,
    required List<BackendSendAttachment> attachments,
  }) async {
    final uri = await _uri('/api/mail/send', null);
    final multipart = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Token ${token.trim()}'
      ..fields.addAll(request.toMultipartScalarFields());

    for (final recipient in request.to) {
      multipart.files.add(http.MultipartFile.fromString('to', recipient));
    }
    for (final recipient in request.cc) {
      multipart.files.add(http.MultipartFile.fromString('cc', recipient));
    }
    for (final recipient in request.bcc) {
      multipart.files.add(http.MultipartFile.fromString('bcc', recipient));
    }
    final replyTo = request.replyTo;
    if (replyTo != null && replyTo.trim().isNotEmpty) {
      multipart.files.add(http.MultipartFile.fromString('reply_to', replyTo));
    }

    for (final attachment in attachments) {
      multipart.files.add(
        http.MultipartFile.fromBytes(
          'attachments',
          attachment.bytes,
          filename: attachment.filename,
          contentType: _mediaType(attachment.contentType),
        ),
      );
    }

    final streamed = await _httpClient.send(multipart).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendMailApiException(
        statusCode: response.statusCode,
        code: decoded['error'] as String?,
        detail: decoded['detail'] as String?,
      );
    }
    return BackendSendResponse.fromJson(decoded);
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    switch (method) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'POST':
        return _httpClient.post(uri, headers: headers, body: body);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  Future<Uri> _uri(String path, Map<String, String>? queryParameters) async {
    final rawBaseUrl = (await _baseUrlLoader()).trim();
    if (rawBaseUrl.isEmpty) {
      throw const BackendMailApiException(
        code: 'missing_base_url',
        detail: 'Backend API base URL is not configured.',
      );
    }

    final baseUri = Uri.parse(rawBaseUrl.replaceFirst(RegExp(r'/+$'), ''));
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(
      path:
          '${baseUri.path}${normalizedPath.startsWith('/') ? normalizedPath : '/$normalizedPath'}',
      queryParameters: queryParameters,
    );
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Expected a JSON object response.');
  }

  Map<String, dynamic> _tryDecodeObject(String body) {
    try {
      return _decodeObject(body);
    } catch (_) {
      return const {};
    }
  }

  String? _filenameFromContentDisposition(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final utf8Match = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(value);
    if (utf8Match != null) {
      return Uri.decodeComponent(utf8Match.group(1)!);
    }
    final quotedMatch = RegExp(
      r'filename="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(value);
    if (quotedMatch != null) {
      return quotedMatch.group(1);
    }
    final plainMatch = RegExp(
      r'filename=([^;]+)',
      caseSensitive: false,
    ).firstMatch(value);
    return plainMatch?.group(1)?.trim();
  }
}

class BackendMailApiException implements Exception {
  const BackendMailApiException({this.statusCode, this.code, this.detail});

  final int? statusCode;
  final String? code;
  final String? detail;

  bool get isUnauthorized => statusCode == 401 || code == 'not_authenticated';

  String get userMessage {
    final currentCode = code;
    if (currentCode == 'missing_base_url') {
      return detail ?? 'Backend API base URL is not configured.';
    }
    if (currentCode == 'mail_auth_failed' ||
        currentCode == 'not_authenticated') {
      return 'Mailbox authentication failed. Check your email and password.';
    }
    if (currentCode == 'invalid_limit' || currentCode == 'invalid_before_uid') {
      return 'The mailbox request was invalid.';
    }
    if (currentCode == 'restore_source_not_trash' ||
        currentCode == 'invalid_target_folder' ||
        currentCode == 'restore_target_is_trash') {
      return 'The restore request was invalid.';
    }
    if (currentCode == 'invalid_folder' ||
        currentCode == 'empty_uid_list' ||
        currentCode == 'invalid_uid') {
      return 'The mailbox action request was invalid.';
    }
    if (currentCode == 'delete_from_trash_not_supported') {
      return 'Messages in Trash cannot be deleted from the app yet.';
    }
    if (currentCode == 'attachment_not_found') {
      return 'Attachment could not be found.';
    }
    if (currentCode == 'attachment_too_large') {
      return 'Attachment is too large to send.';
    }
    if (currentCode == 'attachments_too_large') {
      return 'Attachments are too large to send together.';
    }
    if (currentCode == 'invalid_attachment_payload') {
      return 'The attachment payload was invalid.';
    }
    if (currentCode == 'forward_attachment_not_visible') {
      return 'One forwarded attachment cannot be sent.';
    }
    if (currentCode == 'forward_attachment_not_found') {
      return 'One forwarded attachment could not be found.';
    }
    if (currentCode == 'mail_timeout') {
      return 'The mail server timed out. Try again.';
    }
    if (currentCode == 'mail_connection_failed') {
      return 'The backend could not connect to the mail server.';
    }
    if (currentCode == 'mail_send_failed') {
      return 'The backend could not send the message.';
    }
    if (detail != null && detail!.trim().isNotEmpty) {
      return detail!;
    }
    if (statusCode != null) {
      return 'Backend request failed with status $statusCode.';
    }
    return 'Backend request failed.';
  }

  @override
  String toString() => userMessage;
}

class BackendLoginResponse {
  const BackendLoginResponse({
    required this.authenticated,
    required this.accountEmail,
    required this.token,
    this.folderCount,
  });

  final bool authenticated;
  final String accountEmail;
  final String token;
  final int? folderCount;

  factory BackendLoginResponse.fromJson(Map<String, dynamic> json) {
    return BackendLoginResponse(
      authenticated: json['authenticated'] as bool? ?? false,
      accountEmail: json['account_email'] as String? ?? '',
      token: json['token'] as String? ?? '',
      folderCount: json['folder_count'] as int?,
    );
  }
}

class BackendIdentityResponse {
  const BackendIdentityResponse({
    required this.authenticated,
    required this.accountEmail,
  });

  final bool authenticated;
  final String accountEmail;

  factory BackendIdentityResponse.fromJson(Map<String, dynamic> json) {
    return BackendIdentityResponse(
      authenticated: json['authenticated'] as bool? ?? false,
      accountEmail: json['account_email'] as String? ?? '',
    );
  }
}

class BackendAccountSummariesResponse {
  const BackendAccountSummariesResponse({required this.accounts});

  final List<BackendAccountSummaryDto> accounts;

  factory BackendAccountSummariesResponse.fromJson(Map<String, dynamic> json) {
    return BackendAccountSummariesResponse(
      accounts: _listOfObjects(
        json['accounts'],
      ).map(BackendAccountSummaryDto.fromJson).toList(),
    );
  }
}

class BackendAccountSummaryDto {
  const BackendAccountSummaryDto({
    required this.accountEmail,
    required this.displayName,
    required this.unreadCount,
    required this.importantCount,
  });

  final String accountEmail;
  final String displayName;
  final int unreadCount;
  final int importantCount;

  factory BackendAccountSummaryDto.fromJson(Map<String, dynamic> json) {
    return BackendAccountSummaryDto(
      accountEmail: json['account_email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      unreadCount: json['unread_count'] is num
          ? (json['unread_count'] as num).toInt()
          : 0,
      importantCount: json['important_count'] is num
          ? (json['important_count'] as num).toInt()
          : 0,
    );
  }
}

class BackendFoldersResponse {
  const BackendFoldersResponse({
    required this.accountEmail,
    required this.folders,
  });

  final String accountEmail;
  final List<BackendFolderDto> folders;

  factory BackendFoldersResponse.fromJson(Map<String, dynamic> json) {
    return BackendFoldersResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folders: _listOfObjects(
        json['folders'],
      ).map(BackendFolderDto.fromJson).toList(),
    );
  }
}

class BackendFolderDto {
  const BackendFolderDto({
    required this.name,
    required this.delimiter,
    required this.flags,
    this.path,
    this.displayName,
    this.parentPath,
    this.depth,
    this.selectable = true,
  });

  final String name;
  final String? delimiter;
  final List<String> flags;
  final String? path;
  final String? displayName;
  final String? parentPath;
  final int? depth;
  final bool selectable;

  factory BackendFolderDto.fromJson(Map<String, dynamic> json) {
    return BackendFolderDto(
      name: json['name'] as String? ?? '',
      delimiter: json['delimiter'] as String?,
      flags: _listOfStrings(json['flags']),
      path: json['path'] as String?,
      displayName: json['display_name'] as String?,
      parentPath: json['parent_path'] as String?,
      depth: json['depth'] is num ? (json['depth'] as num).toInt() : null,
      selectable: json['selectable'] as bool? ?? true,
    );
  }
}

class BackendMessagesResponse {
  const BackendMessagesResponse({
    required this.accountEmail,
    required this.folder,
    required this.messages,
    required this.hasMore,
    this.nextBeforeUid,
  });

  final String accountEmail;
  final String folder;
  final List<BackendMessageSummaryDto> messages;
  final bool hasMore;
  final String? nextBeforeUid;

  factory BackendMessagesResponse.fromJson(Map<String, dynamic> json) {
    final nextBeforeUid = json['next_before_uid']?.toString().trim();
    return BackendMessagesResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folder: json['folder'] as String? ?? 'INBOX',
      messages: _listOfObjects(
        json['messages'],
      ).map(BackendMessageSummaryDto.fromJson).toList(),
      hasMore: json['has_more'] as bool? ?? false,
      nextBeforeUid: nextBeforeUid == null || nextBeforeUid.isEmpty
          ? null
          : nextBeforeUid,
    );
  }
}

class BackendConversationsResponse {
  const BackendConversationsResponse({
    required this.accountEmail,
    required this.folder,
    required this.conversations,
  });

  final String accountEmail;
  final String folder;
  final List<BackendConversationDto> conversations;

  factory BackendConversationsResponse.fromJson(Map<String, dynamic> json) {
    return BackendConversationsResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folder: json['folder'] as String? ?? 'INBOX',
      conversations: _listOfObjects(
        json['conversations'],
      ).map(BackendConversationDto.fromJson).toList(),
    );
  }
}

class BackendConversationDto {
  const BackendConversationDto({
    required this.conversationId,
    required this.messageCount,
    required this.replyCount,
    required this.hasUnread,
    required this.hasAttachments,
    required this.hasVisibleAttachments,
    required this.participants,
    required this.rootMessage,
    required this.replies,
    required this.latestDate,
  });

  final String conversationId;
  final int messageCount;
  final int replyCount;
  final bool hasUnread;
  final bool hasAttachments;
  final bool hasVisibleAttachments;
  final List<BackendConversationParticipantDto> participants;
  final BackendMessageSummaryDto rootMessage;
  final List<BackendMessageSummaryDto> replies;
  final DateTime? latestDate;

  factory BackendConversationDto.fromJson(Map<String, dynamic> json) {
    return BackendConversationDto(
      conversationId: json['conversation_id'] as String? ?? '',
      messageCount: json['message_count'] is num
          ? (json['message_count'] as num).toInt()
          : 0,
      replyCount: json['reply_count'] is num
          ? (json['reply_count'] as num).toInt()
          : 0,
      hasUnread: json['has_unread'] as bool? ?? false,
      hasAttachments: json['has_attachments'] as bool? ?? false,
      hasVisibleAttachments: json['has_visible_attachments'] as bool? ?? false,
      participants: _conversationParticipants(json['participants']),
      rootMessage: BackendMessageSummaryDto.fromJson(
        json['root_message'] as Map<String, dynamic>? ?? const {},
      ),
      replies: _listOfObjects(
        json['replies'],
      ).map(BackendMessageSummaryDto.fromJson).toList(),
      latestDate: _dateTime(json['latest_date']),
    );
  }
}

class BackendConversationParticipantDto {
  const BackendConversationParticipantDto({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}

class BackendUnifiedConversationsResponse {
  const BackendUnifiedConversationsResponse({
    required this.accountEmail,
    required this.folders,
    required this.conversations,
  });

  final String accountEmail;
  final List<BackendFolderDto> folders;
  final List<BackendUnifiedConversationDto> conversations;

  factory BackendUnifiedConversationsResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return BackendUnifiedConversationsResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folders: _listOfObjects(json['folders'])
          .map(BackendFolderDto.fromJson)
          .toList(),
      conversations: _listOfObjects(
        json['conversations'],
      ).map(BackendUnifiedConversationDto.fromJson).toList(),
    );
  }
}

class BackendUnifiedConversationDto {
  const BackendUnifiedConversationDto({
    required this.conversationId,
    required this.messageCount,
    required this.replyCount,
    required this.hasUnread,
    required this.hasAttachments,
    required this.hasVisibleAttachments,
    required this.participants,
    required this.messages,
    required this.latestDate,
  });

  final String conversationId;
  final int messageCount;
  final int replyCount;
  final bool hasUnread;
  final bool hasAttachments;
  final bool hasVisibleAttachments;
  final List<BackendConversationParticipantDto> participants;
  final List<BackendUnifiedConversationMessageDto> messages;
  final DateTime? latestDate;

  factory BackendUnifiedConversationDto.fromJson(Map<String, dynamic> json) {
    return BackendUnifiedConversationDto(
      conversationId: json['conversation_id'] as String? ?? '',
      messageCount: json['message_count'] is num
          ? (json['message_count'] as num).toInt()
          : 0,
      replyCount: json['reply_count'] is num
          ? (json['reply_count'] as num).toInt()
          : 0,
      hasUnread: json['has_unread'] as bool? ?? false,
      hasAttachments: json['has_attachments'] as bool? ?? false,
      hasVisibleAttachments: json['has_visible_attachments'] as bool? ?? false,
      participants: _conversationParticipants(json['participants']),
      messages: _listOfObjects(
        json['messages'],
      ).map(BackendUnifiedConversationMessageDto.fromJson).toList(),
      latestDate: _dateTime(json['latest_date']),
    );
  }
}

class BackendUnifiedConversationMessageDto {
  const BackendUnifiedConversationMessageDto({
    required this.summary,
    required this.direction,
  });

  final BackendMessageSummaryDto summary;
  final String direction;

  factory BackendUnifiedConversationMessageDto.fromJson(
    Map<String, dynamic> json,
  ) {
    return BackendUnifiedConversationMessageDto(
      summary: BackendMessageSummaryDto.fromJson(json),
      direction: json['direction'] as String? ?? 'inbound',
    );
  }
}

class BackendMessageDetailResponse {
  const BackendMessageDetailResponse({
    required this.accountEmail,
    required this.folder,
    required this.message,
  });

  final String accountEmail;
  final String folder;
  final BackendMessageDetailDto message;

  factory BackendMessageDetailResponse.fromJson(Map<String, dynamic> json) {
    return BackendMessageDetailResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folder: json['folder'] as String? ?? 'INBOX',
      message: BackendMessageDetailDto.fromJson(
        json['message'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class BackendMessageSummaryDto {
  const BackendMessageSummaryDto({
    required this.uid,
    required this.folder,
    required this.subject,
    required this.sender,
    required this.to,
    required this.cc,
    required this.date,
    required this.messageId,
    required this.flags,
    required this.size,
    required this.hasAttachments,
    this.hasVisibleAttachments,
  });

  final String uid;
  final String folder;
  final String subject;
  final String sender;
  final List<String> to;
  final List<String> cc;
  final DateTime? date;
  final String messageId;
  final List<String> flags;
  final int? size;
  final bool hasAttachments;
  final bool? hasVisibleAttachments;

  factory BackendMessageSummaryDto.fromJson(Map<String, dynamic> json) {
    return BackendMessageSummaryDto(
      uid: json['uid'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      to: _listOfStrings(json['to']),
      cc: _listOfStrings(json['cc']),
      date: _dateTime(json['date']),
      messageId: json['message_id'] as String? ?? '',
      flags: _listOfStrings(json['flags']),
      size: json['size'] as int?,
      hasAttachments: json['has_attachments'] as bool? ?? false,
      hasVisibleAttachments: json.containsKey('has_visible_attachments')
          ? json['has_visible_attachments'] as bool? ?? false
          : null,
    );
  }
}

class BackendMessageDetailDto extends BackendMessageSummaryDto {
  const BackendMessageDetailDto({
    required super.uid,
    required super.folder,
    required super.subject,
    required super.sender,
    required super.to,
    required super.cc,
    required super.date,
    required super.messageId,
    required super.flags,
    required super.size,
    required super.hasAttachments,
    super.hasVisibleAttachments,
    required this.textBody,
    required this.htmlBody,
    required this.attachments,
  });

  final String textBody;
  final String htmlBody;
  final List<BackendAttachmentDto> attachments;

  factory BackendMessageDetailDto.fromJson(Map<String, dynamic> json) {
    return BackendMessageDetailDto(
      uid: json['uid'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      to: _listOfStrings(json['to']),
      cc: _listOfStrings(json['cc']),
      date: _dateTime(json['date']),
      messageId: json['message_id'] as String? ?? '',
      flags: _listOfStrings(json['flags']),
      size: json['size'] as int?,
      hasAttachments: json['has_attachments'] as bool? ?? false,
      hasVisibleAttachments: json.containsKey('has_visible_attachments')
          ? json['has_visible_attachments'] as bool? ?? false
          : null,
      textBody: json['text_body'] as String? ?? '',
      htmlBody: json['html_body'] as String? ?? '',
      attachments: _listOfObjects(
        json['attachments'],
      ).map(BackendAttachmentDto.fromJson).toList(),
    );
  }
}

class BackendAttachmentDto {
  const BackendAttachmentDto({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.size,
    required this.disposition,
    required this.isInline,
    required this.contentId,
    required this.isVisible,
  });

  final String id;
  final String? filename;
  final String contentType;
  final int? size;
  final String? disposition;
  final bool isInline;
  final String contentId;
  final bool? isVisible;

  factory BackendAttachmentDto.fromJson(Map<String, dynamic> json) {
    return BackendAttachmentDto(
      id: json['id'] as String? ?? '',
      filename: json['filename'] as String?,
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int?,
      disposition: json['disposition'] as String?,
      isInline: json['is_inline'] as bool? ?? false,
      contentId: json['content_id'] as String? ?? '',
      isVisible: json.containsKey('is_visible')
          ? json['is_visible'] as bool? ?? false
          : null,
    );
  }
}

class BackendAttachmentDownload {
  const BackendAttachmentDownload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String? filename;
  final String? contentType;
}

class BackendSendRequest {
  const BackendSendRequest({
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.textBody,
    required this.htmlBody,
    required this.replyTo,
    required this.fromDisplayName,
    this.forwardSourceMessage,
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String textBody;
  final String htmlBody;
  final String? replyTo;
  final String fromDisplayName;
  final BackendForwardSourceMessage? forwardSourceMessage;

  Map<String, dynamic> toJson() => {
    'to': to,
    'cc': cc,
    'bcc': bcc,
    'subject': subject,
    'text_body': textBody,
    'html_body': htmlBody,
    'reply_to': replyTo,
    'from_display_name': fromDisplayName,
    if (forwardSourceMessage != null)
      'forward_source_message': forwardSourceMessage!.toJson(),
  };

  Map<String, String> toMultipartScalarFields() => {
    'subject': subject,
    'text_body': textBody,
    'html_body': htmlBody,
    'from_display_name': fromDisplayName,
    if (forwardSourceMessage != null)
      'forward_source_message': jsonEncode(forwardSourceMessage!.toJson()),
  };
}

class BackendForwardSourceMessage {
  const BackendForwardSourceMessage({
    required this.folder,
    required this.uid,
    required this.attachmentIds,
  });

  final String folder;
  final String uid;
  final List<String> attachmentIds;

  Map<String, dynamic> toJson() => {
    'folder': folder,
    'uid': uid,
    'attachment_ids': attachmentIds,
  };
}

class BackendSendAttachment {
  const BackendSendAttachment({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;
  final String contentType;
  final List<int> bytes;
}

class BackendSendResponse {
  const BackendSendResponse({
    required this.accountEmail,
    required this.status,
    required this.messageId,
  });

  final String accountEmail;
  final String status;
  final String? messageId;

  factory BackendSendResponse.fromJson(Map<String, dynamic> json) {
    return BackendSendResponse(
      accountEmail: json['account_email'] as String? ?? '',
      status: json['status'] as String? ?? '',
      messageId: json['message_id'] as String?,
    );
  }
}

class BackendDeleteResponse {
  const BackendDeleteResponse({
    required this.accountEmail,
    required this.folder,
    required this.trashFolder,
    required this.success,
    required this.partial,
    required this.movedToTrash,
    required this.failed,
  });

  final String accountEmail;
  final String folder;
  final String trashFolder;
  final bool success;
  final bool partial;
  final List<String> movedToTrash;
  final List<BackendDeleteFailureDto> failed;

  factory BackendDeleteResponse.fromJson(Map<String, dynamic> json) {
    return BackendDeleteResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      trashFolder: json['trash_folder'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      partial: json['partial'] as bool? ?? false,
      movedToTrash: _listOfStrings(json['moved_to_trash']),
      failed: _listOfObjects(
        json['failed'],
      ).map(BackendDeleteFailureDto.fromJson).toList(),
    );
  }
}

class BackendDeleteFailureDto {
  const BackendDeleteFailureDto({
    required this.uid,
    required this.error,
    required this.detail,
  });

  final String uid;
  final String error;
  final String detail;

  factory BackendDeleteFailureDto.fromJson(Map<String, dynamic> json) {
    return BackendDeleteFailureDto(
      uid: json['uid']?.toString() ?? '',
      error: json['error'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );
  }
}

class BackendRestoreResponse {
  const BackendRestoreResponse({
    required this.accountEmail,
    required this.folder,
    required this.targetFolder,
    required this.success,
    required this.partial,
    required this.restored,
    required this.failed,
  });

  final String accountEmail;
  final String folder;
  final String targetFolder;
  final bool success;
  final bool partial;
  final List<String> restored;
  final List<BackendDeleteFailureDto> failed;

  factory BackendRestoreResponse.fromJson(Map<String, dynamic> json) {
    return BackendRestoreResponse(
      accountEmail: json['account_email'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      targetFolder: json['target_folder'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      partial: json['partial'] as bool? ?? false,
      restored: _listOfStrings(json['restored']),
      failed: _listOfObjects(
        json['failed'],
      ).map(BackendDeleteFailureDto.fromJson).toList(),
    );
  }
}

List<Map<String, dynamic>> _listOfObjects(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map<String, dynamic>>().toList();
}

List<String> _listOfStrings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList();
}

List<BackendConversationParticipantDto> _conversationParticipants(
  Object? value,
) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) {
    if (item is Map<String, dynamic>) {
      return BackendConversationParticipantDto(
        name: item['name'] as String? ?? '',
        email: item['email'] as String? ?? '',
      );
    }
    final email = item.toString();
    return BackendConversationParticipantDto(name: '', email: email);
  }).toList();
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

MediaType _mediaType(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return MediaType('application', 'octet-stream');
  }
  try {
    return MediaType.parse(trimmed);
  } catch (_) {
    return MediaType('application', 'octet-stream');
  }
}
