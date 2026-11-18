import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
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
              .map((e) => Map<String, dynamic>.from(e as Map))
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
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Stored record',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(item),
                      style: AppTheme.monoLabel(color: AppTheme.ink)
                          .copyWith(fontSize: 11, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (widget.kind) {
    'history' => Icons.history_rounded,
    'audit' => Icons.policy_outlined,
    _ => Icons.receipt_long_outlined,
  };

  String get _caption => switch (widget.kind) {
    'history' => 'Every stored content version you may access.',
    'audit' => 'Governance events written by the backend.',
    _ => 'Protected processing receipts for accessible checks.',
  };

  String _title(Map<String, dynamic> item) {
    if (widget.kind == 'history') {
      return '${item['brand_name'] ?? 'Brand'} · content v${item['version'] ?? item['content_version'] ?? '—'}';
    }
    return (item['action'] ?? item['receipt_id'] ?? 'Record').toString();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
            children: [
              PageIntro(
                eyebrow: 'SERVER RECORDS',
                eyebrowTone: Tone.success,
                title: widget.title,
                subtitle: _caption,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_items == null)
                const LoadingBlock()
              else if (_items!.isEmpty)
                EmptyStateCard(
                  title: 'No records yet',
                  message: 'Records appear here after checks, decisions and uploads are stored by the backend.',
                  icon: _icon,
                )
              else
                ..._items!.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      radius: 16,
                      onTap: () => _open(item),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.mint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _icon,
                              size: 18,
                              color: AppTheme.tealText,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _title(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.labelLarge.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (item['created_at'] ??
                                          item['timestamp'] ??
                                          item['check_id'] ??
                                          '')
                                      .toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.monoLabel().copyWith(
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (item['approval_valid'] == true)
                            const StatusPill(
                              label: 'Valid',
                              tone: Tone.success,
                              compact: true,
                            )
                          else if (widget.kind == 'receipts')
                            const StatusPill(label: 'Recorded', compact: true),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppTheme.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
