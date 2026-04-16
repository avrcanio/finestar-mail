import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/mail/send',
      token: token,
      body: request.toJson(),
    );
    return BackendSendResponse.fromJson(json);
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
    if (currentCode == 'invalid_folder' ||
        currentCode == 'empty_uid_list' ||
        currentCode == 'invalid_uid') {
      return 'The delete request was invalid.';
    }
    if (currentCode == 'delete_from_trash_not_supported') {
      return 'Messages in Trash cannot be deleted from the app yet.';
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
  });

  final String name;
  final String? delimiter;
  final List<String> flags;

  factory BackendFolderDto.fromJson(Map<String, dynamic> json) {
    return BackendFolderDto(
      name: json['name'] as String? ?? '',
      delimiter: json['delimiter'] as String?,
      flags: _listOfStrings(json['flags']),
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
    required this.filename,
    required this.contentType,
    required this.size,
    required this.disposition,
  });

  final String? filename;
  final String contentType;
  final int? size;
  final String? disposition;

  factory BackendAttachmentDto.fromJson(Map<String, dynamic> json) {
    return BackendAttachmentDto(
      filename: json['filename'] as String?,
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int?,
      disposition: json['disposition'] as String?,
    );
  }
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
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String textBody;
  final String htmlBody;
  final String? replyTo;
  final String fromDisplayName;

  Map<String, dynamic> toJson() => {
    'to': to,
    'cc': cc,
    'bcc': bcc,
    'subject': subject,
    'text_body': textBody,
    'html_body': htmlBody,
    'reply_to': replyTo,
    'from_display_name': fromDisplayName,
  };
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

DateTime? _dateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
