import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'private_chat_details_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_bar.dart';

class PrivateChatScreen extends StatefulWidget {
  static String? currentActivePrivateChatId;
  final String chatId;
  final String targetUid;
  final String targetName;
  final String? targetAvatar;

  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.targetUid,
    required this.targetName,
    this.targetAvatar,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;
  bool isMuted = false;

  String get myName {
    User? u = FirebaseAuth.instance.currentUser;
    return (u?.displayName != null && u!.displayName!.isNotEmpty)
        ? u.displayName!
        : (u?.phoneNumber ?? u?.email ?? "Me");
  }

  @override
  void initState() {
    super.initState();
    PrivateChatScreen.currentActivePrivateChatId = widget.chatId;
    _checkMuteStatus();
  }

  @override
  void dispose() {
    PrivateChatScreen.currentActivePrivateChatId = null;
    super.dispose();
  }

  void _checkMuteStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => isMuted = prefs.getBool('mute_chat_${widget.chatId}') ?? false);
  }

  void _toggleMute() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => isMuted = !isMuted);
    await prefs.setBool('mute_chat_${widget.chatId}', isMuted);

    final db = FirebaseFirestore.instance;
    if (isMuted) {
      await db.collection('users').doc(myUid).update({
        'mutedChats': FieldValue.arrayUnion([widget.chatId])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🔇 Notifications turned off.")),
        );
      }
    } else {
      await db.collection('users').doc(myUid).update({
        'mutedChats': FieldValue.arrayRemove([widget.chatId])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🔔 Notifications turned on.")),
        );
      }
    }
  }

  void _recallMessage(String messageId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Recall Message"),
        content: const Text("Do you want to recall this message?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Recall",
              style: TextStyle(color: Colors.white),
            ),
          )
        ],
      ),
    );

    if (confirm == true) {
      FirebaseFirestore.instance
          .collection('private_chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({'isRecalled': true, 'text': 'Message was recalled'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              backgroundImage: widget.targetAvatar != null
                  ? NetworkImage(widget.targetAvatar!)
                  : null,
              child: widget.targetAvatar == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.targetName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isMuted ? Icons.notifications_off : Icons.notifications_active,
            ),
            color: isMuted ? Colors.white54 : Colors.yellowAccent,
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrivateChatDetailsScreen(
                  chatId: widget.chatId,
                  targetUid: widget.targetUid,
                  targetName: widget.targetName,
                  targetAvatar: widget.targetAvatar,
                ),
              ),
            ),
          )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
        builder: (context, mySnap) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(widget.targetUid).snapshots(),
            builder: (context, targetSnap) {
              bool iBlockedThem = false;
              bool theyBlockedMe = false;

              if (mySnap.hasData && mySnap.data!.data() != null) {
                var myData = mySnap.data!.data() as Map<String, dynamic>;
                List blocked = myData['blockedUsers'] ?? [];
                iBlockedThem = blocked.contains(widget.targetUid);
              }

              if (targetSnap.hasData && targetSnap.data!.data() != null) {
                var targetData = targetSnap.data!.data() as Map<String, dynamic>;
                List blocked = targetData['blockedUsers'] ?? [];
                theyBlockedMe = blocked.contains(myUid);
              }

              bool isBlocked = iBlockedThem || theyBlockedMe;

              return Column(
                children: [
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

                        var docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              "Send the first greeting message!",
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            var msg = docs[index].data() as Map<String, dynamic>;
                            String msgId = docs[index].id;

                            bool isMyMsg = msg['senderId'] == myUid;

                            return MessageBubble(
                              msg: msg,
                              msgId: msgId,
                              isMyMsg: isMyMsg,
                              senderDisplayName: isMyMsg ? "You" : widget.targetName,
                              primaryColor: Colors.pink,
                              onRecall: () => _recallMessage(msgId),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  ChatInputBar(
                    chatId: widget.chatId,
                    isGroup: false,
                    currentUserId: myUid,
                    currentUserName: myName,
                    isDisabled: isBlocked,
                    disabledMessage: iBlockedThem
                        ? "You have blocked this user."
                        : "You can’t message this user right now.",
                    primaryColor: Colors.pink,
                  )
                ],
              );
            },
          );
        },
      ),
    );
  }
}
