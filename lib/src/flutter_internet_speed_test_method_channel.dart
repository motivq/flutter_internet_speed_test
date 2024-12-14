import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:tuple_dart/tuple.dart';

import 'package:flutter_internet_speed_test/src/models/server_selection_response.dart';
import 'package:flutter_internet_speed_test/src/speed_test_utils.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';

class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.shaz.plugin.fist/method');
  final _logger = Logger();

  Client? _client;
  @override
  bool isLogEnabled = true;

  Future<void> _methodCallHandler(MethodCall call) async {
    if (isLogEnabled) {
      _logger.d('methodCallHandler: method is ${call.method}');
      _logger.d('methodCallHandler: arguments are ${call.arguments}');
      _logger.d(
          'methodCallHandler: callbacks are $callbacksById $latencyCallbacksById');
    }

    if (call.method == 'callListener') {
      final args = call.arguments as Map<dynamic, dynamic>;
      final id = args['id'] as int;
      final type = args['type'] as int;

      if (id == CallbacksEnum.startDownLoadTesting.index) {
        _handleDownloadTesting(type, args);
      } else if (id == CallbacksEnum.startUploadTesting.index) {
        _handleUploadTesting(type, args);
      } else if (id == CallbacksEnum.startLatencyTesting.index) {
        _handleLatencyTesting(type, args);
      }
    } else {
      if (isLogEnabled) {
        _logger.d('Ignoring unknown native call: ${call.method}');
      }
    }
  }

  void _handleLatencyTesting(int type, Map<dynamic, dynamic> args) {
    final idStr = args['id'].toString();
    final callbacks = latencyCallbacksById[idStr];
    if (callbacks == null) {
      if (isLogEnabled) {
        _logger.d('No latency callbacks found for id ${args['id']}');
      }
      return;
    }

    switch (ListenerEnum.values[type]) {
      case ListenerEnum.complete:
        final averageLatency = args['latency'] as double;
        final jitter = args['jitter'] as double;
        if (isLogEnabled) {
          _logger
              .d('LATENCY COMPLETE: latency=$averageLatency, jitter=$jitter');
        }
        callbacks.item3(averageLatency, jitter);
        // For latency, we continue to cancel after done as original.
        methodChannel.invokeMethod("cancelListening", args["id"]);
        latencyCallbacksById.remove(idStr);
        break;
      case ListenerEnum.error:
        final errorMsg = (args['errorMessage'] as String?) ??
            (args['speedTestError'] as String?) ??
            'Unknown error';
        if (isLogEnabled) {
          _logger.d('LATENCY ERROR: $errorMsg');
        }
        callbacks.item1(errorMsg, '');
        methodChannel.invokeMethod("cancelListening", args["id"]);
        latencyCallbacksById.remove(idStr);
        break;
      case ListenerEnum.progress:
        final percent = args['percent'] as double;
        final latency = args['latency'] as double;
        final jitter = args['jitter'] as double;
        if (isLogEnabled) {
          _logger.d(
              'LATENCY PROGRESS: percent=$percent, latency=$latency, jitter=$jitter');
        }
        callbacks.item2(percent, latency, jitter);
        break;
      case ListenerEnum.cancel:
        if (isLogEnabled) {
          _logger.d('LATENCY CANCEL');
        }
        callbacks.item4();
        methodChannel.invokeMethod("cancelListening", args["id"]);
        latencyCallbacksById.remove(idStr);
        break;
    }
  }

  void _handleDownloadTesting(int type, Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('DOWNLOAD EVENT: type=$type args=$args');
    }
    switch (ListenerEnum.values[type]) {
      case ListenerEnum.complete:
        _onDownloadComplete(args);
        break;
      case ListenerEnum.error:
        _onDownloadError(args);
        break;
      case ListenerEnum.progress:
        _onDownloadProgress(args);
        break;
      case ListenerEnum.cancel:
        _onDownloadCancel(args);
        break;
    }
  }

  void _handleUploadTesting(int type, Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('UPLOAD EVENT: type=$type args=$args');
    }
    switch (ListenerEnum.values[type]) {
      case ListenerEnum.complete:
        _onUploadComplete(args);
        break;
      case ListenerEnum.error:
        _onUploadError(args);
        break;
      case ListenerEnum.progress:
        _onUploadProgress(args);
        break;
      case ListenerEnum.cancel:
        _onUploadCancel(args);
        break;
    }
  }

  void _onDownloadComplete(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('DOWNLOAD COMPLETE EVENT RECEIVED');

    downloadSteps++;
    downloadRate += int.parse((args['transferRate'] ~/ 1000).toString());

    double average = (downloadRate ~/ downloadSteps).toDouble();
    average /= 1000;

    // Call the "done" callback
    final cb = callbacksById[args["id"].toString()];
    if (cb == null) {
      if (isLogEnabled) _logger.w('No callback found for download complete!');
    } else {
      if (isLogEnabled)
        _logger.d('Calling download done callback with $average Mbps');
      cb.item3(average, SpeedUnit.mbps);
    }

    // Reset counters
    downloadSteps = 0;
    downloadRate = 0;

    // *** CHANGE START ***
    // Do NOT call cancelListening here. Just log that we are done.
    // Do NOT remove callback now. Let the UI handle that.
    if (isLogEnabled)
      _logger.d('Download test done. Not removing callbacks yet.');
    // *** CHANGE END ***
  }

  void _onDownloadError(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('DOWNLOAD ERROR EVENT RECEIVED');
    final errorMsg = (args['errorMessage'] as String?) ??
        (args['speedTestError'] as String?) ??
        'Unknown error';

    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item1(errorMsg, '');
    }
    downloadSteps = 0;
    downloadRate = 0;

    // For error, we still cancel
    if (isLogEnabled) _logger.d('Download error. Calling cancelListening.');
    methodChannel.invokeMethod("cancelListening", args["id"]);
    callbacksById.remove(args["id"].toString());
  }

  void _onDownloadProgress(Map<dynamic, dynamic> args) {
    double rate = ((args['transferRate'] as double) ~/ 1000).toDouble();
    if (isLogEnabled) _logger.d('DOWNLOAD PROGRESS: rate=$rate');
    if (rate != 0) downloadSteps++;
    downloadRate += rate.toInt();
    rate /= 1000;

    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item2(args['percent'] as double, rate, SpeedUnit.mbps);
    } else {
      if (isLogEnabled) _logger.w('No callback found for download progress!');
    }
  }

  void _onDownloadCancel(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('DOWNLOAD CANCEL EVENT RECEIVED');
    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item4();
    }
    downloadSteps = 0;
    downloadRate = 0;
    methodChannel.invokeMethod("cancelListening", args["id"]);
    callbacksById.remove(args["id"].toString());
  }

  void _onUploadComplete(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('UPLOAD COMPLETE EVENT RECEIVED');

    uploadSteps++;
    uploadRate += int.parse((args['transferRate'] ~/ 1000).toString());

    double average = (uploadRate ~/ uploadSteps).toDouble();
    average /= 1000;

    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      if (isLogEnabled)
        _logger.d('Calling upload done callback with $average Mbps');
      cb.item3(average, SpeedUnit.mbps);
    } else {
      if (isLogEnabled) _logger.w('No callback found for upload complete!');
    }

    uploadSteps = 0;
    uploadRate = 0;

    // *** CHANGE START ***
    // Do NOT call cancelListening here or remove callback immediately.
    if (isLogEnabled)
      _logger.d('Upload test done. Not removing callbacks yet.');
    // *** CHANGE END ***
  }

  void _onUploadError(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('UPLOAD ERROR EVENT RECEIVED');
    final errorMsg = (args['errorMessage'] as String?) ??
        (args['speedTestError'] as String?) ??
        'Unknown error';

    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item1(errorMsg, '');
    }

    methodChannel.invokeMethod("cancelListening", args["id"]);
    callbacksById.remove(args["id"].toString());
  }

  void _onUploadProgress(Map<dynamic, dynamic> args) {
    double rate = ((args['transferRate'] as double) ~/ 1000).toDouble();
    if (isLogEnabled) _logger.d('UPLOAD PROGRESS: rate=$rate');
    if (rate != 0) uploadSteps++;
    uploadRate += rate.toInt();
    rate /= 1000.0;
    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item2(args['percent'] as double, rate, SpeedUnit.mbps);
    } else {
      if (isLogEnabled) _logger.w('No callback found for upload progress!');
    }
  }

  void _onUploadCancel(Map<dynamic, dynamic> args) {
    if (isLogEnabled) _logger.d('UPLOAD CANCEL EVENT RECEIVED');
    final cb = callbacksById[args["id"].toString()];
    if (cb != null) {
      cb.item4();
    }
    downloadSteps = 0;
    downloadRate = 0;
    methodChannel.invokeMethod("cancelListening", args["id"]);
    callbacksById.remove(args["id"].toString());
  }

  Future<CancelListening> _startDownloadOrUploadListening(
      Tuple4<ErrorCallback, ProgressCallback, DoneCallback, CancelCallback>
          callback,
      CallbacksEnum callbacksEnum,
      String testServer,
      {Map<String, dynamic>? args,
      int fileSize = 10000000}) async {
    methodChannel.setMethodCallHandler(_methodCallHandler);
    int currentListenerId = callbacksEnum.index;

    if (isLogEnabled) {
      _logger.d('startDownloadOrUploadListening: test $currentListenerId');
    }
    callbacksById[currentListenerId.toString()] = callback;
    await methodChannel.invokeMethod("startListening", {
      'id': currentListenerId,
      'args': args,
      'testServer': testServer,
      'fileSize': fileSize,
    });
    return () {
      if (isLogEnabled) _logger.d('Manually canceling test $currentListenerId');
      methodChannel.invokeMethod("cancelListening", currentListenerId);
      callbacksById.remove(currentListenerId.toString());
    };
  }

  Future<CancelListening> _startLatencyListening(
      Tuple4<ErrorCallback, LatencyProgressCallback, LatencyDoneCallback,
              CancelCallback>
          callback,
      CallbacksEnum callbacksEnum,
      String testServer) async {
    methodChannel.setMethodCallHandler(_methodCallHandler);
    int currentListenerId = callbacksEnum.index;

    if (isLogEnabled) {
      _logger.d('startLatencyListening: test $currentListenerId');
    }
    latencyCallbacksById[currentListenerId.toString()] = callback;
    await methodChannel.invokeMethod("startListening", {
      'id': currentListenerId,
      'testServer': testServer,
    });
    return () {
      if (isLogEnabled)
        _logger.d('Manually canceling latency test $currentListenerId');
      methodChannel.invokeMethod("cancelListening", currentListenerId);
      latencyCallbacksById.remove(currentListenerId.toString());
    };
  }

  Future<void> _toggleLog(bool value) async {
    await methodChannel.invokeMethod("toggleLog", {
      'value': value,
    });
  }

  @override
  Future<CancelListening> startLatencyTesting({
    required LatencyDoneCallback onDone,
    required LatencyProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required String testServer,
  }) async {
    return await _startLatencyListening(
      Tuple4(onError, onProgress, onDone, onCancel),
      CallbacksEnum.startLatencyTesting,
      testServer,
    );
  }

  @override
  Future<CancelListening> startDownloadTesting({
    required DoneCallback onDone,
    required ProgressCallback onProgress,
    required ErrorCallback onError,
    required CancelCallback onCancel,
    required fileSize,
    required String testServer,
  }) async {
    return await _startDownloadOrUploadListening(
      Tuple4(onError, onProgress, onDone, onCancel),
      CallbacksEnum.startDownLoadTesting,
      testServer,
      fileSize: fileSize,
    );
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
    return await _startDownloadOrUploadListening(
      Tuple4(onError, onProgress, onDone, onCancel),
      CallbacksEnum.startUploadTesting,
      testServer,
      fileSize: fileSize,
    );
  }

  @override
  Future<void> toggleLog({required bool value}) async {
    logEnabled = value;
    await _toggleLog(logEnabled);
  }

  Future<ServerSelectionResponse?> _fetchServerSelectionResponse({
    String? serverListUrl,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    try {
      if (await isInternetAvailable()) {
        Uri serverUrl;
        if (serverListUrl == null) {
          const tag = 'token:"';
          var tokenUrl = Uri.parse('https://fast.com/app-a32983.js');
          var tokenResponse = await http.get(tokenUrl);
          if (tokenResponse.body.contains(tag)) {
            int start = tokenResponse.body.lastIndexOf(tag) + tag.length;
            String token = tokenResponse.body.substring(start, start + 32);
            serverUrl = Uri.parse(
                'https://api.fast.com/netflix/speedtest/v2?https=true&token=$token&urlCount=5');
          } else {
            return null; // Return null if token is not found
          }
        } else {
          serverUrl = Uri.parse(serverListUrl);
        }

        var serverResponse = await http.get(serverUrl);
        var serverSelectionResponse = ServerSelectionResponse.fromJson(
            json.decode(serverResponse.body) as Map<String, dynamic>);
        _client = serverSelectionResponse.client;
        if (additionalConfigs != null && isLogEnabled) {
          additionalConfigs.forEach((key, value) {
            _logger.d('Config $key: $value');
          });
        }

        if (serverSelectionResponse.targets?.isNotEmpty == true) {
          return serverSelectionResponse;
        }
      }
    } catch (e) {
      if (logEnabled) {
        _logger.d(e);
      }
    }
    return null;
  }

  @override
  Future<ServerSelectionResponse?> getDefaultServer({
    String? serverListUrl,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    return await _fetchServerSelectionResponse(
      serverListUrl: serverListUrl,
      additionalConfigs: additionalConfigs,
    );
  }

  @override
  Future<Client?> getClientInformation() async {
    if (_client == null) {
      await _fetchServerSelectionResponse();
    }
    return _client;
  }

  @override
  Future<bool> cancelTest() async {
    if (isLogEnabled) _logger.d('cancelTest called from Dart side.');
    var result = false;
    try {
      result = await methodChannel.invokeMethod("cancelTest", [
        CallbacksEnum.startDownLoadTesting.index,
        CallbacksEnum.startUploadTesting.index,
        CallbacksEnum.startLatencyTesting.index,
      ]) as bool;
      if (isLogEnabled) _logger.d('cancelTest result: $result');
    } on PlatformException {
      result = false;
    }
    return result;
  }

  @override
  Future<String?> getPlatformVersion() async {
    if (isLogEnabled) _logger.d('getPlatformVersion called.');
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> resetTest({bool softReset = false}) async {
    if (isLogEnabled) _logger.d('resetTest called, softReset=$softReset');
    _client = null;
    callbacksById.clear();
    latencyCallbacksById.clear();
    downloadSteps = 0;
    downloadRate = 0;
    uploadSteps = 0;
    uploadRate = 0;

    if (!softReset) {
      logEnabled = false;
    }
  }
}
