/*
  LibreSpeed - Main
  by Federico Dossena
  https://github.com/librespeed/speedtest/
  GNU LGPLv3 License
*/

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math';

class Speedtest {
  List<Map<String, dynamic>> _serverList = []; // List of test points
  Map<String, dynamic>? _selectedServer; // Selected server
  Map<String, dynamic> _settings = {}; // Settings for the speedtest worker
  int _state =
      0; // 0=adding settings, 1=adding servers, 2=server selection done, 3=test running, 4=done
  Worker? worker;
  Function(dynamic data)? onupdate;
  Function(bool aborted)? onend;
  Timer? updater;
  String? _prevData;
  bool _selectServerCalled = false;
  dynamic _originalExtra;

  Speedtest() {
    print(
        "LibreSpeed by Federico Dossena v5.2.4 - https://github.com/librespeed/speedtest");
  }

  /**
   * Returns the state of the test: 0=adding settings, 1=adding servers, 2=server selection done, 3=test running, 4=done
   */
  int getState() {
    return _state;
  }

  /**
   * Change one of the test settings from their defaults.
   * - parameter: string with the name of the parameter that you want to set
   * - value: new value for the parameter
   *
   * Invalid values or nonexistent parameters will be ignored by the speedtest worker.
   */
  void setParameter(String parameter, dynamic value) {
    if (_state == 3) {
      throw Exception(
          "You cannot change the test settings while running the test");
    }
    _settings[parameter] = value;
    if (parameter == "telemetry_extra") {
      _originalExtra = _settings['telemetry_extra'];
    }
  }

  /**
   * Used internally to check if a server object contains all the required elements.
   * Also fixes the server URL if needed.
   */
  void _checkServerDefinition(Map<String, dynamic> server) {
    try {
      if (server['name'] is! String) {
        throw Exception("Name string missing from server definition (name)");
      }
      if (server['server'] is! String) {
        throw Exception(
            "Server address string missing from server definition (server)");
      }

      String serverUrl = server['server'] as String;

      if (!serverUrl.endsWith("/")) {
        serverUrl += "/";
      }
      if (serverUrl.startsWith("//")) {
        serverUrl = window.location.protocol + serverUrl;
      }
      server['server'] = serverUrl;

      if (server['dlURL'] is! String) {
        throw Exception(
            "Download URL string missing from server definition (dlURL)");
      }
      if (server['ulURL'] is! String) {
        throw Exception(
            "Upload URL string missing from server definition (ulURL)");
      }
      if (server['pingURL'] is! String) {
        throw Exception(
            "Ping URL string missing from server definition (pingURL)");
      }
      if (server['getIpURL'] is! String) {
        throw Exception(
            "GetIP URL string missing from server definition (getIpURL)");
      }
    } catch (e) {
      throw Exception("Invalid server definition");
    }
  }

  /**
   * Add a test point (multiple points of test)
   * server: the server to be added as an object. Must contain the following elements:
   *  {
   *       name: "User friendly name",
   *       server:"http://yourBackend.com/",   URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
   *       dlURL:"garbage.php"   path to garbage.php or its replacement on the server
   *       ulURL:"empty.php"   path to empty.php or its replacement on the server
   *       pingURL:"empty.php"   path to empty.php or its replacement on the server. This is used to ping the server by this selector
   *       getIpURL:"getIP.php"   path to getIP.php or its replacement on the server
   *   }
   */
  void addTestPoint(Map<String, dynamic> server) {
    _checkServerDefinition(server);
    if (_state == 0) _state = 1;
    if (_state != 1) {
      throw Exception("You can't add a server after server selection");
    }
    _settings['mpot'] = true;
    _serverList.add(server);
  }

  /**
   * Same as addTestPoint, but you can pass an array of servers
   */
  void addTestPoints(List<Map<String, dynamic>> list) {
    for (var server in list) {
      addTestPoint(server);
    }
  }

