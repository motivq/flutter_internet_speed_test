/*
  LibreSpeed - Worker
  by Federico Dossena
  https://github.com/librespeed/speedtest/
  GNU LGPLv3 License
*/

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math';
import 'dart:typed_data';

// Data reported to the main thread
int testState =
    -1; // -1=not started, 0=starting, 1=download test, 2=ping+jitter test, 3=upload test, 4=finished, 5=abort
String dlStatus = ""; // Download speed in megabit/s with 2 decimal digits
String ulStatus = ""; // Upload speed in megabit/s with 2 decimal digits
String pingStatus = ""; // Ping in milliseconds with 2 decimal digits
String jitterStatus = ""; // Jitter in milliseconds with 2 decimal digits
String clientIp = ""; // Client's IP address as reported by getIP.php
double dlProgress = 0; // Progress of download test 0-1
double ulProgress = 0; // Progress of upload test 0-1
double pingProgress = 0; // Progress of ping+jitter test 0-1
String? testId; // Test ID (sent back by telemetry if used, null otherwise)

String log = ""; // Telemetry log

void tlog(String s) {
  if ((settings['telemetry_level'] as int) >= 2) {
    log += "${DateTime.now().millisecondsSinceEpoch}: $s\n";
  }
}

void tverb(String s) {
  if ((settings['telemetry_level'] as int) >= 3) {
    log += "${DateTime.now().millisecondsSinceEpoch}: $s\n";
  }
}

void twarn(String s) {
  if ((settings['telemetry_level'] as int) >= 2) {
    log += "${DateTime.now().millisecondsSinceEpoch} WARN: $s\n";
  }
  print("WARN: $s");
}

// Test settings. Can be overridden by sending specific values with the start command
Map<String, dynamic> settings = {
  'mpot': false, // Set to true when in MPOT mode
  'test_order':
      "IP_D_U", // Order in which tests will be performed as a string. D=Download, U=Upload, P=Ping+Jitter, I=IP, _=1 second delay
  'time_ul_max': 15, // Max duration of upload test in seconds
  'time_dl_max': 15, // Max duration of download test in seconds
  'time_auto':
      true, // If set to true, tests will take less time on faster connections
  'time_ulGraceTime':
      3, // Time to wait in seconds before actually measuring ul speed (wait for buffers to fill)
  'time_dlGraceTime':
      1.5, // Time to wait in seconds before actually measuring dl speed (wait for TCP window to increase)
  'count_ping': 10, // Number of pings to perform in ping test
  'url_dl':
      "backend/garbage.php", // Path to a large file or garbage.php, used for download test. Must be relative to this js file
  'url_ul':
      "backend/empty.php", // Path to an empty file, used for upload test. Must be relative to this js file
  'url_ping':
      "backend/empty.php", // Path to an empty file, used for ping test. Must be relative to this js file
  'url_getIp':
      "backend/getIP.php", // Path to getIP.php relative to this js file, or a similar thing that outputs the client's IP
  'getIp_ispInfo':
      true, // If set to true, the server will include ISP info with the IP address
  'getIp_ispInfo_distance':
      "km", // km or mi=estimate distance from server in km/mi; set to false to disable distance estimation. getIp_ispInfo must be enabled for this to work
  'xhr_dlMultistream': 6, // Number of download streams to use
  'xhr_ulMultistream': 3, // Number of upload streams to use
  'xhr_multistreamDelay': 300, // How much concurrent requests should be delayed
  'xhr_ignoreErrors':
      1, // 0=fail on errors, 1=attempt to restart a stream if it fails, 2=ignore all errors
  'xhr_dlUseBlob': false, // If true, reduces RAM usage but uses the hard drive
  'xhr_ul_blob_megabytes':
      20, // Size in megabytes of the upload blobs sent in the upload test
  'garbagePhp_chunkSize': 100, // Size of chunks sent by garbage.php
  'enable_quirks': true, // Enable quirks for specific browsers
  'ping_allowPerformanceApi':
      true, // If enabled, the ping test will attempt to calculate the ping more precisely using the Performance API
  'overheadCompensationFactor':
      1.06, // Can be changed to compensate for transport overhead
  'useMebibits':
      false, // If true, speed will be reported in mebibits/s instead of megabits/s
  'telemetry_level':
      0, // 0=disabled, 1=basic (results only), 2=full (results and timing), 3=debug (results+log)
  'url_telemetry':
      "results/telemetry.php", // Path to the script that adds telemetry data to the database
  'telemetry_extra':
      "", // Extra data that can be passed to the telemetry through the settings
  'forceIE11Workaround':
      false, // When true, forces the IE11 upload test on all browsers
};

