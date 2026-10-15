import 'package:flutter/material.dart';

/// Farben passend zu home_radio.
const brandGreen = Color(0xFF2F9E5C);
const brandGreenDark = Color(0xFF1B6B3E);
const panelBackground = Color(0xFF141A22);
const tileBackground = Color(0xFF1E2630);
const accentAmber = Color(0xFFFFB300);

/// TV-optimiertes dunkles Theme (gleiche Basis wie home_radio).
ThemeData buildTvTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorSchemeSeed: brandGreen,
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.standard,
  );
  // Der hellere `primary`-Ton des Seeds ist als Fokusring auf Schwarz besser lesbar.
  final focusColor = base.colorScheme.primary;

  // Deutlicher Fokusrahmen fuer D-Pad-Bedienung vom Sofa aus.
  WidgetStateProperty<BorderSide?> focusBorder({double width = 3}) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: focusColor, width: width);
      }
      return null;
    });
  }

  return base.copyWith(
    focusColor: focusColor,
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: focusBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: focusBorder())),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        side: focusBorder(),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        side: focusBorder(width: 2),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: focusColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// Einheitlicher Fokusrahmen fuer D-Pad-navigierbare Elemente.
class TvFocusHighlight extends StatelessWidget {
  final bool focused;
  final Widget child;
  final BorderRadius borderRadius;

  const TvFocusHighlight({
    super.key,
    required this.focused,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: focused ? Theme.of(context).focusColor : Colors.transparent,
          width: 3,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: Theme.of(context).focusColor.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
