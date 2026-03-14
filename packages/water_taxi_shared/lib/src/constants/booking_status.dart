/// Canonical booking status values used in Firestore and the UI.
///
/// [fromString] normalises legacy aliases so both apps always work with
/// the same typed enum, regardless of which string variant was written.
enum BookingStatus {
  pending,
  accepted,
  onTheWay,
  completed,
  cancelled,
  rejected,

  /// Catch-all for unrecognised values coming from Firestore.
  unknown;

  /// Parses a Firestore status string (including legacy aliases).
  static BookingStatus fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'pending':
        return BookingStatus.pending;
      case 'accepted':
      case 'confirmed':
        return BookingStatus.accepted;
      case 'on_the_way':
      case 'in_progress':
      case 'ongoing':
        return BookingStatus.onTheWay;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
        return BookingStatus.cancelled;
      case 'rejected':
        return BookingStatus.rejected;
      default:
        return BookingStatus.unknown;
    }
  }

  /// Returns the canonical Firestore string for this status.
  /// Always write this value; never write the legacy aliases.
  String get firestoreValue {
    switch (this) {
      case BookingStatus.pending:
        return 'pending';
      case BookingStatus.accepted:
        return 'accepted';
      case BookingStatus.onTheWay:
        return 'on_the_way';
      case BookingStatus.completed:
        return 'completed';
      case BookingStatus.cancelled:
        return 'cancelled';
      case BookingStatus.rejected:
        return 'rejected';
      case BookingStatus.unknown:
        return 'unknown';
    }
  }

  /// `true` if the booking is still in progress.
  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.accepted ||
      this == BookingStatus.onTheWay;

  /// `true` if no further status transitions are possible.
  bool get isTerminal =>
      this == BookingStatus.completed ||
      this == BookingStatus.cancelled ||
      this == BookingStatus.rejected;

  /// `true` if the passenger may request a cancellation.
  bool get canBeCancelledByPassenger =>
      this == BookingStatus.pending ||
      this == BookingStatus.accepted ||
      this == BookingStatus.onTheWay;
}
