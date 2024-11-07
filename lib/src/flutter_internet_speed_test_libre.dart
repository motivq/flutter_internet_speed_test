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

  @override
  bool get isLogEnabled => logEnabled && kDebugMode;

  double _dlStatus = 0.0;
  double _ulStatus = 0.0;
  double _dlProgress = 0.0;
  double _ulProgress = 0.0;
  double _pingStatus = 0.0;
  double _jitterStatus = 0.0;
  double _pingProgress = 0.0;
  int _testState = -1;

  // JavaScript Speedtest object
  JsObject? _speedtest;

  // Current test ID
  int _currentTestId = 0;

  // Initialize the Speedtest object
  void _initSpeedtest() async {
    _speedtest ??= JsObject(context['Speedtest']);
    _speedtest!.callMethod('setParameter', ['telemetry_level', '3']);
    _speedtest!.callMethod(
        'setParameter', ['url_getIp', 'http://localhost:8080/getIP.php']);
    _speedtest!.callMethod(
        'setParameter', ['url_dl', 'http://localhost:8080/garbage.php']);
    _speedtest!.callMethod(
        'setParameter', ['url_ul', 'http://localhost:8080/empty.php']);
    _speedtest!.callMethod(
        'setParameter', ['url_ping', 'http://localhost:8080/empty.php']);
    _speedtest!.callMethod('setParameter',
        ['url_telemetry', 'http://localhost:8080/results/telemetry.php']);
    //_speedtest!.callMethod('onupdate', [allowInterop(_onUpdate)]);
    //_speedtest!.callMethod('onend', [allowInterop(_onEnd)]);
  }

  var downloadCompleter = Completer<void>();

  Future<void> _getIpAndStartDownloadTest() async {
    //final completer = Completer<void>();

    _speedtest!.callMethod('getIp', [
      allowInterop((JSString ispInfo) {
        //print('IP data received1: $ipData');
        // access the getIp javascript function on the window object
        print('IP data received2');
        print(
            json.decode(ispInfo.toDart)); //TODO: need to convert to a dart type

        _speedtest!.callMethod('startDownloadTest');
      })
    ]);

    return downloadCompleter.future;
  }

  @override
  Future<CancelListening> startDownloadTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required int fileSize,
    required String testServer,
  }) async {
    _initSpeedtest();
    _currentTestId++;

    // Store callbacks
    callbacksById[_currentTestId] =
        Tuple4(onError, onProgress, onDone, onCancel);

    // Set up settings
    final settings = {
      'url_dl': '$testServer/garbage.php',
      //time_dl_max': fileSize / 1000000, // Adjust time based on file size
      'telemetry_level': 3,
    };

    // Loop through settings and set each parameter
    settings.forEach((key, value) {
      _speedtest!.callMethod('setParameter', [key, value]);
    });

    // Set up event handlers
    if (_speedtest != null) {
      _speedtest!['onupdate'] = allowInterop(_onUpdate);
      _speedtest!['onend'] = allowInterop(_onEndUploadOrDownload);
    }

    // Wait for IP fetch before starting test
    await _getIpAndStartDownloadTest();

    return () {
      cancelTest();
    };
  }

  @override
  Future<CancelListening> startUploadTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required int fileSize,
    required String testServer,
  }) async {
    _initSpeedtest();
    _currentTestId++;

    // Store callbacks
    callbacksById[_currentTestId] =
        Tuple4(onError, onProgress, onDone, onCancel);

    // Set up settings
    final settings = {
      'url_ul': '$testServer/empty.php',
      'time_ul_max': fileSize / 1000000, // Adjust time based on file size
      'getIp_ispInfo': true,
      'getIp_ispInfo_distance': 10,
      'telemetry_level': 3,
    };

    // Loop through settings and set each parameter
    settings.forEach((key, value) {
      _speedtest!.callMethod('setParameter', [key, value]);
    });

    // Set up event handlers
    if (_speedtest != null) {
      _speedtest!['onupdate'] = allowInterop(_onUpdate);
      _speedtest!['onend'] = allowInterop(_onEndUploadOrDownload);
    }

    // Start the test
    _speedtest!.callMethod('startUploadTest');

    return () {
      cancelTest();
    };
  }

  @override
  Future<CancelListening> startPingTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required String testServer,
  }) async {
    _initSpeedtest();
    _currentTestId++;

    // Store callbacks
    callbacksById[_currentTestId] =
        Tuple4(onError, onProgress, onDone, onCancel);

    // Set up settings
    final settings = {
      'url_ping': '$testServer/garbage.php',
      //time_dl_max': fileSize / 1000000, // Adjust time based on file size
      'telemetry_level': 3,
    };

    // Loop through settings and set each parameter
    settings.forEach((key, value) {
      _speedtest!.callMethod('setParameter', [key, value]);
    });

    // Set up event handlers
    if (_speedtest != null) {
      _speedtest!['onupdate'] = allowInterop(_onUpdate);
      _speedtest!['onend'] = allowInterop(_onEndUploadOrDownload);
    }

    // Wait for IP fetch before starting test
    await _getIpAndStartDownloadTest();

    return () {
      cancelTest();
    };
  }

  @override
  Future<void> toggleLog({
    required bool value,
  }) async {
    logEnabled = value;
  }

  dynamic jsToNative(dynamic jsObject) {
    if (jsObject is JsArray) {
      return jsArrayToList(jsObject);
    } else if (jsObject is JsObject) {
      return jsObjectToMap(jsObject);
    } else if (jsObject is JsFunction) {}
    return jsObject; // Already a native type
  }

  List jsArrayToList(JsArray array) {
    List result = [];
    for (var item in array) {
      result.add(jsToNative(item));
    }
    return result;
  }

  Map jsObjectToMap(JsObject object) {
    Map result = {};
    for (var key in context['Object'].callMethod('keys', [object])) {
      result[key] = jsToNative(object[key]);
    }
    return result;
  }

  @override
  Future<ServerSelectionResponse?> getDefaultServer({
    String? serverListUrl, // Accept serverListUrl
    Map<String, dynamic>? additionalConfigs, // Accept additional configurations
  }) async {
    _initSpeedtest();

    Completer<ServerSelectionResponse?> completer = Completer();

    // Load server list (assuming you have a server list URL)
    //TODO: load this from a config
    serverListUrl ??= 'http://localhost:8080/servers.json';

    _speedtest!.callMethod('loadServerList', [
      serverListUrl,
      allowInterop((servers) {
        if (servers != null) {
          var mappedServers = jsObjectToMap(servers);
          print(mappedServers);
          // Select the best server
          _speedtest!.callMethod('selectServer', [
            allowInterop((bestServer) {
              if (bestServer != null) {
                var theThang = jsObjectToMap(bestServer);
                print(theThang);
                // Server selected
                _speedtest!.callMethod('setSelectedServer', [bestServer]);
                //TODO: Pull in the client information to create the client object
                //_speedtest!
                //    .callMethod('setParameter', ['ipToUse', '76.214.112.25']);
                //_speedtest!.callMethod('setParameter', ['getIp_ispInfo', true]);
                //_speedtest!
                //    .callMethod('setParameter', ['getIp_ispInfo_distance', 10]);
/*
                //we need to call the getIP function
                _speedtest!.callMethod('getIp', [
                  allowInterop((ipData) {
                    print('IP data received: $ipData');
                  })
                ]);
                */
                // Create ServerSelectionResponse
                Client client = Client(
                  ip: theThang['server'] as String,
                  isp: "",
                  latitude: 0,
                  longitude: 0,
                  // Add other necessary fields for Client
                );

                // If mappedServers is a single server object
                List<Targets> targets = [
                  Targets(
                    name: theThang['name'] as String?,
                    url: theThang['url'] as String?,
                    // Add other necessary fields for Targets
                  )
                ];

                ServerSelectionResponse response = ServerSelectionResponse(
                  client: client,
                  targets: targets,
                );
                completer.complete(response);
              } else {
                completer.complete(null);
              }
            })
          ]);
        } else {
          completer.complete(null);
        }
      })
    ]);

    // Apply additional configurations if provided
    additionalConfigs?.forEach((key, value) {
      _speedtest!.callMethod('setParameter', [key, value]);
    });

    return completer.future;
  }

  @override
  Future<bool> cancelTest() async {
    if (_speedtest != null) {
      _speedtest!.callMethod('abort');
      return true;
    }
    return false;
  }

  @override
  Future<String?> getPlatformVersion() async {
    // Return the platform version if needed
    return null;
  }

  // Handler for onupdate event
  void _onUpdate(dynamic data) {
    // Convert JavaScript object to Dart Map
    Map<String, dynamic> result = Map<String, dynamic>.from(jsToNative(data));
    print(result.toString());
    // Extract values
    _dlStatus = double.tryParse(result['dlStatus'].toString()) ?? 0.0;
    _ulStatus = double.tryParse(result['ulStatus'].toString()) ?? 0.0;
    _dlProgress = double.tryParse(result['dlProgress'].toString()) ?? 0.0;
    _ulProgress = double.tryParse(result['ulProgress'].toString()) ?? 0.0;
    final _testType = result['testType']?.toString() ?? "";

    // Callbacks
    switch (_testType) {
      case 'download':
        // Handle download test logic
        var callbackTuple = callbacksById[_currentTestId];
        if (callbackTuple != null) {
          callbackTuple.item2(_dlProgress * 100, _dlStatus, SpeedUnit.mbps);
        }
        break;
      case 'upload':
        // Handle upload test logic
        var callbackTuple = callbacksById[_currentTestId];
        if (callbackTuple != null) {
          callbackTuple.item2(_ulProgress * 100, _ulStatus, SpeedUnit.mbps);
        }
        break;
      case 'ping':
        // Handle ping test logic
        // Add your ping handling code here
        break;
      case 'ip':
        // Handle IP test logic
        // Add your IP handling code here
        break;
      default:
        // Handle unknown test type
        break;
    }
  }

  // Handler for onend event
  void _onEndUploadOrDownload(
      bool aborted, String testType, double finalSpeed) {
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Test aborted', 'Aborted');
      } else {
        // Assuming that we have the final transfer rates
        // You may need to store the final rates in _onUpdate
        callbackTuple.item3(
            finalSpeed, SpeedUnit.mbps); // Replace 0.0 with actual rate
      }
      downloadCompleter.complete();
    }
  }

  void _onEndPing(
      bool aborted, String testType, double finalSpeed, double jitter) {
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      callbackTuple.item3(finalSpeed, SpeedUnit.mbps);
    }
  }

  void _onEndAllTests(bool aborted, String testType, double dlStatus,
      double ulStatus, double pingStatus, double jitterStatus) {
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      callbackTuple.item3(dlStatus, SpeedUnit.mbps);
    }
  }
}
