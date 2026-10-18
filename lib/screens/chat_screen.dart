import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final DBHelper dbHelper = DBHelper();

  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;

  void sendMessage() async {
    String text = controller.text;
    if (text.isEmpty) return;

    setState(() {
      messages.add({"text": text, "isUser": true, "hasUndo": false});
      isLoading = true;
    });
    controller.clear();

    String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    String groupContext = "";

    if (myUid.isNotEmpty) {
      try {
        var groupsQuery = await FirebaseFirestore.instance
            .collection('groups')
            .where('members', arrayContains: myUid)
            .get();

        for (var doc in groupsQuery.docs) {
          var data = doc.data();
          Map<String, dynamic> roles = (data['roles'] as Map<String, dynamic>?) ?? {};
          String role = roles[myUid] ?? 'member';

          if (role == 'admin' || role == 'co-admin') {
            String groupName = data['name'] ?? "Untitled group";
            groupContext += "- Group name: '$groupName' | groupId: '${doc.id}'\n";
          }
        }
      } catch (e) {
        print("Error while fetching group list: $e");
      }
    }

    if (groupContext.isEmpty) {
      groupContext =
          "User currently DOES NOT HAVE Admin/Co-admin privileges. Absolutely REFUSE any request to add/edit/delete the group schedule.";
    }

    final results = await GeminiService.chatAndAct(
      text,
      groupContext: groupContext,
      currentScreen: "personal",
    );

    setState(() {
      isLoading = false;
    });

    if (results == null || results.isEmpty) {
      addBot("❌ The system is busy or there is a connection error.");
      return;
    }

    for (var result in results) {
      if (result["type"] == "error") {
        addBot(result["message"] ?? "❌ Something went wrong.");
      } else if (result["type"] == "text") {
        addBot(result["message"]);
      } else if (result["type"] == "action") {
        try {
          String action = result["action"] ?? "";

          if (action == "create_group_task") {
            String title = result["title"] ?? "Untitled task";
            String groupId = result["groupId"]?.toString() ?? "";

            if (groupId.isEmpty) {
              addBot("⚠️ You do not have permission or the group does not exist.");
              continue;
            }
            if (result["datetime"] == null) {
              addBot("⚠️ Please provide a time.");
              continue;
            }

            DateTime time = DateTime.parse(result["datetime"]);
            String repeatMode = result["repeatMode"]?.toString() ?? "NONE";
            int? remindMins = result["remindBeforeMins"] != null
                ? int.tryParse(result["remindBeforeMins"].toString())
                : null;
            String description = result["description"]?.toString() ?? "";

            User? u = FirebaseAuth.instance.currentUser;
            String myName =
                (u?.displayName?.isNotEmpty == true) ? u!.displayName! : "AI Assistant";

            await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').add({
              'title': title,
              'description': description,
              'datetime': time.toIso8601String(),
              'isCompleted': false,
              'remindBeforeMins': remindMins,
              'repeatMode': repeatMode,
              'createdBy': myName,
              'createdAt': FieldValue.serverTimestamp(),
            });

            await NotificationService().syncAllGroupTasksAlarms();
            addBot("✅ Scheduled for the group: \"$title\".");
          } else if (action == "update_group_task") {
            String groupId = result["groupId"]?.toString() ?? "";
            List<String> targetTitles = result["targetTitles"] != null
                ? List<String>.from(result["targetTitles"])
                : [];
            String newTitle = result["title"] ?? "";
            String? newTimeStr = result["datetime"];

            if (groupId.isEmpty || targetTitles.isEmpty) {
              addBot("⚠️ Missing group or task information.");
              continue;
            }

            var query = await FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .collection('tasks')
                .get();

            bool found = false;

            for (var doc in query.docs) {
              String taskTitle = doc.data()['title'].toString().toLowerCase().trim();

              if (targetTitles.any((t) => taskTitle.contains(t.toLowerCase().trim()))) {
                Map<String, dynamic> updates = {};
                if (newTitle.isNotEmpty) updates['title'] = newTitle;
                if (newTimeStr != null) updates['datetime'] = newTimeStr;

                await doc.reference.update(updates);
                found = true;
              }
            }

            await NotificationService().syncAllGroupTasksAlarms();

            if (found) {
              addBot("✅ Updated the group schedule!");
            } else {
              addBot("⚠️ No group schedule matched the task name.");
            }
          } else if (action == "delete_group_task") {
            String groupId = result["groupId"]?.toString() ?? "";
            List<String> targetTitles = result["targetTitles"] != null
                ? List<String>.from(result["targetTitles"])
                : [];

            if (groupId.isEmpty || targetTitles.isEmpty) {
              addBot("⚠️ Missing group or task information.");
              continue;
            }

            var query = await FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .collection('tasks')
                .get();

            int count = 0;

            for (var doc in query.docs) {
              String taskTitle = doc.data()['title'].toString().toLowerCase().trim();

              if (targetTitles.any((t) => taskTitle.contains(t.toLowerCase().trim()))) {
                await NotificationService().cancelTask(doc.id.hashCode & 0x7FFFFFFF);
                await doc.reference.delete();
                count++;
              }
            }

            if (count > 0) {
              addBot("🗑 Deleted $count group schedule(s).");
            } else {
              addBot("⚠️ No group schedule found to delete.");
            }
          } else if (action == "create") {
            String title = result["title"] ?? "Untitled task";

            if (result["datetime"] == null) {
              addBot("⚠️ A schedule needs a time.");
              continue;
            }

            DateTime time = DateTime.parse(result["datetime"]);
            String repeatMode = result["repeatMode"]?.toString() ?? "NONE";
            String description = result["description"]?.toString() ?? "";
            int? remindMins = result["remindBeforeMins"] != null
                ? int.tryParse(result["remindBeforeMins"].toString())
                : null;

            int id = await dbHelper.insertTask({
              "title": title,
              "description": description,
              "datetime": time.toIso8601String(),
              "isCompleted": 0,
              "remindBeforeMins": remindMins,
              "repeatMode": repeatMode,
            });

            if (repeatMode == "NONE") {
              await NotificationService().scheduleNotification(
                id,
                title,
                time,
                description: description,
              );
            } else {
              await NotificationService().scheduleRepeatingNotification(
                id,
                title,
                time,
                repeat: repeatMode,
                description: description,
              );
            }

            addBot("✅ Scheduled your personal task: \"$title\" at ${time.hour}:${time.minute.toString().padLeft(2, '0')}.");
          } else if (action == "update") {
            List<String> targetTitles = result["targetTitles"] != null
                ? List<String>.from(result["targetTitles"])
                : [];
            String newTitle = result["title"] ?? "";
            String? newTimeStr = result["datetime"];

            if (targetTitles.isEmpty) continue;

            final tasks = await dbHelper.getTasks();
            bool found = false;

            for (var t in tasks) {
              String taskTitle = t["title"].toString().toLowerCase().trim();

              if (targetTitles.any((kw) => taskTitle.contains(kw.toLowerCase().trim()))) {
                String finalTitle = newTitle.isNotEmpty ? newTitle : t["title"];
                String finalTime = newTimeStr ?? t["datetime"];

                await dbHelper.updateTaskDetails(t["id"], finalTitle, finalTime);
                await NotificationService().cancelTask(t["id"]);
                await NotificationService().scheduleNotification(
                  t["id"],
                  finalTitle,
                  DateTime.parse(finalTime),
                );

                found = true;
              }
            }

            if (found) {
              addBot("✅ Updated your personal schedule!");
            } else {
              addBot("⚠️ Could not find a personal task to update.");
            }
          } else if (action == "delete") {
            List<String> targetTitles = result["targetTitles"] != null
                ? List<String>.from(result["targetTitles"])
                : [];
            if (targetTitles.isEmpty) continue;

            final tasks = await dbHelper.getTasks();
            int count = 0;

            for (var t in tasks) {
              String taskTitle = t["title"].toString().toLowerCase().trim();

              if (targetTitles.any((kw) => taskTitle.contains(kw.toLowerCase().trim()))) {
                await NotificationService().cancelTask(t["id"]);
                await dbHelper.deleteTask(t["id"]);
                count++;
              }
            }

            if (count > 0) {
              addBot("🗑 Deleted $count personal schedule(s).");
            } else {
              addBot("⚠️ No personal schedule found to delete.");
            }
          }
        } catch (e) {
          addBot("❌ Error while processing the task. (Details: $e)");
        }
      }
    }
  }

  void addBot(String text) {
    setState(() {
      messages.add({"text": text, "isUser": false, "hasUndo": false});
    });
  }

  Widget bubble(int index) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Map msg = messages[index];
    bool isUser = msg["isUser"];

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // UI clarity for light and dark mode
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : (isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(16),
            bottomLeft: !isUser ? const Radius.circular(0) : const Radius.circular(16),
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Text(
          msg["text"],
          style: TextStyle(
            fontSize: 15,
            // Ensure text does not blend into the background
            color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Assistant 🤖"),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: messages.length,
              itemBuilder: (_, i) => bubble(i),
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text("AI is thinking...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              // Flexible input bar background that adapts to the theme
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color), // Keep normal text color
                    decoration: InputDecoration(
                      hintText: "Example: Rename the schedule 'Team meeting' to 'Report'... ",
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      // Slightly gray input box to separate it from the background
                      fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: sendMessage,
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