List<HttpRequest>? xhr; // List of currently active HTTP requests
Timer? interval; // Timer used in tests
int test_pointer =
    0; // Pointer to the next test to run inside settings.test_order

// Determines whether we need a '?' or an '&' as a separator in URLs
String url_sep(String url) {
  return url.contains('?') ? '&' : '?';
}

// Listener for commands from the main thread to this worker
void main() {
  DedicatedWorkerGlobalScope self = DedicatedWorkerGlobalScope.instance;

  self.onMessage.listen((MessageEvent e) {
    String data = e.data as String;
    List<String> params = data.split(" ");

    if (params[0] == "status") {
      // Return status
      self.postMessage(jsonEncode({
        'testState': testState,
        'dlStatus': dlStatus,
        'ulStatus': ulStatus,
        'pingStatus': pingStatus,
        'clientIp': clientIp,
        'jitterStatus': jitterStatus,
        'dlProgress': dlProgress,
        'ulProgress': ulProgress,
        'pingProgress': pingProgress,
        'testId': testId,
      }));
    }

    if (params[0] == "start" && testState == -1) {
      // Start new test
      testState = 0;
      try {
        // Parse settings, if present
        Map<String, dynamic> s = {};
        try {
          String ss = data.substring(5);
          if (ss.isNotEmpty) s = jsonDecode(ss) as Map<String, dynamic>;
        } catch (e) {
          twarn("Error parsing custom settings JSON. Please check your syntax");
        }

        // Copy custom settings
        s.forEach((key, value) {
          if (settings.containsKey(key)) {
            settings[key] = value;
          } else {
            twarn("Unknown setting ignored: $key");
          }
        });

        String ua = window.navigator.userAgent;

        // Quirks for specific browsers
        if ((settings['enable_quirks'] as bool) ||
            ((s.containsKey('enable_quirks') &&
                (s['enable_quirks'] as bool)))) {
          if (RegExp(r'Firefox.(\d+\.\d+)', caseSensitive: false)
              .hasMatch(ua)) {
            if (!s.containsKey('ping_allowPerformanceApi')) {
              // Firefox performance API issues
              settings['ping_allowPerformanceApi'] = false;
            }
          }
          if (RegExp(r'Edge.(\d+\.\d+)', caseSensitive: false).hasMatch(ua)) {
            if (!s.containsKey('xhr_dlMultistream')) {
              // Edge more precise with 3 download streams
              settings['xhr_dlMultistream'] = 3;
            }
          }
          if (RegExp(r'Chrome.(\d+)', caseSensitive: false).hasMatch(ua) &&
              window.fetch != null) {
            if (!s.containsKey('xhr_dlMultistream')) {
              // Chrome more precise with 5 streams
              settings['xhr_dlMultistream'] = 5;
            }
          }
        }

        if (RegExp(r'Edge.(\d+\.\d+)', caseSensitive: false).hasMatch(ua)) {
          // Edge 15 bug
          settings['forceIE11Workaround'] = true;
        }

        if (RegExp(r'PlayStation 4.(\d+\.\d+)', caseSensitive: false)
            .hasMatch(ua)) {
          // PS4 browser bug
          settings['forceIE11Workaround'] = true;
        }

        if (RegExp(r'Chrome.(\d+)', caseSensitive: false).hasMatch(ua) &&
            RegExp(r'Android|iPhone|iPad|iPod|Windows Phone',
                    caseSensitive: false)
                .hasMatch(ua)) {
          // Chrome mobile limitation
          settings['xhr_ul_blob_megabytes'] = 4;
        }

        if (RegExp(r'^((?!chrome|android|crios|fxios).)*safari',
                caseSensitive: false)
            .hasMatch(ua)) {
          // Safari workaround
          settings['forceIE11Workaround'] = true;
        }

        // Parse telemetry level
        if (s.containsKey('telemetry_level')) {
          var tl = s['telemetry_level'];
          settings['telemetry_level'] = tl == 'basic'
              ? 1
              : tl == 'full'
                  ? 2
                  : tl == 'debug'
                      ? 3
                      : 0;
        }

        // Transform test_order to uppercase
        settings['test_order'] =
            (settings['test_order'] as String).toUpperCase();
      } catch (e) {
        twarn(
            "Possible error in custom test settings. Some settings might not have been applied. Exception: $e");
      }

      // Run the tests
      tverb(jsonEncode(settings));
      test_pointer = 0;
      bool iRun = false, dRun = false, uRun = false, pRun = false;

      void runNextTest() {
        if (testState == 5) return;
        if (test_pointer >= (settings['test_order'] as String).length) {
          // Test is finished
          if ((settings['telemetry_level'] as int) > 0) {
            sendTelemetry((id) {
              testState = 4;
              if (id != null) testId = id;
            });
          } else {
            testState = 4;
          }
          return;
        }

        String testChar = (settings['test_order'] as String)
            .substring(test_pointer, test_pointer + 1);
        switch (testChar) {
          case "I":
            test_pointer++;
            if (iRun) {
              runNextTest();
              return;
            } else {
              iRun = true;
            }
            getIp(runNextTest);
            break;
          case "D":
            test_pointer++;
            if (dRun) {
              runNextTest();
              return;
            } else {
              dRun = true;
            }
            testState = 1;
            dlTest(runNextTest);
            break;
          case "U":
            test_pointer++;
            if (uRun) {
              runNextTest();
              return;
            } else {
              uRun = true;
            }
            testState = 3;
            ulTest(runNextTest);
            break;
          case "P":
            test_pointer++;
            if (pRun) {
              runNextTest();
              return;
            } else {
              pRun = true;
            }
            testState = 2;
            pingTest(runNextTest);
            break;
          case "_":
            test_pointer++;
            Future.delayed(Duration(seconds: 1), () {
              runNextTest();
            });
            break;
          default:
            test_pointer++;
        }
      }

      runNextTest();
    }

    if (params[0] == "abort") {
      // Abort command
      if (testState >= 4) return;
      tlog("manually aborted");
      clearRequests(); // Stop all HTTP activity
      if (interval != null) interval!.cancel(); // Clear timer if present
      if ((settings['telemetry_level'] as int) > 1) sendTelemetry((_) {});
      testState = 5; // Set test as aborted
      dlStatus = "";
      ulStatus = "";
      pingStatus = "";
      jitterStatus = "";
      clientIp = "";
      dlProgress = 0;
      ulProgress = 0;
      pingProgress = 0;
    }
  });
}

