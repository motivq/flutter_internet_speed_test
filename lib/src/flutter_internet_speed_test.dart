import 'package:flutter_internet_speed_test/src/speed_test_utils.dart';
import 'package:flutter_internet_speed_test/src/test_result.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';
import 'models/server_selection_response.dart';

typedef DefaultCallback = void Function();
typedef ResultCallback = void Function(TestResult download, TestResult upload);
typedef TestProgressCallback = void Function(double percent, TestResult data);
typedef ResultCompletionCallback = void Function(TestResult data);
typedef DefaultServerSelectionCallback = void Function(Client? client);
typedef DefaultPingTestCallback = void Function(TestResult data);

class FlutterInternetSpeedTest {
  static const _defaultDownloadTestServer =
      'http://speedtest.ftp.otenet.gr/files/test10Mb.db';
  static const _defaultUploadTestServer = 'http://speedtest.ftp.otenet.gr/';
  static const _defaultFileSize = 10 * 1024 * 1024; //10 MB

  static final FlutterInternetSpeedTest _instance =
      FlutterInternetSpeedTest._private();

  bool _isTestInProgress = false;
  bool _isCancelled = false;

  factory FlutterInternetSpeedTest() => _instance;

  FlutterInternetSpeedTest._private();

  bool isTestInProgress() => _isTestInProgress;

  CancelListening? cancelLatencyTest;

