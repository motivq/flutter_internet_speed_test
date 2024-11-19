// Import necessary libraries
import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:logger/logger.dart';
import 'package:tuple_dart/tuple.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';
import 'models/server_selection_response.dart';
import 'speed_test.dart';

typedef CancelListening = void Function();
typedef DoneCallback = void Function(double transferRate, SpeedUnit unit,
    {double? jitter, double? ping});
typedef ProgressCallback = void Function(
    double percent, double transferRate, SpeedUnit unit,
    {double? jitter, double? ping});
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

abstract class ServerSelector {
  Future<void> ensureServerIsSelected(String testServer);
}

class DownloadServerSelector implements ServerSelector {
  final SpeedTestConfig _speedTestConfig;
  final Function(SpeedTestConfig) _initSpeedtest;
  final Future<void> Function(String, Function(List<dynamic>?)) _loadServerList;
  final void Function(Function(dynamic)) _selectServer;
  final void Function(dynamic) _setSelectedServer;

  DownloadServerSelector(
    this._speedTestConfig,
    this._initSpeedtest,
    this._loadServerList,
    this._selectServer,
    this._setSelectedServer,
  );

  @override
  Future<void> ensureServerIsSelected(String testServer) async {
    if (_speedTestConfig.baseUrl != testServer) {
      await _initSpeedtest(SpeedTestConfig(baseUrl: testServer));
      await _selectAndSetServer();
    }
  }

  Future<void> _selectAndSetServer() async {
    Completer<void> serverSelectionCompleter = Completer();

    await _loadServerList(_speedTestConfig.serverListUrl, (servers) {
      if (servers != null) {
        _selectServer((bestServer) {
          if (bestServer != null) {
            _setSelectedServer(bestServer);
            serverSelectionCompleter.complete();
          } else {
            serverSelectionCompleter.completeError('No server selected');
          }
        });
      } else {
        serverSelectionCompleter.completeError('No servers found');
      }
    });

    await serverSelectionCompleter.future;
  }
}

class LatencyServerSelector extends DownloadServerSelector {
  LatencyServerSelector({
    required SpeedTestConfig speedTestConfig,
    required Function(SpeedTestConfig) initSpeedtest,
    required Future<void> Function(String, Function(List<dynamic>?))
        loadServerList,
    required void Function(Function(dynamic)) selectServer,
    required void Function(dynamic) setSelectedServer,
  }) : super(
          speedTestConfig,
          initSpeedtest,
          loadServerList,
          selectServer,
          setSelectedServer,
        );
}

