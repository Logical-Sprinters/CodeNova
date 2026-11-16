import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../core/network/brandguard_api_service.dart';
import '../receipts/receipt_detail_screen.dart';

class ServerRecordsScreen extends StatefulWidget {
  const ServerRecordsScreen({
    super.key,
    required this.kind,
    required this.title,
  });
  final String kind, title;
  @override
  State<ServerRecordsScreen> createState() => _ServerRecordsScreenState();
}

class _ServerRecordsScreenState extends State<ServerRecordsScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson(
        '/api/v1/${widget.kind}${widget.kind == 'receipts' ? '/' : ''}',
      );
      final raw =
          data['items'] ??
          data['receipts'] ??
          data['events'] ??
          data['audit'] ??
          [];
      if (mounted) {
        setState(() {
          _items = (raw as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _open(Map<String, dynamic> item) {
    final receiptId = item['receipt_id']?.toString();
    if (widget.kind == 'receipts' && receiptId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptDetailScreen(receiptId: receiptId),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(item),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Server records, scoped to your permissions. Tap a row to inspect the stored details.',
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_items == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_items?.isEmpty == true)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('No records yet.'),
            ),
          ...?_items?.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  onTap: () => _open(item),
                  leading: Icon(
                    widget.kind == 'history'
                        ? Icons.history
                        : widget.kind == 'audit'
                        ? Icons.policy_outlined
                        : Icons.receipt_long_outlined,
                  ),
                  title: Text(
                    widget.kind == 'history'
                        ? '${item['brand_name']} · content v${item['version']}'
                        : (item['action'] ?? item['receipt_id'] ?? 'Record')
                              .toString(),
                  ),
                  subtitle: Text(
                    (item['created_at'] ??
                            item['timestamp'] ??
                            item['check_id'] ??
                            '')
                        .toString(),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