  Future<void> startTesting({
    required ResultCallback onCompleted,
    DefaultCallback? onStarted,
    ResultCompletionCallback? onDownloadComplete,
    ResultCompletionCallback? onUploadComplete,
    TestProgressCallback? onProgress,
    DefaultCallback? onDefaultServerSelectionInProgress,
    DefaultServerSelectionCallback? onDefaultServerSelectionDone,
    TestProgressCallback? onPingTestInProgress,
    DefaultPingTestCallback? onPingTestDone,
    DefaultServerSelectionCallback? onGetIPDone,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? downloadTestServer,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
    bool useFastApi = true,
    String? serverListUrl, // New parameter for server list URL
    Map<String, dynamic>? additionalConfigs,
  }) async {
    if (_isTestInProgress) {
      return;
    }

    _isTestInProgress = true;

    if (onStarted != null) onStarted();

    await FlutterInternetSpeedTestPlatform.instance.resetTest(softReset: true);

    // Reset cancelLatencyTest
    cancelLatencyTest = null;
    if (await isInternetAvailable() == false) {
      if (onError != null) {
        onError('No internet connection', 'No internet connection');
      }
      return;
    }

    if (fileSizeInBytes < _defaultFileSize) {
      fileSizeInBytes = _defaultFileSize;
    }

    if ((downloadTestServer == null || uploadTestServer == null) &&
        useFastApi) {
      if (onDefaultServerSelectionInProgress != null) {
        onDefaultServerSelectionInProgress();
      }
      ServerSelectionResponse? serverSelectionResponse =
          await FlutterInternetSpeedTestPlatform.instance.getDefaultServer(
        serverListUrl: serverListUrl,
        additionalConfigs: additionalConfigs,
      );

      if (onDefaultServerSelectionDone != null) {
        onDefaultServerSelectionDone(serverSelectionResponse?.client);
      }
      String? url = serverSelectionResponse?.targets?.first.url;
      if (url != null) {
        downloadTestServer = downloadTestServer ?? url;
        uploadTestServer = uploadTestServer ?? url;
      }
    }
/*
    if (onPingTestInProgress != null) {
      onPingTestInProgress(0, TestResult(TestType.ping, 0, SpeedUnit.ms));
    }
    */

    if (onPingTestDone != null) {
      cancelLatencyTest =
          await FlutterInternetSpeedTestPlatform.instance.startLatencyTesting(
        testServer: downloadTestServer!,
        onDone: (double averageLatency, double jitter) {
          onPingTestDone(TestResult(TestType.ping, averageLatency, SpeedUnit.ms,
              jitter: jitter, ping: averageLatency));
          if (_isCancelled) {
            if (onCancel != null) {
              onCancel();
              _isTestInProgress = false;
              _isCancelled = false;
              return;
            }
          }
        },
        onProgress: (double percent, double averageLatency, double jitter) {
          if (onPingTestInProgress != null) {
            onPingTestInProgress(
                percent,
                TestResult(TestType.ping, averageLatency, SpeedUnit.ms,
                    jitter: jitter, ping: averageLatency));
          }
        },
        onError: (String errorMessage, String speedTestError) {
          if (onError != null) onError(errorMessage, speedTestError);
          _isTestInProgress = false;
          _isCancelled = false;
        },
        onCancel: () {
          if (onCancel != null) onCancel();
          _isTestInProgress = false;
          _isCancelled = false;
        },
      );

      //onGetIpDone(serverSelectionResponse?.client);
    }

    if (downloadTestServer == null || uploadTestServer == null) {
      downloadTestServer = downloadTestServer ?? _defaultDownloadTestServer;
      uploadTestServer = uploadTestServer ?? _defaultUploadTestServer;
    }

    if (_isCancelled) {
      if (onCancel != null) {
        onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
        return;
      }
    }

    var startDownloadTimeStamp = DateTime.now().millisecondsSinceEpoch;
    await FlutterInternetSpeedTestPlatform.instance.startDownloadTesting(
      onDone: (double transferRate, SpeedUnit unit,
          {double? jitter, double? ping}) async {
        final downloadDuration =
            DateTime.now().millisecondsSinceEpoch - startDownloadTimeStamp;
        final downloadResult = TestResult(TestType.download, transferRate, unit,
            durationInMillis: downloadDuration);

        if (onProgress != null) onProgress(100, downloadResult);
        if (onDownloadComplete != null) onDownloadComplete(downloadResult);

        final startUploadTimeStamp = DateTime.now().millisecondsSinceEpoch;

        if (onGetIPDone != null) {
          Client? client = await FlutterInternetSpeedTestPlatform.instance
              .getClientInformation();
          onGetIPDone(client);
        }

        await FlutterInternetSpeedTestPlatform.instance.startUploadTesting(
          onDone: (double transferRate, SpeedUnit unit,
              {double? jitter, double? ping}) {
            // Cancel the latency test
            cancelLatencyTest?.call();
            final uploadDuration =
                DateTime.now().millisecondsSinceEpoch - startUploadTimeStamp;
            final uploadResult = TestResult(TestType.upload, transferRate, unit,
                durationInMillis: uploadDuration);

            if (onProgress != null) onProgress(100, uploadResult);
            if (onUploadComplete != null) onUploadComplete(uploadResult);
            FlutterInternetSpeedTestPlatform.instance
                .resetTest(softReset: true);
            onCompleted(downloadResult, uploadResult);
            _isTestInProgress = false;
            _isCancelled = false;
          },
          onProgress: (double percent, double transferRate, SpeedUnit unit,
              {double? jitter, double? ping}) {
            final uploadProgressResult =
                TestResult(TestType.upload, transferRate, unit);
            if (onProgress != null) {
              onProgress(percent, uploadProgressResult);
            }
          },
          onError: (String errorMessage, String speedTestError) {
            if (onError != null) onError(errorMessage, speedTestError);
            _isTestInProgress = false;
            _isCancelled = false;
          },
          onCancel: () {
            if (onCancel != null) onCancel();
            _isTestInProgress = false;
            _isCancelled = false;
          },
          fileSize: fileSizeInBytes,
          testServer: uploadTestServer!,
        );
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit,
          {double? jitter, double? ping}) {
        final downloadProgressResult =
            TestResult(TestType.download, transferRate, unit);
        if (onProgress != null) onProgress(percent, downloadProgressResult);
      },
      onError: (String errorMessage, String speedTestError) {
        if (onError != null) onError(errorMessage, speedTestError);
        _isTestInProgress = false;
        _isCancelled = false;
      },
      onCancel: () {
        if (onCancel != null) onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
      },
      fileSize: fileSizeInBytes,
      testServer: downloadTestServer,
    );
  }

  void enableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: true);
  }

  void disableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: false);
  }

  Future<bool> cancelTest() async {
    _isCancelled = true;

    // Cancel the latency test
    if (cancelLatencyTest != null) {
      cancelLatencyTest?.call();
      cancelLatencyTest = null; // Reset the variable
    }

    return await FlutterInternetSpeedTestPlatform.instance.cancelTest();
  }

  bool get isLogEnabled => FlutterInternetSpeedTestPlatform.instance.logEnabled;

  Future<String?> getPlatformVersion() async {
    return await FlutterInternetSpeedTestPlatform.instance.getPlatformVersion();
  }
}
