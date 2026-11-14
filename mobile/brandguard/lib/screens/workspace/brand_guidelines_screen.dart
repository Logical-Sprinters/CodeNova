
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrandGuidelinesScreen extends StatefulWidget {
  const BrandGuidelinesScreen({super.key});

  @override
  State<BrandGuidelinesScreen> createState() =>
      _BrandGuidelinesScreenState();
}

class _BrandGuidelinesScreenState extends State<BrandGuidelinesScreen> {
  static const navy = Color(0xFF142C3B);
  static const teal = Color(0xFF006B5E);
  static const background = Color(0xFFF7F8F6);
  static const border = Color(0xFFE5EAE7);
  static const secondary = Color(0xFF73787C);

  static const storageKey = 'brandguard_guidelines_v1';

  bool isLoading = true;
  String selectedCategory = 'All';

  final List<Map<String, dynamic>> guidelines = [];

  final categories = [
    'All',
    'Tone of Voice',
    'Visual Identity',
    'Legal & Compliance',
    'Product Claims',
  ];

  @override
  void initState() {
    super.initState();
    loadGuidelines();
  }

  TextStyle style({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color color = navy,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  Future<void> loadGuidelines() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);

    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as List;
        guidelines
          ..clear()
          ..addAll(
            decoded.map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
      } catch (_) {
        guidelines.clear();
      }
    } else {
      guidelines.addAll([
        {
          'title': 'Professional Tone',
          'category': 'Tone of Voice',
          'description':
              'Use clear, confident and professional language. Avoid slang and exaggerated promises.',
          'source': 'Brand Voice Handbook',
          'enabled': true,
        },
        {
          'title': 'Approved Brand Colors',
          'category': 'Visual Identity',
          'description':
              'Use approved navy, teal and mint colors in all official brand materials.',
          'source': 'Visual Identity Guide',
          'enabled': true,
        },
        {
          'title': 'No Unsupported Guarantees',
          'category': 'Product Claims',
          'description':
              'Never publish absolute guarantees unless supported by approved evidence.',
          'source': 'Product Claims Policy',
          'enabled': true,
        },
        {
          'title': 'Compliance Disclaimer',
          'category': 'Legal & Compliance',
          'description':
              'Include required disclaimers wherever regulated product claims are used.',
          'source': 'Compliance Handbook',
          'enabled': true,
        },
      ]);

      await saveGuidelines();
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> saveGuidelines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(guidelines));
  }

  List<Map<String, dynamic>> get filteredGuidelines {
    if (selectedCategory == 'All') return guidelines;

    return guidelines
        .where((item) => item['category'] == selectedCategory)
        .toList();
  }

  int get activeCount =>
      guidelines.where((item) => item['enabled'] == true).length;

  Future<void> addGuideline() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final sourceController = TextEditingController();

    String category = 'Tone of Voice';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(
                'Add Brand Guideline',
                style: style(size: 18, weight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogField(titleController, 'Guideline title'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: categories
                          .where((item) => item != 'All')
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => category = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      descriptionController,
                      'Describe the guideline',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      sourceController,
                      'Source / Reference',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (titleController.text.trim().isEmpty ||
                        descriptionController.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Save Guideline'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      setState(() {
        guidelines.insert(0, {
          'title': titleController.text.trim(),
          'category': category,
          'description': descriptionController.text.trim(),
          'source': sourceController.text.trim().isEmpty
              ? 'Manually added'
              : sourceController.text.trim(),
          'enabled': true,
        });
      });

      await saveGuidelines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guideline added successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    titleController.dispose();
    descriptionController.dispose();
    sourceController.dispose();
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: style(size: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: style(size: 11, color: secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> toggleGuideline(int index, bool value) async {
    setState(() {
      filteredGuidelines[index]['enabled'] = value;
    });
    await saveGuidelines();
  }

  Future<void> deleteGuideline(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete guideline?', style: style(size: 17)),
        content: Text(
          'This guideline will be removed from your local list.',
          style: style(size: 12, color: secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => guidelines.remove(item));
      await saveGuidelines();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Brand Guidelines',
          style: style(size: 18, weight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: addGuideline,
            icon: const Icon(Icons.add_circle_outline, color: teal),
            tooltip: 'Add guideline',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: teal))
          : Column(
              children: [
                _summary(),
                _categoryFilters(),
                Expanded(
                  child: filteredGuidelines.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            24,
                          ),
                          itemCount: filteredGuidelines.length,
                          itemBuilder: (context, index) {
                            return _guidelineCard(
                              filteredGuidelines[index],
                              index,
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addGuideline,
        backgroundColor: navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          'Add Guideline',
          style: style(
            size: 12,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                color: Color(0xFF81F7E1),
              ),
              const SizedBox(width: 8),
              Text(
                'GOVERNANCE CONTROL CENTER',
                style: style(
                  size: 9,
                  weight: FontWeight.w800,
                  color: const Color(0xFF81F7E1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Keep every message on-brand.',
            style: style(
              size: 20,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Manage the rules and references used to guide brand checks.',
            style: style(
              size: 11,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              _summaryValue('TOTAL RULES', '${guidelines.length}'),
              const SizedBox(width: 28),
              _summaryValue('ACTIVE RULES', '$activeCount'),
              const SizedBox(width: 28),
              _summaryValue(
                'CATEGORIES',
                '${guidelines.map((e) => e['category']).toSet().length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: style(
            size: 21,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: style(
            size: 8,
            weight: FontWeight.w700,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }

  Widget _categoryFilters() {
    return SizedBox(
      height: 45,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = selectedCategory == category;

          return ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (_) {
              setState(() => selectedCategory = category);
            },
            selectedColor: const Color(0xFFDDF3ED),
            backgroundColor: Colors.white,
            labelStyle: style(
              size: 10,
              weight: FontWeight.w700,
              color: selected ? teal : secondary,
            ),
            side: BorderSide(
              color: selected ? teal : border,
            ),
          );
        },
      ),
    );
  }

  Widget _guidelineCard(Map<String, dynamic> item, int index) {
    final enabled = item['enabled'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcon(item['category']),
                  color: teal,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] ?? '',
                      style: style(size: 13, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item['category'] ?? '',
                      style: style(size: 9, color: secondary),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: teal,
                onChanged: (value) => toggleGuideline(index, value),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') deleteGuideline(item);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete guideline'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['description'] ?? '',
            style: style(
              size: 11,
              color: secondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.source_outlined,
                size: 14,
                color: teal,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Source: ${item['source'] ?? 'Not specified'}',
                  style: style(
                    size: 9,
                    weight: FontWeight.w700,
                    color: teal,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFEAF4EE)
                      : const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  enabled ? 'ACTIVE' : 'DISABLED',
                  style: style(
                    size: 8,
                    weight: FontWeight.w800,
                    color: enabled ? teal : secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'Tone of Voice':
        return Icons.record_voice_over_outlined;
      case 'Visual Identity':
        return Icons.palette_outlined;
      case 'Legal & Compliance':
        return Icons.gavel_rounded;
      case 'Product Claims':
        return Icons.fact_check_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: secondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No guidelines found',
              style: style(size: 15, weight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Add a guideline or select another category.',
              textAlign: TextAlign.center,
              style: style(size: 11, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}
