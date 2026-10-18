import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  // 🔥 Variable to store group search keyword
  String _searchGroupQuery = "";
  final TextEditingController _searchController = TextEditingController();

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  void _createGroup() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create a new group"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "Enter group name..."),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(context);

              String code = "G-${_generateCode()}";
              var ref = FirebaseFirestore.instance.collection('groups').doc();

              await ref.set({
                'id': ref.id,
                'name': nameController.text.trim(),
                'inviteCode': code,
                'members': [myUid],
                'roles': {myUid: 'admin'},
                'createdAt': DateTime.now().toIso8601String()
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Group created successfully!")),
                );
              }
            },
            child: const Text("Create"),
          )
        ],
      ),
    );
  }

  void _joinGroup() {
    TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Join a group"),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            hintText: "Enter group code (e.g., G-123456)",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              String code = codeController.text.trim().toUpperCase();
              if (code.isEmpty) return;
              Navigator.pop(context);

              var query = await FirebaseFirestore.instance
                  .collection('groups')
                  .where('inviteCode', isEqualTo: code)
                  .get();

              if (query.docs.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Group code not found!")),
                  );
                }
                return;
              }

              var doc = query.docs.first;

              await doc.reference.update({
                'members': FieldValue.arrayUnion([myUid]),
                'roles.$myUid': 'member'
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Joined successfully!")),
                );
              }
            },
            child: const Text("Join"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (myUid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Please log in to use the Groups feature")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Groups"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: _createGroup,
            tooltip: "Create group",
          ),
          IconButton(
            icon: const Icon(Icons.login),
            onPressed: _joinGroup,
            tooltip: "Join group",
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔥 Group search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search groups you have joined...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchGroupQuery = value;
                });
              },
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .where('members', arrayContains: myUid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_off,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "You haven't joined any groups",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text("Create group"),
                              onPressed: _createGroup,
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.login),
                              label: const Text("Join group"),
                              onPressed: _joinGroup,
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                }

                var groups = snapshot.data!.docs;

                // 🔥 Filter groups by search keyword
                var filteredGroups = groups.where((doc) {
                  var groupData = doc.data() as Map<String, dynamic>;
                  String groupName = groupData['name'] ?? "";
                  return groupName
                      .toLowerCase()
                      .contains(_searchGroupQuery.toLowerCase());
                }).toList();

                if (filteredGroups.isEmpty) {
                  return const Center(child: Text("No matching groups found."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredGroups.length,
                  itemBuilder: (context, index) {
                    var group =
                        filteredGroups[index].data() as Map<String, dynamic>;

                    int memberCount = (group['members'] as List).length;
                    bool isAdmin = group['roles'][myUid] == 'admin';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Icon(Icons.groups, color: Colors.white),
                        ),
                        title: Text(
                          group['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          "$memberCount members  •  Code: ${group['inviteCode']}",
                        ),
                        trailing: isAdmin
                            ? const Icon(Icons.star, color: Colors.amber)
                            : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupDetailScreen(
                                groupData: group,
                                currentUserId: myUid,
                              ),
                            ),
                          );
                        },
                      ),
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
}
