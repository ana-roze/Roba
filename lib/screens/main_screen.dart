import 'package:flutter/material.dart';
import 'today_screen.dart';
import 'upcoming_screen.dart';
import 'inbox_screen.dart';
import 'chat_screen.dart';
import 'add_task_screen.dart';
import 'browse_screen.dart';
import 'groups_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/notification_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/cupertino.dart';

class MainScreen extends StatefulWidget {
  final int initialTab;
  final dynamic highlightTaskId;

  static bool isLoggingIn = false;

  const MainScreen({super.key, this.initialTab = 1, this.highlightTaskId});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  int refreshCounter = 0;

  late PageController _pageController;

  final GlobalKey<InboxScreenState> inboxKey = GlobalKey();
  final GlobalKey<TodayScreenState> todayKey = GlobalKey();
  final GlobalKey<UpcomingScreenState> upcomingKey = GlobalKey();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;

    _pageController = PageController(initialPage: widget.initialTab);

    NotificationService().syncGroupTopics();
    NotificationService().syncAllGroupTasksAlarms();

    _listenToAuthAndSession();
  }

  void _listenToAuthAndSession() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _sessionSubscription?.cancel();

      if (user != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();

        _sessionSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((snapshot) async {

          // 1. Stop checking if we are currently handling login
          if (MainScreen.isLoggingIn) return;

          // 2. Prevent cache issues:
          //    If this is a Firebase “pending writes” draft or not synced to cloud yet -> skip
          if (snapshot.metadata.hasPendingWrites) return;
          if (!snapshot.exists) return;

          var data = snapshot.data() as Map<String, dynamic>?;
          String? cloudSessionId = data?['currentSessionId'];
          String? localSessionId = prefs.getString('local_session_id');

          if (cloudSessionId != null && localSessionId != null && cloudSessionId != localSessionId) {
            // 🔥 Double check:
            // wait 1.5 seconds and force server reload to prevent cache “glitch” / false detection
            Future.delayed(const Duration(milliseconds: 1500), () async {
              if (!mounted) return;

              var doubleCheckSnap = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(const GetOptions(source: Source.server));

              String? latestCloudSession = doubleCheckSnap.data()?['currentSessionId'];

              // If after server cross-check the session ID still differs,
              // then confirm it as an intruder / unauthorized device
              if (latestCloudSession != null && latestCloudSession != localSessionId) {
                await _sessionSubscription?.cancel();
                _handleKickOut();
              }
            });
          }
        });
      }
    });
  }

  void _handleKickOut() async {
    await _authSubscription?.cancel();
    await _sessionSubscription?.cancel();

    // Clean up notifications and token before signing out
    await NotificationService().clearAllNotificationsOnLogout();
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: const Text(
            "Security Notice",
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Your account was signed in on a new device. This device will be signed out to keep your account secure.",
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const MainScreen(initialTab: 4)),
                  (route) => false,
                );
              },
              child: const Text(
                "AGREE",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _authSubscription?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  void openChat() {
    if (FirebaseAuth.instance.currentUser == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Text(
            "Login Required",
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "The AI Assistant feature is only available to logged-in members. Do you want to log in now?",
            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Not now", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () {
                Navigator.pop(context);
                _pageController.animateToPage(
                  4,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: const Text(
                "Log in",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatScreen()),
    ).then((value) {
      setState(() {
        refreshCounter++;
        inboxKey.currentState?.loadTasks();
        todayKey.currentState?.loadTasks();
        upcomingKey.currentState?.loadTasks();
      });
    });
  }

  void openAddTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );

    if (result == true) {
      inboxKey.currentState?.loadTasks();
      todayKey.currentState?.loadTasks();
      upcomingKey.currentState?.loadTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Widget> screens = [
      InboxScreen(
        key: inboxKey,
        highlightTaskId: _currentIndex == 0 ? widget.highlightTaskId : null,
      ),
      TodayScreen(
        key: todayKey,
        highlightTaskId: _currentIndex == 1 ? widget.highlightTaskId : null,
      ),
      UpcomingScreen(
        key: upcomingKey,
        highlightTaskId: _currentIndex == 2 ? widget.highlightTaskId : null,
      ),
      const GroupsScreen(),
      const BrowseScreen(),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children: screens,
      ),

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: "btnChatAI",
              backgroundColor: isDark ? Colors.blueAccent.shade700 : Colors.blue,
              onPressed: openChat,
              child: const Icon(Icons.smart_toy, color: Colors.white),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: "btnAddTask",
              backgroundColor: Theme.of(context).colorScheme.primary,
              onPressed: openAddTask,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (i) {
          _pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.tray),
            activeIcon: Icon(CupertinoIcons.tray_fill),
            label: "Inbox",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.sun_min),
            activeIcon: Icon(CupertinoIcons.sun_min_fill),
            label: "Today",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            activeIcon: Icon(CupertinoIcons.calendar_today),
            label: "Upcoming",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_3),
            activeIcon: Icon(CupertinoIcons.person_3_fill),
            label: "Groups",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_circle),
            activeIcon: Icon(CupertinoIcons.person_circle_fill),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
