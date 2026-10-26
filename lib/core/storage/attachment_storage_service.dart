import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

/// Prefix stored in [CredentialEntry.attachmentPath] for on-device files.
const String kLocalAttachmentPrefix = 'local::';

/// Result of compressing + storing a credential attachment (cloud or local).
class AttachmentUploadResult {
  const AttachmentUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.isLocal = false,
  });

  /// Remote download URL, or `file://…` when saved locally.
  final String downloadUrl;

  /// Firebase Storage path, or `local::{absolutePath}` when offline / upload failed.
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final bool isLocal;
}

/// Compresses files (≤1 MB) and stores them in Firebase Storage,
/// falling back to app documents when upload fails.
class AttachmentStorageService {
  AttachmentStorageService({FirebaseStorage? storage, Uuid? uuid})
      : _storage = storage ?? FirebaseStorage.instance,
        _uuid = uuid ?? const Uuid();

  final FirebaseStorage _storage;
  final Uuid _uuid;

  static const _imageExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.bmp',
    '.gif',
  };

  static const _textExts = {
    '.txt',
    '.env',
    '.json',
    '.xml',
    '.yaml',
    '.yml',
    '.md',
    '.csv',
    '.log',
    '.ini',
    '.cfg',
    '.conf',
    '.properties',
    '.pem',
    '.crt',
    '.key',
  };

  /// True for dotenv / plain-text secrets (keep original bytes + name).
  static bool isTextLikeAttachment(String fileName, [String? mime]) {
    final base = p.basename(fileName).toLowerCase();
    if (base == '.env' ||
        base.startsWith('.env.') ||
        base.endsWith('.env') ||
        base == 'env' ||
        base == 'dotenv') {
      return true;
    }
    final ext = p.extension(base);
    if (_textExts.contains(ext)) return true;
    final m = (mime ?? '').toLowerCase();
    return m.startsWith('text/') ||
        m == 'application/json' ||
        m == 'application/xml' ||
        m == 'application/x-dotenv' ||
        m == 'text/x-env';
  }

  /// Storage object names cannot be awkward hidden/dotfiles — keep display name separate.
  static String storageObjectFileName(String originalName) {
    final base = p.basename(originalName);
    if (base == '.env' || base.startsWith('.env')) {
      final suffix = base == '.env' ? 'env' : base.substring(1); // env / env.local
      return 'dotenv_$suffix';
    }
    if (base.startsWith('.')) {
      return 'dot_${base.substring(1)}';
    }
    return base.replaceAll(' ', '_');
  }

  static bool isLocalPath(String? storagePath) =>
      storagePath != null && storagePath.startsWith(kLocalAttachmentPrefix);

  static String? absoluteLocalPath(String? storagePath) {
    if (!isLocalPath(storagePath)) return null;
    return storagePath!.substring(kLocalAttachmentPrefix.length);
  }

  /// Validates, compresses, then uploads to Firebase.
  /// On network / Storage failure, saves the compressed file locally instead.
  Future<AttachmentUploadResult> compressAndUpload({
    required String userId,
    required String credentialId,
    required File file,
  }) async {
    final compressed = await _prepareCompressed(file);

    final storageObjectPath =
        'users/$userId/credentials/$credentialId/${compressed.storedFileName}';

    try {
      final ref = _storage.ref(storageObjectPath);
      await ref.putData(
        compressed.bytes,
        SettableMetadata(
          contentType: compressed.mimeType,
          customMetadata: {
            'originalName': compressed.originalName,
            'compressed': 'true',
          },
        ),
      );
      final url = await ref.getDownloadURL();
      // Keep a local copy so later opens don't hit Firebase.
      await _mirrorToCache(
        userId: userId,
        credentialId: credentialId,
        fileName: compressed.storedFileName,
        bytes: compressed.bytes,
      );
      return AttachmentUploadResult(
        downloadUrl: url,
        storagePath: storageObjectPath,
        fileName: compressed.originalName,
        mimeType: compressed.mimeType,
        sizeBytes: compressed.bytes.length,
        isLocal: false,
      );
    } catch (_) {
      // Offline / Storage not enabled / permission — keep vault usable.
      return _saveLocally(
        userId: userId,
        credentialId: credentialId,
        compressed: compressed,
      );
    }
  }

  /// Uploads an existing local attachment to Firebase when online.
  /// Returns null if upload still fails.
  Future<AttachmentUploadResult?> uploadLocalToRemote({
    required String userId,
    required String credentialId,
    required String localStoragePath,
    required String fileName,
    required String mimeType,
  }) async {
    final abs = absoluteLocalPath(localStoragePath);
    if (abs == null) return null;
    final file = File(abs);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length > AppConstants.maxAttachmentBytes) return null;

    final safeName = p.basename(fileName).replaceAll(' ', '_');
    final storageObjectPath =
        'users/$userId/credentials/$credentialId/$safeName';

    try {
      final ref = _storage.ref(storageObjectPath);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: mimeType,
          customMetadata: {
            'originalName': fileName,
            'compressed': 'true',
            'syncedFromLocal': 'true',
          },
        ),
      );
      final url = await ref.getDownloadURL();
      await _mirrorToCache(
        userId: userId,
        credentialId: credentialId,
        fileName: safeName,
        bytes: bytes,
      );
      try {
        await file.delete();
      } catch (_) {}

      return AttachmentUploadResult(
        downloadUrl: url,
        storagePath: storageObjectPath,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        isLocal: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Deletes local file, cache copy, and/or Firebase Storage object.
  /// Returns `true` if gone / nothing to delete; `false` if remote delete failed
  /// (caller should queue a retry).
  Future<bool> deleteIfExists(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return true;

    if (isLocalPath(storagePath)) {
      final abs = absoluteLocalPath(storagePath);
      if (abs == null) return true;
      try {
        final f = File(abs);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return true;
    }

    await _deleteCacheForStoragePath(storagePath);

    try {
      await _storage.ref(storagePath).delete();
      return true;
    } on FirebaseException catch (e) {
      // Already gone — treat as success.
      if (e.code == 'object-not-found') return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Resolves attachment from app cache first; fetches Firebase only on miss.
  /// On successful fetch, keeps a durable copy under app documents so the next
  /// open does not hit the network. Retries on failure.
  Future<File> resolveAttachmentFile({
    required String userId,
    required String credentialId,
    required String? storagePath,
    required String? downloadUrl,
    required String fileName,
    int maxAttempts = 3,
  }) async {
    final safeName = _safeFileName(fileName);
    if (safeName.isEmpty) {
      throw AttachmentException('Invalid file name');
    }

    // 1) Offline / upload-failed local primary file.
    if (isLocalPath(storagePath)) {
      final abs = absoluteLocalPath(storagePath);
      if (abs != null && await File(abs).exists()) {
        return File(abs);
      }
    }

    // 2) Durable app cache (previous download / upload mirror).
    final cached = await _cacheFile(
      userId: userId,
      credentialId: credentialId,
      fileName: safeName,
    );
    if (await cached.exists() && await cached.length() > 0) {
      return cached;
    }

    // Also try cache name derived from remote storage object.
    final remoteName = fileNameFromStoragePath(storagePath);
    if (remoteName != null && remoteName != safeName) {
      final alt = await _cacheFile(
        userId: userId,
        credentialId: credentialId,
        fileName: remoteName,
      );
      if (await alt.exists() && await alt.length() > 0) {
        return alt;
      }
    }

    // 3) Fetch from Firebase / URL, then keep in cache.
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final bytes = await _fetchRemoteBytes(
          storagePath: storagePath,
          downloadUrl: downloadUrl,
        );
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(bytes, flush: true);
        return cached;
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }

    final detail = lastError?.toString() ?? 'unknown error';
    throw AttachmentException(
      'Download failed after $maxAttempts tries. $detail',
    );
  }

  /// @deprecated Use [resolveAttachmentFile] (cache-first).
  Future<File> downloadToTempFile({
    required String? storagePath,
    required String? downloadUrl,
    required String fileName,
    String userId = '_',
    String credentialId = '_',
  }) {
    return resolveAttachmentFile(
      userId: userId,
      credentialId: credentialId,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      fileName: fileName,
    );
  }

  Future<bool> hasCachedFile({
    required String userId,
    required String credentialId,
    required String? storagePath,
    required String fileName,
  }) async {
    if (isLocalPath(storagePath)) {
      final abs = absoluteLocalPath(storagePath);
      return abs != null && await File(abs).exists();
    }
    final safeName = _safeFileName(fileName);
    final cached = await _cacheFile(
      userId: userId,
      credentialId: credentialId,
      fileName: safeName,
    );
    if (await cached.exists() && await cached.length() > 0) return true;
    final remoteName = fileNameFromStoragePath(storagePath);
    if (remoteName != null && remoteName != safeName) {
      final alt = await _cacheFile(
        userId: userId,
        credentialId: credentialId,
        fileName: remoteName,
      );
      if (await alt.exists() && await alt.length() > 0) return true;
    }
    return false;
  }

  Future<void> _mirrorToCache({
    required String userId,
    required String credentialId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final cached = await _cacheFile(
      userId: userId,
      credentialId: credentialId,
      fileName: _safeFileName(fileName),
    );
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes(bytes, flush: true);
  }

  Future<File> _cacheFile({
    required String userId,
    required String credentialId,
    required String fileName,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    return File(
      p.join(
        docs.path,
        'attachment_cache',
        userId,
        credentialId,
        _safeFileName(fileName),
      ),
    );
  }

  Future<void> _deleteCacheForStoragePath(String storagePath) async {
    final parsed = _parseRemoteStoragePath(storagePath);
    if (parsed == null) return;
    try {
      final dir = Directory(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'attachment_cache',
          parsed.userId,
          parsed.credentialId,
        ),
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<Uint8List> _fetchRemoteBytes({
    required String? storagePath,
    required String? downloadUrl,
  }) async {
    if (storagePath != null &&
        storagePath.isNotEmpty &&
        !isLocalPath(storagePath)) {
      try {
        final data = await _storage.ref(storagePath).getData(
              AppConstants.maxAttachmentBytes * 2,
            );
        if (data != null && data.isNotEmpty) return data;
      } catch (_) {
        // Fall through to HTTPS URL.
      }
    }

    final url = downloadUrl?.trim();
    if (url == null || url.isEmpty || url.startsWith('file:')) {
      throw AttachmentException('Attachment not available for download');
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AttachmentException('Download failed (${response.statusCode})');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) {
        throw AttachmentException('Downloaded file is empty');
      }
      if (bytes.length > AppConstants.maxAttachmentBytes * 2) {
        throw AttachmentException('Downloaded file is too large');
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close(force: true);
    }
  }

  static String _safeFileName(String fileName) =>
      p.basename(fileName).replaceAll(' ', '_');

  static String? fileNameFromStoragePath(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty || isLocalPath(storagePath)) {
      return null;
    }
    return p.basename(storagePath);
  }

  static ({String userId, String credentialId, String fileName})?
      _parseRemoteStoragePath(String storagePath) {
    final parts = storagePath.split('/');
    // users/{uid}/credentials/{credentialId}/{fileName}
    if (parts.length >= 5 &&
        parts[0] == 'users' &&
        parts[2] == 'credentials') {
      return (
        userId: parts[1],
        credentialId: parts[3],
        fileName: parts.sublist(4).join('/'),
      );
    }
    return null;
  }

  Future<AttachmentUploadResult> _saveLocally({
    required String userId,
    required String credentialId,
    required _PreparedAttachment compressed,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'attachments', userId, credentialId),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final localFile = File(p.join(dir.path, compressed.storedFileName));
    await localFile.writeAsBytes(compressed.bytes, flush: true);

    return AttachmentUploadResult(
      downloadUrl: Uri.file(localFile.path).toString(),
      storagePath: '$kLocalAttachmentPrefix${localFile.path}',
      fileName: compressed.originalName,
      mimeType: compressed.mimeType,
      sizeBytes: compressed.bytes.length,
      isLocal: true,
    );
  }

  Future<_PreparedAttachment> _prepareCompressed(File file) async {
    if (!await file.exists()) {
      throw AttachmentException('Selected file was not found');
    }

    final originalSize = await file.length();
    if (originalSize <= 0) {
      throw AttachmentException('File is empty');
    }
    if (originalSize > AppConstants.maxAttachmentBytes) {
      throw AttachmentException(
        'File must be ${AppConstants.maxAttachmentBytes ~/ 1024} KB or smaller',
      );
    }

    final originalName = p.basename(file.path);
    final ext = p.extension(file.path).toLowerCase();
    final mime = lookupMimeType(file.path) ??
        (isTextLikeAttachment(originalName)
            ? 'text/plain'
            : 'application/octet-stream');

    final CompressedAttachment compressed;
    if (_imageExts.contains(ext) || mime.startsWith('image/')) {
      compressed = await _compressImage(file, originalName);
    } else if (isTextLikeAttachment(originalName, mime)) {
      // Keep .env / text readable — do not gzip-rename to .gz
      final raw = await file.readAsBytes();
      compressed = CompressedAttachment(
        bytes: Uint8List.fromList(raw),
        fileName: storageObjectFileName(originalName),
        mimeType: 'text/plain',
      );
    } else {
      compressed = await _compressBinary(file, originalName, mime);
    }

    if (compressed.bytes.length > AppConstants.maxAttachmentBytes) {
      throw AttachmentException(
        'Compressed file still exceeds 1 MB. Choose a smaller file.',
      );
    }

    return _PreparedAttachment(
      bytes: compressed.bytes,
      originalName: originalName,
      storedFileName: compressed.fileName,
      mimeType: compressed.mimeType,
    );
  }

  Future<CompressedAttachment> _compressImage(
    File file,
    String originalName,
  ) async {
    Uint8List? best;
    var quality = 85;
    while (quality >= 35) {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: quality,
        minWidth: 1600,
        minHeight: 1600,
        format: CompressFormat.jpeg,
      );
      if (result == null) break;
      best = result;
      if (result.length <= AppConstants.maxAttachmentBytes) break;
      quality -= 15;
    }

    if (best == null) {
      final raw = await file.readAsBytes();
      return CompressedAttachment(
        bytes: Uint8List.fromList(raw),
        fileName: originalName,
        mimeType: lookupMimeType(file.path) ?? 'image/jpeg',
      );
    }

    final base = p.basenameWithoutExtension(originalName);
    return CompressedAttachment(
      bytes: best,
      fileName: '${base}_${_uuid.v4().substring(0, 8)}.jpg',
      mimeType: 'image/jpeg',
    );
  }

  Future<CompressedAttachment> _compressBinary(
    File file,
    String originalName,
    String mime,
  ) async {
    final raw = await file.readAsBytes();
    final compressed = Uint8List.fromList(GZipCodec(level: 6).encode(raw));

    if (compressed.length < raw.length) {
      return CompressedAttachment(
        bytes: compressed,
        fileName: '${storageObjectFileName(originalName)}.gz',
        mimeType: 'application/gzip',
      );
    }

    return CompressedAttachment(
      bytes: Uint8List.fromList(raw),
      fileName: storageObjectFileName(originalName),
      mimeType: mime,
    );
  }
}

class _PreparedAttachment {
  const _PreparedAttachment({
    required this.bytes,
    required this.originalName,
    required this.storedFileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String originalName;
  final String storedFileName;
  final String mimeType;
}

class CompressedAttachment {
  const CompressedAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class AttachmentException implements Exception {
  AttachmentException(this.message);
  final String message;

  @override
  String toString() => message;
}
