import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const primary = Colors.deepPurple;
  static const primaryDark = Colors.deepPurpleAccent;
  static const accent = Color(0xFFE0A458);
  static const surface = Color(0xFFFFFBF3);

  // CAN task states: soft fills keep the card readable while making the
  // non-actionable states easy to scan in a busy task list.
  static const canTaskCompletedSurface = Color(0xFFEAF4EC);
  static const canTaskCompletedBorder = Color(0xFF8BBF94);
  static const canTaskCompletedIcon = Color(0xFF2E6B3E);
  static const canTaskDisabledSurface = Color(0xFFF1F2F3);
  static const canTaskDisabledBorder = Color(0xFFB7BCC1);
  static const canTaskDisabledIcon = Color(0xFF59636D);
}
