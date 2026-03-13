# Melaka Water Taxi - Passenger App

A Flutter mobile application for passengers to book water taxi services in Melaka, Malaysia. This app provides an easy-to-use interface for booking rides between various jetties along the Melaka River and tracking your bookings in real-time.

## Features

### Authentication
- **Phone Number Authentication**: Secure login using Firebase phone authentication with OTP verification
- **Persistent Sessions**: Users stay logged in across app sessions
- **User Registration**: New users complete their profile with name and email

### Booking Management
- **Ride Booking**: Select origin and destination from predefined jetties
- **Passenger Count Selection**: Book for 1-10 passengers
- **Fare Calculation**: Automatic fare calculation
- **Real-time Tracking**: Track your booking status with live updates
- **Google Maps Integration**: View your pickup location on an interactive map

### User Profile
- **View Profile**: Display user information (name, email, phone number)
- **Edit Profile**: Update personal information
- **Booking History**: View all past bookings with details
- **Logout**: Secure sign out functionality

### Payment
- **Payment Information Entry**: Collect cardholder name and card number
- **Order Summary**: Review booking details before confirmation
- **Booking Confirmation**: Generate unique booking IDs
- **Firebase Storage**: All bookings saved to Firestore database

## Tech Stack

- **Framework**: Flutter 3.8.1
- **Language**: Dart
- **Backend**: Firebase
  - Firebase Authentication (Phone Auth)
  - Cloud Firestore (Database)
  - Firebase Core
- **Maps**: Google Maps Flutter
- **UI**: Material Design 3

## Project Structure

```
lib/
├── main.dart                      # App entry point with theme & auth routing
├── phone_login_page.dart          # Phone authentication screen
├── registration_page.dart         # New user registration
├── main_screen.dart               # Bottom navigation (Home/Profile tabs)
├── home_screen.dart               # Ride booking interface
├── payment_screen.dart            # Payment information entry
├── booking_tracking_screen.dart   # Real-time booking tracking
├── profile_screen.dart            # User profile & booking history
└── firebase_options.dart          # Firebase configuration
```

## Prerequisites

- Flutter SDK (>= 3.8.1)
- Dart SDK (>= 3.8.1)
- Firebase project with:
  - Authentication enabled (Phone provider)
  - Cloud Firestore database
  - Google Maps API key
- Android Studio / VS Code
- Android SDK / Xcode (for iOS)

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/xen9ne98/passenger_app.git
cd passenger_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Firebase Setup

#### a. Create a Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use an existing one
3. Enable **Phone Authentication** in Authentication settings
4. Create a **Cloud Firestore** database in test mode

#### b. Configure Firebase for Flutter
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure
```

#### c. Add google-services.json (Android)
- Download `google-services.json` from Firebase Console
- Place it in `android/app/google-services.json`

#### d. Add GoogleService-Info.plist (iOS)
- Download `GoogleService-Info.plist` from Firebase Console
- Place it in `ios/Runner/GoogleService-Info.plist`

### 4. Google Maps Setup

#### Android Configuration
1. Get a Google Maps API key from [Google Cloud Console](https://console.cloud.google.com/)
2. Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<application>
    <meta-data
        android:name="com.google.android.geo.API_KEY"
        android:value="YOUR_API_KEY_HERE"/>
</application>
```

#### iOS Configuration
1. Add to `ios/Runner/AppDelegate.swift`:
```swift
import GoogleMaps

GMSServices.provideAPIKey("YOUR_API_KEY_HERE")
```

### 5. Run the App

```bash
# For Android
flutter run

# For iOS
flutter run -d ios

# For web
flutter run -d chrome
```

## Firestore Database Structure

### Users Collection
```
users/{userId}
├── name: string
├── email: string
├── phoneNumber: string
└── createdAt: timestamp
```

### Bookings Collection
```
bookings/{bookingId}
├── userId: string
├── userName: string
├── userPhone: string
├── origin: string
├── destination: string
├── originCoords: GeoPoint
├── destinationCoords: GeoPoint
├── passengerCount: number
├── fare: number
├── cardholderName: string
├── cardNumber: string
├── status: string (pending/confirmed/completed/cancelled)
├── createdAt: timestamp
└── driverId: string (optional)
```

## Configuration

### App Theme
The app uses a custom blue theme defined in `main.dart`:
- Primary Color: `#0066CC`
- Background: `#F8FBFF`
- Material Design 3

### Authentication Flow
1. User enters phone number
2. Receives OTP via SMS
3. Verifies OTP
4. New users complete registration
5. Existing users go directly to home screen

## Building for Production

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Troubleshooting

### Firebase Initialization Error
- Ensure `WidgetsFlutterBinding.ensureInitialized()` is called before Firebase initialization
- Run `flutterfire configure` to regenerate configuration

### Google Maps Not Showing
- Verify API key is correctly configured
- Enable Maps SDK for Android/iOS in Google Cloud Console
- Check billing is enabled for Google Cloud project

### Phone Authentication Issues
- Ensure Phone Authentication is enabled in Firebase Console
- For testing, add test phone numbers in Firebase Console
- Check SHA-1 certificate is added in Firebase project settings (Android)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- Google Maps Platform for mapping services
- Material Design for UI/UX guidelines

---

**Note**: This is a demonstration project for educational purposes. Ensure proper security measures and compliance with local regulations before deploying to production.
