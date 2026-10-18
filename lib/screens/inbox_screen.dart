import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';
import '../widgets/task_item.dart';

class InboxScreen extends StatefulWidget {
  final dynamic highlightTaskId;
  const InboxScreen({super.key, this.highlightTaskId});

  @override
  State<InboxScreen> createState() => InboxScreenState();
}

class InboxScreenState extends State<InboxScreen> {
  final DBHelper dbHelper = DBHelper();
  List<Map<String, dynamic>> allLoadedTasks = [];
  List<Map<String, dynamic>> tasks = [];

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final ScrollController _scrollController = ScrollController();

  dynamic highlightTaskId;

  String filterType = 'ALL';
  DateTimeRange? filterDateRange;

  @override
  void initState() {
    super.initState();

    if (widget.highlightTaskId != null &&
        NotificationService.lastFlashedTaskId != widget.highlightTaskId) {
      highlightTaskId = widget.highlightTaskId;
    }

    loadTasks(highlightId: highlightTaskId);
  }

  void loadTasks({dynamic highlightId}) async {
    final data = await dbHelper.getMixedTasks();
    if (!mounted) return;

    allLoadedTasks = data;
    applyFilters(highlightId: highlightId);
  }

  void applyFilters({dynamic highlightId}) {
    List<Map<String, dynamic>> result = List.from(allLoadedTasks);

    if (filterType == 'PERSONAL') {
      result.retainWhere((t) => t["isGroupTask"] != true);
    } else if (filterType == 'GROUP') {
      result.retainWhere((t) => t["isGroupTask"] == true);
    }

    if (filterDateRange != null) {
      result.retainWhere((t) {
        DateTime time = DateTime.parse(t["datetime"]);
        return time.isAfter(
                filterDateRange!.start.subtract(
                  const Duration(seconds: 1),
                )) &&
            time.isBefore(
              filterDateRange!.end.add(const Duration(days: 1)),
            );
      });
    }

    setState(() {
      tasks = result;
      highlightTaskId = highlightId;
    });

    if (highlightTaskId != null &&
        NotificationService.lastFlashedTaskId != highlightTaskId) {
      NotificationService.lastFlashedTaskId = highlightTaskId;

      Future.delayed(const Duration(milliseconds: 300), () {
        int index = tasks.indexWhere(
          (t) => t["id"].toString() == highlightTaskId.toString(),
        );

        if (index != -1 && _scrollController.hasClients) {
          _scrollController.animateTo(
            index * 90.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => highlightTaskId = null);
          });
        }
      });
    }
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Removed fixed color: Colors.deepPurple
                const Text(
                  "Filter list",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),

                RadioListTile<String>(
                  title: const Text("All"),
                  value: 'ALL',
                  groupValue: filterType,
                  activeColor: Colors.deepPurple,
                  onChanged: (v) {
                    setState(() => filterType = v!);
                    applyFilters();
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
                    applyFilters();
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
                    applyFilters();
                    Navigator.pop(context);
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(
                    Icons.date_range,
                    color: Colors.deepPurple,
                  ),
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
                            applyFilters();
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
                      applyFilters();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void deleteCompleted() async {
    for (var t in tasks) {
      if ((t["isCompleted"] == 1 || t["isCompleted"] == true) &&
          t["isGroupTask"] != true) {
        await NotificationService().cancelTask(t["id"]);
        await dbHelper.archiveTask(t["id"]);
      }
    }
    loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    bool hasFilter = filterType != 'ALL' || filterDateRange != null;

    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Inbox"),
          actions: [
            IconButton(
              icon: Icon(
                hasFilter ? Icons.filter_list_alt : Icons.filter_list,
              ),
              color: hasFilter ? Colors.yellowAccent : Colors.white,
              onPressed: _showFilterModal,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: deleteCompleted,
            )
          ],
        ),
        body: tasks.isEmpty
            ? Center(
                child: Text(
                  hasFilter
                      ? "No tasks match your filters."
                      : "Inbox is empty!",
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: tasks.length,
                itemBuilder: (_, i) {
                  return TaskItem(
                    task: tasks[i],
                    onTaskChanged: (id) {
                      NotificationService.lastFlashedTaskId = null;
                      loadTasks(highlightId: id);
                    },
                    messengerKey: messengerKey,
                    highlightTaskId: highlightTaskId,
                    showDeleteIcon: false,
                  );
                },
              ),
      ),
    );
  }
}
