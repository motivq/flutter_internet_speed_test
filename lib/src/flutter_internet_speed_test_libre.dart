// Import necessary libraries
import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:tuple_dart/tuple.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';
import 'models/server_selection_response.dart';
import 'speed_test.dart';

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

class SpeedTestConfig {
  final String baseUrl;
  final String urlGetIp;
  final String urlDl;
  final String urlUl;
  final String urlPing;
  final String urlTelemetry;
  final String urlServerList;
  final String telemetryLevel;

  SpeedTestConfig({
    required this.baseUrl,
    this.urlGetIp = 'getIP.php',
    this.urlDl = 'garbage.php',
    this.urlUl = 'empty.php',
    this.urlPing = 'empty.php',
    this.urlTelemetry = 'results/telemetry.php',
    this.urlServerList = 'servers.json',
    this.telemetryLevel = '3',
  });

  // getters combine baseUrl and urlServerList
  String get serverListUrl => '$baseUrl/$urlServerList';

  String get getIpUrl => '$baseUrl/$urlGetIp';
  String get dlUrl => '$baseUrl/$urlDl';
  String get ulUrl => '$baseUrl/$urlUl';
  String get pingUrl => '$baseUrl/$urlPing';
  String get telemetryUrl => '$baseUrl/$urlTelemetry';
  String get getTelemetryLevel => telemetryLevel;
}

