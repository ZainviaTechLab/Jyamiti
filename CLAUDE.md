# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a monorepo for **Jyamiti**, a math tutoring platform, with two independent projects:

- `backend/` — Node.js/Express REST API + Socket.io real-time server, MongoDB (Mongoose) database.
- `jyamiti/` — Flutter client (Android, iOS, Windows, macOS, Linux, and Web from one codebase).

There is no root-level build tool; each project is developed and run independently from its own directory. Ignore stray root files like `fix_attendance.py`, `fix_theme_errors.py`, `refactor_theme.py`, `temp_deploy/`, `temp_analyze.txt`, `user_inputs.txt`, `backend.zip`, `youtube-embed.html`, `task.md` — these are one-off scratch/migration scripts and notes, not part of the shipped app.

## Commands

### Backend (`backend/`)

```
npm install                # install deps
npm run dev                # start with nodemon (auto-reload), reads backend/.env
npm start                  # start with node (production-style)
npm run test:integration   # runs tests/verify.js against a running server on localhost:5000
node tests/test_smtp.js    # ad-hoc SMTP/email check
```

There is no linter configured for the backend. `backend/tests/` and the root-level `test_api.js` / `test_chat.js` / `test_mongoose.js` are standalone scripts (not a test runner suite) — run them individually with `node <file>` against a running server/DB, not via a test command.

Requires a `.env` in `backend/` (not committed) with at least `MONGODB_URI`, `JWT_SECRET`, `PORT`, `REDIS_URL`. MongoDB and Redis are optional-but-expected local services; if Redis is unreachable, Socket.io silently falls back to an in-memory adapter (see `backend/socket.js`).

### Flutter app (`jyamiti/`)

```
flutter pub get                    # install deps
flutter run                        # run on a connected device/emulator (add -d chrome / -d windows to target a platform)
flutter analyze                    # static analysis (uses flutter_lints, see analysis_options.yaml)
flutter test                       # run widget/unit tests (test/widget_test.dart is currently the flutter-create boilerplate, not app-specific)
flutter test test/widget_test.dart --plain-name "test name"   # run a single test
flutter build web --release        # production web build (what CI deploys)
flutter build apk / flutter build windows / flutter build ios   # platform builds
```

`jyamiti/lib/services/api_service.dart` hardcodes the production API base URL (`https://api.jyamitimath.com/api`); when pointing the app at a local backend, temporarily swap in the commented local-IP `baseUrl` line rather than adding new config plumbing.

## Backend architecture

Standard layered Express app, entry point `backend/server.js`:

- **Models** (`backend/models/*.js`) — one Mongoose schema per file (User, Course, Batch, Worksheet, Exam, AssessmentQuestion/Submission, Note, Payment, Chat/Message, Competition, ParentMeeting, Schedule, Attendance, LeaveRequest, SlideDeck, Tutorial, Update, ...). `role` on `User` is one of `ADMIN | TUTOR | MENTOR | STUDENT` and drives most authorization.
- **Routes** (`backend/routes/*.js`) — one router per resource, mounted in `server.js` under `/api/<resource>`. Route handlers query Mongoose directly (no service/repository layer); business rules like "a tutor can only touch batches/worksheets they own" are checked inline in the handler (e.g. `batch.tutor.toString() !== req.user.id`).
- **Auth** (`backend/middleware/authMiddleware.js`) — JWT bearer auth via `authenticateToken` (populates `req.user` from the token payload) and `requireRole([...])` for role gating. Apply both as route-level middleware, in that order, on any protected endpoint.
- **File uploads** — handled per-route with `multer` disk storage into `backend/uploads/`, served statically at `/uploads`. Filenames are typically timestamp-based; some routes prefix by type (`note_...`, `assessment_...`).
- **Real-time** (`backend/socket.js`) — a single Socket.io server initialized in `server.js` after DB connect. Two independent concerns share it:
  - Chat: `join_chat`, `new_message`, `typing`/`stop_typing`, with unread counts tracked on the `Chat` document.
  - Live batch competitions ("arena" quiz game): `competition:join_room`, `competition:start_game`, `competition:submit_answer`, `competition:end_round`, `competition:next_round`, `competition:end_game`. Scoring (streak multiplier + speed bonus) and ranking are computed server-side on each submit and persisted onto the `Competition` document — the client only renders what it's sent.
  - Personal per-user rooms (`socket.join(userId)`) are used for out-of-room notifications (e.g. `new_message_notification`).
  - Uses `@socket.io/redis-adapter` for cross-instance pub/sub when Redis is available (needed for horizontal scaling behind pm2/nginx), otherwise falls back in-process.
