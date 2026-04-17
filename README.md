# FS Mail

<p align="center">
  <img src="assets/images/fs_mail_logo.png" alt="FS Mail Logo" width="300" />
</p>

<p align="center">
  Modern email experience for the Fine Star ecosystem.<br>
  Built with a Flutter client, a Django backend, and a backend-first architecture.
</p>

---

## Overview

FS Mail is a modern mail application project designed to deliver a cleaner, more maintainable email experience.

Instead of relying on direct IMAP/SMTP access in the mobile client, FS Mail moves core mail operations into the backend. That gives the project a stronger foundation for authentication, mailbox access, message retrieval, attachments, push notifications, and future mailbox features.

## What FS Mail includes

### Mobile app

The Flutter / Android client is focused on everyday mailbox workflows:

- login and account access
- folder and mailbox navigation
- message list and message detail views
- compose and send flows
- HTML email rendering
- attachment handling
- push notification support
- conversation-oriented mail UX

### Backend

The Django backend powers the app with a dedicated mail API:

- authentication and session endpoints
- IMAP mailbox read services
- SMTP send services
- folder, message list, and message detail APIs
- attachment metadata and mail operations
- push registration and delivery support
- documented API schema and integration layer

## Architecture

FS Mail follows a backend-first approach.

The mobile app focuses on user experience, navigation, and local UI state.
The backend handles mailbox communication, mail parsing, sending, and the API contract used by the client.

This separation makes the project easier to extend with features such as attachments, mailbox actions, multi-account flows, threaded conversations, and operational mail services.

## Project scope

FS Mail is being developed around these product areas:

- backend-driven mailbox access
- mobile-first email experience
- HTML and attachment-friendly message rendering
- push-aware mailbox updates
- support for richer conversation views
- scalable foundation for multi-account workflows

## Related infrastructure

This repository focuses on the application and API side of FS Mail.

A related `mailserver` repository covers the infrastructure layer, including mail server operations and supporting backend-side operational capabilities.

## Development

### Flutter / Android

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --debug
```

### Backend

```bash
docker compose build mailadmin
docker compose run --rm mailadmin python manage.py test
docker compose run --rm mailadmin python manage.py spectacular --file /tmp/schema.yaml
```

## Ownership

FS Mail is a project of **Fine Star**.

- Website: [www.finestar.hr](https://www.finestar.hr)

## License

Add the project license information here.
