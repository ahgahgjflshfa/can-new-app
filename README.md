# 立碼幫幫忙 App

Flutter app for station staff to log in, view assistance tasks, reply to a task, and complete a task through the `立碼幫幫忙` API.

## Project Structure

```text
lib/
  main.dart                         # app entry point
  app.dart                          # MaterialApp/theme wiring
  models/                           # API data models and enums
  services/                         # API contract, client, exceptions
  screens/                          # full-screen user flows
  widgets/                          # reusable UI pieces
```

## API

The API base URL is defined in `lib/services/limabang_api_client.dart`:

```text
https://www-u.tymetro.com.tw/station_services/api
```

Implemented endpoints:

- `POST /auth/login`
- `POST /auth/logout`
- `GET /tasks`
- `POST /tasks/{id}/reply`
- `POST /tasks/{id}/complete`

All authenticated requests send `Authorization: Bearer <token>`.

Login also sends `fcm_token` when Firebase Messaging has produced one.

Login sessions are persisted with secure storage. Reopening the app restores the saved token, user profile, and device id, then opens the task list directly. The saved session is cleared only when the user logs out.

## Firebase Push Notifications

Android Firebase configuration lives at:

```text
android/app/google-services.json
```

Current Android package/application id:

```text
com.tymetro.station_service
```

The app initializes Firebase on startup, requests notification permission, reads the FCM token, logs foreground/background/opened messages, and refreshes the task list when a push message is received while the app is active.

## Settings

The task list has a settings button in the app bar.

- Main settings: current user, station/section, role, push notification status, logout.
- `進階設定`: API base URL, timeout, device ID, token status, Firebase push status, and app logs.

Use `進階設定 > Export Log` to copy the in-app log buffer to the clipboard. Logs are redacted: passwords and bearer tokens are not printed.

## Run Locally

Install dependencies:

```bash
flutter pub get
```

List devices/emulators:

```bash
flutter devices
flutter emulators
```

If using the command-line Android emulator created for this project:

```bash
export PATH="$ANDROID_HOME/emulator:$PATH"
flutter emulators --launch Pixel_API_36
flutter run -d Pixel_API_36
```

## Debug API Logs

Run the app from the terminal to see API connection logs:

```bash
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
flutter run -d emulator-5554
```

Look for lines prefixed with:

```text
[LimabangApi]
```

The logs show request stage, endpoint, elapsed time, HTTP status, response body size, and error type. Passwords and bearer tokens are not printed.

## Verification

```bash
flutter analyze
flutter test
flutter build apk --debug
```

## Notes

- iOS/macOS builds require a complete Xcode installation. Android development does not.
