import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final String msgId;
  final bool isMyMsg;
  final String senderDisplayName;
  final VoidCallback? onRecall;
  final Color primaryColor;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.msgId,
    required this.isMyMsg,
    required this.senderDisplayName,
    required this.primaryColor,
    this.onRecall,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Fix system messages layout/image
    if (msg['isSystem'] == true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200], // Highlight background
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2),
              ],
            ),
            child: Text(
              msg['text'] ?? "",
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black87, // Clear white/black text
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    bool isRecalled = msg['isRecalled'] == true;
    List<dynamic> images = msg['images'] ?? [];
    String text = msg['text'] ?? "";

    Color bubbleColor = isMyMsg
        ? primaryColor
        : (isDark ? const Color(0xFF2C2C2C) : Colors.white);

    Color textColor = isMyMsg
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    return Align(
      alignment: isMyMsg ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: (isMyMsg && !isRecalled) ? onRecall : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment:
                isMyMsg ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMyMsg)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    senderDisplayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isRecalled ? Colors.transparent : bubbleColor,
                  border: isRecalled
                      ? Border.all(color: Colors.grey.shade400)
                      : (isMyMsg
                          ? null
                          : Border.all(
                              color: isDark ? Colors.white12 : Colors.black12)),
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomRight:
                        isMyMsg ? const Radius.circular(0) : const Radius.circular(16),
                    bottomLeft:
                        !isMyMsg ? const Radius.circular(0) : const Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRecalled)
                      Text(
                        "Message recalled",
                        style: TextStyle(
                          color: isDark ? Colors.grey[500] : Colors.grey,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      ...[
                        if (images.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: images.map((url) {
                              return GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: EdgeInsets.zero,
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: InteractiveViewer(
                                              child: Image.network(
                                                url,
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
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        if (images.isNotEmpty && text.isNotEmpty)
                          const SizedBox(height: 8),
                        if (text.isNotEmpty)
                          Text(
                            text,
                            style: TextStyle(color: textColor, fontSize: 15),
                          ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
