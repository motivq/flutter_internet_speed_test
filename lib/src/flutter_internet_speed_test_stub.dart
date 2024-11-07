// Import necessary libraries
import 'dart:async';
import 'dart:convert';
import 'dart:js';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:tuple_dart/tuple.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';
import 'models/server_selection_response.dart';

typedef CancelListening = void Function();
typedef DoneCallback = void Function(double transferRate, SpeedUnit unit);
typedef ProgressCallback = void Function(
  double percent,
  double transferRate,
  SpeedUnit unit,
);
typedef ErrorCallback = void Function(
    String errorMessage, String speedTestError);
typedef CancelCallback = void Function();

class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  MethodChannelFlutterInternetSpeedTest();

  static void registerWith(Registrar registrar) {
    FlutterInternetSpeedTestPlatform.instance =
        MethodChannelFlutterInternetSpeedTest();
  }
}
