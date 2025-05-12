import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';

void main() =>
    runApp(MaterialApp(home: RunMapPage(), debugShowCheckedModeBanner: false));

class RunMapPage extends StatefulWidget {
  @override
  _RunMapPageState createState() => _RunMapPageState();
}

class _RunMapPageState extends State<RunMapPage> {
  Completer<GoogleMapController> _mapController = Completer();
  List<LatLng> _points = [];
  bool _isRecording = false;
  Timer? _timer;
  DateTime _simulatedStartTime = DateTime(2025, 5, 11, 12, 0, 0); // 擬似スタート時間
  List<DateTime> _timestamps = [];
  int _fakeSecond = 0;
  DateTime? _endTime;
  double _distance = 0.0;
  Duration _duration = Duration.zero;
  bool _isPaused = false;
  List<Map<String, dynamic>> _laps = [];
  int _cameraUpdateCounter = 0;
  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    await Permission.location.request();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _distance = 0.0;
      _duration = Duration.zero;
      _points.clear();
      _timestamps.clear();
      _laps.clear();
      _fakeSecond = 0;
    });

    _timer = Timer.periodic(Duration(milliseconds: 500), (_) async {
      final pos = await Geolocator.getCurrentPosition();
      final latlng = LatLng(pos.latitude, pos.longitude);
      final simulatedTime = _simulatedStartTime.add(
        Duration(seconds: _fakeSecond++),
      );

      _points.add(latlng);
      _timestamps.add(simulatedTime);

      if (++_cameraUpdateCounter % 2 == 0) {
        _moveCameraTo(latlng);
      }

      setState(() {
        if (_points.length > 1) {
          _distance += Geolocator.distanceBetween(
            _points[_points.length - 2].latitude,
            _points[_points.length - 2].longitude,
            latlng.latitude,
            latlng.longitude,
          );
        }
        _duration = simulatedTime.difference(_simulatedStartTime);
      });
    });
  }

  void _pauseRecording() {
    _timer?.cancel();
    setState(() => _isPaused = true);
  }

  void _stopRecording() {
    _timer?.cancel();
    _isRecording = false;
  }

  void _resumeRecording() {
    _timer = Timer.periodic(Duration(milliseconds: 500), (_) async {
      final pos = await Geolocator.getCurrentPosition();
      final latlng = LatLng(pos.latitude, pos.longitude);
      final simulatedTime = _simulatedStartTime.add(
        Duration(seconds: _fakeSecond++),
      );

      _points.add(latlng);
      _timestamps.add(simulatedTime);

      if (++_cameraUpdateCounter % 2 == 0) {
        _moveCameraTo(latlng);
      }

      setState(() {
        if (_points.length > 1) {
          _distance += Geolocator.distanceBetween(
            _points[_points.length - 2].latitude,
            _points[_points.length - 2].longitude,
            latlng.latitude,
            latlng.longitude,
          );
        }
        _duration = simulatedTime.difference(_simulatedStartTime);
      });
    });
    setState(() => _isPaused = false);
  }

  void _recordLap() {
    setState(() {
      _laps.add({"time": _duration, "distance": _distance});
    });
  }

  String _formatDuration(Duration d) {
    return d.toString().split('.').first.padLeft(8, "0");
  }

  String _formatPace() {
    if (_distance == 0) return "0:00";
    final paceSec = _duration.inSeconds / (_distance / 1000);
    final min = (paceSec ~/ 60).toString();
    final sec = (paceSec % 60).toInt().toString().padLeft(2, "0");
    return "$min:$sec /km";
  }

  Set<Polyline> _buildPolyline() => {
    Polyline(
      polylineId: PolylineId("run"),
      points: _points,
      color: Colors.blue,
      width: 5,
    ),
  };
  Future<void> _moveCameraTo(LatLng target) async {
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 17)),
    );
  }

  Future<void> _saveRoute() async {
    if (_timestamps.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final routes = prefs.getStringList('routes') ?? [];

    final routeData = {
      "points":
          _points.map((p) => {"lat": p.latitude, "lng": p.longitude}).toList(),
      "start": _timestamps.first.toIso8601String(),
      "end": _endTime!.toIso8601String(),
      "distance": _distance,
    };

    routes.add(jsonEncode(routeData));
    await prefs.setStringList('routes', routes);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("ルートを保存しました")));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("ランニング中")),
    body: Column(
      children: [
        // 📊 距離・時間・ペース表示
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                "距離: ${(_distance / 1000).toStringAsFixed(2)} km",
                style: TextStyle(fontSize: 20),
              ),
              Text(
                "時間: ${_formatDuration(_duration)}",
                style: TextStyle(fontSize: 20),
              ),
              Text("ペース: ${_formatPace()}", style: TextStyle(fontSize: 20)),
            ],
          ),
        ),

        // 🗺️ Google Map
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target:
                  _points.isNotEmpty
                      ? _points.last
                      : LatLng(37.4219, -122.0840),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            polylines: _buildPolyline(),
            onMapCreated: (controller) => _mapController.complete(controller),
          ),
        ),

        // 🎮 操作ボタン
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
          child: Wrap(
            spacing: 8.0, // 横の間隔
            runSpacing: 8.0, // 縦の間隔（折り返し行）
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _isRecording ? null : _startRecording,
                child: Text("スタート"),
              ),
              ElevatedButton(
                onPressed: _isRecording ? _stopRecording : null,
                child: Text("ストップ"),
              ),
              ElevatedButton(
                onPressed:
                    !_isRecording && _points.isNotEmpty ? _saveRoute : null,
                child: Text("保存"),
              ),
              ElevatedButton(
                onPressed:
                    _isRecording
                        ? (_isPaused ? _resumeRecording : _pauseRecording)
                        : null,
                child: Text(_isPaused ? "再開" : "一時停止"),
              ),
              ElevatedButton(
                onPressed: _isRecording && !_isPaused ? _recordLap : null,
                child: Text("ラップ"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RunHistoryPage()),
                  );
                },
                child: Text("履歴"),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class RunHistoryPage extends StatelessWidget {
  Future<List<Map<String, dynamic>>> _loadRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('routes') ?? [];

    List<Map<String, dynamic>> result = [];

    for (final jsonStr in saved) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } catch (e) {
        print("読み込み失敗: $e");
      }
    }

    return result;
  }

  String _formatDuration(String startStr, String endStr) {
    final start = DateTime.parse(startStr);
    final end = DateTime.parse(endStr);
    final duration = end.difference(start);
    return duration.toString().split('.').first;
  }

  Future<void> _exportCSV(
    BuildContext context,
    List<Map<String, dynamic>> routes,
  ) async {
    final dir = await getApplicationDocumentsDirectory();

    for (int i = 0; i < routes.length; i++) {
      final r = routes[i];
      final points =
          (r['points'] as List).map((e) => LatLng(e['lat'], e['lng'])).toList();
      final start = DateTime.parse(r['start']);
      final rows = <List<dynamic>>[];
      rows.add(["index", "latitude", "longitude", "timestamp"]);

      for (int j = 0; j < points.length; j++) {
        final p = points[j];
        final timestamp = start.add(Duration(seconds: j * 3));
        rows.add([j, p.latitude, p.longitude, timestamp.toIso8601String()]);
      }

      final csvData = const ListToCsvConverter().convert(rows);
      final file = File("${dir.path}/run_log_$i.csv");
      await file.writeAsString(csvData);
      print("✅ 書き出しました: ${file.path}");
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("CSV保存済み（${routes.length}件）")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("履歴一覧")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadRoutes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text("履歴がありません"));
          }

          final routes = snapshot.data!;
          return ListView.builder(
            itemCount: routes.length,
            itemBuilder: (_, index) {
              final r = routes[index];
              final dist = (r['distance'] / 1000).toStringAsFixed(2);
              final time = _formatDuration(r['start'], r['end']);
              return ListTile(
                title: Text("ラン ${index + 1}"),
                subtitle: Text("距離: ${dist} km  時間: $time"),
                onTap: () {
                  final points =
                      (r['points'] as List)
                          .map((e) => LatLng(e['lat'], e['lng']))
                          .toList();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ViewRoutePage(points)),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final routes = await _loadRoutes();
          if (routes.isNotEmpty) {
            await _exportCSV(context, routes);
          }
        },
        label: Text("CSV出力"),
        icon: Icon(Icons.download),
      ),
    );
  }
}

class ViewRoutePage extends StatelessWidget {
  final List<LatLng> points;

  ViewRoutePage(this.points);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("ルート再生")),
    body: GoogleMap(
      initialCameraPosition: CameraPosition(target: points.first, zoom: 16),
      polylines: {
        Polyline(
          polylineId: PolylineId("route"),
          points: points,
          color: Colors.red,
          width: 5,
        ),
      },
    ),
  );
}
