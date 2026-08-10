import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const primary = Colors.deepPurple;
  static const primaryDark = Colors.deepPurpleAccent;
  static const accent = Color(0xFFE0A458);
  static const surface = Color(0xFFFFFBF3);

  // Shared task-state semantics across Limabang, CAN, and Charge.
  static const taskPending = Color(0xFFB42318);
  static const taskConfirmed = Color(0xFF9A6700);
  static const taskCompleted = Color(0xFF2E6B3E);
  static const taskDisabled = Color(0xFF59636D);
  static const taskPendingSurface = Color(0xFFFFECEB);
  static const taskPendingBorder = Color(0xFFF0AAA5);
  static const taskConfirmedSurface = Color(0xFFFFF4D6);
  static const taskConfirmedBorder = Color(0xFFE5C26B);
  static const taskCompletedSurface = Color(0xFFEAF4EC);
  static const taskCompletedBorder = Color(0xFF8BBF94);
  static const taskDisabledSurface = Color(0xFFF1F2F3);
  static const taskDisabledBorder = Color(0xFFB7BCC1);

  // Charge identity: electric blue with a quiet cyan accent. Keep this local
  // to the Charge lane rather than changing the shared app seed color.
  static const chargePrimary = Color(0xFF087EA4);
  static const chargeAccent = Color(0xFF42D3C5);
  static const chargeSurface = Color(0xFFEAF8FA);
  static const chargeCompletedSurface = taskCompletedSurface;
  static const chargeCompletedBorder = Color(0xFF8BBF94);
  static const chargeCompletedIcon = Color(0xFF2E6B3E);
  static const chargeDisabledSurface = Color(0xFFF1F2F3);
  static const chargeDisabledBorder = Color(0xFFB7BCC1);
  static const chargeDisabledIcon = Color(0xFF59636D);

  // CAN task states: soft fills keep the card readable while making the
  // non-actionable states easy to scan in a busy task list.
  static const canTaskCompletedSurface = Color(0xFFEAF4EC);
  static const canTaskCompletedBorder = Color(0xFF8BBF94);
  static const canTaskCompletedIcon = Color(0xFF2E6B3E);
  static const canTaskDisabledSurface = Color(0xFFF1F2F3);
  static const canTaskDisabledBorder = Color(0xFFB7BCC1);
  static const canTaskDisabledIcon = Color(0xFF59636D);
}