// Stops all HTTP requests aggressively
void clearRequests() {
  tverb("stopping pending HTTP requests");
  if (xhr != null) {
    for (var x in xhr!) {
      try {
        x.onProgress.listen(null);
        x.onLoad.listen(null);
        x.onError.listen(null);
      } catch (e) {}
      try {
        x.upload.onProgress.listen(null);
        x.upload.onLoad.listen(null);
        x.upload.onError.listen(null);
      } catch (e) {}
      try {
        x.abort();
      } catch (e) {}
    }
    xhr = null;
  }
}

// Gets client's IP using url_getIp, then calls the done function
bool ipCalled = false; // Used to prevent multiple accidental calls to getIp
dynamic ispInfo = ""; // Used for telemetry
void getIp(void Function() done) {
  tverb("getIp");
  if (ipCalled) return;
  ipCalled = true; // getIp already called?
  int startT = DateTime.now().millisecondsSinceEpoch;
  HttpRequest x = HttpRequest();

  x.onLoad.listen((_) {
    tlog(
        "IP: ${x.responseText}, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
    try {
      var data = jsonDecode(x.responseText!);
      clientIp = data['processedString'] as String;
      ispInfo = data['rawIspInfo'];
    } catch (e) {
      clientIp = x.responseText!;
      ispInfo = "";
    }
    done();
  });

  x.onError.listen((_) {
    tlog(
        "getIp failed, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
    done();
  });

  String url =
      "${settings['url_getIp'] as String}${url_sep(settings['url_getIp'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}${(settings['getIp_ispInfo'] as bool) ? "isp=true${settings['getIp_ispInfo_distance'] != null ? "&distance=${settings['getIp_ispInfo_distance']}" : ""}&" : "&"}r=${Random().nextDouble()}";

  x.open('GET', url, async: true);
  x.send();
}

// Download test, calls done function when it's over
bool dlCalled = false; // Used to prevent multiple accidental calls to dlTest
void dlTest(void Function() done) {
  tverb("dlTest");
  if (dlCalled) return;
  dlCalled = true; // dlTest already called?
  double totLoaded = 0.0; // Total number of loaded bytes
  int startT =
      DateTime.now().millisecondsSinceEpoch; // Timestamp when test was started
  double bonusT = 0; // How many milliseconds the test has been shortened by
  bool graceTimeDone = false; // Set to true after the grace time is past
  bool failed = false; // Set to true if a stream fails
  xhr = [];

  // Function to create a download stream
  void testStream(int i, int delay) {
    Future.delayed(Duration(milliseconds: 1 + delay), () {
      if (testState != 1)
        return; // Delayed stream ended up starting after the end of the download test
      tverb("dl test stream started $i $delay");
      double prevLoaded =
          0; // Number of bytes loaded last time onprogress was called
      HttpRequest x = HttpRequest();
      xhr!.add(x);

      x.onProgress.listen((event) {
        tverb("dl stream progress event $i ${event.loaded}");
        if (testState != 1) {
          try {
            x.abort();
          } catch (e) {}
        }
        // Progress event, add number of new loaded bytes to totLoaded
        double loadDiff = event.loaded! <= 0 ? 0 : event.loaded! - prevLoaded;
        if (loadDiff.isNaN || !loadDiff.isFinite || loadDiff < 0) return;
        totLoaded += loadDiff;
        prevLoaded = event.loaded!.toDouble();
      });

      x.onLoad.listen((_) {
        // The large file has been loaded entirely, start again
        tverb("dl stream finished $i");
        try {
          x.abort();
        } catch (e) {}
        testStream(i, 0);
      });

      x.onError.listen((_) {
        // Error
        tverb("dl stream failed $i");
        if (settings['xhr_ignoreErrors'] == 0) failed = true; // Abort
        try {
          x.abort();
        } catch (e) {}
        xhr!.remove(x);
        if (settings['xhr_ignoreErrors'] == 1)
          testStream(i, 0); // Restart stream
      });

      // Send HTTP request
      try {
        if ((settings['xhr_dlUseBlob'] as bool))
          x.responseType = 'blob';
        else
          x.responseType = 'arraybuffer';
      } catch (e) {}

      String url =
          "${settings['url_dl'] as String}${url_sep(settings['url_dl'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}r=${Random().nextDouble()}&ckSize=${settings['garbagePhp_chunkSize']}";

      x.open('GET', url, async: true);
      x.send();
    });
  }

  // Open streams
  for (int i = 0; i < (settings['xhr_dlMultistream'] as int); i++) {
    testStream(i, (settings['xhr_multistreamDelay'] as int) * i);
  }

  // Every 200ms, update dlStatus
  interval = Timer.periodic(Duration(milliseconds: 200), (timer) {
    tverb("DL: $dlStatus${graceTimeDone ? "" : " (in grace time)"}");
    int t = DateTime.now().millisecondsSinceEpoch - startT;
    if (graceTimeDone) {
      dlProgress =
          ((t + bonusT) / ((settings['time_dl_max'] as int) * 1000)).toDouble();
    }
    if (t < 200) {
      return;
    }
    if (!graceTimeDone) {
      if (t > 1000 * (settings['time_dlGraceTime'] as int)) {
        if (totLoaded > 0) {
          // If the connection is so slow that we didn't get a single chunk yet, do not reset
          startT = DateTime.now().millisecondsSinceEpoch;
          bonusT = 0;
          totLoaded = 0.0;
        }
        graceTimeDone = true;
      }
    } else {
      double speed = totLoaded / (t / 1000.0);
      if ((settings['time_auto'] as bool)) {
        // Decide how much to shorten the test
        double bonus = (5.0 * speed) / 100000;
        bonusT += bonus > 400 ? 400 : bonus;
      }
      // Update status
      dlStatus =
          ((speed * 8 * (settings['overheadCompensationFactor'] as num)) /
                  (settings['useMebibits'] as bool ? 1048576 : 1000000))
              .toStringAsFixed(2);
      if (((t + bonusT) / 1000.0) > (settings['time_dl_max'] as int) ||
          failed) {
        // Test is over, stop streams and timer
        if (failed || dlStatus == 'NaN') dlStatus = "Fail";
        clearRequests();
        interval!.cancel();
        dlProgress = 1;
        tlog(
            "dlTest: $dlStatus, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
        done();
      }
    }
  });
}

// Upload test, calls done function when it's over
bool ulCalled = false; // Used to prevent multiple accidental calls to ulTest
void ulTest(void Function() done) {
  tverb("ulTest");
  if (ulCalled) return;
  ulCalled = true; // ulTest already called?

  // Garbage data for upload test
  List<Uint8List> req = [];
  int maxInt = pow(2, 32) - 1 as int;
  Uint8List r = Uint8List(1048576);

  for (int i = 0; i < r.length; i++) {
    r[i] = Random().nextInt(maxInt);
  }

  for (var i = 0; i < (settings['xhr_ul_blob_megabytes'] as int); i++) {
    req.add(r);
  }

  Blob reqBlob = Blob(req);

  Uint8List rSmall = Uint8List(262144);
  for (int i = 0; i < rSmall.length; i++) {
    rSmall[i] = Random().nextInt(maxInt);
  }

  Blob reqSmallBlob = Blob([rSmall]);

  void testFunction() {
    double totLoaded = 0.0; // Total number of transmitted bytes
    int startT = DateTime.now()
        .millisecondsSinceEpoch; // Timestamp when test was started
    double bonusT = 0; // How many milliseconds the test has been shortened by
    bool graceTimeDone = false; // Set to true after the grace time is past
    bool failed = false; // Set to true if a stream fails
    xhr = [];

    // Function to create an upload stream
    void testStream(int i, int delay) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (testState != 3)
          return; // Delayed stream ended up starting after the end of the upload test
        tverb("ul test stream started $i $delay");
        double prevLoaded =
            0; // Number of bytes transmitted last time onprogress was called
        HttpRequest x = HttpRequest();
        xhr!.add(x);

        bool ie11workaround = (settings['forceIE11Workaround'] as bool);
        if (!ie11workaround) {
          try {
            x.upload.onProgress.listen((_) {});
            ie11workaround = false;
          } catch (e) {
            ie11workaround = true;
          }
        }

        if (ie11workaround) {
          // IE11 workaround
          x.onLoad.listen((_) {
            tverb("ul stream progress event (ie11wa)");
            totLoaded += reqSmallBlob.size;
            testStream(i, 0);
          });

          x.open("POST",
              "${settings['url_ul'] as String}${url_sep(settings['url_ul'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}r=${Random().nextDouble()}",
              async: true);
          try {
            x.setRequestHeader("Content-Encoding", "identity");
          } catch (e) {
            // ignore
          }
          x.send(reqSmallBlob);
        } else {
          // Regular version
          x.upload.onProgress.listen((event) {
            tverb("ul stream progress event $i ${event.loaded}");
            if (testState != 3) {
              try {
                x.abort();
              } catch (e) {
                // ignore
              }
            }
            // Progress event, add number of new loaded bytes to totLoaded
            double loadDiff =
                event.loaded! <= 0 ? 0 : event.loaded! - prevLoaded;
            if (loadDiff.isNaN || !loadDiff.isFinite || loadDiff < 0) return;
            totLoaded += loadDiff;
            prevLoaded = event.loaded!.toDouble();
          });

          x.upload.onLoad.listen((_) {
            // Stream sent all the garbage data, start again
            tverb("ul stream finished $i");
            testStream(i, 0);
          });

          x.upload.onError.listen((_) {
            tverb("ul stream failed $i");
            if (settings['xhr_ignoreErrors'] == 0) failed = true; // Abort
            try {
              x.abort();
            } catch (e) {
              // ignore
            }
            xhr!.remove(x);
            if ((settings['xhr_ignoreErrors'] as int) == 1) {
              testStream(i, 0); // Restart stream
            }
          });

          // Send HTTP request
          x.open("POST",
              "${settings['url_ul'] as String}${url_sep(settings['url_ul'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}r=${Random().nextDouble()}",
              async: true);
          try {
            x.setRequestHeader("Content-Encoding", "identity");
          } catch (e) {
            // ignore
          }
          x.send(reqBlob);
        }
      });
    }

    // Open streams
    for (int i = 0; i < (settings['xhr_ulMultistream'] as int); i++) {
      testStream(i, (settings['xhr_multistreamDelay'] as int) * i);
    }

    // Every 200ms, update ulStatus
    interval = Timer.periodic(Duration(milliseconds: 200), (timer) {
      tverb("UL: $ulStatus${graceTimeDone ? "" : " (in grace time)"}");
      int t = DateTime.now().millisecondsSinceEpoch - startT;
      if (graceTimeDone)
        ulProgress = ((t + bonusT) / ((settings['time_ul_max'] as int) * 1000))
            .toDouble();
      if (t < 200) return;
      if (!graceTimeDone) {
        if (t > 1000 * (settings['time_ulGraceTime'] as int)) {
          if (totLoaded > 0) {
            // If the connection is so slow that we didn't get a single chunk yet, do not reset
            startT = DateTime.now().millisecondsSinceEpoch;
            bonusT = 0;
            totLoaded = 0.0;
          }
          graceTimeDone = true;
        }
      } else {
        double speed = totLoaded / (t / 1000.0);
        if ((settings['time_auto'] as bool)) {
          // Decide how much to shorten the test
          double bonus = (5.0 * speed) / 100000;
          bonusT += bonus > 400 ? 400 : bonus;
        }
        // Update status
        ulStatus =
            ((speed * 8 * (settings['overheadCompensationFactor'] as num)) /
                    (settings['useMebibits'] as bool ? 1048576 : 1000000))
                .toStringAsFixed(2);
        if (((t + bonusT) / 1000.0) > (settings['time_ul_max'] as int) ||
            failed) {
          // Test is over, stop streams and timer
          if (failed || ulStatus == 'NaN') ulStatus = "Fail";
          clearRequests();
          interval!.cancel();
          ulProgress = 1;
          tlog(
              "ulTest: $ulStatus, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
          done();
        }
      }
    });
  }

  if ((settings['mpot'] as bool)) {
    tverb("Sending POST request before performing upload test");
    xhr = [];
    HttpRequest x = HttpRequest();

    x.onLoad.listen((_) {
      tverb("POST request sent, starting upload test");
      testFunction();
    });

    x.onError.listen((_) {
      tverb("Failed to send initial POST request");
      testFunction();
    });

    x.open("POST", settings['url_ul'] as String);
    x.send();
  } else {
    testFunction();
  }
}

// Ping+jitter test, function done is called when it's over
bool ptCalled = false; // Used to prevent multiple accidental calls to pingTest
void pingTest(void Function() done) {
  tverb("pingTest");
  if (ptCalled) return;
  ptCalled = true; // pingTest already called?
  int startT =
      DateTime.now().millisecondsSinceEpoch; // When the test was started
  int? prevT; // Last time a pong was received
  double ping = 0.0; // Current ping value
  double jitter = 0.0; // Current jitter value
  int i = 0; // Counter of pongs received
  double prevInstspd = 0; // Last ping time, used for jitter calculation
  xhr = [];

  // Ping function
  void doPing() {
    tverb("ping");
    pingProgress = (i / (settings['count_ping'] as int)).toDouble();
    prevT = DateTime.now().millisecondsSinceEpoch;
    HttpRequest x = HttpRequest();
    xhr!.add(x);

    x.onLoad.listen((_) {
      // Pong
      tverb("pong");
      if (i == 0) {
        prevT = DateTime.now().millisecondsSinceEpoch; // First pong
      } else {
        int instspd = DateTime.now().millisecondsSinceEpoch - prevT!;
        if ((settings['ping_allowPerformanceApi'] as bool)) {
          // Attempt to get accurate timing using Performance API
          try {
            var entries = window.performance.getEntries();
            if (entries.isNotEmpty) {
              var p = entries.last;
              if (p is PerformanceResourceTiming) {
                double d =
                    ((p.responseStart ?? 0) - (p.requestStart ?? 0)).toDouble();
                if (d <= 0) d = (p.duration).toDouble();
                if (d > 0 && d < instspd) instspd = d.toInt();
              }
            }
          } catch (e) {
            // Fallback to estimate
            tverb("Performance API not supported, using estimate");
          }
        }

        if (instspd < 1) instspd = prevInstspd.toInt();
        if (instspd < 1) instspd = 1;
        double instjitter = (instspd - prevInstspd).abs();
        if (i == 1) {
          ping = instspd.toDouble();
        } else {
          if (instspd < ping) ping = instspd.toDouble();
          if (i == 2) {
            jitter = instjitter;
          } else {
            jitter = instjitter > jitter
                ? jitter * 0.3 + instjitter * 0.7
                : jitter * 0.8 + instjitter * 0.2;
          }
        }
        prevInstspd = instspd.toDouble();
      }
      pingStatus = ping.toStringAsFixed(2);
      jitterStatus = jitter.toStringAsFixed(2);
      i++;
      tverb("ping: $pingStatus jitter: $jitterStatus");
      if (i < (settings['count_ping'] as int)) {
        doPing();
      } else {
        pingProgress = 1;
        tlog(
            "ping: $pingStatus jitter: $jitterStatus, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
        done();
      }
    });

    x.onError.listen((_) {
      // A ping failed, cancel test
      tverb("ping failed");
      if (settings['xhr_ignoreErrors'] == 0) {
        // Abort
        pingStatus = "Fail";
        jitterStatus = "Fail";
        clearRequests();
        tlog(
            "ping test failed, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
        pingProgress = 1;
        done();
      }
      if (settings['xhr_ignoreErrors'] == 1) {
        doPing(); // Retry ping
      }
      if (settings['xhr_ignoreErrors'] == 2) {
        // Ignore failed ping
        i++;
        if (i < (settings['count_ping'] as int)) {
          doPing();
        } else {
          pingProgress = 1;
          tlog(
              "ping: $pingStatus jitter: $jitterStatus, took ${DateTime.now().millisecondsSinceEpoch - startT}ms");
          done();
        }
      }
    });

    // Send HTTP request
    x.open("GET",
        "${settings['url_ping'] as String}${url_sep(settings['url_ping'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}r=${Random().nextDouble()}",
        async: true);
    x.send();
  }

  doPing(); // Start first ping
}

// Telemetry
void sendTelemetry(void Function(String?) done) {
  if ((settings['telemetry_level'] as int) < 1) return;
  HttpRequest x = HttpRequest();

  x.onLoad.listen((_) {
    try {
      List<String> parts = x.responseText!.split(" ");
      if (parts[0] == "id") {
        try {
          String id = parts[1];
          done(id);
        } catch (e) {
          done(null);
        }
      } else {
        done(null);
      }
    } catch (e) {
      done(null);
    }
  });

  x.onError.listen((_) {
    print("TELEMETRY ERROR ${x.status}");
    done(null);
  });

  x.open("POST",
      "${settings['url_telemetry'] as String}${url_sep(settings['url_telemetry'] as String)}${settings['mpot'] as bool ? "cors=true&" : ""}r=${Random().nextDouble()}",
      async: true);

  Map<String, dynamic> telemetryIspInfo = {
    'processedString': clientIp,
    'rawIspInfo': ispInfo is Map ? ispInfo : ""
  };

  try {
    FormData fd = FormData();
    fd.append("ispinfo", jsonEncode(telemetryIspInfo));
    fd.append("dl", dlStatus);
    fd.append("ul", ulStatus);
    fd.append("ping", pingStatus);
    fd.append("jitter", jitterStatus);
    fd.append("log", (settings['telemetry_level'] as int) > 1 ? log : "");
    fd.append("extra", settings['telemetry_extra'] as String);
    x.send(fd);
  } catch (ex) {
    String postData =
        "extra=${Uri.encodeComponent(settings['telemetry_extra'] as String)}&ispinfo=${Uri.encodeComponent(jsonEncode(telemetryIspInfo))}&dl=${Uri.encodeComponent(dlStatus)}&ul=${Uri.encodeComponent(ulStatus)}&ping=${Uri.encodeComponent(pingStatus)}&jitter=${Uri.encodeComponent(jitterStatus)}&log=${Uri.encodeComponent((settings['telemetry_level'] as int) > 1 ? log : "")}";
    x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    x.send(postData);
  }
}