class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  final Logger _logger;

  MethodChannelFlutterInternetSpeedTest({
    ISpeedtest? downloadSpeedTest,
    ISpeedtest? uploadSpeedTest,
    ISpeedtest? latencySpeedTest,
  }) : _logger = Logger() {
    _loadJavascriptFiles().then((_) {
      _downloadSpeedTest =
          downloadSpeedTest ?? _initializeJsSpeedtest('download');
      _uploadSpeedTest = uploadSpeedTest ?? _initializeJsSpeedtest('upload');
      _latencySpeedTest = latencySpeedTest ?? _initializeJsSpeedtest('ping');
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
    final jsObject = context['Speedtest'] as JsFunction?;
    if (jsObject == null) {
      throw Exception('Speedtest JavaScript object is not available.');
    }
    return JsSpeedtest(JsObject(jsObject, [
      'packages/flutter_internet_speed_test/assets/speedtest_worker.js',
      type,
      true
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

  // client object
  Client? _client;

  SpeedTestConfig? _speedTestConfig;

  Future<void> _initSpeedtest({required SpeedTestConfig config}) async {
    bool configChanged =
        _speedTestConfig == null || _speedTestConfig!.baseUrl != config.baseUrl;

    _speedTestConfig = config;

    if (configChanged) {
      _downloadSpeedTest ??= _initializeJsSpeedtest('download');
      if (_downloadSpeedTest != null) {
        _initializeSpeedTestInstance(_downloadSpeedTest!);
      }

      _uploadSpeedTest ??= _initializeJsSpeedtest('upload');
      if (_uploadSpeedTest != null) {
        _initializeSpeedTestInstance(_uploadSpeedTest!);
      }

      _latencySpeedTest ??= _initializeJsSpeedtest('ping');
      if (_latencySpeedTest != null) {
        _initializeSpeedTestInstance(_latencySpeedTest!);
      }

      //await ensureDownloadServerIsSelected(config.baseUrl);
      //await ensureUploadServerIsSelected(config.baseUrl);
      //await ensureLatencyServerIsSelected(config.baseUrl);
    } else {
      await _copyTheTestPointsIfPossible();
    }
  }

  Future<void> _copyTheTestPointsIfPossible() async {
    Completer<void> completer = Completer();
    //TODO: copy from download or upload to latency
    if ((_downloadSpeedTest!.getState() as int) >= 2 &&
        (_uploadSpeedTest!.getState() as int) < 2) {
      final testPoints = _downloadSpeedTest!.getTestPoints();
      //List.from(_downloadSpeedTest!.getTestPoints() as Iterable<dynamic>);
      final selectedServer =
          _downloadSpeedTest!.getSelectedServer(); //Map.from(
      //jsToNative(_downloadSpeedTest!.getSelectedServer() as JsObject)
      //  as Map<dynamic, dynamic>);

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
  var _clientCompleter = Completer<Client>();

  Future<Client> _fetchClientFromIp(ISpeedtest speedTest) async {
    speedTest.getIp((JSString ispInfo) {
      final decodedIspInfo = json.decode(ispInfo.toDart);
      if (decodedIspInfo is Map<String, dynamic>) {
        final client = Client.fromNewModel(decodedIspInfo);
        _clientCompleter.complete(client);
      } else {
        _clientCompleter.completeError(Exception(
            'Invalid ispInfo type. likely the server url for getIP is wrong${_speedTestConfig?.getIpUrl ?? ""}'));
      }
    });

    return _clientCompleter.future;
  }

  Future<void> _getIpAndStartDownloadTest() async {
    try {
      await _copyTheTestPointsIfPossible();
      _client ??= await _fetchClientFromIp(_downloadSpeedTest!);
      _downloadSpeedTest!.startDownloadTest();
      return _downloadCompleter.future;
    } catch (e) {
      _downloadCompleter.completeError(e);
    }
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
              'Invalid ispInfo type. likely the server url for getIP is wrong${_speedTestConfig?.getIpUrl ?? ""}');
        }

        _uploadSpeedTest!.startUploadTest();
      });
    } else {
      _uploadSpeedTest!.startUploadTest();
    }

    return _uploadCompleter.future;
  }

  Future<void> ensureDownloadServerIsSelected(String testServer) async {
    if (_downloadSpeedTest == null ||
        _speedTestConfig == null ||
        _speedTestConfig!.baseUrl != testServer) {
      await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));
    }
    await _selectAndSetServer(_downloadSpeedTest!);
  }

  Future<void> ensureUploadServerIsSelected(String testServer) async {
    if (_uploadSpeedTest == null ||
        _speedTestConfig == null ||
        _speedTestConfig!.baseUrl != testServer) {
      await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));
    }
    await _selectAndSetServer(_uploadSpeedTest!);
  }

  Future<void> ensureLatencyServerIsSelected(String testServer) async {
    if (_latencySpeedTest == null ||
        _speedTestConfig == null ||
        _speedTestConfig!.baseUrl != testServer) {
      await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));
    }
    await _selectAndSetServer(_latencySpeedTest!);
  }

  Future<void> _selectAndSetServer(ISpeedtest targetTest) async {
    Completer<void> serverSelectionCompleter = Completer();

    // Helper function to copy test points and selected server
    void copyTestPointsAndServer(ISpeedtest from, ISpeedtest to) {
      final testPoints = from.getTestPoints();
      final selectedServer = from.getSelectedServer();
      to.addTestPoints(testPoints);
      to.setSelectedServer(selectedServer);
    }

    // Check and copy test points and selected server
    if ((targetTest.getState() as int) < 2) {
      if ((_downloadSpeedTest!.getState() as int) >= 2) {
        copyTestPointsAndServer(_downloadSpeedTest!, targetTest);
        serverSelectionCompleter.complete();
      } else if ((_uploadSpeedTest!.getState() as int) >= 2) {
        copyTestPointsAndServer(_uploadSpeedTest!, targetTest);
        serverSelectionCompleter.complete();
      } else if ((_latencySpeedTest!.getState() as int) >= 2) {
        copyTestPointsAndServer(_latencySpeedTest!, targetTest);
        serverSelectionCompleter.complete();
      } else {
        // If none have the test points, proceed with server selection for the target test
        await loadServerListForTest(targetTest, _speedTestConfig!.serverListUrl,
            (servers) {
          if (servers != null) {
            selectServerForTest(targetTest, (bestServer) {
              if (bestServer != null) {
                setSelectedServerForTest(targetTest, bestServer);
                serverSelectionCompleter.complete();
              } else {
                serverSelectionCompleter.completeError('No server selected');
              }
            });
          } else {
            serverSelectionCompleter.completeError('No servers found');
          }
        });
      }
    } else {
      serverSelectionCompleter.complete();
    }

    await serverSelectionCompleter.future;
  }

  Future<void> loadServerListForTest(
      ISpeedtest test, String serverListUrl, Function callback) async {
    test.callMethod('loadServerList', [
      serverListUrl,
      allowInterop(callback),
    ]);
  }

  Future<void> selectServerForTest(ISpeedtest test, Function callback) async {
    test.callMethod('selectServer', [
      allowInterop(callback),
    ]);
  }

  void setSelectedServerForTest(ISpeedtest test, dynamic server) {
    test.callMethod('setSelectedServer', [server]);
  }

  @override
  Future<CancelListening> startDownloadTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required int fileSize,
    required String testServer,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    await ensureDownloadServerIsSelected(testServer);

    callbacksById[TestType.download.toString()] =
        Tuple4(onError, onProgress, onDone, onCancel);

    if (_downloadSpeedTest != null) {
      additionalConfigs?.forEach((key, value) {
        _downloadSpeedTest!.setParameter(key, value);
      });
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

    callbacksById[TestType.upload.toString()] =
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
  Future<CancelListening> startLatencyTesting({
    required LatencyDoneCallback onDone,
    required LatencyProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required String testServer,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    await ensureLatencyServerIsSelected(testServer);

    latencyCallbacksById[CallbacksEnum.startLatencyTesting.index.toString()] =
        Tuple4(onError, onProgress, onDone, onCancel);

    if (_latencySpeedTest != null) {
      _latencySpeedTest!.setParameter('count_ping', 100);
      additionalConfigs?.forEach((key, value) {
        _latencySpeedTest!.setParameter(key, value);
      });
      _latencySpeedTest!.onUpdate(_onLatencyUpdate);
      _latencySpeedTest!.onEnd(_onEndLatency);
    }

    await _getIpAndStartLatencyTest();

    return () {
      cancelTest();
    };
  }

  ISpeedtest? _latencySpeedTest;

  Future<void> _getIpAndStartLatencyTest() async {
    if (_latencySpeedTest == null) {
      throw Exception('Latency SpeedTest instance is not initialized.');
    }
    _client ??= await _fetchClientFromIp(_latencySpeedTest!);
    _latencySpeedTest!.startContinuousPingTest();
    // You might need to create a new Completer for latency if required
    //return _latencyCompleter.future;
  }

//TODO: need to implement the start ping testing
// have
  @override
  Future<CancelListening> startPingTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required String testServer,
  }) async {
    await _initSpeedtest(config: SpeedTestConfig(baseUrl: testServer));
    await ensureLatencyServerIsSelected(testServer);

    // Store callbacks
    callbacksById[TestType.ping.toString()] =
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
    await _getIpAndStartLatencyTest();

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
    var keys = context['Object'].callMethod('keys', [object]) as List;
    for (var key in keys) {
      result[key] = jsToNative(object[key as Object]);
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
          //var mappedServers = jsObjectToMap(servers as JsObject);
          //print(mappedServers);

          selectDownloadServer((bestServer) {
            if (bestServer != null) {
              var dartedBestServer = jsObjectToMap(bestServer as JsObject);
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
    }
    if (_uploadSpeedTest != null) {
      _uploadSpeedTest!.callMethod('abort');
    }
    if (_latencySpeedTest != null) {
      _latencySpeedTest!.callMethod('abort');
    }
    return true;
  }

  @override
  Future<String?> getPlatformVersion() async {
    // Return the platform version if needed
    return null;
  }

  // Handler for download update event
  void _onDownloadUpdate(Map<String, dynamic> result) {
    _dlStatus = double.tryParse(result['dlStatus'].toString()) ?? 0.0;
    _dlProgress = double.tryParse(result['dlProgress'].toString()) ?? 0.0;

    var callbackTuple = callbacksById[TestType.download.toString()];
    if (callbackTuple != null) {
      print("Download and dlProgress: " +
          _dlProgress.toString() +
          " and the testid: " +
          TestType.download.toString());
      callbackTuple.item2(_dlProgress * 100, _dlStatus, SpeedUnit.mbps,
          jitter: _jitterStatus, ping: _pingStatus);
    }
  }

  // Handler for upload update event
  void _onUploadUpdate(Map<String, dynamic> result) {
    _ulStatus = double.tryParse(result['ulStatus'].toString()) ?? 0.0;
    _ulProgress = double.tryParse(result['ulProgress'].toString()) ?? 0.0;

    var callbackTuple = callbacksById[TestType.upload.toString()];
    if (callbackTuple != null) {
      print("Upload and ulProgress: " +
          _ulProgress.toString() +
          " and the testid: " +
          TestType.upload.toString());
      callbackTuple.item2(_ulProgress * 100, _ulStatus, SpeedUnit.mbps,
          jitter: _jitterStatus, ping: _pingStatus);
    }
  }

  // Original onUpdate method refactored to use the new methods
  void _onUpdate(dynamic data) {
    Map<String, dynamic> result =
        Map<String, dynamic>.from(jsToNative(data) as Map<dynamic, dynamic>);
    _pingStatus = double.tryParse(result['pingStatus'].toString()) ?? 0.0;
    _pingProgress = double.tryParse(result['pingProgress'].toString()) ?? 0.0;
    _jitterStatus = double.tryParse(result['jitterStatus'].toString()) ?? 0.0;

    final String testType = result['testType']?.toString() ?? "";

    switch (testType) {
      case 'download':
        _onDownloadUpdate(result);
        break;
      case 'upload':
        _onUploadUpdate(result);
        break;
      case 'ping':
        print("Ping progress: " + _pingProgress.toString());
        var callbackTuple = callbacksById[TestType.ping.toString()];
        if (callbackTuple != null) {
          callbackTuple.item2(_pingProgress * 100, _pingStatus, SpeedUnit.ms,
              jitter: _jitterStatus, ping: _pingStatus);
        }
        break;
    }
  }

  // Handler for onend event
  void _onEndDownload(bool aborted, String testType, String finalSpeed) {
    var callbackTuple = callbacksById[TestType.download.toString()];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Test aborted', 'Aborted');
      } else {
        // Assuming that we have the final transfer rates
        // You may need to store the final rates in _onUpdate
        callbackTuple.item3(double.tryParse(finalSpeed) ?? 0.0,
            SpeedUnit.mbps); // Replace 0.0 with actual rate
      }

      _downloadCompleter.complete();
      callbacksById.remove(TestType.download.toString());
    }
  }

  void _onEndUpload(bool aborted, String testType, String finalSpeed) {
    var callbackTuple = callbacksById[TestType.upload.toString()];
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
      callbacksById.remove(TestType.upload.toString());
    }
  }

  void _onEndPing(
      bool aborted, String testType, double finalPing, double finalJitter) {
    var callbackTuple = callbacksById[TestType.ping.toString()];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Test aborted', 'Aborted');
      } else {
        double averageLatency = double.tryParse(finalPing.toString()) ?? 0.0;
        double jitter = finalJitter;
        callbackTuple.item3(averageLatency, SpeedUnit.ms,
            jitter: jitter, ping: averageLatency);
      }
      callbacksById.remove(TestType.ping.toString());
    }
  }

  void _onEndAllTests(bool aborted, String testType, double dlStatus,
      double ulStatus, double pingStatus, double jitterStatus) {
    var callbackTuple = callbacksById[testType];
    if (callbackTuple != null) {
      callbackTuple.item3(dlStatus, SpeedUnit.mbps);
    }
  }

  void _onLatencyUpdate(dynamic data) {
    Map<String, dynamic> result =
        Map<String, dynamic>.from(jsToNative(data) as Map<dynamic, dynamic>);
    _pingStatus = double.tryParse(result['pingStatus'].toString()) ?? 0.0;
    _jitterStatus = double.tryParse(result['jitterStatus'].toString()) ?? 0.0;

    var callbackTuple = latencyCallbacksById[
        CallbacksEnum.startLatencyTesting.index.toString()];
    if (callbackTuple != null) {
      if (isLogEnabled) {
        _logger.d('onLatencyProgress: latency=$_pingStatus');
      }
      callbackTuple.item2(_pingProgress * 100, _pingStatus, _jitterStatus);
    }
  }

  void _onEndLatency(
      bool aborted, String testType, String finalPing, String finalJitter) {
    var callbackTuple = latencyCallbacksById[
        CallbacksEnum.startLatencyTesting.index.toString()];
    if (callbackTuple != null) {
      if (aborted) {
        callbackTuple.item1('Latency test aborted', 'Aborted');
      } else {
        double averageLatency = double.tryParse(finalPing) ?? 0.0;
        double jitter = double.tryParse(finalJitter) ?? 0.0;
        if (isLogEnabled) {
          _logger
              .d('onLatencyComplete: latency=$averageLatency, jitter=$jitter');
        }
        callbackTuple.item3(averageLatency, jitter);
      }
      latencyCallbacksById
          .remove(CallbacksEnum.startLatencyTesting.index.toString());
    }
  }

  @override
  Future<void> resetTest({bool softReset = false}) async {
    _downloadCompleter = Completer<void>();
    _uploadCompleter = Completer<void>();
    _clientCompleter = Completer<Client>();
    _dlStatus = 0.0;
    _ulStatus = 0.0;
    _dlProgress = 0.0;
    _ulProgress = 0.0;
    _pingStatus = 0.0;
    _pingProgress = 0.0;
    _jitterStatus = 0.0;
    if (!softReset) {
      _speedTestConfig = null;
    }
    _downloadSpeedTest!.callMethod('reset', [softReset]);
    _uploadSpeedTest!.callMethod('reset', [softReset]);
  }

  @override
  Future<Client> getClientInformation() async {
    try {
      _client ??= await _fetchClientFromIp(_downloadSpeedTest!);
    } catch (e) {
      // Handle the error appropriately, e.g., log it or rethrow
      throw Exception('Failed to fetch client information: $e');
    }

    if (_client == null) {
      throw Exception('Client information could not be retrieved.');
    }

    return _client!;
  }
}
