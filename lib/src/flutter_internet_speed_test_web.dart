import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:xml/xml.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/client.dart';
import 'models/server.dart';
import 'models/server_selection_response.dart';

class FlutterInternetSpeedTestWeb extends FlutterInternetSpeedTestPlatform {
  @override
  bool isLogEnabled = false;
  bool _testCancelled = false;

  FlutterInternetSpeedTestWeb();

  static void registerWith(Registrar registrar) {
    FlutterInternetSpeedTestPlatform.instance = FlutterInternetSpeedTestWeb();
  }

  void _log(String message) {
    if (isLogEnabled) {
      if (kDebugMode) {
        print(message);
      }
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = window.navigator.userAgent;
    return version;
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
    _testCancelled = false;

    try {
      // Perform download test by fetching data from the testServer
      // Due to CORS restrictions, we need to ensure the server supports CORS
      var url = '$testServer/download?size=$fileSize';
      //url = "http://localhost:8080";
      int downloadedBytes = 0;
      var startTime = DateTime.now();

      var request = HttpRequest();
      request
        ..open('GET', url)
        ..responseType = 'arraybuffer';

      request.onProgress.listen((event) {
        if (_testCancelled) {
          request.abort();
          onCancel();
          return;
        }

        downloadedBytes = event.loaded!;
        int totalBytes = event.total ?? fileSize;
        double percent = (downloadedBytes / totalBytes) * 100;
        if (percent > 100) percent = 100;

        var currentTime = DateTime.now();
        double elapsedTime =
            currentTime.difference(startTime).inMilliseconds / 1000.0;
        double speed = (downloadedBytes * 8) / elapsedTime; // bits per second
        double speedMbps = speed / 1000000.0;

        onProgress(percent, speedMbps, SpeedUnit.mbps);
      });

      request.onLoad.listen((event) {
        if (_testCancelled) {
          onCancel();
          return;
        }
        var endTime = DateTime.now();
        double elapsedTime =
            endTime.difference(startTime).inMilliseconds / 1000.0;
        double speed = (downloadedBytes * 8) / elapsedTime; // bits per second
        double speedMbps = speed / 1000000.0;

        onDone(speedMbps, SpeedUnit.mbps);
      });

      request.onError.listen((event) {
        onError('Error during download test', 'DOWNLOAD_ERROR');
      });

      request.send();

      return () {
        _testCancelled = true;
        request.abort();
      };
    } catch (e) {
      onError(e.toString(), 'DOWNLOAD_ERROR');
      return () {};
    }
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
    _testCancelled = false;

    try {
      // Perform upload test by sending data to the testServer
      // Due to CORS restrictions, we need to ensure the server supports CORS
      var url = '$testServer/upload';

      var data = Uint8List(fileSize);
      var random = Random();
      for (int i = 0; i < data.length; i++) {
        data[i] = random.nextInt(256);
      }

      int uploadedBytes = 0;
      var startTime = DateTime.now();

      var request = HttpRequest();
      request
        ..open('POST', url)
        ..setRequestHeader('Content-Type', 'application/octet-stream');

      request.upload.onProgress.listen((event) {
        if (_testCancelled) {
          request.abort();
          onCancel();
          return;
        }

        uploadedBytes = event.loaded!;
        int totalBytes = event.total ?? fileSize;
        double percent = (uploadedBytes / totalBytes) * 100;
        if (percent > 100) percent = 100;

        var currentTime = DateTime.now();
        double elapsedTime =
            currentTime.difference(startTime).inMilliseconds / 1000.0;
        double speed = (uploadedBytes * 8) / elapsedTime; // bits per second
        double speedMbps = speed / 1000000.0;

        onProgress(percent, speedMbps, SpeedUnit.mbps);
      });

      request.onLoad.listen((event) {
        if (_testCancelled) {
          onCancel();
          return;
        }
        var endTime = DateTime.now();
        double elapsedTime =
            endTime.difference(startTime).inMilliseconds / 1000.0;
        double speed = (uploadedBytes * 8) / elapsedTime; // bits per second
        double speedMbps = speed / 1000000.0;

        onDone(speedMbps, SpeedUnit.mbps);
      });

      request.onError.listen((event) {
        onError('Error during upload test', 'UPLOAD_ERROR');
      });

      request.send(data);

      return () {
        _testCancelled = true;
        request.abort();
      };
    } catch (e) {
      onError(e.toString(), 'UPLOAD_ERROR');
      return () {};
    }
  }

  @override
  Future<void> toggleLog({required bool value}) async {
    isLogEnabled = value;
  }

  @override
  Future<ServerSelectionResponse?> getDefaultServer({
    String? serverListUrl,
    Map<String, dynamic>? additionalConfigs,
  }) async {
    try {
      if (serverListUrl != null) {
        _log(
            'Custom serverListUrl is not supported in the web implementation.');
      }
      // Fetch configuration
      var configResponse = await HttpRequest.request(
        'https://www.speedtest.net/speedtest-config.php',
        method: 'GET',
      );

      if (configResponse.status == 200) {
        var configXml = configResponse.responseText!;
        // Parse the configuration XML
        var configDocument = XmlDocument.parse(configXml);
        // Extract client information
        var clientElement = configDocument.findAllElements('client').first;
        var client = Client(
          ip: clientElement.getAttribute('ip')!,
          isp: clientElement.getAttribute('isp')!,
          latitude: double.parse(clientElement.getAttribute('lat')!),
          longitude: double.parse(clientElement.getAttribute('lon')!),
        );

        // Fetch server list
        var serversResponse = await HttpRequest.request(
          'https://www.speedtest.net/speedtest-servers.php',
          method: 'GET',
        );

        if (serversResponse.status == 200) {
          var serversXml = serversResponse.responseText!;
          // Parse the servers XML
          var serversDocument = XmlDocument.parse(serversXml);
          var serverElements = serversDocument.findAllElements('server');
          List<Server> servers = [];
          for (var serverElement in serverElements) {
            double distance = calculateDistance(
              client.latitude,
              client.longitude,
              double.parse(serverElement.getAttribute('lat')!),
              double.parse(serverElement.getAttribute('lon')!),
            );

            var server = Server(
              id: int.parse(serverElement.getAttribute('id')!),
              name: serverElement.getAttribute('name')!,
              sponsor: serverElement.getAttribute('sponsor')!,
              country: serverElement.getAttribute('country')!,
              cc: serverElement.getAttribute('cc')!,
              host: serverElement.getAttribute('host')!,
              latitude: double.parse(serverElement.getAttribute('lat')!),
              longitude: double.parse(serverElement.getAttribute('lon')!),
              url: serverElement.getAttribute('url')!,
              url2: serverElement.getAttribute('url2'),
              distance: distance,
            );
            servers.add(server);
          }

          // Sort servers by distance
          servers.sort((a, b) => a.distance!.compareTo(b.distance!));

          // Apply additional configurations if provided
          if (additionalConfigs != null) {
            additionalConfigs.forEach((key, value) {
              _log('Config $key: $value');
              // Implement any specific logic needed for additionalConfigs
            });
          }

          // Select best server based on latency
          // Since we cannot perform TCP latency tests in the browser, we'll attempt to estimate latency via HTTP requests
          Server? bestServer;
          double minLatency = double.infinity;

          for (var server in servers.take(5)) {
            try {
              var latency = await testServerLatency(server.url);
              var updatedServer = server.copyWith(
                  latency: Duration(milliseconds: latency.toInt()));
              if (latency < minLatency) {
                minLatency = latency;
                bestServer = updatedServer;
              }
            } catch (e) {
              _log('Error testing latency to server ${server.id}: $e');
            }
          }

          if (bestServer != null) {
            // Return the selected server as ServerSelectionResponse
            var target = Targets.fromServer(bestServer);
            return ServerSelectionResponse(targets: [target]);
          }
        }
      }
    } catch (e) {
      if (isLogEnabled) {
        _log(e.toString());
      }
    }
    return null;
  }

  @override
  Future<bool> cancelTest() async {
    _testCancelled = true;
    return true;
  }

  Future<double> testServerLatency(String url) async {
    // Perform multiple HTTP HEAD requests to the server and calculate average latency
    int attempts = 3;
    double totalLatency = 0;

    for (int i = 0; i < attempts; i++) {
      var startTime = DateTime.now();
      try {
        await HttpRequest.request(
          url,
          method: 'HEAD',
          requestHeaders: {'Cache-Control': 'no-cache'},
        );
        var endTime = DateTime.now();
        double latency =
            endTime.difference(startTime).inMilliseconds.toDouble();
        totalLatency += latency;
      } catch (e) {
        // If there's an error, use a high latency value
        totalLatency += 1000;
      }
    }

    return totalLatency / attempts;
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var earthRadiusKm = 6371;

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    lat1 = _degreesToRadians(lat1);
    lat2 = _degreesToRadians(lat2);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}