class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  MethodChannelFlutterInternetSpeedTest({
    ISpeedtest? downloadSpeedTest,
    ISpeedtest? uploadSpeedTest,
  }) {
    _loadJavascriptFiles().then((_) {
      _downloadSpeedTest =
          downloadSpeedTest ?? _initializeJsSpeedtest('download');
      _uploadSpeedTest = uploadSpeedTest ?? _initializeJsSpeedtest('upload');
    }).catchError((error) {
      throw Exception('Failed to load JavaScript files: $error');
    });
  }

  Future<void> _loadJavascriptFiles() async {
    final completer = Completer<void>();
    final script = ScriptElement()
      ..type = 'application/javascript'
      ..src = 'packages/flutter_internet_speed_test/assets/speedtest.js'
      ..async = false
      ..onLoad.listen((_) => completer.complete())
      ..onError
          .listen((error) => completer.completeError('Failed to load script'));

    document.head!.append(script);
    await completer.future;
  }

  static JsSpeedtest _initializeJsSpeedtest(String type) {
    final jsObject = context['Speedtest'];
    if (jsObject == null) {
      throw Exception('Speedtest JavaScript object is not available.');
    }
    return JsSpeedtest(JsObject(jsObject, [
      'packages/flutter_internet_speed_test/assets/speedtest_worker.js',
      type
    ]));
  }

  ISpeedtest? _downloadSpeedTest;
  ISpeedtest? _uploadSpeedTest;

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
  // JsObject? _downloadSpeedTest;
  // JsObject? _uploadSpeedTest;
  // Current test ID
  int _currentTestId = 0;

  // client object
  Client? _client;

  SpeedTestConfig? _speedTestConfig;

  Future<void> _initSpeedtest({required SpeedTestConfig config}) async {
    _speedTestConfig = config;

    _downloadSpeedTest ??= JsSpeedtest(JsObject(context['Speedtest'], [
      'packages/flutter_internet_speed_test/assets/speedtest_worker.js',
      'download'
    ]));
    _initializeSpeedTestInstance(_downloadSpeedTest!);

    _uploadSpeedTest ??= JsSpeedtest(JsObject(context['Speedtest'], [
      'packages/flutter_internet_speed_test/assets/speedtest_worker.js',
      'upload'
    ]));
    _initializeSpeedTestInstance(_uploadSpeedTest!);

    await _copyTheTestPointsIfPossible();
  }

  Future<void> _copyTheTestPointsIfPossible() async {
    Completer<void> completer = Completer();

    if (_downloadSpeedTest!.getState() >= 2 &&
        _uploadSpeedTest!.getState() < 2) {
      final testPoints = _downloadSpeedTest!.getTestPoints();
      final selectedServer = _downloadSpeedTest!.getSelectedServer();

      _uploadSpeedTest!.addTestPoints(testPoints);

      // Assuming setSelectedServer is synchronous, complete the completer immediately
      _uploadSpeedTest!.setSelectedServer(selectedServer);
      completer.complete();
    } else {
      // If the conditions are not met, complete the completer immediately
      completer.complete();
    }

    return completer.future;
  }

  void _initializeSpeedTestInstance(ISpeedtest speedTestInstance) {
    speedTestInstance.setParameter(
        'telemetry_level', _speedTestConfig!.telemetryLevel);
    speedTestInstance.setParameter('url_getIp', _speedTestConfig!.getIpUrl);
    speedTestInstance.setParameter('url_dl', _speedTestConfig!.dlUrl);
    speedTestInstance.setParameter('url_ul', _speedTestConfig!.ulUrl);
    speedTestInstance.setParameter('url_ping', _speedTestConfig!.pingUrl);
    speedTestInstance.setParameter(
        'url_telemetry', _speedTestConfig!.telemetryUrl);
  }

  var _downloadCompleter = Completer<void>();
  var _uploadCompleter = Completer<void>();

  Future<void> _getIpAndStartDownloadTest() async {
    if (_client == null) {
      _downloadSpeedTest!.getIp((JSString ispInfo) {
        final decodedIspInfo = json.decode(ispInfo.toDart);
        // check if this is a valid type
        if (decodedIspInfo is Map<String, dynamic>) {
          _client = Client.fromNewModel(decodedIspInfo);
        } else {
          throw Exception(
              'Invalid ispInfo type. likely the server url for getIP is wrong' +
                  (_speedTestConfig?.getIpUrl ?? ""));
        }

        _downloadSpeedTest!.startDownloadTest();
      });
    } else {
      _downloadSpeedTest!.startDownloadTest();
    }
    return _downloadCompleter.future;
  }

  Future<void> _getIpAndStartUploadTest() async {
    await _copyTheTestPointsIfPossible();
    if (_client == null) {
      _uploadSpeedTest!.getIp((JSString ispInfo) {
        final decodedIspInfo = json.decode(ispInfo.toDart);
        // check if this is a valid type
        if (decodedIspInfo is Map<String, dynamic>) {
          _client = Client.fromNewModel(decodedIspInfo);
        } else {
          throw Exception(
              'Invalid ispInfo type. likely the server url for getIP is wrong' +
                  (_speedTestConfig?.getIpUrl ?? ""));
        }

        _uploadSpeedTest!.startUploadTest();
      });
    } else {
      _uploadSpeedTest!.startUploadTest();
    }

    return _uploadCompleter.future;
  }

  Future<void> ensureDownloadServerIsSelected(String testServer) async {
    if (_speedTestConfig == null || _speedTestConfig!.baseUrl != testServer) {
      // Initialize speed test with the new server
      await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));

      // Create a completer to wait for the server selection process to complete
      Completer<void> serverSelectionCompleter = Completer();

      // Load server list and select the server
      await loadDownloadServerList(_speedTestConfig!.serverListUrl, (servers) {
        if (servers != null) {
          var mappedServers = jsObjectToMap(servers);
          print(mappedServers);

          selectDownloadServer((bestServer) {
            if (bestServer != null) {
              setSelectedDownloadServer(bestServer);

              serverSelectionCompleter.complete(); // Complete the completer
            } else {
              serverSelectionCompleter.completeError('No server selected');
            }
          });
        } else {
          serverSelectionCompleter.completeError('No servers found');
        }
      });

      // Wait for the server selection process to complete
      await serverSelectionCompleter.future;
    }
  }

  Future<void> ensureUploadServerIsSelected(String testServer) async {
    if (_speedTestConfig == null || _speedTestConfig!.baseUrl != testServer) {
      // Initialize speed test with the new server
      await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));

      // Create a completer to wait for the server selection process to complete
      Completer<void> serverSelectionCompleter = Completer();

      // Load server list and select the server
      await loadUploadServerList(_speedTestConfig!.serverListUrl, (servers) {
        if (servers != null) {
          var mappedServers = jsObjectToMap(servers);
          print(mappedServers);

          selectUploadServer((bestServer) {
            if (bestServer != null) {
              setSelectedUploadServer(bestServer);

              serverSelectionCompleter.complete(); // Complete the completer
            } else {
              serverSelectionCompleter.completeError('No server selected');
            }
          });
        } else {
          serverSelectionCompleter.completeError('No servers found');
        }
      });

      // Wait for the server selection process to complete
      await serverSelectionCompleter.future;
    }
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
    await ensureDownloadServerIsSelected(testServer);

    _currentTestId++;
    callbacksById[_currentTestId] =
        Tuple4(onError, onProgress, onDone, onCancel);

    if (_downloadSpeedTest != null) {
      _downloadSpeedTest!.onUpdate(_onUpdate);
      _downloadSpeedTest!.onEnd(_onEndDownload);
    }

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
    await ensureUploadServerIsSelected(testServer);

    _currentTestId++;
    callbacksById[_currentTestId] =
        Tuple4(onError, onProgress, onDone, onCancel);

    if (_uploadSpeedTest != null) {
      _uploadSpeedTest!.onUpdate(_onUpdate);
      _uploadSpeedTest!.onEnd(_onEndUpload);
    }

    await _getIpAndStartUploadTest();

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
    await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));
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
      _downloadSpeedTest!.callMethod('setParameter', [key, value]);
    });

    // Set up event handlers
    if (_downloadSpeedTest != null) {
      _downloadSpeedTest!.onUpdate(_onUpdate);
      _downloadSpeedTest!.onEnd(_onEndPing);
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

  Future<void> loadDownloadServerList(
      String serverListUrl, Function callback) async {
    _downloadSpeedTest!.callMethod('loadServerList', [
      serverListUrl,
      allowInterop(callback),
    ]);
  }

  Future<void> loadUploadServerList(
      String serverListUrl, Function callback) async {
    _uploadSpeedTest!.callMethod('loadServerList', [
      serverListUrl,
      allowInterop(callback),
    ]);
  }

  Future<void> selectDownloadServer(Function callback) async {
    _downloadSpeedTest!.callMethod('selectServer', [
      allowInterop(callback),
    ]);
  }

  Future<void> selectUploadServer(Function callback) async {
    _uploadSpeedTest!.callMethod('selectServer', [
      allowInterop(callback),
    ]);
  }

  void setSelectedDownloadServer(dynamic server) {
    _downloadSpeedTest!.callMethod('setSelectedServer', [server]);
  }

  void setSelectedUploadServer(dynamic server) {
    _uploadSpeedTest!.callMethod('setSelectedServer', [server]);
  }

  @override
  Future<ServerSelectionResponse?> getDefaultServer({
    String? serverListUrl,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    Completer<ServerSelectionResponse?> completer = Completer();

    serverListUrl ??= 'http://localhost:8080';

    await _initSpeedtest(
        config: SpeedTestConfig(
            baseUrl: serverListUrl, urlServerList: "servers.json"));

    if (serverListUrl.isNotEmpty) {
      await loadDownloadServerList(serverListUrl, (servers) {
        if (servers != null) {
          var mappedServers = jsObjectToMap(servers);
          print(mappedServers);

          selectDownloadServer((bestServer) {
            if (bestServer != null) {
              var dartedBestServer = jsObjectToMap(bestServer);
              setSelectedDownloadServer(bestServer);

              List<Targets> targets = [
                Targets(
                  name: dartedBestServer['name'] as String?,
                  url: dartedBestServer['server'] as String?,
                )
              ];

              ServerSelectionResponse response = ServerSelectionResponse(
                client: _client,
                targets: targets,
              );
              completer.complete(response);
            } else {
              completer.complete(null);
            }
          });
        } else {
          completer.complete(null);
        }
      });
    } else {
      completer.complete(null);
    }

    additionalConfigs?.forEach((key, value) {
      _downloadSpeedTest!.setParameter(key, value);
    });

    return completer.future;
  }

  @override
  Future<bool> cancelTest() async {
    if (_downloadSpeedTest != null) {
      _downloadSpeedTest!.callMethod('abort');
      return true;
    }
    if (_uploadSpeedTest != null) {
      _uploadSpeedTest!.callMethod('abort');
    }
    return true;
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

    // Extract values
    _dlStatus = double.tryParse(result['dlStatus'].toString()) ?? 0.0;
    _ulStatus = double.tryParse(result['ulStatus'].toString()) ?? 0.0;
    _dlProgress = double.tryParse(result['dlProgress'].toString()) ?? 0.0;
    _ulProgress = double.tryParse(result['ulProgress'].toString()) ?? 0.0;
    final _testType = result['testType']?.toString() ?? "";

    // Callbacks
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      switch (_testType) {
        case 'download':
          callbackTuple.item2(_dlProgress * 100, _dlStatus, SpeedUnit.mbps);
          break;
        case 'upload':
          callbackTuple.item2(_ulProgress * 100, _ulStatus, SpeedUnit.mbps);
          break;
        // Handle other test types if needed
      }
    }
  }

  // Handler for onend event
  void _onEndDownload(bool aborted, String testType, String finalSpeed) {
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Test aborted', 'Aborted');
      } else {
        // Assuming that we have the final transfer rates
        // You may need to store the final rates in _onUpdate
        callbackTuple.item3(double.tryParse(finalSpeed) ?? 0.0,
            SpeedUnit.mbps); // Replace 0.0 with actual rate
      }
      //todo: THIS DOESN'T HANDLE THE UPLOAD CASE
      _downloadCompleter.complete();
    }
  }

  void _onEndUpload(bool aborted, String testType, String finalSpeed) {
    var callbackTuple = callbacksById[_currentTestId];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Test aborted', 'Aborted');
      } else {
        // Assuming that we have the final transfer rates
        // You may need to store the final rates in _onUpdate
        callbackTuple.item3(double.tryParse(finalSpeed) ?? 0.0,
            SpeedUnit.mbps); // Replace 0.0 with actual rate
      }
      //todo: THIS DOESN'T HANDLE THE UPLOAD CASE
      _uploadCompleter.complete();
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

  @override
  Future<void> resetTest({bool softReset = false}) async {
    _downloadCompleter = Completer<void>();
    _uploadCompleter = Completer<void>();
    _downloadSpeedTest!.callMethod('reset', [softReset]);
    _uploadSpeedTest!.callMethod('reset', [softReset]);
  }
}
