/// Base exception for SMB-related errors.
class SmbException implements Exception {
  /// Human-readable error message.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  const SmbException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'SmbException: $message (caused by $cause)';
    }
    return 'SmbException: $message';
  }
}

/// Thrown when an SMB connection fails.
class SmbConnectionException extends SmbException {
  const SmbConnectionException(super.message, [super.cause]);
}

/// Thrown when an SMB authentication fails.
class SmbAuthException extends SmbException {
  const SmbAuthException(super.message, [super.cause]);
}

/// Thrown when an SMB file or directory is not found.
class SmbNotFoundException extends SmbException {
  const SmbNotFoundException(super.message, [super.cause]);
}

/// Thrown when an SMB operation is attempted while disconnected.
class SmbNotConnectedException extends SmbException {
  const SmbNotConnectedException([super.message = 'Not connected to SMB share']);
}
