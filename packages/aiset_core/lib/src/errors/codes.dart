part of 'errors.dart';

/// The stable, transport-neutral error codes of `SPEC.md` amendment 26.
///
/// These are the base codes the Python `errors.py` set defines, and the
/// identifiers a client and a backend agree on. They are
/// constants rather than an enum on purpose: a code travels through an
/// envelope, and a value that must round-trip is a string.
abstract final class AisetErrorCode {
  /// A malformed request: a bad pointer, an unknown operation, a rejected
  /// argument.
  static const String badRequest = 'BAD_REQUEST';

  /// The source text is not valid JSON5/template text, including
  /// duplicate object keys.
  static const String parseError = 'PARSE_ERROR';

  /// No authenticated actor was supplied.
  static const String unauthorized = 'UNAUTHORIZED';

  /// The actor is known but lacks the permission the operation needs.
  static const String forbidden = 'FORBIDDEN';

  /// Nothing is registered under that document id or path.
  static const String notFound = 'NOT_FOUND';

  /// A revision-bound operation arrived without the expected pair.
  static const String revisionRequired = 'REVISION_REQUIRED';

  /// The expected source or descriptor revision is stale.
  static const String revisionConflict = 'REVISION_CONFLICT';

  /// A replacement could not keep the comments of the value it replaces.
  static const String commentPreservationConflict = 'COMMENT_PRESERVATION_CONFLICT';

  /// The document or body exceeds the size limit.
  static const String payloadTooLarge = 'PAYLOAD_TOO_LARGE';

  /// The candidate value violates the descriptor.
  static const String validationError = 'VALIDATION_ERROR';

  /// The descriptor itself is invalid or cannot be composed.
  static const String invalidDescriptor = 'INVALID_DESCRIPTOR';

  /// The actor may not read or edit a secret subtree.
  static const String secretAccessDenied = 'SECRET_ACCESS_DENIED';

  /// A storage lock could not be taken within its bound.
  static const String lockTimeout = 'LOCK_TIMEOUT';

  /// A host callback ran past its bound.
  static const String callbackTimeout = 'CALLBACK_TIMEOUT';

  /// No valid backup exists to fall back to.
  static const String noValidBackup = 'NO_VALID_BACKUP';

  /// The storage layer failed.
  static const String storageError = 'STORAGE_ERROR';

  /// A recognized capability this build does not execute.
  static const String unsupportedCapability = 'UNSUPPORTED_CAPABILITY';

  /// A failure that is the library's own bug.
  static const String internalError = 'INTERNAL_ERROR';

  /// Every base code, in the order `SPEC.md` amendment 26 lists them.
  static const List<String> all = [
    badRequest,
    parseError,
    unauthorized,
    forbidden,
    notFound,
    revisionRequired,
    revisionConflict,
    commentPreservationConflict,
    payloadTooLarge,
    validationError,
    invalidDescriptor,
    secretAccessDenied,
    lockTimeout,
    callbackTimeout,
    noValidBackup,
    storageError,
    unsupportedCapability,
    internalError,
  ];

  /// The HTTP status each code maps to — the transport half of the interface
  /// contract `SPEC.md` amendment 26 carries over from the baseline.
  ///
  /// `aiset_remote` and a `host_api` server use this table; the core
  /// itself never speaks HTTP.
  static const Map<String, int> httpStatus = {
    badRequest: 400,
    parseError: 400,
    unauthorized: 401,
    forbidden: 403,
    secretAccessDenied: 403,
    notFound: 404,
    revisionConflict: 409,
    commentPreservationConflict: 409,
    payloadTooLarge: 413,
    validationError: 422,
    invalidDescriptor: 422,
    revisionRequired: 428,
    callbackTimeout: 504,
    lockTimeout: 503,
    noValidBackup: 404,
    storageError: 500,
    unsupportedCapability: 501,
    internalError: 500,
  };

  /// The status [code] maps to, or 500 for a code outside the base set
  /// (`SPEC.md` amendment 26: namespaced network and AI codes still
  /// have to produce a status).
  static int statusOf(String code) => httpStatus[code] ?? 500;
}
