import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class AddTaskScreen extends StatefulWidget {
  final String? prefilledGroupId; // Retrieve the group ID passed in externally

  const AddTaskScreen({super.key, this.prefilledGroupId});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final titleController = TextEditingController();
  final descController = TextEditingController();

  DateTime? selectedDate = DateTime.now();
  TimeOfDay? selectedTime = TimeOfDay.now();

  int remindBefore = 0;
  String repeatMode = 'NONE';

  bool isGroupTask = false;
  String? selectedGroupId;
  List<Map<String, dynamic>> myGroups = [];
  bool isLoadingGroups = false;

  final DBHelper dbHelper = DBHelper();

  @override
  void initState() {
    super.initState();
    // 🔥 Lock logic when entered from a group
    if (widget.prefilledGroupId != null) {
      isGroupTask = true;
      selectedGroupId = widget.prefilledGroupId;
    }
    _fetchMyGroups();
  }

  void _fetchMyGroups() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isLoadingGroups = true);
    try {
      var snapshot = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: user.uid).get();

      List<Map<String, dynamic>> temp = [];
      for (var doc in snapshot.docs) {
        var data = doc.data();
        String role = data['roles']?[user.uid] ?? 'member';

        temp.add({
          'id': doc.id,
          'name': data['name'] ?? 'Untitled group',
          'role': role,
          'canAdd': role == 'admin' || role == 'co-admin'
        });
      }
      if (mounted) setState(() { myGroups = temp; isLoadingGroups = false; });
    } catch (e) {
      if (mounted) setState(() => isLoadingGroups = false);
    }
  }

  void saveTask() async {
    if (titleController.text.isEmpty || selectedDate == null || selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter the Title, Date, and Time!")));
      return;
    }

    if (isGroupTask && selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng chọn một Nhóm để thêm lịch!")));
      return;
    }

    DateTime finalDate = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, selectedTime!.hour, selectedTime!.minute);

    if (isGroupTask) {
      User? user = FirebaseAuth.instance.currentUser;
      String creatorName = (user?.displayName?.isNotEmpty == true) ? user!.displayName! : (user?.phoneNumber ?? 'Anonymous');

      await FirebaseFirestore.instance.collection('groups').doc(selectedGroupId).collection('tasks').add({
        'title': titleController.text,
        'description': descController.text,
        'datetime': finalDate.toIso8601String(),
        'isCompleted': false,
        'completedMembers': [], // 🔥 Add an array to store users who have submitted
        'remindBeforeMins': remindBefore,
        'repeatMode': repeatMode,
        'createdBy': creatorName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await NotificationService().syncAllGroupTasksAlarms();

    } else {
      int id = await dbHelper.insertTask({
        "title": titleController.text, "description": descController.text, "datetime": finalDate.toIso8601String(), "isCompleted": 0, "remindBeforeMins": remindBefore, "repeatMode": repeatMode,
      });

      if (repeatMode == "NONE") await NotificationService().scheduleNotification(id, titleController.text, finalDate, description: descController.text);
      else await NotificationService().scheduleRepeatingNotification(id, titleController.text, finalDate, repeat: repeatMode, description: descController.text);

      if (remindBefore > 0 && repeatMode == "NONE") {
        DateTime remindTime = finalDate.subtract(Duration(minutes: remindBefore));
        await NotificationService().scheduleNotification(id * 10 + 1, "Upcoming: ${titleController.text}", remindTime, description: descController.text);
      }
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    bool isLockedGroup = widget.prefilledGroupId != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Schedule")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Task Type", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text("Personal"), value: false, groupValue: isGroupTask, activeColor: Colors.deepPurple, contentPadding: EdgeInsets.zero,
                    onChanged: isLockedGroup ? null : (v) => setState(() { isGroupTask = v!; selectedGroupId = null; }),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text("Group"), value: true, groupValue: isGroupTask, activeColor: Colors.deepPurple, contentPadding: EdgeInsets.zero,
                    onChanged: isLockedGroup ? null : (v) {
                      if (FirebaseAuth.instance.currentUser == null) return;
                      setState(() => isGroupTask = v!);
                    },
                  ),
                ),
              ],
            ),

            if (isGroupTask && !isLockedGroup) ...[
              const SizedBox(height: 10),
              isLoadingGroups
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: "Select a group", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.group, color: Colors.deepPurple)),
                value: selectedGroupId,
                items: myGroups.map((g) {
                  bool canAdd = g['canAdd'];
                  return DropdownMenuItem<String>(value: canAdd ? g['id'] : null, enabled: canAdd, child: Text("${g['name']} ${canAdd ? '' : '(Admins/Co-admins only)'}", style: TextStyle(color: canAdd ? Colors.black : Colors.grey, fontStyle: canAdd ? FontStyle.normal : FontStyle.italic)));
                }).toList(),
                onChanged: (v) { if (v != null) setState(() => selectedGroupId = v); },
              ),
              const SizedBox(height: 20),
            ],

            if (isLockedGroup) ...[
              Container(
                padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [const Icon(Icons.lock, color: Colors.deepPurple, size: 18), const SizedBox(width: 8), Text("Creating a schedule for this group", style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold))]),
              )
            ],

            TextField(controller: titleController, decoration: InputDecoration(labelText: "Title", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 15),
            TextField(controller: descController, decoration: InputDecoration(labelText: "Detailed description", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), maxLines: 3),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today), label: Text(selectedDate == null ? "Date" : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"), onPressed: () async { var d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100)); if (d != null) setState(() => selectedDate = d); })),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.access_time), label: Text(selectedTime == null ? "Time" : selectedTime!.format(context)), onPressed: () async { var t = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (t != null) setState(() => selectedTime = t); })),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: DropdownButtonFormField<int>(decoration: const InputDecoration(labelText: "Reminder", border: InputBorder.none), value: remindBefore, items: const [DropdownMenuItem(value: 0, child: Text("On time")), DropdownMenuItem(value: 5, child: Text("5 minutes")), DropdownMenuItem(value: 10, child: Text("10 minutes")), DropdownMenuItem(value: 30, child: Text("30 minutes")), DropdownMenuItem(value: 60, child: Text("1 hour"))], onChanged: (v) => setState(() => remindBefore = v!))),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Repeat", border: InputBorder.none), value: repeatMode, items: const [DropdownMenuItem(value: 'NONE', child: Text("No repeat")), DropdownMenuItem(value: 'DAILY', child: Text("Daily")), DropdownMenuItem(value: 'WEEKLY', child: Text("Weekly"))], onChanged: (v) => setState(() => repeatMode = v!))),
              ],
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isGroupTask ? Colors.deepPurple : Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: saveTask,
                child: Text(isGroupTask ? "CREATE GROUP SCHEDULE" : "CREATE PERSONAL SCHEDULE", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
