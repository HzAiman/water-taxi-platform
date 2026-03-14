/// Result type returned by ViewModel action methods.
///
/// The widget layer calls a ViewModel method, awaits its [OperationResult],
/// and uses `switch` to show the appropriate notification — keeping
/// UI concerns in the widget and business logic in the ViewModel.
sealed class OperationResult {
  const OperationResult();
}

/// The operation completed without error.
final class OperationSuccess extends OperationResult {
  const OperationSuccess(this.message);
  final String message;
}

/// The operation could not be completed.
///
/// [isInfo] is `true` for "soft" failures (e.g., booking already accepted
/// by someone else) where a neutral info alert is more appropriate than a
/// red error alert.
final class OperationFailure extends OperationResult {
  const OperationFailure(
    this.title,
    this.message, {
    this.isInfo = false,
  });
  final String title;
  final String message;
  final bool isInfo;
}
