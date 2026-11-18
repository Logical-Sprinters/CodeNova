import 'package:material_ui/material_ui.dart';

import 'library_screen.dart';

class BrandGuidelinesScreen extends StatelessWidget {
  const BrandGuidelinesScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const LibraryScreen(kind: 'guidelines', title: 'Brand Guidelines');
}
