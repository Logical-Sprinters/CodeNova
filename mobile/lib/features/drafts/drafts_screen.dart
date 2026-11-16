import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';
import '../checks/new_brand_check_screen.dart';

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});
  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson('/api/v1/drafts');
      if (mounted) {
        setState(() {
          _items = (data['items'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _open([Map<String, dynamic>? item]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewBrandCheckScreen(draft: item)),
    );
    await _load();
  }

  Future<void> _delete(String id) async {
    try {
      await BrandGuardApiService.request(
        'DELETE',
        '/api/v1/drafts/${Uri.encodeComponent(id)}',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Saved drafts'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('New draft'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              const PageIntro(
                eyebrow: 'PRIVATE WORKSPACE',
                eyebrowTone: Tone.info,
                title: 'Saved drafts',
                subtitle: 'Continue a private, server-stored draft. Revision numbers protect against overwriting.',
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LoadingBlock(label: 'Loading your drafts…')
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_items.isEmpty)
                EmptyStateCard(
                  title: 'No saved drafts',
                  message: 'Save one from the brand-check editor and it will appear here with its revision number.',
                  icon: Icons.edit_note_rounded,
                  action: FilledButton.icon(
                    onPressed: () => _open(),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Create a draft'),
                  ),
                )
              else
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      radius: 16,
                      onTap: () => _open(item),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.mint,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.edit_note_rounded,
                              size: 19,
                              color: AppTheme.tealText,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['title']?.toString() ?? 'Draft',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.labelLarge.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item['brand_name']} · revision ${item['revision']}',
                                  style: AppTheme.monoLabel().copyWith(
                                    fontSize: 9.5,
                                  ),
                                ),
                                Text(
                                  '${item['updated_at'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.monoLabel().copyWith(
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete draft',
                            onPressed: () => _delete(item['id'].toString()),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
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
