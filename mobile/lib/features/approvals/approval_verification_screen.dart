import 'package:material_ui/material_ui.dart';

import '../../core/network/brandguard_api_service.dart';

class ApprovalVerificationScreen extends StatefulWidget {
  const ApprovalVerificationScreen({super.key});

  @override
  State<ApprovalVerificationScreen> createState() =>
      _ApprovalVerificationScreenState();
}

class _ApprovalVerificationScreenState
    extends State<ApprovalVerificationScreen> {
  final _checkIdCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _checkIdCtrl.dispose();
    _brandNameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    try {
      final resp = await BrandGuardApiService.verifyApproval(
        checkId: _checkIdCtrl.text.trim(),
        brandName: _brandNameCtrl.text.trim(),
        content: _contentCtrl.text,
      );
      if (!mounted) return;
      setState(() => _result = resp);
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = {'valid': false, 'reason': e.toString()});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approval Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _checkIdCtrl,
              decoration: const InputDecoration(labelText: 'Check ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _brandNameCtrl,
              decoration: const InputDecoration(labelText: 'Brand Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _verify,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Verify'),
            ),
            const SizedBox(height: 20),
            if (_result != null)
              Card(
                color: _result!['valid'] == true
                    ? Colors.green[100]
                    : Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valid: ${_result!['valid']}',
                        style: const TextStyle(fontFamily: 'Manrope'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${_result!['reason']}',
                        style: const TextStyle(fontFamily: 'Manrope'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
