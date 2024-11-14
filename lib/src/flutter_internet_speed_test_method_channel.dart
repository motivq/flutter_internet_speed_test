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

/// An implementation of [FlutterInternetSpeedTestPlatform] that uses method channels.
class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.shaz.plugin.fist/method');
  final _logger = Logger();

  Client? _client;
  @override
  bool isLogEnabled = false;

  Future<void> _methodCallHandler(MethodCall call) async {
    if (isLogEnabled) {
      _logger.d('call method is ${call.method}');
      _logger.d('arguments are ${call.arguments}');
      _logger.d('callbacks are $callbacksById');
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
        _logger.d(
            'TestFairy: Ignoring invoke from native. This normally shouldn\'t happen.');
      }
    }

    await methodChannel.invokeMethod("cancelListening", call.arguments["id"]);
  }

  void _handleLatencyTesting(int type, Map<dynamic, dynamic> args) {
    final idStr = args['id'].toString();
    final callbacks = latencyCallbacksById[idStr];
    if (callbacks == null) {
      if (isLogEnabled) {
        _logger.d('No callbacks found for id ${args['id']}');
      }
      return;
    }

    switch (ListenerEnum.values[type]) {
      case ListenerEnum.complete:
        final averageLatency = args['latency'] as double;
        final jitter = args['jitter'] as double;
        if (isLogEnabled) {
          _logger
              .d('onLatencyComplete: latency=$averageLatency, jitter=$jitter');
        }
        callbacks.item3(averageLatency, jitter);
        latencyCallbacksById.remove(idStr);
        break;
      case ListenerEnum.error:
        final errorMessage = args['errorMessage'] as String;
        if (isLogEnabled) {
          _logger.d('onLatencyError: $errorMessage');
        }
        callbacks.item1(errorMessage, '');
        latencyCallbacksById.remove(idStr);
        break;
      case ListenerEnum.progress:
        final latency = args['latency'] as double;
        if (isLogEnabled) {
          _logger.d('onLatencyProgress: latency=$latency');
        }
        callbacks.item2(
            args['percent'] as double, latency, args['jitter'] as double);
        break;
      case ListenerEnum.cancel:
        if (isLogEnabled) {
          _logger.d('onLatencyCancel');
        }
        callbacks.item4();
        latencyCallbacksById.remove(idStr);
        break;
    }
  }

  void _handleDownloadTesting(int type, Map<dynamic, dynamic> args) {
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
    downloadSteps++;
    downloadRate += int.parse((args['transferRate'] ~/ 1000).toString());
    if (isLogEnabled) {
      _logger.d('download steps is $downloadSteps}');
      _logger.d('download rate is $downloadRate}');
    }
    double average = (downloadRate ~/ downloadSteps).toDouble();
    average /= 1000;
    callbacksById[args["id"].toString()]!.item3(average, SpeedUnit.mbps);
    downloadSteps = 0;
    downloadRate = 0;
    callbacksById.remove(args["id"].toString());
  }

  void _onDownloadError(Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('onError : ${args["speedTestError"]}');
      _logger.d('onError : ${args["errorMessage"]}');
    }
    callbacksById[args["id"].toString()]!.item1(
        args['errorMessage'] as String, args['speedTestError'] as String);
    downloadSteps = 0;
    downloadRate = 0;
    callbacksById.remove(args["id"].toString());
  }

  void _onDownloadProgress(Map<dynamic, dynamic> args) {
    double rate = ((args['transferRate'] as double) ~/ 1000).toDouble();
    if (isLogEnabled) {
      _logger.d('rate is $rate');
      _logger.d('latency is ${args['latency']}');
      _logger.d('jitter is ${args['jitter']}');
    }
    if (rate != 0) downloadSteps++;
    downloadRate += rate.toInt();
    rate /= 1000;
    callbacksById[args["id"].toString()]!
        .item2(args['percent'] as double, rate, SpeedUnit.mbps);
  }

  void _onDownloadCancel(Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('onCancel : ${args["id"]}');
    }
    callbacksById[args["id"].toString()]!.item4();
    downloadSteps = 0;
    downloadRate = 0;
    callbacksById.remove(args["id"].toString());
  }

  void _onUploadComplete(Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('onComplete : ${args['transferRate']}');
    }
    uploadSteps++;
    uploadRate += int.parse((args['transferRate'] ~/ 1000).toString());
    if (isLogEnabled) {
      _logger.d('upload steps is $uploadSteps}');
      _logger.d('upload rate is $uploadRate}');
    }
    double average = (uploadRate ~/ uploadSteps).toDouble();
    average /= 1000;
    callbacksById[args["id"].toString()]!.item3(average, SpeedUnit.mbps);
    uploadSteps = 0;
    uploadRate = 0;
    callbacksById.remove(args["id"].toString());
  }

  void _onUploadError(Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('onError : ${args["speedTestError"]}');
      _logger.d('onError : ${args["errorMessage"]}');
    }
    callbacksById[args["id"].toString()]!.item1(
        args['errorMessage'] as String, args['speedTestError'] as String);
  }

  void _onUploadProgress(Map<dynamic, dynamic> args) {
    double rate = ((args['transferRate'] as double) ~/ 1000).toDouble();
    if (isLogEnabled) {
      _logger.d('rate is $rate');
    }
    if (rate != 0) uploadSteps++;
    uploadRate += rate.toInt();
    rate /= 1000.0;
    callbacksById[args["id"].toString()]!
        .item2(args['percent'] as double, rate, SpeedUnit.mbps);
  }

  void _onUploadCancel(Map<dynamic, dynamic> args) {
    if (isLogEnabled) {
      _logger.d('onCancel : ${args["id"]}');
    }
    callbacksById[args["id"].toString()]!.item4();
    downloadSteps = 0;
    downloadRate = 0;
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
      _logger.d('test $currentListenerId');
    }
    callbacksById[currentListenerId.toString()] = callback;
    await methodChannel.invokeMethod(
      "startListening",
      {
        'id': currentListenerId,
        'args': args,
        'testServer': testServer,
        'fileSize': fileSize,
      },
    );
    return () {
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
      _logger.d('test $currentListenerId');
    }
    latencyCallbacksById[currentListenerId.toString()] = callback;
    await methodChannel.invokeMethod(
      "startListening",
      {
        'id': currentListenerId,
        'testServer': testServer,
      },
    );
    return () {
      methodChannel.invokeMethod("cancelListening", currentListenerId);
      latencyCallbacksById.remove(currentListenerId.toString());
    };
  }

  Future<void> _toggleLog(bool value) async {
    await methodChannel.invokeMethod(
      "toggleLog",
      {
        'value': value,
      },
    );
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
  Future<CancelListening> startDownloadTesting(
      {required DoneCallback onDone,
      required ProgressCallback onProgress,
      required ErrorCallback onError,
      required CancelCallback onCancel,
      required fileSize,
      required String testServer}) async {
    return await _startDownloadOrUploadListening(
        Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startDownLoadTesting,
        testServer,
        fileSize: fileSize);
  }

  @override
  Future<CancelListening> startUploadTesting(
      {required DoneCallback onDone,
      required ProgressCallback onProgress,
      required ErrorCallback onError,
      required CancelCallback onCancel,
      required int fileSize,
      required String testServer}) async {
    return await _startDownloadOrUploadListening(
        Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startUploadTesting,
        testServer,
        fileSize: fileSize);
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
        // Apply additional configurations if provided
        if (additionalConfigs != null) {
          additionalConfigs.forEach((key, value) {
            _logger.d('Config $key: $value');
            // Doesn't apply to this implementation
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
    var result = false;
    try {
      result = await methodChannel.invokeMethod("cancelTest", [
        CallbacksEnum.startDownLoadTesting.index,
        CallbacksEnum.startUploadTesting.index,
        CallbacksEnum.startLatencyTesting.index,
      ]) as bool;
    } on PlatformException {
      result = false;
    }
    return result;
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> resetTest({bool softReset = false}) async {
    // Reset client information
    _client = null;

    // Clear callbacks
    callbacksById.clear();

    // Reset download/upload state
    downloadSteps = 0;
    downloadRate = 0;
    uploadSteps = 0;
    uploadRate = 0;

    // Optionally reset logging state
    if (!softReset) {
      logEnabled = false;
    }
  }
}
