import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

Future<bool> isInternetAvailable() async {
  final connectivity = Connectivity();
  final connectivityResults = await connectivity.checkConnectivity();
  if (connectivityResults.any((result) => result != ConnectivityResult.none)) {
    return true;
  }

  // Listen to connectivity changes
  final completer = Completer<bool>();
  final subscription = connectivity.onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none) {
      completer.complete(true);
    }
  });

  // Wait for a connectivity change or timeout
  return completer.future.timeout(Duration(seconds: 5), onTimeout: () {
    subscription.cancel();
    return false;
  });
}
