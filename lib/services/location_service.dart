import 'dart:async';
import 'package:geolocator/geolocator.dart';

typedef OnPosition = void Function(Position pos);

class LocationService {
  StreamSubscription<Position>? _positionSub;

  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<void> startForegroundLocationStream(OnPosition onPosition) async {
    final ok = await requestPermission();
    if (!ok) throw Exception('Location permission denied');

    final settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // 5m 변화 마다 콜백
      // timeLimit: Duration(seconds: 5) // optional
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      onPosition(pos);
    });
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
  }
}
