import 'package:flutter/material.dart';

/// Every colour, size and spacing value the app uses lives here, so the whole look can be changed in one place.

// Brand colours
const navy = Color(0xFF0E1A3A);
const saffron = Color(0xFFF59E1B);
const paper = Color(0xFFF7F5EF);

// Meaning colours (always shown with an icon and words too, never colour alone)
const good = Color(0xFF2E7D32);
const warn = Color(0xFFE65100);
const bad = Color(0xFFC62828);

// Spacing and shape
const gap = 14.0;
const radius = 14.0;

ThemeData buildTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: saffron),
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
    );

/// A small banner that says what is happening, with an icon, a title and one line of detail.
class StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool busy;
  const StatusBanner({super.key, required this.icon, required this.color, required this.title, required this.detail, this.busy = false});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: busy ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) : Icon(icon, color: color, size: 32),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(detail),
        ),
      );
}
