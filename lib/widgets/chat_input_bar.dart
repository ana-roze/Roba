import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class ChatInputBar extends StatefulWidget {
  final String chatId;
  final bool isGroup;
  final String currentUserId;
  final String currentUserName;
  final bool isDisabled;
  final String disabledMessage;
  final Color primaryColor;

  const ChatInputBar({
    super.key,
    required this.chatId,
    required this.isGroup,
    required this.currentUserId,
    required this.currentUserName,
    this.isDisabled = false,
    this.disabledMessage = "You can't send messages.",
    this.primaryColor = Colors.blue,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _chatController = TextEditingController();
  bool isUploading = false;

  Future<void> _sendImages() async {
    final ImagePicker picker = ImagePicker();
    List<XFile> images = [];
    try {
      images = await picker.pickMultiImage(imageQuality: 70);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking images: $e")),
        );
      }
      return;
    }
    if (images.isEmpty) return;

    setState(() => isUploading = true);
    List<String> imageUrls = [];

    try {
      String folder = widget.isGroup ? 'group_chat_images' : 'chat_images';

      for (var img in images) {
        final ref = FirebaseStorage.instance.ref().child(
              '$folder/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${img.name}',
            );
        await ref.putFile(File(img.path));
        imageUrls.add(await ref.getDownloadURL());
      }

      String text = _chatController.text.trim();
      _chatController.clear();

      String collection = widget.isGroup ? 'groups' : 'private_chats';

      Map<String, dynamic> msgData = {
        'text': text,
        'images': imageUrls,
        'hasImage': true,
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'timestamp': FieldValue.serverTimestamp(),
        'isRecalled': false,
      };
      if (widget.isGroup) msgData['isSystem'] = false;

      await FirebaseFirestore.instance
          .collection(collection)
          .doc(widget.chatId)
          .collection('messages')
          .add(msgData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sending images: $e")),
        );
      }
    }
    if (mounted) setState(() => isUploading = false);
  }

  void _sendMessage() {
    String text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();

    String collection = widget.isGroup ? 'groups' : 'private_chats';

    Map<String, dynamic> msgData = {
      'text': text,
      'images': <String>[],
      'hasImage': false,
      'senderId': widget.currentUserId,
      'senderName': widget.currentUserName,
      'timestamp': FieldValue.serverTimestamp(),
      'isRecalled': false,
    };
    if (widget.isGroup) msgData['isSystem'] = false;

    FirebaseFirestore.instance
        .collection(collection)
        .doc(widget.chatId)
        .collection('messages')
        .add(msgData);
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isUploading)
          LinearProgressIndicator(color: widget.primaryColor),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            // Update the background color of the input bar based on the system theme.
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
          ),
          child: widget.isDisabled
              ? Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Center(
                    child: Text(
                      widget.disabledMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.image,
                          color: widget.primaryColor, size: 28),
                      onPressed: isUploading ? null : _sendImages,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.color,
                        ),
                        decoration: InputDecoration(
                          hintText: "Enter a message...",
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          // The text container background color adapts to the dark theme softly.
                          fillColor:
                              isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: widget.primaryColor,
                      child: IconButton(
                        icon: const Icon(Icons.send,
                            color: Colors.white, size: 20),
                        onPressed: _sendMessage,
                      ),
                    )
                  ],
                ),
        ),
      ],
    );
  }
}
