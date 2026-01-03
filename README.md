# Operator App

A Flutter mobile application for ride-sharing operators to manage their online/offline status, view and edit their profile information, and handle ride requests.

## Features

- **Authentication**: Secure login with email and password using Firebase Authentication
- **Profile Management**: Operators can view, edit their name and operator ID
- **Online/Offline Status**: Toggle availability status with a single tap
- **Bottom Navigation**: Easy navigation between Home and Profile screens
- **Real-time Data**: Firestore integration for instant data synchronization
- **Responsive Design**: Clean and intuitive user interface

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Firebase (Authentication, Firestore)
- **State Management**: StatefulWidget
- **Package Manager**: Pub

## Project Structure

```
lib/
├── main.dart                          # App entry point & AuthWrapper
├── operator_login_page.dart          # Login screen
├── operator_profile_setup_page.dart  # Profile setup for new operators
├── operator_home_screen.dart         # Home screen with status toggle
├── operator_profile_page.dart        # Profile editing screen
├── operator_main_screen.dart         # Main shell with bottom navbar
└── firebase_options.dart             # Firebase configuration
```

## Getting Started

### Prerequisites

- Flutter SDK (3.0+)
- Dart SDK
- Firebase project with Authentication and Firestore enabled
- iOS/Android development environment setup

### Installation

1. Clone the repository:
    ```bash
    git clone <repository-url>
    cd operator_app
    ```

2. Install dependencies:
    ```bash
    flutter pub get
    ```

3. Configure Firebase:
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place them in the appropriate directories
   - Update `firebase_options.dart` with your Firebase project credentials

4. Run the app:
    ```bash
    flutter run
    ```

## App Flow

1. **Login**: Operators enter email and password
2. **Profile Setup**: New operators are prompted to enter name and operator ID
3. **Home Screen**: Display status toggle button and available actions
4. **Profile Screen**: View and edit operator information
5. **Logout**: Operators can logout from the profile screen

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
  status: string ('active' or 'inactive')
  createdAt: timestamp
  updatedAt: timestamp
}
```

## Authentication Flow

1. User enters credentials on login page
2. Firebase authenticates the user
3. App checks if operator profile exists in Firestore
4. If profile missing → redirect to profile setup page
5. If profile exists and status is 'active' → show home screen
6. If status is not 'active' → sign out and show login page

## Key Components

### AuthWrapper
Handles authentication state and routing logic:
- Checks Firebase auth state
- Verifies operator profile in Firestore
- Routes to appropriate screen based on auth status and profile completion

### OperatorHomeScreen
Main dashboard with:
- Online/offline status toggle button
- Real-time status updates to Firestore
- Error handling and loading states

### OperatorProfilePage
Profile management with:
- Edit name and operator ID
- Read-only email display
- Save changes functionality
- Logout option

### OperatorMainScreen
Navigation shell with:
- Bottom navigation bar (Home & Profile)
- Screen switching functionality

## Dependencies

Key packages used:
- `firebase_core`: Firebase initialization
- `firebase_auth`: User authentication
- `cloud_firestore`: Database operations
- `flutter`: UI framework

## Error Handling

- Network errors display user-friendly snackbar messages
- Loading states show circular progress indicators
- Form validation prevents invalid data submission
- Mounted checks prevent UI updates after widget disposal

## Future Enhancements

- Real-time ride request notifications
- Map integration for location tracking
- Ride history and analytics
- Rating and review system
- Payment integration

## Support

For issues or questions, please create an issue in the repository.

## License

This project is licensed under the MIT License - see LICENSE file for details.
