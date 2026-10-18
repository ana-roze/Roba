import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/social_service.dart'; // 👉 NEW SERVICE IMPORT
import 'group_detail_screen.dart';

class PrivateChatDetailsScreen extends StatefulWidget {
  final String chatId;
  final String targetUid;
  final String targetName;
  final String? targetAvatar;

  const PrivateChatDetailsScreen({
    super.key,
    required this.chatId,
    required this.targetUid,
    required this.targetName,
    this.targetAvatar,
  });

  @override
  State<PrivateChatDetailsScreen> createState() => _PrivateChatDetailsScreenState();
}

class _PrivateChatDetailsScreenState extends State<PrivateChatDetailsScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();

  String searchQuery = "";
  List<Map<String, dynamic>> commonGroups = [];
  bool isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _findCommonGroups();
  }

  void _findCommonGroups() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: myUid)
          .get();

      List<Map<String, dynamic>> tempGroups = [];
      for (var doc in snapshot.docs) {
        var groupData = doc.data();
        List<dynamic> members = groupData['members'] ?? [];

        if (members.contains(widget.targetUid)) {
          tempGroups.add({...groupData, 'id': doc.id});
        }
      }

      if (mounted) {
        setState(() {
          commonGroups = tempGroups;
          isLoadingGroups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingGroups = false);
      }
    }
  }

  // 🔥 CALL FUNCTION FROM SOCIAL SERVICE
  void _toggleBlock(bool isCurrentlyBlocked) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isCurrentlyBlocked ? "Unblock" : "Block User"),
        content: Text(
          isCurrentlyBlocked
              ? "Do you want to unblock ${widget.targetName}?"
              : "Block ${widget.targetName}? This person will not be able to message you and you two will be unfriended.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyBlocked ? Colors.green : Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              isCurrentlyBlocked ? "Unblock" : "Block",
              style: const TextStyle(color: Colors.white),
            ),
          )
        ],
      ),
    );

    if (confirm == true) {
      await SocialService.toggleBlockUser(
        myUid,
        widget.targetUid,
        isCurrentlyBlocked,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
          title: Text(
            "Details: ${widget.targetName}",
            style: const TextStyle(fontSize: 16),
          ),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.search), text: "Messages"),
              Tab(icon: Icon(Icons.image), text: "Photo Folder"),
              Tab(icon: Icon(Icons.groups), text: "Groups & Settings"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: SEARCH
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Enter keywords...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (val) =>
                        setState(() => searchQuery = val.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('private_chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var docs = snapshot.data!.docs.where((doc) {
                        if (searchQuery.isEmpty) return false;

                        var data = doc.data() as Map<String, dynamic>;

                        if (data['isRecalled'] == true) return false;

                        String text = (data['text'] ?? "").toString().toLowerCase();
                        return text.contains(searchQuery);
                      }).toList();

                      if (searchQuery.isNotEmpty && docs.isEmpty) {
                        return const Center(
                          child: Text("No messages found."),
                        );
                      }

                      if (searchQuery.isEmpty) {
                        return const Center(
                          child: Text(
                            "Enter keywords to search",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var msg = docs[index].data() as Map<String, dynamic>;
                          bool isMyMsg = msg['senderId'] == myUid;

                          DateTime? time = msg['timestamp'] != null
                              ? (msg['timestamp'] as Timestamp).toDate()
                              : null;

                          String timeStr = time != null
                              ? "${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}"
                              : "";

                          return ListTile(
                            leading: Icon(
                              isMyMsg ? Icons.arrow_circle_right : Icons.arrow_circle_left,
                              color: isMyMsg ? Colors.pink : Colors.grey,
                            ),
                            title: Text(
                              msg['text'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "${isMyMsg ? 'You' : widget.targetName} • $timeStr",
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),

            // TAB 2: PHOTO FOLDER
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('private_chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;

                  bool hasImage = data['hasImage'] == true ||
                      (data['images'] != null &&
                          (data['images'] as List).isNotEmpty);

                  return hasImage && data['isRecalled'] != true;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No photos have been shared yet.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                List<Map<String, dynamic>> allImages = [];
                for (var doc in docs) {
                  var msg = doc.data() as Map<String, dynamic>;
                  List<dynamic> images = msg['images'] ?? [];

                  DateTime? time = msg['timestamp'] != null
                      ? (msg['timestamp'] as Timestamp).toDate()
                      : null;

                  String senderName = msg['senderId'] == myUid ? "You" : widget.targetName;

                  for (var url in images) {
                    allImages.add({
                      'url': url,
                      'senderName': senderName,
                      'time': time,
                    });
                  }
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: allImages.length,
                  itemBuilder: (context, index) {
                    var imgInfo = allImages[index];
                    DateTime? time = imgInfo['time'];

                    String timeStr = time != null
                        ? "${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}"
                        : "";

                    return GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: EdgeInsets.zero,
                            child: Stack(
                              children: [
                                Center(
                                  child: InteractiveViewer(
                                    child: Image.network(
                                      imgInfo['url'],
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 40,
                                  right: 20,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                                Positioned(
                                  bottom: 20,
                                  left: 20,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      "Sent by: ${imgInfo['senderName']}\nTime: $timeStr",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imgInfo['url'],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // TAB 3: COMMON GROUPS & SETTINGS
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
              builder: (context, snapshot) {
                bool isBlocked = false;

                if (snapshot.hasData && snapshot.data!.data() != null) {
                  var myData = snapshot.data!.data() as Map<String, dynamic>;
                  List blocked = myData['blockedUsers'] ?? [];
                  isBlocked = blocked.contains(widget.targetUid);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Settings",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        isBlocked ? Icons.block : Icons.block,
                        color: isBlocked ? Colors.green : Colors.red,
                      ),
                      title: Text(
                        isBlocked ? "Unblock this user" : "Block user",
                        style: TextStyle(
                          color: isBlocked ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _toggleBlock(isBlocked),
                    ),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Common Groups",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                    Expanded(
                      child: isLoadingGroups
                          ? const Center(child: CircularProgressIndicator())
                          : commonGroups.isEmpty
                              ? const Center(
                                  child: Text(
                                    "The two of you haven't joined any common groups yet.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: commonGroups.length,
                                  itemBuilder: (context, index) {
                                    var group = commonGroups[index];

                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          backgroundColor: Colors.deepPurple,
                                          child: Icon(
                                            Icons.group,
                                            color: Colors.white,
                                          ),
                                        ),
                                        title: Text(
                                          group['name'] ?? "Unnamed group",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                        ),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => GroupDetailScreen(
                                              groupData: group,
                                              currentUserId: myUid,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
