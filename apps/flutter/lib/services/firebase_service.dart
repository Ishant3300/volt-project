import 'dart:convert';
import 'dart:developer';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  log('📩 [FCM] Background message: ${message.messageId}');
}

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize Firebase Messaging. Call after Firebase.initializeApp().
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Request permission (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    log('🔔 [FCM] Permission: ${settings.authorizationStatus}');

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'stocker_trades',
      'Trade Notifications',
      description: 'Notifications for trade executions and updates',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Initialize local notifications plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Handle notification tap when app was terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedApp(initialMessage);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      log('🔄 [FCM] Token refreshed');
      _registerTokenWithBackend(newToken);
    });
  }

  /// Get FCM token and register with backend
  Future<void> registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        log('📲 [FCM] Token: ${token.substring(0, 20)}...');
        await _registerTokenWithBackend(token);
      }
    } catch (e) {
      log('❌ [FCM] Error getting token: $e');
    }
  }

  /// Remove FCM token from backend (call on logout)
  Future<void> unregisterToken() async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) return;

      final authToken = await SecureStorageService().getToken();
      if (authToken == null) return;

      await ApiService(backendUrl).delete(
        '/auth/fcm-token',
        token: authToken,
        body: {'fcm_token': fcmToken},
      );
      log('🗑️ [FCM] Token unregistered from backend');
    } catch (e) {
      log('⚠️  [FCM] Error unregistering token: $e');
    }
  }

  Future<void> _registerTokenWithBackend(String fcmToken) async {
    try {
      final authToken = await SecureStorageService().getToken();
      if (authToken == null) return;

      await ApiService(backendUrl).post(
        '/auth/fcm-token',
        {'fcm_token': fcmToken},
        token: authToken,
      );
      log('✅ [FCM] Token registered with backend');
    } catch (e) {
      log('⚠️  [FCM] Error registering token: $e');
    }
  }

  /// Show a local notification when a message arrives in the foreground
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'stocker_trades',
          'Trade Notifications',
          channelDescription: 'Notifications for trade executions and updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    log('📱 [FCM] Notification tapped: ${message.data}');
    // Deep linking can be added here in the future
  }

  void _onNotificationTap(NotificationResponse response) {
    log('📱 [FCM] Local notification tapped: ${response.payload}');
    // Deep linking can be added here in the future
  }
}
