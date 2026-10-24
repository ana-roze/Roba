import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class TaskItem extends StatefulWidget {
  final Map<String, dynamic> task;
  final Function(dynamic) onTaskChanged;
  final dynamic highlightTaskId;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final bool showDeleteIcon;
  final bool isArchiveMode;

  const TaskItem({
    super.key,
    required this.task,
    required this.onTaskChanged,
    required this.messengerKey,
    this.highlightTaskId,
    this.showDeleteIcon = false,
    this.isArchiveMode = false,
  });

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  final DBHelper dbHelper = DBHelper();
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  Future<bool> _checkAdminPermission(String groupId) async {
    if (myUid.isEmpty) return false;
    try {
      var doc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
      if (!doc.exists) return false;
      String role = doc.data()?['roles']?[myUid] ?? 'member';
      return role == 'admin' || role == 'co-admin';
    } catch (e) {
      return false;
    }
  }

  String _getMyName() {
    User? u = FirebaseAuth.instance.currentUser;
    return (u?.displayName?.isNotEmpty == true) ? u!.displayName! : (u?.phoneNumber ?? "A member");
  }

  String formatLogTime(String? isoString) {
    if (isoString == null) return "";
    DateTime dt = DateTime.parse(isoString);
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month}/${dt.year}";
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchProgressData(String groupId, List<dynamic> completedUids) async {
    var groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    List<dynamic> allMemberIds = groupDoc.data()?['members'] ?? [];

    List<Map<String, dynamic>> doneUsers = [];
    List<Map<String, dynamic>> pendingUsers = [];

    if (allMemberIds.isEmpty) return {'done': [], 'pending': []};

    List<Map<String, dynamic>> allUsers = [];
    for (int i = 0; i < allMemberIds.length; i += 10) {
      var chunk = allMemberIds.sublist(i, i + 10 > allMemberIds.length ? allMemberIds.length : i + 10);
      var snap = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      allUsers.addAll(snap.docs.map((doc) => {...doc.data(), 'uid': doc.id}));
    }

    for (var u in allUsers) {
      if (completedUids.contains(u['uid'])) {
        doneUsers.add(u);
      } else {
        pendingUsers.add(u);
      }
    }
    return {'done': doneUsers, 'pending': pendingUsers};
  }

  void _editTask() async {
    bool isGroupTask = widget.task['isGroupTask'] == true;
    bool isTaskCompletelyDone = widget.task["isCompleted"] == 1 || widget.task["isCompleted"] == true;
    String? groupId = widget.task['groupId'];
    String? firebaseId = widget.task['id'] is String ? widget.task['id'] : null;
    List<dynamic> completedMembers = widget.task['completedMembers'] ?? [];

    bool isReadOnly = widget.isArchiveMode || (isGroupTask && isTaskCompletelyDone);

    if (isGroupTask) {
      bool hasPermission = await _checkAdminPermission(groupId!);
      if (!hasPermission && !isReadOnly) {
        widget.messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text("❌ Only Admins can view/edit group schedule details!")),
        );
        return;
      }
    }

    TextEditingController titleController = TextEditingController(text: widget.task["title"]);
    TextEditingController descController = TextEditingController(text: widget.task["description"] ?? "");
    DateTime oldDate = DateTime.parse(widget.task["datetime"]);
    DateTime editSelectedDate = oldDate;
    TimeOfDay editSelectedTime = TimeOfDay(hour: oldDate.hour, minute: oldDate.minute);
    int remindBefore = widget.task["remindBeforeMins"] ?? 0;
    String repeatMode = widget.task["repeatMode"] ?? "NONE";

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              clipBehavior: Clip.antiAlias,
              // 🔥 Theme-based background UI
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: DefaultTabController(
                length: isGroupTask ? 2 : 1,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    title: Text(isReadOnly ? "Task Details" : (isGroupTask ? "Manage Group Schedule" : "Edit Schedule")),
                    automaticallyImplyLeading: false,
                    backgroundColor: Colors.transparent,
                    foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                    elevation: 0,
                    actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
                    bottom: isGroupTask
                        ? TabBar(
                            labelColor: Theme.of(context).colorScheme.primary,
                            indicatorColor: Theme.of(context).colorScheme.primary,
                            tabs: const [Tab(text: "Info"), Tab(text: "Progress")],
                          )
                        : null,
                  ),
                  body: TabBarView(
                    children: [
                      SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isReadOnly) ...[
                              Text("Title:", style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12)),
                              Text(widget.task["title"], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 15),
                              Text("Notes:", style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12)),
                              Text(widget.task["description"] ?? "None", style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 15),
                              Text("Time:", style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12)),
                              Text(
                                "${oldDate.hour.toString().padLeft(2, '0')}:${oldDate.minute.toString().padLeft(2, '0')} - ${oldDate.day}/${oldDate.month}/${oldDate.year}",
                                style: const TextStyle(fontSize: 16, color: Colors.blue, fontWeight: FontWeight.bold),
                              ),
                            ] else ...[
                              TextField(controller: titleController, decoration: const InputDecoration(labelText: "Title")),
                              TextField(controller: descController, decoration: const InputDecoration(labelText: "Notes")),
                              const SizedBox(height: 10),
                              Row(children: [
                                Text("${editSelectedDate.day}/${editSelectedDate.month}/${editSelectedDate.year}"),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.calendar_today),
                                  onPressed: () async {
                                    var d = await showDatePicker(
                                      context: context,
                                      initialDate: editSelectedDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (d != null) setModalState(() => editSelectedDate = d);
                                  },
                                )
                              ]),
                              Row(children: [
                                Text(editSelectedTime.format(context)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.access_time),
                                  onPressed: () async {
                                    var t = await showTimePicker(context: context, initialTime: editSelectedTime);
                                    if (t != null) setModalState(() => editSelectedTime = t);
                                  },
                                )
                              ]),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text("Remind before:"),
                                DropdownButton<int>(
                                  value: remindBefore,
                                  items: const [
                                    DropdownMenuItem(value: 0, child: Text("None")),
                                    DropdownMenuItem(value: 5, child: Text("5 minutes")),
                                    DropdownMenuItem(value: 10, child: Text("10 minutes")),
                                    DropdownMenuItem(value: 30, child: Text("30 minutes")),
                                    DropdownMenuItem(value: 60, child: Text("1 hour")),
                                  ],
                                  onChanged: (v) => setModalState(() => remindBefore = v!),
                                )
                              ]),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text("Repeat:"),
                                DropdownButton<String>(
                                  value: repeatMode,
                                  items: const [
                                    DropdownMenuItem(value: 'NONE', child: Text("Never")),
                                    DropdownMenuItem(value: 'DAILY', child: Text("Daily")),
                                    DropdownMenuItem(value: 'WEEKLY', child: Text("Weekly")),
                                  ],
                                  onChanged: (v) => setModalState(() => repeatMode = v!),
                                )
                              ]),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 45,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    if (titleController.text.isEmpty) return;
                                    DateTime finalDate = DateTime(
                                      editSelectedDate.year,
                                      editSelectedDate.month,
                                      editSelectedDate.day,
                                      editSelectedTime.hour,
                                      editSelectedTime.minute,
                                    );
                                    String editTimeStr = DateTime.now().toIso8601String();

                                    if (isGroupTask) {
                                      await FirebaseFirestore.instance
                                          .collection('groups')
                                          .doc(groupId)
                                          .collection('tasks')
                                          .doc(firebaseId)
                                          .update({
                                        "title": titleController.text,
                                        "description": descController.text,
                                        "datetime": finalDate.toIso8601String(),
                                        "remindBeforeMins": remindBefore,
                                        "repeatMode": repeatMode,
                                        "lastEditedAt": editTimeStr,
                                        "lastEditedBy": _getMyName(),
                                      });
                                      await FirebaseFirestore.instance
                                          .collection('groups')
                                          .doc(groupId)
                                          .collection('messages')
                                          .add({
                                        'text': "🤖 Schedule '${titleController.text}' was updated.",
                                        'isSystem': true,
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                      await NotificationService().syncAllGroupTasksAlarms();
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      widget.onTaskChanged(firebaseId);
                                    } else {
                                      int id = widget.task["id"];
                                      await NotificationService().cancelTask(id);
                                      await dbHelper.updateFullTask(id, {
                                        "title": titleController.text,
                                        "description": descController.text,
                                        "datetime": finalDate.toIso8601String(),
                                        "remindBeforeMins": remindBefore,
                                        "repeatMode": repeatMode,
                                        "lastEditedAt": editTimeStr,
                                        "lastEditedBy": _getMyName(),
                                      });
                                      if (repeatMode == "NONE") {
                                        await NotificationService().scheduleNotification(
                                          id,
                                          titleController.text,
                                          finalDate,
                                          description: descController.text,
                                        );
                                      } else {
                                        await NotificationService().scheduleRepeatingNotification(
                                          id,
                                          titleController.text,
                                          finalDate,
                                          repeat: repeatMode,
                                          description: descController.text,
                                        );
                                      }
                                      if (remindBefore > 0 && repeatMode == "NONE") {
                                        DateTime remindTime = finalDate.subtract(Duration(minutes: remindBefore));
                                        await NotificationService().scheduleNotification(
                                          id * 10 + 1,
                                          "Upcoming: ${titleController.text}",
                                          remindTime,
                                          description: descController.text,
                                        );
                                      }
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      widget.onTaskChanged(id);
                                    }
                                  },
                                  child: const Text("SAVE CHANGES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              )
                            ]
                          ],
                        ),
                      ),
                      if (isGroupTask)
                        FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                          future: _fetchProgressData(groupId!, completedMembers),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            var done = snapshot.data!['done']!;
                            var pending = snapshot.data!['pending']!;

                            return ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Text("Submitted / Completed (${done.length})", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                                const SizedBox(height: 10),
                                if (done.isEmpty) const Text("No one has completed this yet.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                                ...done.map((u) => ListTile(
                                      leading: const Icon(Icons.check_circle, color: Colors.green),
                                      title: Text(u['displayName']?.isNotEmpty == true ? u['displayName'] : (u['phone'] ?? 'Anonymous')),
                                    )),
                                const Divider(height: 30),
                                Text("Incomplete (${pending.length})", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                                const SizedBox(height: 10),
                                if (pending.isEmpty) const Text("Great job, everyone has completed it!", style: TextStyle(color: Colors.green, fontStyle: FontStyle.italic)),
                                ...pending.map((u) => ListTile(
                                      leading: const Icon(Icons.pending, color: Colors.red),
                                      title: Text(u['displayName']?.isNotEmpty == true ? u['displayName'] : (u['phone'] ?? 'Anonymous')),
                                    )),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _deleteTaskWithButton() async {
    bool isGroupTask = widget.task['isGroupTask'] == true;
    if (isGroupTask) {
      bool hasPermission = await _checkAdminPermission(widget.task['groupId']);
      if (!hasPermission) {
        widget.messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text("❌ You do not have permission to delete this group schedule!")),
        );
        return;
      }
    }
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Task"),
        content: Text("Are you sure you want to delete \"${widget.task["title"]}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    if (widget.isArchiveMode && !isGroupTask) {
      await NotificationService().cancelTask(widget.task["id"]);
      await dbHelper.deleteTask(widget.task["id"]);
      widget.messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("Permanently deleted from device")),
      );
      widget.onTaskChanged(null);
      return;
    }
    _executeDelete(widget.task);
  }

  void _executeDelete(Map<String, dynamic> deletedTask) async {
    int id = deletedTask["id"] is int ? deletedTask["id"] : deletedTask["id"].hashCode & 0x7FFFFFFF;
    bool isGroupTask = deletedTask['isGroupTask'] == true;
    bool isCompleted = deletedTask["isCompleted"] == 1 || deletedTask["isCompleted"] == true;

    if (isGroupTask) {
      await NotificationService().cancelTask(id);
      await FirebaseFirestore.instance.collection('groups').doc(deletedTask['groupId']).collection('tasks').doc(deletedTask['id']).delete();
    } else {
      await NotificationService().cancelTask(deletedTask["id"]);
      if (isCompleted) {
        await dbHelper.archiveTask(deletedTask["id"]);
      } else {
        await dbHelper.deleteTask(deletedTask["id"]);
      }
    }
    widget.onTaskChanged(null);
    widget.messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(isCompleted ? "Archived ${deletedTask["title"]}" : "Deleted ${deletedTask["title"]}"),
        action: SnackBarAction(
          label: "Undo",
          onPressed: () async {
            if (isGroupTask) {
              // Group task undo logic if needed
            } else {
              if (isCompleted) {
                await dbHelper.unarchiveTask(deletedTask["id"]);
              } else {
                await dbHelper.insertTask(deletedTask);
              }
              DateTime time = DateTime.parse(deletedTask["datetime"]);
              await NotificationService().scheduleNotification(
                deletedTask["id"],
                deletedTask["title"],
                time,
                description: deletedTask["description"],
              );
              widget.onTaskChanged(deletedTask["id"]);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    var t = widget.task;
    DateTime time = DateTime.parse(t["datetime"]);
    var id = t["id"];
    String desc = t["description"] ?? "";

    bool isGroupTask = t["isGroupTask"] == true;
    bool isTaskCompletelyDone = t["isCompleted"] == 1 || t["isCompleted"] == true;

    List<dynamic> completedMembers = t['completedMembers'] ?? [];
    bool didIComplete = completedMembers.contains(myUid);

    bool isHighlighted = false;
    if (widget.highlightTaskId != null) {
      if (widget.highlightTaskId.toString() == id.toString()) isHighlighted = true;
      else if (isGroupTask && widget.highlightTaskId.toString() == (id.hashCode & 0x7FFFFFFF).toString()) isHighlighted = true;
    }

    Widget listTile = ListTile(
      leading: Checkbox(
        activeColor: Theme.of(context).colorScheme.primary, // Change checkbox color according to Theme
        value: widget.isArchiveMode ? true : (isGroupTask ? (isTaskCompletelyDone || didIComplete) : isTaskCompletelyDone),
        onChanged: widget.isArchiveMode
            ? null
            : (val) async {
                if (isGroupTask) {
                  bool isAdmin = await _checkAdminPermission(t['groupId']);
                  if (val == true && !didIComplete) {
                    bool? confirm = await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Confirm Completion"),
                        content: const Text("This action cannot be undone. Are you sure you have completed this task?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Done"),
                          )
                        ],
                      ),
                    );

                    if (confirm == true) {
                      List<dynamic> updatedCompletedMembers = List.from(completedMembers)..add(myUid);
                      var groupDoc = await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).get();
                      List<dynamic> allMembers = groupDoc.data()?['members'] ?? [];
                      String completeTimeStr = DateTime.now().toIso8601String();

                      Map<String, dynamic> updatePayload = {'completedMembers': updatedCompletedMembers};
                      if (updatedCompletedMembers.length >= allMembers.length && allMembers.isNotEmpty) {
                        updatePayload['isCompleted'] = true;
                        updatePayload['isArchived'] = true;
                        updatePayload['completedAt'] = completeTimeStr;
                      }

                      await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).collection('tasks').doc(t['id']).update(updatePayload);

                      if (isAdmin) {
                        await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).collection('messages').add({
                          'text': "✅ Admin ${_getMyName()} submitted: ${t['title']}",
                          'isSystem': true,
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                      } else {
                        await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).collection('messages').add({
                          'text': "✅ ${_getMyName()} submitted: ${t['title']}",
                          'isSystem': true,
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                      }

                      if (updatedCompletedMembers.length >= allMembers.length && allMembers.isNotEmpty) {
                        DateTime now = DateTime.now();
                        String timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.day}/${now.month}/${now.year}";
                        await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).collection('messages').add({
                          'text': "🎉 [${t['title']}]: completed at $timeStr",
                          'isSystem': true,
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                      }
                    }
                  } else if (val == false && isAdmin && isTaskCompletelyDone) {
                    bool? confirmOpen = await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Reopen Schedule"),
                        content: const Text("This schedule was closed because everyone submitted their work. Do you want to reopen it?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Reopen"),
                          )
                        ],
                      ),
                    );
                    if (confirmOpen == true) {
                      await FirebaseFirestore.instance
                          .collection('groups')
                          .doc(t['groupId'])
                          .collection('tasks')
                          .doc(t['id'])
                          .update({'isCompleted': false, 'isArchived': false, 'completedAt': FieldValue.delete()});
                    }
                  } else if (didIComplete) {
                    widget.messengerKey.currentState?.showSnackBar(
                      const SnackBar(content: Text("⚠️ You have already submitted and cannot uncheck this yourself!")),
                    );
                  }
                } else {
                  await dbHelper.updateTask(id as int, val! ? 1 : 0);
                }
                widget.onTaskChanged(null);
              },
      ),
      title: Row(
        children: [
          // 🔥 Text color changes according to Theme
          Expanded(
            child: Text(
              t["title"],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: isTaskCompletelyDone ? TextDecoration.lineThrough : null,
                color: (widget.isArchiveMode && (t["isArchived"] == 1 || t["isArchived"] == true))
                    ? Colors.grey
                    : Theme.of(context).textTheme.bodyLarge?.color, // Use standard OS color
              ),
            ),
          ),
          if (isHighlighted)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
              child: const Text("🔔 Just notified", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isGroupTask)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4), // 🔥 Soft background color
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("👥 ${t['groupName']}", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  FutureBuilder<bool>(
                    future: _checkAdminPermission(t['groupId']),
                    builder: (context, snapshot) {
                      if (snapshot.data == true) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.white,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text("Progress: ${completedMembers.length}", style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  )
                ],
              ),
            ),
          Row(
            children: [
              Text(
                "${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
              ),
              if (t["repeatMode"] == 'DAILY' || t["repeatMode"] == 'WEEKLY')
                const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.repeat, size: 14, color: Colors.grey)),
              if (t["remindBeforeMins"] != null && t["remindBeforeMins"] > 0)
                const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.notifications_active, size: 14, color: Colors.orange)),
              if (widget.isArchiveMode && (t["isArchived"] == 1 || t["isArchived"] == true))
                const Padding(padding: EdgeInsets.only(left: 8.0), child: Text("Archived", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
          if (desc.isNotEmpty) Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (t['lastEditedAt'] != null)
            Text(
              "Last edited: ${formatLogTime(t['lastEditedAt'])} by ${t['lastEditedBy'] ?? 'Someone'}",
              style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic),
            ),
          if (t['completedAt'] != null)
            Text(
              "Completed at: ${formatLogTime(t['completedAt'])}",
              style: const TextStyle(fontSize: 10, color: Colors.green, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      trailing: widget.showDeleteIcon ? IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: _deleteTaskWithButton) : null,
      onTap: _editTask,
    );

    // 🔥 Wrap in Card for standard M3 rounded corners
    Widget taskCard = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isHighlighted ? Container(color: Colors.yellow.withOpacity(0.3), child: listTile) : listTile,
      ),
    );

    if (!widget.showDeleteIcon && !widget.isArchiveMode) {
      return Dismissible(
        key: Key(id.toString()),
        direction: DismissDirection.horizontal,
        background: Container(
          color: Colors.green,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 20), child: Icon(Icons.check, color: Colors.white))),
        ),
        secondaryBackground: Container(
          color: Colors.red,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.only(right: 20), child: Icon(Icons.delete, color: Colors.white))),
        ),
        confirmDismiss: (direction) async {
          if (isGroupTask) {
            bool hasPermission = await _checkAdminPermission(t['groupId']);
            if (!hasPermission) {
              widget.messengerKey.currentState?.showSnackBar(
                const SnackBar(content: Text("❌ Only Admins can swipe to perform this action!")),
              );
              return false;
            }
          }
          if (direction == DismissDirection.startToEnd) {
            if (isGroupTask) {
              await FirebaseFirestore.instance.collection('groups').doc(t['groupId']).collection('tasks').doc(t['id']).update({'isCompleted': true});
            } else {
              await dbHelper.updateTask(id as int, 1);
            }
            widget.onTaskChanged(null);
            return false;
          }
          return true;
        },
        onDismissed: (_) => _executeDelete(Map<String, dynamic>.from(t)),
        child: taskCard,
      );
    }
    return taskCard;
  }
}