import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_internet_speed_test/flutter_internet_speed_test.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final internetSpeedTest = FlutterInternetSpeedTest()..enableLog();

  bool _testInProgress = false;
  double _downloadRate = 0;
  double _uploadRate = 0;
  String _downloadProgress = '0';
  String _uploadProgress = '0';
  int _downloadCompletionTime = 0;
  int _uploadCompletionTime = 0;
  bool _isServerSelectionInProgress = false;

  String? _ip;
  String? _asn;
  String? _isp;

  String _unitText = 'Mbps';

  double _latency = 0;
  double _jitter = 0;
  String _latencyProgress = '0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reset();
    });
  }

  void _updateUIOnCompletion() {
    // Called when a test completes to ensure UI updates even if onCompleted isn't fired.
    // If tests are done, show final results and ensure _testInProgress = false.
    setState(() {
      _testInProgress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('FlutterInternetSpeedTest example'),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Latency Test Section
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Latency Test',
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Progress: $_latencyProgress%'),
                    Text('Latency: $_latency ms'),
                    Text('Jitter: $_jitter ms'),
                  ],
                ),
                const SizedBox(height: 32.0),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Download Speed',
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Progress: $_downloadProgress%'),
                    Text('Download Rate: $_downloadRate $_unitText'),
                    if (_downloadCompletionTime > 0)
                      Text(
                          'Time taken: ${(_downloadCompletionTime / 1000).toStringAsFixed(2)} sec(s)'),
                  ],
                ),
                const SizedBox(height: 32.0),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Upload Speed',
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Progress: $_uploadProgress%'),
                    Text('Upload Rate: $_uploadRate $_unitText'),
                    if (_uploadCompletionTime > 0)
                      Text(
                          'Time taken: ${(_uploadCompletionTime / 1000).toStringAsFixed(2)} sec(s)'),
                  ],
                ),
                const SizedBox(height: 32.0),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(_isServerSelectionInProgress
                      ? 'Selecting Server...'
                      : 'IP: ${_ip ?? '--'} | ASN: ${_asn ?? '--'} | ISP: ${_isp ?? '--'}'),
                ),
                if (!_testInProgress) ...{
                  ElevatedButton(
                    child: const Text('Start Testing'),
                    onPressed: () async {
                      reset();
                      if (kDebugMode) {
                        print('Starting the test...');
                      }
                      await internetSpeedTest.startTesting(
                        onGetIPDone: (Client? client) {
                          if (kDebugMode) {
                            print('onGetIPDone: $client');
                          }
                          setState(() {
                            if (client != null) {
                              _ip = client.ip;
                              _asn = client.asn;
                              _isp = client.isp;
                            }
                          });
                        },
                        downloadTestServer:
                            kIsWeb ? 'http://localhost:8080' : null,
                        uploadTestServer:
                            kIsWeb ? 'http://localhost:8080' : null,
                        onStarted: () {
                          if (kDebugMode) {
                            print('Test started');
                          }
                          setState(() => _testInProgress = true);
                        },
                        onCompleted: (TestResult download, TestResult upload) {
                          if (kDebugMode) {
                            print(
                                'onCompleted: Download=${download.value} ${download.unit}, Upload=${upload.value} ${upload.unit}');
                          }
                          setState(() {
                            // If onCompleted is triggered, show final results
                            if (download.hasRan()) {
                              _downloadRate = double.parse(
                                  download.value.toStringAsFixed(2));
                              _unitText = download.unit == SpeedUnit.kbps
                                  ? 'Kbps'
                                  : 'Mbps';
                              _downloadProgress = '100';
                              _downloadCompletionTime =
                                  download.durationInMillis;
                            }

                            if (upload.hasRan()) {
                              _uploadRate =
                                  double.parse(upload.value.toStringAsFixed(2));
                              _unitText = upload.unit == SpeedUnit.kbps
                                  ? 'Kbps'
                                  : 'Mbps';
                              _uploadProgress = '100';
                              _uploadCompletionTime = upload.durationInMillis;
                            }

                            _testInProgress = false;
                          });
                        },
                        onProgress: (double percent, TestResult data) {
                          if (kDebugMode) {
                            print(
                                'onProgress: ${data.type} rate=${data.value} ${data.unit}, percent=$percent');
                          }
                          setState(() {
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            if (data.type == TestType.download) {
                              _downloadRate =
                                  double.parse(data.value.toStringAsFixed(2));
                              _downloadProgress = percent.toStringAsFixed(1);
                            } else if (data.type == TestType.upload) {
                              _uploadRate =
                                  double.parse(data.value.toStringAsFixed(2));
                              _uploadProgress = percent.toStringAsFixed(1);
                            }
                          });
                        },
                        onError: (String errorMessage, String speedTestError) {
                          if (kDebugMode) {
                            print('onError: $errorMessage $speedTestError');
                          }
                          setState(() {
                            _testInProgress = false;
                          });
                          reset();
                        },
                        onDefaultServerSelectionInProgress: () {
                          if (kDebugMode) {
                            print('Selecting best server...');
                          }
                          setState(() {
                            _isServerSelectionInProgress = true;
                          });
                        },
                        onDefaultServerSelectionDone: (Client? client) {
                          if (kDebugMode) {
                            print('Default server selected: $client');
                          }
                          setState(() {
                            _isServerSelectionInProgress = false;
                            _ip = client?.ip;
                            _asn = client?.asn;
                            _isp = client?.isp;
                          });
                        },
                        onDownloadComplete: (TestResult data) {
                          if (kDebugMode) {
                            print(
                                'onDownloadComplete: ${data.value} ${data.unit}, Time: ${data.durationInMillis}ms');
                          }
                          setState(() {
                            _downloadRate =
                                double.parse(data.value.toStringAsFixed(2));
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            _downloadCompletionTime = data.durationInMillis;
                            _downloadProgress = '100';
                            // UI might need to end test if upload won't run
                            // If this is a single test scenario, finalize UI here:
                            //_testInProgress = false; // Uncomment if needed
                          });
                        },
                        onUploadComplete: (TestResult data) {
                          if (kDebugMode) {
                            print(
                                'onUploadComplete: ${data.value} ${data.unit}, Time: ${data.durationInMillis}ms');
                          }
                          setState(() {
                            _uploadRate =
                                double.parse(data.value.toStringAsFixed(2));
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            _uploadCompletionTime = data.durationInMillis;
                            _uploadProgress = '100';
                            // If tests won't trigger onCompleted, finalize UI here:
                            //_testInProgress = false; // Uncomment if needed
                          });
                        },
                        onPingTestDone: (TestResult data) {
                          if (kDebugMode) {
                            print(
                                'onPingTestDone: Latency ${data.value}, Jitter ${data.jitter}');
                          }
                          setState(() {
                            _latency =
                                double.parse(data.value.toStringAsFixed(2));
                            _jitter = double.parse(
                                (data.jitter ?? 0).toStringAsFixed(2));
                            _latencyProgress = '100';
                          });
                        },
                        onPingTestInProgress:
                            (double percent, TestResult data) {
                          if (kDebugMode) {
                            print(
                                'onPingTestInProgress: $percent%, Latency ${data.value}, Jitter: ${data.jitter}');
                          }
                          setState(() {
                            _latency =
                                double.parse(data.value.toStringAsFixed(2));
                            _jitter = double.parse(
                                (data.jitter ?? 0).toStringAsFixed(2));
                            _latencyProgress = percent.toStringAsFixed(1);
                          });
                        },
                        onCancel: () {
                          if (kDebugMode) {
                            print('Test cancelled');
                          }
                          setState(() {
                            _testInProgress = false;
                          });
                          reset();
                        },
                      );
                    },
                  )
                } else ...{
                  const CircularProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton.icon(
                      onPressed: () {
                        if (kDebugMode) {
                          print('Cancel button pressed');
                        }
                        internetSpeedTest.cancelTest().then((_) {
                          setState(() {
                            _testInProgress = false;
                          });
                        });
                      },
                      icon: const Icon(Icons.cancel_rounded),
                      label: const Text('Cancel'),
                    ),
                  )
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  void reset() {
    if (kDebugMode) {
      print('resetTest called');
    }
    setState(() {
      _testInProgress = false;
      _downloadRate = 0;
      _uploadRate = 0;
      _downloadProgress = '0';
      _uploadProgress = '0';
      _downloadCompletionTime = 0;
      _uploadCompletionTime = 0;
      _isServerSelectionInProgress = false;

      _ip = null;
      _asn = null;
      _isp = null;

      _unitText = 'Mbps';

      _latency = 0;
      _jitter = 0;
      _latencyProgress = '0';
    });
  }
}
