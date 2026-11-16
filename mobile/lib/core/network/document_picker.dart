import 'package:file_selector/file_selector.dart';

import 'brandguard_api_service.dart';

Future<Map<String, dynamic>?> pickAndUploadDocument({
  bool asFact = false,
  String brandName = 'Acme',
}) async {
  const group = XTypeGroup(
    label: 'Text documents',
    extensions: ['txt', 'md', 'pdf'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  if (await file.length() > 5 * 1024 * 1024) {
    throw Exception('Maximum document size is 5 MB.');
  }
  return BrandGuardApiService.uploadDocument(
    file.name,
    await file.readAsBytes(),
    asFact: asFact,
    brandName: brandName,
  );
}
