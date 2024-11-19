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

  // Add variables for latency and jitter
  double _latency = 0;
  double _jitter = 0;
  // ignore: unused_field
  String _latencyProgress = '0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      reset();
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
            // Added SingleChildScrollView to prevent overflow
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
                const SizedBox(
                  height: 32.0,
                ),
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
                const SizedBox(
                  height: 32.0,
                ),
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
                const SizedBox(
                  height: 32.0,
                ),
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
                      await internetSpeedTest.startTesting(
                        downloadTestServer:
                            kIsWeb ? 'http://localhost:8080' : null,
                        uploadTestServer:
                            kIsWeb ? 'http://localhost:8080' : null,
                        onGetIPDone: (Client? client) {
                          setState(() {
                            if (client != null) {
                              _ip = client.ip;
                              _asn = client.asn;
                              _isp = client.isp;
                            }
                          });
                        },
                        onStarted: () {
                          setState(() => _testInProgress = true);
                        },
                        onCompleted: (TestResult download, TestResult upload) {
                          if (kDebugMode) {
                            print(
                                'Download rate: ${download.value}, Upload rate: ${upload.value}');
                          }
                          if (download.hasRan()) {
                            setState(() {
                              _downloadRate = download.value;
                              _downloadRate = double.parse(
                                  _downloadRate.toStringAsFixed(2));
                              _unitText = download.unit == SpeedUnit.kbps
                                  ? 'Kbps'
                                  : 'Mbps';
                              _downloadProgress = '100';
                              _downloadCompletionTime =
                                  download.durationInMillis;
                            });
                          }
                          if (upload.hasRan()) {
                            setState(() {
                              _uploadRate = upload.value;
                              _uploadRate =
                                  double.parse(_uploadRate.toStringAsFixed(2));
                              _unitText = upload.unit == SpeedUnit.kbps
                                  ? 'Kbps'
                                  : 'Mbps';
                              _uploadProgress = '100';
                              _uploadCompletionTime = upload.durationInMillis;
                              _testInProgress = false;
                            });
                          }
                        },
                        onProgress: (double percent, TestResult data) {
                          if (kDebugMode) {
                            print(
                                'Transfer rate: ${data.value}, Percent: $percent');
                          }
                          setState(() {
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            if (data.type == TestType.download) {
                              _downloadRate = data.value;
                              _downloadProgress = percent.toStringAsFixed(1);
                              _downloadRate = double.parse(
                                  _downloadRate.toStringAsFixed(2));
                            } else if (data.type == TestType.upload) {
                              _uploadRate = data.value;
                              _uploadProgress = percent.toStringAsFixed(1);
                              _uploadRate =
                                  double.parse(_uploadRate.toStringAsFixed(2));
                            }
                          });
                        },
                        onError: (String errorMessage, String speedTestError) {
                          if (kDebugMode) {
                            print(
                                'Error Message: $errorMessage, SpeedTestError: $speedTestError');
                          }
                          reset();
                        },
                        onDefaultServerSelectionInProgress: () {
                          setState(() {
                            _isServerSelectionInProgress = true;
                          });
                        },
                        onDefaultServerSelectionDone: (Client? client) {
                          setState(() {
                            _isServerSelectionInProgress = false;
                            _ip = client?.ip;
                            _asn = client?.asn;
                            _isp = client?.isp;
                          });
                        },
                        onDownloadComplete: (TestResult data) {
                          setState(() {
                            _downloadRate = data.value;
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            _downloadCompletionTime = data.durationInMillis;
                            _downloadRate =
                                double.parse(_downloadRate.toStringAsFixed(2));
                          });
                        },
                        onUploadComplete: (TestResult data) {
                          setState(() {
                            _uploadRate = data.value;
                            _unitText =
                                data.unit == SpeedUnit.kbps ? 'Kbps' : 'Mbps';
                            _uploadCompletionTime = data.durationInMillis;
                            _uploadRate =
                                double.parse(_uploadRate.toStringAsFixed(1));
                          });
                        },
                        onPingTestDone: (TestResult data) {
                          if (kDebugMode) {
                            print(
                                'Ping test completed: Latency ${data.value}, Jitter ${data.jitter}');
                          }
                          setState(() {
                            _latency = data.value;
                            _jitter = data.jitter ?? 0;
                            _latencyProgress = '100';
                            _latency =
                                double.parse(_latency.toStringAsFixed(2));
                            _jitter = double.parse(_jitter.toStringAsFixed(2));
                          });
                        },
                        onPingTestInProgress:
                            (double percent, TestResult data) {
                          if (kDebugMode) {
                            print(
                                'Ping test progress: $percent%, Latency ${data.value}');
                          }
                          setState(() {
                            _latency = data.value;
                            _latencyProgress = percent.toStringAsFixed(1);
                            _jitter = data.jitter ?? 0;
                            _latency = double.parse(_latency
                                .toStringAsFixed(2)); // One decimal place
                            _jitter = double.parse(_jitter.toStringAsFixed(2));
                          });
                        },
                        onCancel: () {
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
                      onPressed: () => internetSpeedTest.cancelTest(),
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

      // Reset latency variables
      _latency = 0;
      _jitter = 0;
      _latencyProgress = '0';
    });
  }
}
