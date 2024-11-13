import 'dart:convert';
import 'dart:ffi';

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

//TODO: need to implement the start ping testing
/// An implementation of [FlutterInternetSpeedTestPlatform] that uses method channels.
class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.shaz.plugin.fist/method');
  final _logger = Logger();

  Client? _client;

  Future<void> _methodCallHandler(MethodCall call) async {
    if (isLogEnabled) {
      _logger.d('arguments are ${call.arguments}');
//    _logger.d('arguments type is  ${call.arguments['type']}');
      _logger.d('callbacks are $callbacksById');
    }
    switch (call.method) {
      case 'callListener':
        if (call.arguments["id"] as int ==
            CallbacksEnum.startDownLoadTesting.index) {
          if (call.arguments['type'] == ListenerEnum.complete.index) {
            downloadSteps++;
            downloadRate +=
                int.parse((call.arguments['transferRate'] ~/ 1000).toString());
            if (isLogEnabled) {
              _logger.d('download steps is $downloadSteps}');
              _logger.d('download steps is $downloadRate}');
            }
            double average = (downloadRate ~/ downloadSteps).toDouble();
            SpeedUnit unit = SpeedUnit.kbps;
            average /= 1000;
            unit = SpeedUnit.mbps;
            callbacksById[call.arguments["id"].toString()]!
                .item3(average, unit);
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"].toString());
          } else if (call.arguments['type'] == ListenerEnum.error.index) {
            if (isLogEnabled) {
              _logger.d('onError : ${call.arguments["speedTestError"]}');
              _logger.d('onError : ${call.arguments["errorMessage"]}');
            }
            callbacksById[call.arguments["id"].toString()]!.item1(
                call.arguments['errorMessage'],
                call.arguments['speedTestError']);
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"].toString());
          } else if (call.arguments['type'] == ListenerEnum.progress.index) {
            double rate = (call.arguments['transferRate'] ~/ 1000).toDouble();
            if (isLogEnabled) {
              _logger.d('rate is $rate');
            }
            if (rate != 0) downloadSteps++;
            downloadRate += rate.toInt();
            SpeedUnit unit = SpeedUnit.kbps;
            rate /= 1000;
            unit = SpeedUnit.mbps;
            callbacksById[call.arguments["id"].toString()]!
                .item2(call.arguments['percent'].toDouble(), rate, unit);
          } else if (call.arguments['type'] == ListenerEnum.cancel.index) {
            if (isLogEnabled) {
              _logger.d('onCancel : ${call.arguments["id"]}');
            }
            callbacksById[call.arguments["id"].toString()]!.item4();
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"].toString());
          }
        } else if (call.arguments["id"] as int ==
            CallbacksEnum.startUploadTesting.index) {
          if (call.arguments['type'] == ListenerEnum.complete.index) {
            if (isLogEnabled) {
              _logger.d('onComplete : ${call.arguments['transferRate']}');
            }

            uploadSteps++;
            uploadRate +=
                int.parse((call.arguments['transferRate'] ~/ 1000).toString());
            if (isLogEnabled) {
              _logger.d('download steps is $uploadSteps}');
              _logger.d('download steps is $uploadRate}');
            }
            double average = (uploadRate ~/ uploadSteps).toDouble();
            SpeedUnit unit = SpeedUnit.kbps;
            average /= 1000;
            unit = SpeedUnit.mbps;
            callbacksById[call.arguments["id"].toString()]!
                .item3(average, unit);
            uploadSteps = 0;
            uploadRate = 0;
            callbacksById.remove(call.arguments["id"].toString());
          } else if (call.arguments['type'] == ListenerEnum.error.index) {
            if (isLogEnabled) {
              _logger.d('onError : ${call.arguments["speedTestError"]}');
              _logger.d('onError : ${call.arguments["errorMessage"]}');
            }
            callbacksById[call.arguments["id"].toString()]!.item1(
                call.arguments['errorMessage'],
                call.arguments['speedTestError']);
          } else if (call.arguments['type'] == ListenerEnum.progress.index) {
            double rate = (call.arguments['transferRate'] ~/ 1000).toDouble();
            if (isLogEnabled) {
              _logger.d('rate is $rate');
            }
            if (rate != 0) uploadSteps++;
            uploadRate += rate.toInt();
            SpeedUnit unit = SpeedUnit.kbps;
            rate /= 1000.0;
            unit = SpeedUnit.mbps;
            callbacksById[call.arguments["id"].toString()]!
                .item2(call.arguments['percent'].toDouble(), rate, unit);
          } else if (call.arguments['type'] == ListenerEnum.cancel.index) {
            if (isLogEnabled) {
              _logger.d('onCancel : ${call.arguments["id"]}');
            }
            callbacksById[call.arguments["id"].toString()]!.item4();
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"].toString());
          }
        }
//        callbacksById[call.arguments["id"]](call.arguments["args"]);
        break;
      default:
        if (isLogEnabled) {
          _logger.d(
              'TestFairy: Ignoring invoke from native. This normally shouldn\'t happen.');
        }
    }

    methodChannel.invokeMethod("cancelListening", call.arguments["id"]);
  }

  Future<CancelListening> _startListening(
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

  Future<void> _toggleLog(bool value) async {
    await methodChannel.invokeMethod(
      "toggleLog",
      {
        'value': value,
      },
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
    return await _startListening(Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startDownLoadTesting, testServer,
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
    return await _startListening(Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startUploadTesting, testServer,
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
        var serverSelectionResponse =
            ServerSelectionResponse.fromJson(json.decode(serverResponse.body));
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
      result = await methodChannel.invokeMethod("cancelTest", {
        'id1': CallbacksEnum.startDownLoadTesting.index,
        'id2': CallbacksEnum.startUploadTesting.index,
      });
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