  /**
   * Load a JSON server list from URL (multiple points of test)
   * url: the url where the server list can be fetched. Must be an array with objects containing the following elements:
   *  {
   *       "name": "User friendly name",
   *       "server":"http://yourBackend.com/",   URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
   *       "dlURL":"garbage.php"   path to garbage.php or its replacement on the server
   *       "ulURL":"empty.php"   path to empty.php or its replacement on the server
   *       "pingURL":"empty.php"   path to empty.php or its replacement on the server. This is used to ping the server by this selector
   *       "getIpURL":"getIP.php"   path to getIP.php or its replacement on the server
   *   }
   * result: callback to be called when the list is loaded correctly. An array with the loaded servers will be passed to this function, or null if it failed
   */
  void loadServerList(
      String url, void Function(List<Map<String, dynamic>>? servers) result) {
    if (_state == 0) _state = 1;
    if (_state != 1) {
      throw Exception("You can't add a server after server selection");
    }
    _settings['mpot'] = true;

    HttpRequest xhr = HttpRequest();
    xhr.onLoad.listen((event) {
      try {
        List<dynamic> serversJson =
            jsonDecode(xhr.responseText!) as List<dynamic>;
        List<Map<String, dynamic>> servers =
            serversJson.cast<Map<String, dynamic>>();
        for (var server in servers) {
          _checkServerDefinition(server);
        }
        addTestPoints(servers);
        result(servers);
      } catch (e) {
        result(null);
      }
    });

    xhr.onError.listen((event) {
      result(null);
    });

    xhr.open('GET', url);
    xhr.send();
  }

  /**
   * Returns the selected server (multiple points of test)
   */
  Map<String, dynamic> getSelectedServer() {
    if (_state < 2 || _selectedServer == null) {
      throw Exception("No server is selected");
    }
    return _selectedServer!;
  }

  /**
   * Manually selects one of the test points (multiple points of test)
   */
  void setSelectedServer(Map<String, dynamic> server) {
    _checkServerDefinition(server);
    if (_state == 3) {
      throw Exception("You can't select a server while the test is running");
    }
    _selectedServer = server;
    _state = 2;
  }

  /**
   * Automatically selects a server from the list of added test points. The server with the lowest ping will be chosen. (multiple points of test)
   * The process is asynchronous and the passed result callback function will be called when it's done, then the test can be started.
   */
  void selectServer(void Function(Map<String, dynamic>? server) result) {
    if (_state != 1) {
      if (_state == 0) throw Exception("No test points added");
      if (_state == 2) throw Exception("Server already selected");
      if (_state >= 3) {
        throw Exception("You can't select a server while the test is running");
      }
    }
    if (_selectServerCalled) {
      throw Exception("selectServer already called");
    } else {
      _selectServerCalled = true;
    }

    const int PING_TIMEOUT = 2000;
    bool USE_PING_TIMEOUT = true;
    if (window.navigator.userAgent
        .contains(RegExp(r'MSIE.(\d+\.\d+)', caseSensitive: false))) {
      USE_PING_TIMEOUT = false;
    }

    Future<int> ping(String url) async {
      url += (url.contains('?') ? '&' : '?') + 'cors=true';
      int t = DateTime.now().millisecondsSinceEpoch;
      try {
        HttpRequest xhr = await HttpRequest.request(
          url,
          method: 'GET',
          responseType: 'text',
          requestHeaders: {},
          //timeout: USE_PING_TIMEOUT ? PING_TIMEOUT : 0,
          withCredentials: false,
        );
        if (xhr.responseText!.length == 0) {
          int instspd = DateTime.now().millisecondsSinceEpoch - t;
          try {
            var entries = window.performance.getEntriesByName(url, 'resource');
            if (entries.isNotEmpty) {
              var p = entries.last as PerformanceResourceTiming;
              double d =
                  ((p.responseStart ?? 0) - (p.requestStart ?? 0)).toDouble();
              if (d <= 0) d = (p.duration ?? 0).toDouble();
              if (d > 0 && d < instspd) instspd = d.round();
            }
          } catch (e) {}
          return instspd;
        } else {
          return -1;
        }
      } catch (e) {
        return -1;
      }
    }

    const int PINGS = 3;
    const int SLOW_THRESHOLD = 500;

    Future<void> checkServer(Map<String, dynamic> server) async {
      int i = 0;
      server['pingT'] = -1;
      if (!server['server'].toString().startsWith(window.location.protocol)) {
        return;
      } else {
        while (i++ < PINGS) {
          String pingURL = server['pingURL'] as String;
          int t = await ping((server['server'] as String) + pingURL);
          if (t >= 0) {
            if (t < (server['pingT'] as num) || server['pingT'] == -1) {
              server['pingT'] = t;
            }
            if (t < SLOW_THRESHOLD) {
              continue;
            } else {
              break;
            }
          } else {
            break;
          }
        }
      }
    }

    Future<void> select(List<Map<String, dynamic>> serverList) async {
      for (var server in serverList) {
        await checkServer(server);
      }
    }

    const int CONCURRENCY = 6;
    List<List<Map<String, dynamic>>> serverLists =
        List.generate(CONCURRENCY, (_) => []);

    for (int i = 0; i < _serverList.length; i++) {
      serverLists[i % CONCURRENCY].add(_serverList[i]);
    }

    int completed = 0;
    Map<String, dynamic>? bestServer;

    for (var serverList in serverLists) {
      select(serverList).then((_) {
        for (var server in serverList) {
          if (server['pingT'] != -1 &&
              (bestServer == null ||
                  (server['pingT'] as int) < (bestServer!['pingT'] as int))) {
            bestServer = server;
          }
        }
        completed++;
        if (completed == CONCURRENCY) {
          _selectedServer = bestServer;
          _state = 2;
          result(bestServer);
        }
      });
    }
  }