- **Cron jobs** — `services/scheduleGenerator.js` and `services/paymentGenerator.js` register recurring jobs (`initScheduleCron`, `initPaymentCron`) started at server boot.
- `backend/prisma/schema.prisma` exists but Prisma is **not wired into any route/model** — the app runs entirely on Mongoose/MongoDB. Don't assume Prisma is live without checking for actual usage first.
- Default admin/tutor/mentor/student accounts are auto-seeded on boot if missing (`seedDefaultUsers` in `server.js`) — useful for local testing (`admin@jyamitimath.com` / `test-tutor@gmail.com` / etc., see that function for passwords).

## Flutter app architecture

`jyamiti/lib/` is organized feature-first, not by strict layering — the `domain/` folder exists but is barely used (only `domain/models/slide_deck_models.dart`); most models/state live inside each feature.

- `main.dart` — wraps the app in `MultiBlocProvider` (flutter_bloc) + `MultiProvider` (provider), then `AuthWrapper` decides the landing screen by role (`AdminStatsDashboard` / `TutorDashboard` / `MentorDashboard` / `StudentDashboard`) after `AuthProvider.tryAutoLogin()` resolves. There is no router package (no go_router/auto_route) — navigation is via `Navigator` push/pop between widgets.
- `presentation/features/<feature>/` — each feature (auth, dashboard, academic, admin, chat, competitions, exams, meetings, slides) holds its own `screens/` and, where state is nontrivial, a `bloc/` (flutter_bloc event/state/bloc triplets, e.g. `dashboard/bloc/student_dashboard/`). Simpler/global state (auth session, theme) instead lives in `providers/` (`ChangeNotifier` + `provider` package). Expect this mix — don't try to migrate one to the other as a side effect of unrelated changes.
- `services/` — singletons for cross-cutting concerns, notably:
  - `api_service.dart` — thin static REST client wrapper around `package:http` (get/post/put/patch/delete/uploadFile/uploadWorksheet), injecting the JWT from `SharedPreferences` (`auth_token`) into every request.
  - `offline_sync_service.dart` — queues failed mutating requests (endpoint/method/payload) in `SharedPreferences` and replays them on connectivity/auto-sync; initialized at app startup in `main()`.
  - `slide_cache_service.dart`, `speech_service.dart`, `tts_service.dart`, `jyammy_service.dart`, `deepseek_service.dart`, `competition_service.dart`, `parent_meeting_service.dart` — feature-specific API/device integrations, each independent.
- `presentation/widgets/whiteboard/` and `writing_pad_widget.dart` implement freehand drawing/annotation (used in worksheets/exams); shape auto-fill on closed scribbled paths was added recently — check `writing_pad_widget.dart` for the current gesture/painting logic before extending it.
- `core/theme/app_theme.dart` defines `AppTheme.lightTheme` / `darkTheme`; theme switching goes through `ThemeProvider` + `ThemeReveal` (an animated theme-transition wrapper applied in `MaterialApp.builder`).

## CI/CD

`.github/workflows/deploy.yml` runs on every push to `main`/`master`: builds `flutter build web --release`, then rsyncs/scp's the web build and a trimmed backend tarball (excludes `node_modules`, `uploads`, `.env`, `mongodb_data`) to a DigitalOcean droplet, running `npm install --omit=dev` and `pm2 restart jyamiti-backend` for the backend and reloading nginx for the web frontend. There's no test gate in CI — `flutter analyze` is run non-blocking (`|| true`) against a single file only.
