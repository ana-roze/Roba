import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class GeminiService {
  // 🔥 RAM CACHE: Cache API Key to prevent redundant Firebase Firestore fetches
  static String? _cachedApiKey;

  static Future<List<Map<String, dynamic>>?> chatAndAct(String input, {String groupContext = "", String currentScreen = "personal"}) async {

    // Only fetch key from Firebase if it's not cached in RAM
    if (_cachedApiKey == null || _cachedApiKey!.isEmpty) {
      try {
        var doc = await FirebaseFirestore.instance.collection('app_config').doc('keys').get();
        if (doc.exists && doc.data() != null) {
          _cachedApiKey = doc.data()!['gemini_api_key'] ?? "";
        }
      } catch (e) {
        return [{"type": "error", "message": "Error connecting to AI server."}];
      }
    }

    if (_cachedApiKey == null || _cachedApiKey!.isEmpty) {
      return [{"type": "error", "message": "AI System maintenance (Missing API Key)."}] ;
    }

    // Updated model to Gemini 3.1 Flash-Lite
    final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=$_cachedApiKey";
    String now = DateTime.now().toIso8601String();

    String locationContext = currentScreen == "personal"
        ? "User is in PERSONAL SPACE. Default to creating Personal schedules if no group is mentioned."
        : "User is IN A GROUP. Default to creating Group schedules unless specified otherwise.";

    final systemInstruction = """
You are a Schedule Management AI (Personal & Group). Current time: $now.
$locationContext

LIST OF GROUPS WITH ADMIN/CO-ADMIN PERMISSIONS (Only create/update/delete allowed here):
$groupContext

FUNCTION USAGE INSTRUCTIONS:
1. Communication: Respond naturally using text.
2. Personal schedule: "create", "update", "delete". 
3. Group schedule: "create_group_task", "update_group_task", "delete_group_task".
  - MUST accurately pass "groupId" retrieved from the list above.
  - Refuse if requested group operation is not in the allowed list.
4. Update/Delete: Must pass `targetTitles` array containing title keywords.
""";

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "system_instruction": {
            "parts": [{"text": systemInstruction}]
          },
          "contents": [
            {"role": "user", "parts": [{"text": input}]}
          ],
          "tools": [
            {
              "function_declarations": [
                {
                  "name": "manage_tasks",
                  "description": "Call to Create, Update, or Delete Personal or Group schedules.",
                  "parameters": {
                    "type": "OBJECT",
                    "properties": {
                      "tasks": {
                        "type": "ARRAY",
                        "items": {
                          "type": "OBJECT",
                          "properties": {
                            "action": {"type": "STRING"},
                            "title": {"type": "STRING"},
                            "description": {"type": "STRING"},
                            "datetime": {"type": "STRING"},
                            "remindBeforeMins": {"type": "NUMBER"},
                            "repeatMode": {"type": "STRING"},
                            "groupId": {"type": "STRING"},
                            "targetTitles": {
                              "type": "ARRAY",
                              "items": {"type": "STRING"}
                            }
                          },
                          "required": ["action"]
                        }
                      }
                    }
                  }
                }
              ]
            }
          ],
          "tool_config": {
            "function_calling_config": {"mode": "AUTO"}
          }
        }),
      );

      final data = jsonDecode(res.body);

      if (data.containsKey("error")) {
        return [{"type": "error", "message": "Google API Error: ${data['error']['message']}"}];
      }

      final parts = data["candidates"][0]["content"]["parts"];
      final firstPart = parts[0] as Map<String, dynamic>;

      if (firstPart.containsKey("functionCall")) {
        final args = firstPart["functionCall"]["args"] ?? {};
        List<Map<String, dynamic>> results = [];
        if (args.containsKey("tasks")) {
          for (var item in args["tasks"]) {
            results.add({
              "type": "action",
              "action": item["action"],
              "title": item["title"],
              "description": item["description"],
              "datetime": item["datetime"],
              "remindBeforeMins": item["remindBeforeMins"],
              "repeatMode": item["repeatMode"],
              "groupId": item["groupId"],
              "targetTitles": item["targetTitles"] != null ? List<String>.from(item["targetTitles"]) : null,
            });
          }
          return results;
        }
      }

      return [{"type": "text", "message": firstPart["text"] ?? "I did not understand your request."}];

    } catch (e) {
      return [{"type": "error", "message": "System error: $e"}];
    }
  }
}
