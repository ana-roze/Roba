import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/main_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/private_chat_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔥 Global variable managing Light/Dark mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Received background notification: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Read saved Theme state from the device
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isDark = prefs.getBool('isDarkTheme') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // BLOCKER: FORCE APP TO WAIT FOR FIREBASE TO FINISH READING AUTH STATE
  await FirebaseAuth.instance.authStateChanges().first;

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    NotificationService().handleRouting(message.data);
  });

  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      Future.delayed(const Duration(seconds: 1), () {
        NotificationService().handleRouting(message.data);
      });
    }
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    if (message.notification != null) {
      String? type = message.data['type'];
      String? incomingGroupId = message.data['groupId'];
      String? incomingChatId = message.data['chatId'];

      NotificationService().syncAllGroupTasksAlarms();

      if (incomingGroupId != null && incomingGroupId == GroupDetailScreen.currentActiveGroupId) return;
      if (incomingChatId != null && incomingChatId == PrivateChatScreen.currentActivePrivateChatId) return;

      if (incomingChatId != null) {
        bool isMuted = prefs.getBool('mute_chat_$incomingChatId') ?? false;
        if (isMuted) return;
      }
      if (incomingGroupId != null) {
        bool isMuted = prefs.getBool('mute_group_$incomingGroupId') ?? false;
        if (isMuted) return;
      }

      NotificationService().showInstantNotification(
        id: DateTime.now().millisecond,
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        type: type,
        groupId: incomingGroupId,
        tabIndex: int.tryParse(message.data['tabIndex']?.toString() ?? '0') ?? 0,
        taskId: message.data['taskId'] != null ? int.tryParse(message.data['taskId'].toString()) : null,
        privateChatId: incomingChatId,
        privateChatTargetUid: message.data['targetUid'],
        privateChatTargetName: message.data['targetName'],
      );
    }
  });

  await NotificationService().init(navigatorKey);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to real-time Theme changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'AI Todo App',
          navigatorKey: navigatorKey,
          themeMode: currentMode,

          // 🔥 LIGHT MODE
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.redAccent,
              brightness: Brightness.light,
              surface: const Color(0xFFF8F9FA), // Elegant off-white background
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: Colors.redAccent,
              unselectedItemColor: Colors.grey,
            ),
          ),

          // 🔥 DARK MODE
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.redAccent,
              brightness: Brightness.dark,
              surface: const Color(0xFF121212), // Standard OLED black
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white12),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E1E1E),
              selectedItemColor: Colors.redAccent,
              unselectedItemColor: Colors.white54,
            ),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}