import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';
import '../widgets/task_item.dart';

class UpcomingScreen extends StatefulWidget {
  final dynamic highlightTaskId;
  const UpcomingScreen({super.key, this.highlightTaskId});
  @override
  State<UpcomingScreen> createState() => UpcomingScreenState();
}

class UpcomingScreenState extends State<UpcomingScreen> {
  final DBHelper dbHelper = DBHelper();
  DateTime selectedDay = DateTime.now();
  DateTime focusedDay = DateTime.now();

  CalendarFormat _calendarFormat = CalendarFormat.month;

  List<Map<String, dynamic>> allTasks = [];
  List<Map<String, dynamic>> filteredTasks = [];

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final ScrollController _scrollController = ScrollController();
  dynamic highlightTaskId;

  String filterType = 'ALL';

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
    setState(() {
      allTasks = data;
      highlightTaskId = highlightId;
    });

    if (highlightTaskId != null) {
      var task = allTasks.firstWhere(
        (t) => t["id"].toString() == highlightTaskId.toString(),
        orElse: () => {},
      );
      if (task.isNotEmpty) {
        setState(() {
          selectedDay = DateTime.parse(task["datetime"]);
        });
      }
    }

    filterTasks();

    if (highlightTaskId != null &&
        NotificationService.lastFlashedTaskId != highlightTaskId) {
      NotificationService.lastFlashedTaskId = highlightTaskId;

      Future.delayed(const Duration(milliseconds: 500), () {
        int index = filteredTasks.indexWhere(
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

  void filterTasks() {
    setState(() {
      filteredTasks = allTasks.where((t) {
        DateTime time = DateTime.parse(t["datetime"]);
        bool isSameDayCheck = time.year == selectedDay.year &&
            time.month == selectedDay.month &&
            time.day == selectedDay.day;
        if (!isSameDayCheck) return false;

        if (filterType == 'PERSONAL' && t["isGroupTask"] == true)
          return false;
        if (filterType == 'GROUP' && t["isGroupTask"] != true)
          return false;

        return true;
      }).toList();
    });
  }

  bool hasTask(DateTime day) {
    return allTasks.any((t) {
      DateTime time = DateTime.parse(t["datetime"]);
      bool isSameDate =
          time.year == day.year && time.month == day.month && time.day == day.day;
      if (!isSameDate) return false;

      if (filterType == 'PERSONAL' && t['isGroupTask'] == true) return false;
      if (filterType == 'GROUP' && t['isGroupTask'] != true) return false;

      return true;
    });
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
                const Text(
                  "Schedule Filter",
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
                    filterTasks();
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
                    filterTasks();
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
                    filterTasks();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasFilter = filterType != 'ALL';
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    CalendarFormat currentFormat = isLandscape ? CalendarFormat.week : _calendarFormat;

    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Schedule (Upcoming)"),
          actions: [
            IconButton(
              icon: Icon(hasFilter ? Icons.filter_list_alt : Icons.filter_list),
              color: hasFilter ? Colors.yellowAccent : Colors.white,
              onPressed: _showFilterModal,
            )
          ],
        ),
        body: Column(
          children: [
            TableCalendar(
              key: const Key("upcomingTableCalendar"),
              firstDay: DateTime(2020),
              lastDay: DateTime(2100),
              focusedDay: focusedDay,
              calendarFormat: currentFormat,
              onFormatChanged: (format) {
                if (!isLandscape) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              selectedDayPredicate: (day) => isSameDay(day, selectedDay),
              onDaySelected: (selected, focused) {
                setState(() {
                  selectedDay = selected;
                  focusedDay = focused;
                });
                filterTasks();
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  bool has = hasTask(day);
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: has ? Colors.red.withValues(alpha: 0.3) : null,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text("${day.day}"),
                  );
                },
              ),
            ),
            Expanded(
              child: filteredTasks.isEmpty
                  ? Center(
                      key: const Key("txtEmptyUpcomingMessage"),
                      child: Text(
                        hasFilter
                            ? "No tasks match the filter."
                            : "No tasks",
                      ),
                    )
                  : ListView.builder(
                      key: const Key("upcomingTasksListView"),
                      controller: _scrollController,
                      itemCount: filteredTasks.length,
                      itemBuilder: (_, i) {
                        return TaskItem(
                          key: ValueKey(
                            "upcoming_task_item_${filteredTasks[i]['id']}",
                          ),
                          task: filteredTasks[i],
                          onTaskChanged: (id) {
                            NotificationService.lastFlashedTaskId = null;
                            loadTasks(highlightId: id);
                          },
                          messengerKey: messengerKey,
                          highlightTaskId: highlightTaskId,
                          showDeleteIcon: true,
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}
