/// Native-file storage adapter for the Aiset pipeline
/// (`SPEC.md` amendments 10 and 11, slice 2E-a).
///
/// The package is pure Dart with `dart:io`: the `local`/`native_file`
/// adapter for CLI tools and for mobile/desktop Flutter apps as a
/// plain Dart dependency. It must never import Flutter (LIB-03, like
/// `aiset_core`); the browser adapters arrive as a separate,
/// Flutter-free package in slice 2E-b.
///
/// The entry point is [AisetNativeFileStorage], which implements the
/// `AisetStorage` port of `aiset_core` against one document file: a
/// revision read of the stored bytes, a cross-process
/// compare-and-swap that replaces the file atomically under a
/// bounded sidecar lock, and honest capability flags.
///
/// The backup chain, the last-known-good read-back and
/// conflicted-copy preservation are a separate, explicit surface
/// (`AisetBackupChain`) rather than more methods on the port:
/// the port's three-member contract is what the pipeline
/// calls, and `SPEC.md` amendment 11 keeps "load and loadLkg
/// separate calls" for the bootstrap layer of slice 2E-c.
library;

export 'src/backup_chain.dart' show AisetBackupChain, AisetBackupEntry;
export 'src/native_file_storage.dart' show AisetNativeFileSettings, AisetNativeFileStorage;
export 'src/storage_lock.dart' show AisetSidecarLock;
