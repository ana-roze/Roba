import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../widgets/task_item.dart';

class TaskDetailListScreen extends StatefulWidget {
  final String listType; // 'ALL', 'COMPLETED', 'PENDING'
  final String title;

  const TaskDetailListScreen({
    super.key,
    required this.listType,
    required this.title,
  });

  @override
  State<TaskDetailListScreen> createState() => _TaskDetailListScreenState();
}

class _TaskDetailListScreenState extends State<TaskDetailListScreen> {
  final DBHelper dbHelper = DBHelper();
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  String filterType = 'ALL';
  DateTimeRange? filterDateRange;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  void loadTasks() async {
    // 🔥 Load all data from the newly added function
    final data = await dbHelper.getAllMixedTasks();

    String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

    bool isArchived(Map<String, dynamic> t) {
      return t['isArchived'] == 1 || t['isArchived'] == true;
    }

    List<Map<String, dynamic>> filtered = data.where((t) {
      bool passListType = false;

      if (widget.listType == 'ALL') {
        passListType = !isArchived(t);
      } else if (widget.listType == 'COMPLETED') {
        if (t['isGroupTask'] == true) {
          List<dynamic> doneMembers = t['completedMembers'] ?? [];
          passListType = isArchived(t) || doneMembers.contains(myUid);
        } else {
          passListType = isArchived(t);
        }
      } else if (widget.listType == 'PENDING') {
        if (isArchived(t)) return false;

        if (t['isGroupTask'] == true) {
          List<dynamic> doneMembers = t['completedMembers'] ?? [];
          passListType = t['isCompleted'] != true && !doneMembers.contains(myUid);
        } else {
          passListType = t['isCompleted'] == 0 || t['isCompleted'] == false;
        }
      }

      if (!passListType) return false;

      // Filter by task ownership type
      if (filterType == 'PERSONAL' && t['isGroupTask'] == true) return false;
      if (filterType == 'GROUP' && t['isGroupTask'] == false) return false;

      // Filter by date range
      if (filterDateRange != null) {
        DateTime time = DateTime.parse(t["datetime"]);
        if (time.isBefore(filterDateRange!.start.subtract(const Duration(seconds: 1))) ||
            time.isAfter(filterDateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }

      return true;
    }).toList();

    if (mounted) {
      setState(() {
        tasks = filtered;
        isLoading = false;
      });
    }
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(builder: (context, setModalState) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Filter list",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const Divider(),
              RadioListTile<String>(
                title: const Text("All"),
                value: 'ALL',
                groupValue: filterType,
                activeColor: Colors.deepPurple,
                onChanged: (v) {
                  setState(() => filterType = v!);
                  loadTasks();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text("Personal"),
                value: 'PERSONAL',
                groupValue: filterType,
                activeColor: Colors.deepPurple,
                onChanged: (v) {
                  setState(() => filterType = v!);
                  loadTasks();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text("Group"),
                value: 'GROUP',
                groupValue: filterType,
                activeColor: Colors.deepPurple,
                onChanged: (v) {
                  setState(() => filterType = v!);
                  loadTasks();
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.date_range, color: Colors.deepPurple),
                title: Text(
                  filterDateRange == null
                      ? "Select a date range"
                      : "From ${filterDateRange!.start.day}/${filterDateRange!.start.month} to ${filterDateRange!.end.day}/${filterDateRange!.end.month}",
                ),
                trailing: filterDateRange != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () {
                          setState(() => filterDateRange = null);
                          loadTasks();
                          Navigator.pop(context);
                        },
                      )
                    : null,
                onTap: () async {
                  var range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (range != null) {
                    setState(() => filterDateRange = range);
                    loadTasks();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              )
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasFilter = filterType != 'ALL' || filterDateRange != null;

    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(
                hasFilter ? Icons.filter_list_alt : Icons.filter_list,
              ),
              color: hasFilter ? Colors.yellowAccent : Colors.white,
              onPressed: _showFilterModal,
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : tasks.isEmpty
                ? const Center(
                    child: Text(
                      "No tasks match",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, i) {
                      return TaskItem(
                        task: tasks[i],
                        onTaskChanged: (_) {
                          loadTasks();
                        },
                        messengerKey: messengerKey,
                        showDeleteIcon: true,
                        isArchiveMode: widget.listType == 'COMPLETED',
                      );
                    },
                  ),
      ),
    );
  }
}
