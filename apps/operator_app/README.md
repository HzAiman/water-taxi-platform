# Operator App

A Flutter Android app for ride-sharing operators to log in, complete their profile, toggle availability, and view their current location on a map.

## Features

- **Authentication**: Email/password via Firebase Auth
- **Profile Management**: Edit name and operator ID; email is read-only
- **Availability**: One-tap online/offline toggle with optimistic updates
- **Navigation**: Bottom nav (Home, Profile)
- **Maps**: Shows current location, custom recenter button
- **Realtime**: Firestore-backed profile and status

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Firebase (Auth, Firestore)
- **State**: Stateful widgets
- **Maps/Location**: google_maps_flutter, geolocator, permission_handler

## Project Structure

```
lib/
├── app.dart                           # App shell and auth/profile routing
├── main.dart                          # Firebase bootstrap
├── firebase_options.dart              # Firebase configuration
├── core/
│   ├── constants/
│   │   └── app_constants.dart         # App-level constants
│   └── theme/
│       └── app_theme.dart             # Shared app theme
├── features/
│   ├── auth/presentation/pages/
│   │   ├── operator_login_page.dart
│   │   └── operator_profile_setup_page.dart
│   ├── home/presentation/pages/
│   │   └── operator_home_screen.dart
│   └── profile/presentation/pages/
│       └── operator_profile_page.dart
└── routes/
    ├── app_routes.dart                # Route constants
    └── main_screen.dart               # Main shell with bottom navbar
```

## Getting Started (Android)

### Prerequisites
- Flutter SDK 3.x
- Firebase project with Auth + Firestore enabled
- Android device/emulator with Google Play services and location enabled

### Setup
1) Clone
```bash
git clone <repository-url>
cd operator_app
```

2) Dependencies
```bash
flutter pub get
```

3) Firebase config (Android)
- Download `google-services.json` from Firebase Console and place it at `android/app/google-services.json`.
- Ensure your Firebase Android app uses the correct package name and SHA-1/256 fingerprints.

4) Google Maps API key (Android)
- In `android/local.properties`, set:
```
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```
- The manifest reads this via `${MAPS_API_KEY}`.

5) Run
```bash
flutter run
```

## App Flow

1. **Login**: Operators enter email and password
2. **Profile Setup**: New operators are prompted to enter name and operator ID
3. **Home Screen**: Map centers on current location; toggle online/offline
4. **Profile Screen**: View/edit name & operator ID, logout

## Firestore Database Structure

### Collections

**operators/**
```
{
    uid: string (document ID)
    name: string
    operatorId: string
    email: string
    isOnline: boolean
    createdAt: timestamp
    updatedAt: timestamp
}
```

## Authentication Flow

1. User enters credentials on login page
2. Firebase authenticates the user
3. App checks if operator profile exists in Firestore
4. If profile missing → redirect to profile setup page
5. If profile exists → show home screen

## Key Components

### AuthWrapper
Handles authentication state and routing logic:
- Checks Firebase auth state
- Verifies operator profile in Firestore
- Routes to appropriate screen based on auth status and profile completion

### OperatorHomeScreen
Main dashboard with:
- Online/offline status toggle (optimistic update + Firestore sync)
- Google Map with current location, custom recenter button
- Pending booking pickup, accept/start/complete actions
- Permission handling and error snackbars

### OperatorProfilePage
Profile management with:
- Edit name and operator ID
- Read-only email display
- Save changes and logout

### OperatorMainScreen
Navigation shell with bottom navigation (Home, Profile)

## Dependencies

Key packages used:
- `firebase_core`, `firebase_auth`, `cloud_firestore`
- `google_maps_flutter`, `geolocator`, `permission_handler`
- `flutter`

## Error Handling

- Network errors display user-friendly snackbar messages
- Loading states show circular progress indicators
- Form validation prevents invalid data submission
- Mounted checks prevent UI updates after widget disposal

## Future Enhancements

- Ride request handling
- Route display and navigation
- History and analytics
- Ratings and payments

## Support

For issues or questions, please create an issue in the repository.

## License

This project is licensed under the MIT License - see LICENSE file for details.
