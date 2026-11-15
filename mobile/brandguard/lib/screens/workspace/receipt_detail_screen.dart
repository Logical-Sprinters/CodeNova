import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/brandguard_api_service.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final String receiptId;
  const ReceiptDetailScreen({Key? key, required this.receiptId}) : super(key: key);

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getReceipt(receiptId: widget.receiptId);
      setState(() => _receipt = data);
    } catch (e) {
      setState(() => _receipt = {'error': e.toString()});
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _receipt == null
              ? const Center(child: Text('No data'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: _receipt!.entries.map((e) {
                      return ListTile(
                        title: Text(e.key, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                        subtitle: Text(e.value?.toString() ?? ''),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}
