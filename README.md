# FS Mail

<p align="center">
  <img src="assets/images/fs_mail_logo.png" alt="FS Mail Logo" width="300" />
</p>

FS Mail is an email application project owned by [Fine Star](https://www.finestar.hr).

The project is being developed as a modern mail solution with an Android client and a backend service. It is evolving from direct protocol-based access toward a backend-first architecture, where the client communicates with a dedicated API for authentication, mailbox access, message retrieval, and sending mail.

## Project Overview

FS Mail is designed to provide a cleaner and more maintainable email experience by separating the user-facing mobile app from the lower-level mail integration logic.

The project currently focuses on:

- Android mail experience
- backend API for authentication and mail operations
- mailbox folder listing and navigation
- message list and message detail flows
- sending email through backend services
- future-ready architecture for sync and message actions

## Project Ownership

FS Mail is a project of **Fine Star**.

- Website: [www.finestar.hr](https://www.finestar.hr)

## Architecture

The repository is moving toward a two-part architecture:

### Android App

The Android client is responsible for:

- login flow
- mailbox and folder navigation
- message list rendering
- message detail display
- compose and send flow
- local cache and UI support logic

### Backend Service

The backend is responsible for:

- authentication/session endpoints
- mail API endpoints
- IMAP mailbox access
- SMTP send integration
- normalized folder and message data for the client
- API documentation generation

## Backend API Direction

The current MVP backend direction includes the following endpoints:

- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET /api/mail/folders`
- `GET /api/mail/messages?folder=INBOX&limit=50`
- `GET /api/mail/messages/{uid}?folder=INBOX`
- `POST /api/mail/send`

These endpoints are intended to become the primary interface used by the Android app.

## Development Roadmap

Based on the current project direction, the main areas of work include:

- backend mail API MVP
- Android migration to backend-driven mail access
- support for nested IMAP folders under `INBOX`
- Android rendering of nested folders as a collapsible tree
- lazy-loaded infinite scrolling for mailbox messages
- server-wide read/unread synchronization
- future support for additional mail actions such as restore, attachment handling, and message state APIs

## Development Status

The project is under active development.

Recent and ongoing work suggests a transition from direct IMAP/SMTP handling inside the mobile client toward a backend-first architecture that keeps protocol-specific behavior in the backend and exposes a more stable API contract to the app.

## Getting Started

### Android / Flutter

Common checks for the Android app:

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --debug
```

### Backend

Common backend validation flow:

```bash
docker compose build mailadmin
docker compose run --rm mailadmin python manage.py test
docker compose run --rm mailadmin python manage.py spectacular --file /tmp/schema.yaml
```

Make sure local environment variables and mail server settings are configured correctly before running backend services.

## Testing

Recommended checks:

### Android

```bash
dart analyze
flutter test
flutter build apk --debug
```

### Backend

```bash
docker compose run --rm mailadmin python manage.py test
docker compose run --rm mailadmin python manage.py spectacular --file /tmp/schema.yaml
```

## Notes

- Backend folder paths should remain canonical identifiers for mailbox operations.
- UI labels may be normalized for better readability without changing backend identifiers.
- New features should ideally be developed in small, clearly separated slices.
- Backend and Android follow-up work should remain scoped and explicit where practical.

## Contributing

When contributing, prefer focused changesets such as:

- backend API changes
- Android UI/client changes
- mailbox behavior improvements
- asset-only updates
- issue-scoped feature slices

Keeping work separated into small, reviewable slices will make the project easier to maintain.

## License

Add the project license information here.
