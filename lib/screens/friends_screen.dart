import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import 'private_chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;

  // 🔥 Variable storing search query for contacts
  String _contactSearchQuery = "";
  final TextEditingController _contactSearchController = TextEditingController();

  String get myName {
    User? u = FirebaseAuth.instance.currentUser;
    return (u?.displayName != null && u!.displayName!.isNotEmpty) ? u.displayName! : (u?.phoneNumber ?? u?.email ?? "Anonymous");
  }

  // UI TAB 1: SEARCH FOR NEW FRIENDS ON SYSTEM
  Widget _buildSearchTab() {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    return StatefulBuilder(
        builder: (context, setSearchState) {
          void searchUser() async {
            String input = searchController.text.trim();
            if (input.isEmpty) return;

            setSearchState(() => isSearching = true);
            String phoneInput = input.startsWith('0') ? '+84${input.substring(1)}' : input;

            try {
              var emailQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: input).get();
              var phoneQuery = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: phoneInput).get();

              Map<String, Map<String, dynamic>> resultsMap = {};
              for (var doc in emailQuery.docs) {
                if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
              }
              for (var doc in phoneQuery.docs) {
                if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
              }

              setSearchState(() => searchResults = resultsMap.values.toList());

              if (searchResults.isEmpty && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No one found.")));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Search error: $e")));
            }
            setSearchState(() => isSearching = false);
          }

          void sendFriendRequest(String targetUid) async {
            try {
              await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
                'friendRequests': FieldValue.arrayUnion([myUid])
              }, SetOptions(merge: true));

              await NotificationService().sendFriendRequestNotification(targetUid, myName);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent!")));
                setSearchState(() => searchResults.removeWhere((u) => u['uid'] == targetUid));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error sending request: $e")));
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                            hintText: "Enter Email or Phone Number...",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0)
                        ),
                        onSubmitted: (_) => searchUser(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: searchUser,
                      child: const Text("Search"),
                    )
                  ],
                ),
                const SizedBox(height: 20),
                if (isSearching) const CircularProgressIndicator(),
                Expanded(
                  child: ListView.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = searchResults[index];
                      return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox();
                            var data = snapshot.data!.data() as Map<String, dynamic>?;
                            List friends = data?['friends'] ?? [];
                            List blocked = data?['blockedUsers'] ?? [];

                            bool isFriend = friends.contains(user['uid']);
                            bool isBlocked = blocked.contains(user['uid']);

                            if (isBlocked) return const SizedBox.shrink();

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.pink,
                                backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                                child: user['photoURL'] == null ? const Icon(Icons.person, color: Colors.white) : null,
                              ),
                              title: Text(user['displayName'] ?? "Anonymous", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(user['email']?.isNotEmpty == true ? user['email'] : user['phone']),
                              trailing: isFriend
                                  ? const Text("Already friends", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                  : ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                onPressed: () => sendFriendRequest(user['uid']),
                                child: const Text("Add Friend"),
                              ),
                            );
                          }
                      );
                    },
                  ),
                )
              ],
            ),
          );
        }
    );
  }

  // UI TAB 2: REQUESTS
  Widget _buildRequestsTab() {
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          Map<String, dynamic>? data = snapshot.data!.data() as Map<String, dynamic>?;
          List<dynamic> requestIds = data?['friendRequests'] ?? [];

          if (requestIds.isEmpty) return const Center(child: Text("No friend requests."));

          return FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: requestIds).get(),
              builder: (context, reqSnapshot) {
                if (!reqSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                var reqUsers = reqSnapshot.data!.docs;

                void acceptRequest(String targetUid) async {
                  final db = FirebaseFirestore.instance;
                  await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayUnion([targetUid])});
                  await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayUnion([myUid])});
                  await db.collection('users').doc(myUid).update({'friendRequests': FieldValue.arrayRemove([targetUid])});
                }

                void rejectRequest(String targetUid) async {
                  await FirebaseFirestore.instance.collection('users').doc(myUid).update({'friendRequests': FieldValue.arrayRemove([targetUid])});
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reqUsers.length,
                  itemBuilder: (context, index) {
                    var user = reqUsers[index].data() as Map<String, dynamic>;
                    String uid = reqUsers[index].id;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                          child: user['photoURL'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(user['displayName'] ?? "Anonymous"),
                        subtitle: const Text("Wants to be friends with you"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.check_circle, color: Colors.green, size: 30), onPressed: () => acceptRequest(uid)),
                            IconButton(icon: const Icon(Icons.cancel, color: Colors.red, size: 30), onPressed: () => rejectRequest(uid)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }
          );
        }
    );
  }

  // UI TAB 3: CONTACTS (WITH SEARCH)
  Widget _buildFriendsListTab() {
    return Column(
      children: [
        // 🔥 SEARCH BAR IN CONTACTS
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _contactSearchController,
            decoration: InputDecoration(
              hintText: "Search friends in contacts...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (value) {
              setState(() {
                _contactSearchQuery = value;
              });
            },
          ),
        ),

        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                Map<String, dynamic>? data = snapshot.data!.data() as Map<String, dynamic>?;
                List<dynamic> friendIds = data?['friends'] ?? [];
                List<dynamic> blockedIds = data?['blockedUsers'] ?? [];

                if (friendIds.isEmpty && blockedIds.isEmpty) return const Center(child: Text("You don't have any friends yet."));

                List<dynamic> allRelevantIds = {...friendIds, ...blockedIds}.toList();

                return FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: allRelevantIds).get(),
                    builder: (context, friendsSnapshot) {
                      if (!friendsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var users = friendsSnapshot.data!.docs;

                      // 🔥 FILTER LIST BY SEARCH QUERY
                      var filteredUsers = users.where((doc) {
                        var user = doc.data() as Map<String, dynamic>;
                        String name = user['displayName']?.toLowerCase() ?? "anonymous";
                        String email = user['email']?.toLowerCase() ?? "";
                        String phone = user['phone']?.toLowerCase() ?? "";
                        String query = _contactSearchQuery.toLowerCase();

                        return name.contains(query) || email.contains(query) || phone.contains(query);
                      }).toList();

                      void removeFriend(String targetUid, String targetName) async {
                        bool? confirm = await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                                title: const Text("Unfriend"),
                                content: Text("Are you sure you want to unfriend $targetName?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Unfriend", style: TextStyle(color: Colors.white)))
                                ]
                            )
                        );

                        if (confirm == true) {
                          final db = FirebaseFirestore.instance;
                          await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayRemove([targetUid])});
                          await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayRemove([myUid])});
                        }
                      }

                      void toggleBlock(String targetUid, String targetName, bool isBlocked) async {
                        bool? confirm = await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                                title: Text(isBlocked ? "Unblock" : "Block User"),
                                content: Text(isBlocked ? "Do you want to unblock $targetName?" : "Are you sure you want to block $targetName? You won't be able to message each other privately."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: isBlocked ? Colors.green : Colors.red), onPressed: () => Navigator.pop(context, true), child: Text(isBlocked ? "Confirm" : "Block", style: const TextStyle(color: Colors.white)))
                                ]
                            )
                        );

                        if (confirm == true) {
                          final db = FirebaseFirestore.instance;
                          if (isBlocked) {
                            await db.collection('users').doc(myUid).update({'blockedUsers': FieldValue.arrayRemove([targetUid])});
                          } else {
                            await db.collection('users').doc(myUid).update({'blockedUsers': FieldValue.arrayUnion([targetUid])});
                            await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayRemove([targetUid])});
                            await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayRemove([myUid])});
                          }
                        }
                      }

                      if (filteredUsers.isEmpty) {
                        return const Center(child: Text("No friends found."));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          var user = filteredUsers[index].data() as Map<String, dynamic>;
                          String uid = filteredUsers[index].id;
                          String name = user['displayName'] ?? "Anonymous";
                          bool isBlocked = blockedIds.contains(uid);
                          bool isFriend = friendIds.contains(uid);

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isBlocked ? Colors.grey : Colors.green,
                                backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                                child: user['photoURL'] == null ? const Icon(Icons.person, color: Colors.white) : null,
                              ),
                              // 🔥 FIXED TEXT COLOR ISSUE: Removed "color: Colors.black", replaced with null to auto-adapt to Light/Dark mode
                              title: Text(
                                  name + (isBlocked ? " (Blocked)" : ""),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isBlocked ? Colors.grey : null
                                  )
                              ),
                              subtitle: Text(user['email']?.isNotEmpty == true ? user['email'] : user['phone']),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isBlocked && isFriend)
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble, color: Colors.blue),
                                      tooltip: "Message",
                                      onPressed: () {
                                        String chatId = myUid.compareTo(uid) < 0 ? '${myUid}_$uid' : '${uid}_$myUid';
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(
                                          chatId: chatId,
                                          targetUid: uid,
                                          targetName: name,
                                          targetAvatar: user['photoURL'],
                                        )));
                                      },
                                    ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'remove') removeFriend(uid, name);
                                      else if (value == 'block') toggleBlock(uid, name, isBlocked);
                                    },
                                    itemBuilder: (context) => [
                                      if (isFriend)
                                        const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.person_remove, color: Colors.orange, size: 20), SizedBox(width: 8), Text("Unfriend")])),
                                      PopupMenuItem(value: 'block', child: Row(children: [Icon(isBlocked ? Icons.check_circle : Icons.block, color: Colors.red, size: 20), SizedBox(width: 8), Text(isBlocked ? "Unblock" : "Block User")])),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                );
              }
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Friends & Contacts"),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.contacts), text: "Contacts"),
              Tab(icon: Icon(Icons.person_add), text: "Requests"),
              Tab(icon: Icon(Icons.search), text: "Search"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFriendsListTab(),
            _buildRequestsTab(),
            _buildSearchTab(),
          ],
        ),
      ),
    );
  }
}