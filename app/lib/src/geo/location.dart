import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';

/// Testes: posição fixa (ou nula para "sem localização"), sem GPS.
@visibleForTesting
bool locationFakeForTests = false;
@visibleForTesting
(double, double)? locationForTests;

/// Posição aproximada do aparelho (precisão baixa, só o necessário). Usada no
/// feed regional e ao postar para a região: o servidor arredonda para uma
/// célula de ~500 m e não guarda a posição de quem lê.
Future<(double, double)> approxLocation() async {
  if (locationFakeForTests) {
    final l = locationForTests;
    if (l == null) throw const ApiException('location_unavailable');
    return l;
  }
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException('location_unavailable');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw const ApiException('location_unavailable');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return (p.latitude, p.longitude);
  } on ApiException {
    rethrow;
  } catch (_) {
    throw const ApiException('location_unavailable');
  }
}
