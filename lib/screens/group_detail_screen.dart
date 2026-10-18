import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_task_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/task_item.dart';
import '../widgets/chat_input_bar.dart';
import 'group_info_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  static String? currentActiveGroupId;
  final Map<String, dynamic> groupData;
  final String currentUserId;
  final int initialTabIndex;
  final int? highlightTaskId;

  const GroupDetailScreen({super.key, required this.groupData, required this.currentUserId, this.initialTabIndex = 0, this.highlightTaskId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  Map<String, dynamic> currentGroupData = {};
  bool isNotificationsMuted = false;

  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  dynamic highlightTaskId;
  DateTimeRange? taskFilterDateRange;

  String get myName {
    User? u = FirebaseAuth.instance.currentUser;
    return u?.displayName?.isNotEmpty == true ? u!.displayName! : (u?.phoneNumber ?? u?.email ?? "Anonymous");
  }

  @override
  void initState() {
    super.initState();
    currentGroupData = widget.groupData;
    GroupDetailScreen.currentActiveGroupId = widget.groupData['id'];

    highlightTaskId = widget.highlightTaskId;
    if (highlightTaskId != null) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => highlightTaskId = null);
      });
    }

    _loadGroupData();
    _checkMuteStatus();
    _checkBlockedUsersOnEntry();
  }

  void _checkBlockedUsersOnEntry() async {
    try {
      var myDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();
      List<dynamic> myBlockedUsers = myDoc.data()?['blockedUsers'] ?? [];
      List<dynamic> groupMembers = currentGroupData['members'] ?? [];

      List<String> blockedInGroup = [];
      for (var memberId in groupMembers) {
        if (myBlockedUsers.contains(memberId)) {
          blockedInGroup.add(memberId);
        }
      }

      if (blockedInGroup.isNotEmpty && mounted) {
        var userDoc = await FirebaseFirestore.instance.collection('users').doc(blockedInGroup.first).get();
        String name = userDoc.data()?['displayName'] ?? userDoc.data()?['phone'] ?? "User";

        bool? confirm = await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text("Warning"),
              content: Text("This group contains a user [$name] whom you have blocked. Are you sure you want to chat in this group?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
              ],
            )
        );

        if (confirm != true && mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint("Error checking blocked users: $e");
    }
  }

  @override
  void dispose() {
    GroupDetailScreen.currentActiveGroupId = null;
    super.dispose();
  }

  void _checkMuteStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => isNotificationsMuted = prefs.getBool('mute_group_${widget.groupData['id']}') ?? false);
  }

  void _toggleGroupNotification() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String topic = 'group_${widget.groupData['id']}';
    setState(() { isNotificationsMuted = !isNotificationsMuted; });

    if (isNotificationsMuted) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      await prefs.setBool('mute_group_${widget.groupData['id']}', true);
      messengerKey.currentState?.showSnackBar(const SnackBar(content: Text("🔇 Group notifications muted.")));
    } else {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      await prefs.setBool('mute_group_${widget.groupData['id']}', false);
      messengerKey.currentState?.showSnackBar(const SnackBar(content: Text("🔔 Group notifications enabled.")));
    }
  }

  void _loadGroupData() {
    FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).snapshots().listen((groupDoc) {
      if (!groupDoc.exists) {
        if (mounted) {
          Navigator.pop(context);
          messengerKey.currentState?.showSnackBar(const SnackBar(content: Text("The group has been deleted!")));
        }
        return;
      }
      if (mounted) {
        setState(() { currentGroupData = groupDoc.data() as Map<String, dynamic>; });
        List<dynamic> memberIds = currentGroupData['members'] ?? [];
        if (!memberIds.contains(widget.currentUserId)) {
          Navigator.pop(context);
          messengerKey.currentState?.showSnackBar(const SnackBar(content: Text("You have left the group!")));
        }
      }
    });
  }

  void _recallMessage(String messageId) async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Recall"), content: const Text("Recall this message?"), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Yes"))]));
    if (confirm == true) {
      FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('messages').doc(messageId).update({'isRecalled': true, 'text': 'Message recalled'});
    }
  }

  Widget _buildChatTab(bool isMeMuted, bool isDark) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('messages').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Center(child: Text("Send the first message!", style: TextStyle(color: Colors.grey)));

              return ListView.builder(
                reverse: true, padding: const EdgeInsets.all(16), itemCount: docs.length,
                itemBuilder: (context, index) {
                  var msg = docs[index].data() as Map<String, dynamic>;
                  String msgId = docs[index].id;
                  bool isMyMsg = msg['senderId'] == widget.currentUserId;

                  return MessageBubble(
                    msg: msg, msgId: msgId, isMyMsg: isMyMsg,
                    senderDisplayName: msg['senderName'] ?? "Anonymous",
                    primaryColor: isDark ? Colors.deepPurpleAccent : Colors.deepPurple,
                    onRecall: () => _recallMessage(msgId),
                  );
                },
              );
            },
          ),
        ),
        ChatInputBar(
          chatId: currentGroupData['id'],
          isGroup: true,
          currentUserId: widget.currentUserId,
          currentUserName: myName,
          isDisabled: isMeMuted,
          disabledMessage: "🚫 You have been banned from chatting.",
          primaryColor: isDark ? Colors.deepPurpleAccent : Colors.deepPurple,
        ),
      ],
    );
  }

  Widget _buildTasksTab(String myRole, bool isDark) {
    bool canEdit = myRole == 'admin' || myRole == 'co-admin';

    return Scaffold(
      backgroundColor: Colors.transparent, // 🔥 Use the Theme's background automatically
      floatingActionButton: canEdit ? FloatingActionButton(
        backgroundColor: isDark ? Colors.deepPurpleAccent : Colors.deepPurple,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddTaskScreen(prefilledGroupId: currentGroupData['id']))),
        child: const Icon(Icons.add_task),
      ) : null,
      body: Column(
        children: [
          // 🔥 Fix the white background issue here 
          Container(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: ListTile(
              leading: Icon(Icons.date_range, color: isDark ? Colors.deepPurpleAccent : Colors.deepPurple),
              title: Text(
                  taskFilterDateRange == null ? "Filter schedule by date" : "From ${taskFilterDateRange!.start.day}/${taskFilterDateRange!.start.month} to ${taskFilterDateRange!.end.day}/${taskFilterDateRange!.end.month}",
                  style: TextStyle(color: taskFilterDateRange == null ? Colors.grey : (isDark ? Colors.deepPurpleAccent : Colors.deepPurple), fontWeight: FontWeight.bold)
              ),
              trailing: taskFilterDateRange != null ? IconButton(icon: const Icon(Icons.clear, color: Colors.red), onPressed: () => setState(() => taskFilterDateRange = null)) : const Icon(Icons.arrow_drop_down, color: Colors.grey),
              onTap: () async {
                var range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (range != null) setState(() => taskFilterDateRange = range);
              },
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('tasks').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var docs = snapshot.data!.docs.where((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  if (d['isArchived'] == true || d['isArchived'] == 1) return false;
                  if (taskFilterDateRange != null) {
                    DateTime time = DateTime.parse(d['datetime']);
                    if (time.isBefore(taskFilterDateRange!.start.subtract(const Duration(seconds: 1))) || time.isAfter(taskFilterDateRange!.end.add(const Duration(days: 1)))) return false;
                  }
                  return true;
                }).toList();

                if (docs.isEmpty) return const Center(child: Text("No schedules found.", style: TextStyle(color: Colors.grey)));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var taskData = docs[index].data() as Map<String, dynamic>;
                    taskData['id'] = docs[index].id;
                    taskData['isGroupTask'] = true;
                    taskData['groupId'] = currentGroupData['id'];
                    taskData['groupName'] = currentGroupData['name'];

                    return TaskItem(
                      task: taskData,
                      onTaskChanged: (id) {
                        if (id != null) {
                          setState(() => highlightTaskId = id);
                          Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => highlightTaskId = null); });
                        }
                      },
                      messengerKey: messengerKey,
                      highlightTaskId: highlightTaskId,
                      showDeleteIcon: true,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    String myRole = currentGroupData['roles']?[widget.currentUserId] ?? 'member';
    List<dynamic> mutedList = currentGroupData['muted'] ?? [];
    bool isMeMuted = mutedList.contains(widget.currentUserId);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex > 1 ? 0 : widget.initialTabIndex,
      child: ScaffoldMessenger(
        key: messengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(currentGroupData['name'] ?? "Loading..."),
            // 🔥 In dark mode, the AppBar will use an OLED dark gray instead of purple
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.deepPurple,
            foregroundColor: Colors.white,
            actions: [
              IconButton(icon: Icon(isNotificationsMuted ? Icons.notifications_off : Icons.notifications_active), color: isNotificationsMuted ? Colors.white54 : Colors.yellowAccent, tooltip: "Message notifications", onPressed: _toggleGroupNotification),

              IconButton(icon: const Icon(Icons.info_outline), tooltip: "Group info", onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(
                  groupData: currentGroupData,
                  currentUserId: widget.currentUserId,
                  myName: myName,
                  myRole: myRole,
                )));
              }),
            ],
            bottom: TabBar(
                labelColor: isDark ? Colors.amber : Colors.white,
                unselectedLabelColor: isDark ? Colors.white54 : Colors.white60,
                indicatorColor: Colors.amber,
                tabs: const [Tab(icon: Icon(Icons.chat), text: "Discussion"), Tab(icon: Icon(Icons.event_note), text: "Group Schedule")]
            ),
          ),
          body: TabBarView(children: [_buildChatTab(isMeMuted, isDark), _buildTasksTab(myRole, isDark)]),
        ),
      ),
    );
  }
}
