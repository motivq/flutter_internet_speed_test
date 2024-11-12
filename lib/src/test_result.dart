import 'package:flutter_internet_speed_test/src/callbacks_enum.dart';

class TestResult {
  final TestType type;
  final double transferRate;
  final SpeedUnit unit;
  final int durationInMillis; // Duration to complete
  final double? jitter; // New field for jitter
  final double? ping; // New field for ping

  TestResult(
    this.type,
    this.transferRate,
    this.unit, {
    int durationInMillis = 0,
    this.jitter, // Initialize jitter
    this.ping, // Initialize ping
  }) : durationInMillis = durationInMillis - (durationInMillis % 1000);

  bool hasRan() => durationInMillis > 0;
}
