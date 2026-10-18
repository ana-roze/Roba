import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../main.dart';
import '../services/social_service.dart';
import '../services/notification_service.dart';
import '../database/db_helper.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool isLoading = false;
  String loadingText = "Deleting..."; // Display status when Deep Delete

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 🔥 CAMPAIGN DEEP DELETE
  Future<void> _performDelete() async {
    setState(() {
      isLoading = true;
      loadingText = "Initializing the data deletion process...";
    });

    try {
      String uid = user!.uid;
      String myName = user!.displayName ?? "User";

      // 1. Get document information for User
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List<dynamic> friends = userDoc.data()?['friends'] ?? [];

      // 2. Delete all personal schedules (Local DB & Notifications)
      setState(() => loadingText = "Cleaning up personal schedules...");
      final dbHelper = DBHelper();
      var allTasks = await dbHelper.getAllTasks();
      for (var t in allTasks) {
        await dbHelper.deleteTask(t['id']);
      }

      // 3. Unfriend everyone in your contacts
      setState(() => loadingText = "Disconnecting friends...");
      await SocialService.unfriendAll(uid, friends);

      // 4. Processing group data (Leave / Unbanned)
      setState(() => loadingText = "Processing group data...");
      await SocialService.processGroupsOnDelete(uid, myName);

      // 5. Scan and delete messages Private Chat
      setState(() => loadingText = "Deleting private message data...");
      await SocialService.deleteAllPrivateChats(uid);

      // 6. Delete Avatar from Firebase Storage
      setState(() => loadingText = "Cleaning up Storage...");
      try {
        await FirebaseStorage.instance.ref().child('avatars/$uid.jpg').delete();
      } catch (e) {
        debugPrint("No avatar to delete.");
      }

      // 7. Delete all local notifications, Push Token and Cache
      setState(() => loadingText = "Disconnecting from the system...");
      await NotificationService().clearAllNotificationsOnLogout();

      // 8. Final blow: Delete User Document and Firebase Auth
      setState(() => loadingText = "Permanently deleting account...");
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      await GoogleSignIn().signOut();
      await user!.delete();

      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      _showMsg("Error deleting account: Please try again later.");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _verifyPhoneForReauth(String phoneNumber) async {
    setState(() {
      isLoading = true;
      loadingText = "Sending SMS verification code...";
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await user!.reauthenticateWithCredential(credential);
        await _performDelete();
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => isLoading = false);
        _showMsg("SMS verification error: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() => isLoading = false);
        _showOTPDialog(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  void _showOTPDialog(String verificationId) {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Verify OTP"),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 5),
          maxLength: 6,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              try {
                PhoneAuthCredential credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otpController.text.trim());
                await user!.reauthenticateWithCredential(credential);
                Navigator.pop(context);
                await _performDelete();
              } catch (e) {
                _showMsg("Invalid OTP code!");
              }
            },
            child: const Text("Confirm"),
          )
        ],
      ),
    );
  }

  void _deleteAccount() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("ACCOUNT DELETION WARNING", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
        "Deleting your account will:\n\n"
        "- Permanently delete your personal schedules.\n"
        "- Disband groups you manage.\n"
        "- Leave all groups you are a member of.\n"
        "- Remove all friends from your contacts.\n"
        "- Delete all messages you have sent.\n\n"
        "Are you sure you want to proceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Agree to delete", style: TextStyle(color: Colors.white))),
        ],
      ),
    );

    if (confirm != true) return;

    if (user == null) return;
    String providerId = user!.providerData.isNotEmpty ? user!.providerData.first.providerId : 'unknown';

    try {
      if (providerId == 'password') {
        final passController = TextEditingController();
        bool? authConfirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                title: const Text("Security Verification"),
                content: TextField(controller: passController, decoration: const InputDecoration(labelText: "Enter your current password"), obscureText: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm"))
                ]
            )
        );
        if (authConfirm == true) {
          AuthCredential credential = EmailAuthProvider.credential(email: user!.email!, password: passController.text);
          await user!.reauthenticateWithCredential(credential);
          await _performDelete();
        }
      } else if (providerId == 'google.com') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser != null) {
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          AuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
          await user!.reauthenticateWithCredential(credential);
          await _performDelete();
        }
      } else if (providerId == 'phone' || user!.phoneNumber != null) {
        _verifyPhoneForReauth(user!.phoneNumber!);
      } else {
        _showMsg("Error: No authentication method found.");
      }
    } catch (e) {
      _showMsg("Authentication failed. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Account Settings")),
      body: isLoading
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.red),
            const SizedBox(height: 20),
            Text(loadingText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Text("Please do not close the app...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: isDarkMode ? Colors.yellow : Colors.orange,
                size: 30
            ),
            title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: const Text("Change app appearance"),
            trailing: Switch(
              value: isDarkMode,
              activeColor: Colors.red,
              onChanged: (value) async {
                setState(() {
                  themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                });
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isDarkTheme', value);
              },
            ),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red, size: 30),
            title: const Text("Delete Account", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: const Text("Permanently delete your account and related data"),
            onTap: _deleteAccount,
          ),
          const Divider(),
        ],
      ),
    );
  }
}
