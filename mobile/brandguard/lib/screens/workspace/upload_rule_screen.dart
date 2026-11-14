
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadRuleScreen extends StatefulWidget {
  const UploadRuleScreen({super.key});

  @override
  State<UploadRuleScreen> createState() => _UploadRuleScreenState();
}

class _UploadRuleScreenState extends State<UploadRuleScreen> {
  static const Color navy = Color(0xFF142C3B);
  static const Color darkNavy = Color(0xFF001725);
  static const Color teal = Color(0xFF006B5E);
  static const Color mint = Color(0xFF81F7E1);
  static const Color background = Color(0xFFF7F8F6);
  static const Color border = Color(0xFFE5EAE7);
  static const Color secondary = Color(0xFF73787C);
  static const Color green = Color(0xFF4B9475);
  static const Color red = Color(0xFFC96B6B);

  static const String storageKey = 'brandguard_uploaded_rules_v1';

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceController = TextEditingController();

  final List<String> categories = const [
    'Tone of Voice',
    'Visual Identity',
    'Legal & Compliance',
    'Product Claims',
  ];

  String selectedCategory = 'Tone of Voice';
  List<Map<String, dynamic>> rules = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);

    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as List;
        rules = decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } catch (_) {
        rules = [];
      }
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(rules));
  }

  Future<void> _addRule() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a rule title and description.'),
        ),
      );
      return;
    }

    final rule = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'title': title,
      'category': selectedCategory,
      'description': description,
      'source': _sourceController.text.trim(),
      'createdAt': DateTime.now().toIso8601String(),
      'active': true,
    };

    setState(() => rules.insert(0, rule));
    await _saveRules();

    _titleController.clear();
    _descriptionController.clear();
    _sourceController.clear();

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Brand rule saved successfully.')),
    );
  }

  Future<void> _deleteRule(int index) async {
    setState(() => rules.removeAt(index));
    await _saveRules();
  }

  Future<void> _toggleRule(int index, bool value) async {
    setState(() => rules[index]['active'] = value);
    await _saveRules();
  }

  void _showAddRuleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 22,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Add Brand Rule',
                      style: _style(
                        size: 19,
                        weight: FontWeight.w800,
                        color: darkNavy,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Create a rule for your brand governance system.',
                      style: _style(size: 11, color: secondary),
                    ),
                    const SizedBox(height: 18),
                    _label('RULE TITLE'),
                    _input(
                      _titleController,
                      'e.g. Always use approved brand terminology',
                    ),
                    const SizedBox(height: 14),
                    _label('CATEGORY'),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: _decoration(),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(
                            category,
                            style: _style(size: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedCategory = value);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    _label('RULE DESCRIPTION'),
                    _input(
                      _descriptionController,
                      'Describe what users must follow...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 14),
                    _label('REFERENCE SOURCE (OPTIONAL)'),
                    _input(
                      _sourceController,
                      'Document name or reference URL',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _addRule,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          'Save Brand Rule',
                          style: _style(
                            size: 12,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _label(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        value,
        style: _style(
          size: 9,
          weight: FontWeight.w800,
          color: secondary,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: _style(size: 12),
      decoration: _decoration(hint: hint),
    );
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _style(size: 11, color: secondary.withValues(alpha: 0.7)),
      filled: true,
      fillColor: const Color(0xFFF8FAF9),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: teal, width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount =
        rules.where((rule) => rule['active'] == true).length;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: darkNavy,
        title: Text(
          'Upload Rule',
          style: _style(size: 17, weight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRuleSheet,
        backgroundColor: navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Rule',
          style: _style(
            size: 12,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.rule_folder_rounded,
                        size: 35,
                        color: mint,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Brand Rule Library',
                              style: _style(
                                size: 15,
                                weight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$activeCount active rules • ${rules.length} total rules',
                              style: _style(size: 10, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Your Brand Rules',
                  style: _style(size: 16, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (rules.isEmpty)
                  _emptyState()
                else
                  ...rules.asMap().entries.map((entry) {
                    final index = entry.key;
                    final rule = entry.value;
                    final active = rule['active'] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 11),
                      padding: const EdgeInsets.all(14),
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
                              Expanded(
                                child: Text(
                                  rule['title']?.toString() ?? '',
                                  style: _style(
                                    size: 12,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteRule(index),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: red,
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            rule['category']?.toString() ?? '',
                            style: _style(
                              size: 9,
                              weight: FontWeight.w800,
                              color: teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            rule['description']?.toString() ?? '',
                            style: _style(
                              size: 11,
                              color: secondary,
                              height: 1.5,
                            ),
                          ),
                          if ((rule['source'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Source: ${rule['source']}',
                              style: _style(size: 10, color: navy),
                            ),
                          ],
                          const Divider(height: 20),
                          Row(
                            children: [
                              Text(
                                active ? 'Active' : 'Inactive',
                                style: _style(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: active ? green : secondary,
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: active,
                                activeThumbColor: teal,
                                onChanged: (value) =>
                                    _toggleRule(index, value),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          const Icon(Icons.rule_rounded, size: 34, color: secondary),
          const SizedBox(height: 10),
          Text(
            'No rules added yet',
            style: _style(size: 13, weight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Tap Add Rule to create your first brand rule.',
            textAlign: TextAlign.center,
            style: _style(size: 10, color: secondary),
          ),
        ],
      ),
    );
  }

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = const Color(0xFF26363C),
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
