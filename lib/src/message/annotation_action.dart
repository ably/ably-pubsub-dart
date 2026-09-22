/// The type of action performed on an annotation.
///
/// Spec: TAN2b
enum AnnotationAction {
  /// An annotation being created.
  annotationCreate,

  /// An annotation being deleted.
  annotationDelete,
}

/// Extension methods for AnnotationAction.
extension AnnotationActionExtension on AnnotationAction {
  /// Converts to the numeric representation used by the Ably wire protocol.
  ///
  /// Values: annotationCreate=0, annotationDelete=1.
  int toInt() {
    switch (this) {
      case AnnotationAction.annotationCreate:
        return 0;
      case AnnotationAction.annotationDelete:
        return 1;
    }
  }

  /// Creates an AnnotationAction from the numeric wire protocol value.
  ///
  /// Returns `null` for a value this SDK does not recognise, so a future
  /// server-side action degrades instead of throwing from inside the
  /// transport handler. Callers must ignore-with-log.
  static AnnotationAction? fromInt(int value) {
    switch (value) {
      case 0:
        return AnnotationAction.annotationCreate;
      case 1:
        return AnnotationAction.annotationDelete;
      default:
        return null;
    }
  }
}
