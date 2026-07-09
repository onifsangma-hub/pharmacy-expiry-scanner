// lib/utils/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // Palette — clean clinical teal with amber alerts
  static const Color primary = Color(0xFF0D7377); // deep teal
  static const Color primaryLight = Color(0xFF14BDBC); // lighter teal
  static const Color surface = Color(0xFFF5F8F8); // off-white teal tint
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color expired = Color(0xFFD32F2F); // red
  static const Color expiring7Days = Color(0xFFF57C00); // orange
  static const Color expiring30Days = Color(0xFFFBC02D); // yellow
  static const Color expiringSoon = expiring30Days;
  static const Color healthy = Color(0xFF2E7D32); // green
  static const Color lowStock = Color(0xFF7B1FA2); // purple
  static const Color expiryMissing = Color(0xFF6A5F7D); // purple-gray
  static const Color textPrimary = Color(0xFF1A2D2E);
  static const Color textSecondary = Color(0xFF5A7A7B);
  static const Color divider = Color(0xFFDDE8E8);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          surface: surface,
        ),
        scaffoldBackgroundColor: surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: divider, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(color: textSecondary),
        ),
        dividerTheme: const DividerThemeData(color: divider, space: 1),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: primary,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      );
}

class AppCategories {
  static const List<String> list = [
    'Antibiotics',
    'Antifungal',
    'Analgesics',
    'Antacids',
    'Antihistamines',
    'Cardiovascular',
    'Dermatology',
    'Diabetes',
    'Eye/Ear Drops',
    'Gastrointestinal',
    'Medical Supply',
    'Neurological',
    'Respiratory',
    'Vitamins & Supplements',
    'Other',
  ];

  /// Offline, best-effort category suggestion from a medicine name. Purely
  /// local (no external database) — used only to pre-select a sensible category
  /// that the user can still change. Returns '' when there is no confident
  /// match, so the field stays blank rather than being guessed.
  static String suggestForName(String name) {
    final n = name.toLowerCase();
    if (n.trim().isEmpty) return '';

    // Antifungals — e.g. Terconazole, Fluconazole, Clotrimazole, Nystatin.
    const antifungal = [
      'terconazole',
      'fluconazole',
      'clotrimazole',
      'miconazole',
      'ketoconazole',
      'itraconazole',
      'voriconazole',
      'econazole',
      'tioconazole',
      'butoconazole',
      'nystatin',
      'terbinafine',
      'griseofulvin',
      'amphotericin',
      'antifungal',
    ];
    if (antifungal.any(n.contains)) return 'Antifungal';

    // Common antibiotics (kept conservative to avoid mis-categorizing).
    const antibiotic = [
      'amoxicillin',
      'penicillin',
      'azithromycin',
      'ciprofloxacin',
      'doxycycline',
      'cephalexin',
      'clindamycin',
      'metronidazole',
      'erythromycin',
      'levofloxacin',
    ];
    if (n.contains('antibiotic') ||
        n.endsWith('cillin') ||
        antibiotic.any(n.contains)) {
      return 'Antibiotics';
    }

    if (n.contains('alcohol prep pad') ||
        n.contains('prep pads') ||
        n.contains('prep pad')) {
      return 'Medical Supply';
    }

    return '';
  }
}

class AppDosageForms {
  static const List<String> list = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Cream',
    'Ointment',
    'Drops',
    'Alcohol Prep Pads',
    'Inhaler',
    'Suspension',
    'Solution',
    'Powder',
    'Other',
  ];

  /// Offline, best-effort dosage-form suggestion from a medicine name (purely
  /// local, no external database). e.g. "Terconazole Vaginal Cream 0.4%" →
  /// "Cream". Returns '' when there is no confident match so nothing is guessed.
  static String suggestForName(String name) {
    final n = name.toLowerCase();
    if (n.trim().isEmpty) return '';
    if (n.contains('cream')) return 'Cream';
    if (n.contains('ointment')) return 'Ointment';
    if (n.contains('syrup')) return 'Syrup';
    if (n.contains('suspension')) return 'Suspension';
    if (n.contains('inhaler') ||
        n.contains('inhalation') ||
        n.contains('aerosol')) {
      return 'Inhaler';
    }
    if (n.contains('injection') ||
        n.contains('injectable') ||
        n.contains('vial') ||
        n.contains('ampoule') ||
        n.contains('ampule')) {
      return 'Injection';
    }
    if (n.contains('drop') ||
        n.contains('eye ') ||
        n.contains('ear ') ||
        n.contains('ophthalmic') ||
        n.contains('otic')) {
      return 'Drops';
    }
    if (n.contains('powder') || n.contains('sachet')) return 'Powder';
    if (n.contains('solution')) return 'Solution';
    if (n.contains('alcohol prep pad') ||
        n.contains('prep pads') ||
        n.contains('prep pad')) {
      return 'Alcohol Prep Pads';
    }
    if (n.contains('capsule') || n.contains('cap ')) return 'Capsule';
    if (n.contains('tablet') || n.contains(' tab') || n.contains('caplet')) {
      return 'Tablet';
    }
    return '';
  }
}
