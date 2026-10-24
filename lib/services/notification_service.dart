import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/main_screen.dart';
import '../screens/group_detail_screen.dart';
import '../screens/private_chat_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  GlobalKey<NavigatorState>? navKey;
  final List<String> _subscribedGroupTopics = [];

  static dynamic lastFlashedTaskId;

  // 🔥 NEW FEATURE: CLEAR ALL NOTIFICATION TRACES, UNSUBSCRIBE FROM TOPICS AND TOKENS ON LOGOUT
  Future<void> clearAllNotificationsOnLogout() async {
    try {
      // 1. Turn off all local alarms
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin.cancelAll();

      // 2. 🔥 ROOT OUT: UNSUBSCRIBE FROM PERSONAL AND ALL GROUP TOPICS
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic('user_${currentUser.uid}');
        } catch (e) {
          debugPrint("Error unsubscribing from personal topic: $e");
        }
      }

      for (String groupId in _subscribedGroupTopics) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');
        } catch (e) {
          debugPrint("Error unsubscribing from group topic: $e");
        }
      }
      _subscribedGroupTopics.clear();

      // 3. Sever Push Notification connection from Google Server
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (e) {
        debugPrint("Error deleting FCM Token: $e");
      }

      // 4. Clear SharedPreferences cache but KEEP Dark Mode settings
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_session_id');
      await prefs.remove('scheduled_group_tasks');

      final keys = prefs.getKeys();
      for (String key in keys) {
        if (key.startsWith('mute_group_') || key.startsWith('mute_chat_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint("Error cleaning up notifications: $e");
    }
  }

  Future<void> handleRouting(Map<String, dynamic> data) async {
    if (navKey?.currentState == null) return;

    String? type = data["type"];
    int? taskId;
    if (data["taskId"] != null) taskId = int.tryParse(data["taskId"].toString());

    if (type == 'private_chat' || (data['chatId'] != null && data['groupId'] == null)) {
      navKey!.currentState!.push(MaterialPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: data['chatId'] ?? '', 
            targetUid: data['targetUid'] ?? '', 
            targetName: data['targetName'] ?? 'Message'
          )
      ));
      return;
    }

    bool isGroup = data["isGroup"] == true || data["isGroup"] == 'true';
    String? groupId = data["groupId"];
    int tabIndex = int.tryParse(data["tabIndex"]?.toString() ?? '1') ?? 1;

    if ((isGroup || type == 'chat' || type == 'task') && groupId != null) {
      try {
        var groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
          navKey!.currentState!.push(MaterialPageRoute(
              builder: (_) => GroupDetailScreen(
                groupData: {...groupDoc.data()!, 'id': groupDoc.id}, 
                currentUserId: myUid, 
                initialTabIndex: tabIndex, 
                highlightTaskId: taskId
              )
          ));
        }
      } catch(e) { debugPrint("Error opening group: $e"); }
    } else if (taskId != null) {
      navKey!.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainScreen(initialTab: 1, highlightTaskId: taskId)), 
        (route) => false
      );
    }
  }

  Future<void> sendFriendRequestNotification(String targetUid, String myName) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUid': targetUid, 
        'title': 'Friend Request', 
        'body': '$myName wants to connect with you', 
        'type': 'friend_request', 
        'timestamp': FieldValue.serverTimestamp()
      });
    } catch (e) { debugPrint("Error sending friend request notification: $e"); }
  }

  Future<void> syncGroupTopics() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      // Always subscribe to personal topic on app launch
      await FirebaseMessaging.instance.subscribeToTopic('user_${user.uid}');

      FirebaseFirestore.instance.collection('groups').where('members', arrayContains: user.uid).snapshots().listen((snapshot) async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        List<String> currentGroups = [];

        for (var doc in snapshot.docs) {
          String groupId = doc.id;
          currentGroups.add(groupId);

          bool isMuted = prefs.getBool('mute_group_$groupId') ?? false;
          if (!isMuted && !_subscribedGroupTopics.contains(groupId)) {
            await FirebaseMessaging.instance.subscribeToTopic('group_$groupId');
            _subscribedGroupTopics.add(groupId);
          }
        }

        List<String> toRemove = [];
        for (String oldGroupId in _subscribedGroupTopics) {
          if (!currentGroups.contains(oldGroupId)) {
            await FirebaseMessaging.instance.unsubscribeFromTopic('group_$oldGroupId');
            toRemove.add(oldGroupId);
          }
        }
        _subscribedGroupTopics.removeWhere((id) => toRemove.contains(id));
      });
    } catch (e) { debugPrint("Error subscribing to notifications: $e"); }
  }

  Future<void> syncAllGroupTasksAlarms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> oldTaskHashes = prefs.getStringList('scheduled_group_tasks') ?? [];
      List<String> currentTaskHashes = [];

      var groupsSnapshot = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: user.uid).get();

      for (var groupDoc in groupsSnapshot.docs) {
        String groupId = groupDoc.id;
        String groupName = groupDoc.data()['name'] ?? 'Group';

        var tasksSnapshot = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').where('isCompleted', isEqualTo: false).get();

        for (var taskDoc in tasksSnapshot.docs) {
          var task = taskDoc.data();
          DateTime time = DateTime.parse(task['datetime']);

          if (time.isAfter(DateTime.now())) {
            int safeId = taskDoc.id.hashCode & 0x7fffffff;
            currentTaskHashes.add(safeId.toString());

            String title = "$groupName Schedule: ${task['title']}";
            String desc = task['description'] ?? '';
            String repeat = task['repeatMode'] ?? 'NONE';
            int remindBefore = task['remindBeforeMins'] ?? 0;

            if (repeat == "NONE") {
              await scheduleNotification(safeId, title, time, description: desc, isGroup: true, groupId: groupId);
            } else {
              await scheduleRepeatingNotification(safeId, title, time, repeat: repeat, description: desc, isGroup: true, groupId: groupId);
            }

            if (remindBefore > 0 && repeat == "NONE") {
              DateTime remindTime = time.subtract(Duration(minutes: remindBefore));
              await scheduleNotification(safeId * 10 + 1, "Upcoming: $title", remindTime, description: desc, isGroup: true, groupId: groupId);
            }
          }
        }
      }

      for (String oldHash in oldTaskHashes) {
        if (!currentTaskHashes.contains(oldHash)) await cancelTask(int.parse(oldHash));
      }
      await prefs.setStringList('scheduled_group_tasks', currentTaskHashes);

    } catch (e) { debugPrint("Error syncing group alarms: $e"); }
  }

  Future<void> init([GlobalKey<NavigatorState>? key]) async {
    if (_isInitialized) return;
    if (key != null) navKey = key;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);

    await _plugin.initialize(settings: initSettings, onDidReceiveNotificationResponse: _onNotificationTap);

    const AndroidNotificationChannel todoChannel = AndroidNotificationChannel(
      'todo_channel', 
      'Todo Reminder', 
      description: 'Todo Reminder', 
      importance: Importance.max
    );
    const AndroidNotificationChannel groupChannel = AndroidNotificationChannel(
      'group_channel', 
      'Group Notifications', 
      description: 'Group message and schedule notifications', 
      importance: Importance.max, 
      playSound: true, 
      enableVibration: true
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(todoChannel);
      await androidImpl.createNotificationChannel(groupChannel);
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }
    _isInitialized = true;
  }

  Future<void> _onNotificationTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null) return;
    final data = jsonDecode(payload);
    await handleRouting(data);
  }

  Future<void> showInstantNotification({
    required int id, 
    required String title, 
    required String body, 
    String? type, 
    String? groupId, 
    int tabIndex = 0, 
    int? taskId, 
    String? privateChatId, 
    String? privateChatTargetUid, 
    String? privateChatTargetName
  }) async {
    try {
      await init();
      final payload = jsonEncode({
        "type": type, 
        "isGroup": groupId != null, 
        "groupId": groupId, 
        "tabIndex": tabIndex, 
        "taskId": taskId, 
        "chatId": privateChatId, 
        "targetUid": privateChatTargetUid, 
        "targetName": privateChatTargetName
      });
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'group_channel', 
        'Group Notifications', 
        importance: Importance.max, 
        priority: Priority.high
      );
      await _plugin.show(id: id, title: title, body: body, notificationDetails: const NotificationDetails(android: androidDetails), payload: payload);
    } catch (e) { debugPrint("Error in showInstantNotification: $e"); }
  }

  int normalizeId(dynamic id) {
    if (id is int) return id & 0x7fffffff;
    if (id is String) return id.hashCode & 0x7fffffff;
    return 0;
  }

  Future<void> cancel(dynamic id) async {
    try { await init(); await _plugin.cancel(id: normalizeId(id)); } catch (e) { debugPrint("Error in cancel: $e"); }
  }

  Future<void> cancelTask(dynamic id) async {
    try { 
      await init(); 
      final mainId = normalizeId(id); 
      final remindId = normalizeId(id.hashCode * 10 + 1); 
      await _plugin.cancel(id: mainId); 
      await _plugin.cancel(id: remindId); 
    } catch (e) { debugPrint("Error in cancelTask: $e"); }
  }

  tz.TZDateTime _convertToTZ(DateTime time) {
    final utcTime = time.toUtc();
    return tz.TZDateTime.utc(utcTime.year, utcTime.month, utcTime.day, utcTime.hour, utcTime.minute, utcTime.second);
  }

  Future<void> scheduleRepeatingNotification(dynamic id, String title, DateTime time, {String repeat = "NONE", String? description, bool isGroup = false, String? groupId}) async {
    try {
      await init();
      final payload = jsonEncode({"taskId": id, "title": title, "description": description, "isGroup": isGroup, "groupId": groupId, "tabIndex": 1});
      final safeId = normalizeId(id);
      await _plugin.zonedSchedule(
        id: safeId, 
        title: "Task Reminder", 
        body: title, 
        scheduledDate: _convertToTZ(time), 
        notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('todo_channel', 'Todo Reminder', importance: Importance.max, priority: Priority.high)), 
        payload: payload, 
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, 
        matchDateTimeComponents: repeat == "DAILY" ? DateTimeComponents.time : DateTimeComponents.dayOfWeekAndTime
      );
    } catch (e) { debugPrint("Error scheduling repeating notification: $e"); }
  }

  Future<void> scheduleNotification(dynamic id, String title, DateTime time, {String? description, bool isGroup = false, String? groupId}) async {
    try {
      await init();
      if (time.isBefore(DateTime.now())) return;
      final payload = jsonEncode({"taskId": id, "title": title, "description": description, "isGroup": isGroup, "groupId": groupId, "tabIndex": 1});
      final safeId = normalizeId(id);
      await _plugin.zonedSchedule(
        id: safeId, 
        title: "Task Reminder", 
        body: title, 
        scheduledDate: _convertToTZ(time), 
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'todo_channel', 
            'Todo Reminder', 
            importance: Importance.max, 
            priority: Priority.high, 
            styleInformation: BigTextStyleInformation(description ?? title, contentTitle: title, summaryText: "Notes")
          )
        ), 
        payload: payload, 
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle
      );
    } catch (e) { debugPrint("Error scheduling notification: $e"); }
  }
}
