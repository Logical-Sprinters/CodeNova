import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'brandguard_api_service.dart';

Future<Map<String, dynamic>?> pickAndUploadDocument({
  bool asFact = false,
  String brandName = 'Acme',
}) async {
  const group = XTypeGroup(
    label: 'Documents & images',
    extensions: ['txt', 'md', 'pdf', 'png', 'jpg', 'jpeg', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  if (await file.length() > 5 * 1024 * 1024) {
    throw Exception('Maximum document or image size is 5 MB.');
  }
  final bytes = await file.readAsBytes();
  final uploaded = await BrandGuardApiService.uploadDocument(
    file.name,
    bytes,
    asFact: asFact,
    brandName: brandName,
  );
  return {...uploaded, '_local_bytes': bytes};
}

Future<({String name, Uint8List bytes})?> pickLocalFileBytes({
  List<String> extensions = const ['png', 'jpg', 'jpeg', 'webp', 'txt', 'md'],
  String label = 'Verification file',
}) async {
  final group = XTypeGroup(label: label, extensions: extensions);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  if (await file.length() > 5 * 1024 * 1024) {
    throw Exception('Maximum file size is 5 MB.');
  }
  return (name: file.name, bytes: await file.readAsBytes());
}

Future<Map<String, dynamic>?> pickAndUploadLogoTemplate({
  required String ruleId,
  String brandName = 'Acme',
  String label = 'Deprecated 2024 Logo',
}) async {
  final picked = await pickLocalFileBytes(
    extensions: const ['png', 'jpg', 'jpeg', 'webp'],
    label: 'Deprecated logo image',
  );
  if (picked == null) return null;
  return BrandGuardApiService.uploadLogoTemplate(
    ruleId: ruleId,
    fileName: picked.name,
    bytes: picked.bytes,
    brandName: brandName,
    label: label,
  );
}
