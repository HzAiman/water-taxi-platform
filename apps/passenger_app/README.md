# Passenger App

passenger_app is the customer-facing Flutter app for booking and tracking water taxi rides. It handles phone authentication, fare validation, Stripe payment holds, booking creation, live tracking, and account history.

The app uses repository + view model layers (Provider) and shared schema/models from packages/water_taxi_shared.

## Architecture

```
lib/
|-- app.dart
|-- main.dart
|-- firebase_options.dart
|-- core/
|   |-- constants/
|   |-- theme/
|   |-- utils/
|   `-- widgets/
|-- data/
|   `-- repositories/
|-- features/
|   |-- auth/presentation/pages/
|   |-- home/presentation/pages/
|   |-- home/presentation/viewmodels/
|   `-- profile/presentation/
|-- routes/
|   |-- app_routes.dart
|   `-- main_screen.dart
`-- services/
    |-- firebase/
    |-- notifications/
    `-- payment/
```

Key view models:

- HomeViewModel: loads user, jetties, fare checks, and active booking stream.
- PaymentViewModel: fare breakdown, payment + booking creation flow.
- BookingTrackingViewModel: real-time booking + tracking merge, cancellation.
- ProfileViewModel: profile and booking history streams.

## Core flows

### Authentication and session recovery

- Phone number sign-in with OTP.
- AuthWrapper routes to MainScreen when a user is authenticated.
- FirebaseSessionService refreshes ID tokens on resume after idle periods.

### Booking creation

1. HomeViewModel loads jetties and validates route selection.
2. PaymentViewModel loads fare by canonical jetty IDs, applies minimum Stripe charge rule, and builds a fare breakdown.
3. Order numbers are reserved in order_number_index with a 24-hour expiry to prevent duplicates.
4. PaymentGatewayService requests a Stripe PaymentIntent (manual capture) and presents the Stripe Payment Sheet.
5. BookingRepository creates the bookings/{id} document with paymentStatus=authorized and embedded route geometry.

### Route polyline selection

BookingRepository builds routePolyline from polylines/{id}:

- If booking contains a routePolyline, it is normalized and used.
- If a routePolylineId exists, the polyline is fetched from polylines/{id}.
- If no route is found, a direct origin->destination line is used.
- When creating a booking, the repository selects a best-fit polyline by snapping origin/destination to stored routes and choosing the lowest detour score.

### Tracking

- streamBooking merges bookings/{id} with tracking/{id} to show live operator position.
- Route polyline normalization accepts legacy keys (routeCoordinates, polylineCoordinates, routePoints).
- Operator marker is shown after status transitions to on_the_way.
- Passenger cancellation triggers backend payment release and archive write.

### Notifications and deep links

- FCM tokens are stored in user_devices/{uid}.
- PassengerNotificationCoordinator watches booking history and emits local OS notifications when backgrounded.
- PushNotificationService shows in-app alerts for foreground FCM notifications.
- MainScreen handles FCM tap, local-notification tap, and app-links deep links and navigates to BookingTrackingScreen.

## Firestore model highlights

New booking writes include:

- bookingId, userId, userName, userPhone
- origin/destination + originJettyId/destinationJettyId
- originCoords/destinationCoords
- adultCount, childCount, passengerCount
- totalFare + fareSnapshotId
- paymentMethod, paymentStatus=authorized, orderNumber, transactionId
- status=pending
- routePolylineId and routePolyline (selected from polylines)
- createdAt, updatedAt

Legacy fields (adultFare, childFare, subtotals) may still exist in older documents.

## Configuration

### Stripe (dart-define)

- STRIPE_PUBLISHABLE_KEY
- STRIPE_MERCHANT_IDENTIFIER (iOS)
- STRIPE_URL_SCHEME
- STRIPE_MERCHANT_DISPLAY_NAME
- STRIPE_RETURN_URL
- STRIPE_PAYMENT_INTENT_ENDPOINT

The default endpoint points to createStripePaymentIntentHttp in Cloud Functions.

### Firebase and Maps

- Phone Auth enabled.
- Firestore collections: users, bookings, fares, jetties, polylines.
- FCM enabled for booking status notifications.
- Google Maps API key in android/local.properties:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

## Run and test

```bash
flutter pub get
flutter run
```

```bash
flutter analyze
flutter test
```

Documentation sync: May 2026 (code-aligned update).

