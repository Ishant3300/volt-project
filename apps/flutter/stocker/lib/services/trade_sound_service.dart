import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class TradeSoundService {
  static final TradeSoundService _instance = TradeSoundService._();
  factory TradeSoundService() => _instance;
  TradeSoundService._();

  final AudioPlayer _player = AudioPlayer();

  /// Checks backend trading_sound setting, plays bell if enabled.
  Future<void> playIfEnabled() async {
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl)
          .get('/auth/notification-settings', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final ns = data['data']?['notification_settings'];
        if (ns != null && ns['trading_sound'] == true) {
          await _player.play(AssetSource('trade_bell_sound.mp3'));
        }
      }
    } catch (_) {}
  }
}