  /**
   * Starts the test.
   * During the test, the onupdate(data) callback function will be called periodically with data from the worker.
   * At the end of the test, the onend(aborted) function will be called with a boolean telling you if the test was aborted or if it ended normally.
   */
  void start() {
    if (_state == 3) throw Exception("Test already running");
    worker = Worker("speedtest_worker.js?r=${Random().nextDouble()}");
    worker!.onMessage.listen((MessageEvent e) {
      if (e.data == _prevData) {
        return;
      } else {
        _prevData = e.data as String?;
      }

      Map<String, dynamic> data =
          jsonDecode(e.data as String) as Map<String, dynamic>;
      try {
        if (onupdate != null) onupdate!(data);
      } catch (e) {
        print("Speedtest onupdate event threw exception: $e");
      }
      if ((data['testState'] as int) >= 4) {
        if (updater != null) updater!.cancel();
        _state = 4;
        try {
          if (onend != null) onend!(data['testState'] == 5);
        } catch (e) {
          print("Speedtest onend event threw exception: $e");
        }
      }
    });

    updater = Timer.periodic(Duration(milliseconds: 200), (timer) {
      worker!.postMessage("status");
    });

    if (_state == 1) {
      throw Exception(
          "When using multiple points of test, you must call selectServer before starting the test");
    }

    if (_state == 2) {
      _settings['url_dl'] =
          _selectedServer!['server'] + _selectedServer!['dlURL'];
      _settings['url_ul'] =
          _selectedServer!['server'] + _selectedServer!['ulURL'];
      _settings['url_ping'] =
          _selectedServer!['server'] + _selectedServer!['pingURL'];
      _settings['url_getIp'] =
          _selectedServer!['server'] + _selectedServer!['getIpURL'];
      if (_originalExtra != null) {
        _settings['telemetry_extra'] = jsonEncode({
          'server': _selectedServer!['name'],
          'extra': _originalExtra,
        });
      } else {
        _settings['telemetry_extra'] = jsonEncode({
          'server': _selectedServer!['name'],
        });
      }
    }
    _state = 3;
    worker!.postMessage("start ${jsonEncode(_settings)}");
  }

  /**
   * Aborts the test while it's running.
   */
  void abort() {
    if (_state < 3) {
      throw Exception("You cannot abort a test that's not started yet");
    }
    if (_state < 4) worker!.postMessage("abort");
  }
}
