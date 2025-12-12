import 'package:flutter/material.dart';
import '../services/appwrite_service.dart';

class ChatPage extends StatefulWidget {
  final AppwriteService appwrite;
  final String groupId;
  final String userId;

  const ChatPage({super.key, required this.appwrite, required this.groupId, required this.userId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Map<String, dynamic>> messages = [];
  final TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.appwrite.subscribeToMessages(widget.groupId, (payload) {
      setState(() => messages.add(payload));
    });
  }

  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    widget.appwrite.sendMessage(widget.groupId, widget.userId, text);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Group Chat")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final msg = messages[i];
                return ListTile(
                  title: Text(msg['text'] ?? ''),
                  subtitle: Text(msg['userId'] ?? ''),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(controller: controller, decoration: const InputDecoration(hintText: "Type message...")),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
