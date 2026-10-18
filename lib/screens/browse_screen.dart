import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../database/db_helper.dart';
import 'task_detail_list_screen.dart';
import 'friends_screen.dart';
import '../services/notification_service.dart';
import 'account_detail_screen.dart';
import 'main_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DBHelper dbHelper = DBHelper();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;

  int totalTasks = 0;
  int completedTasks = 0;
  int pendingTasks = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() async {
    final personalTasks = await dbHelper.getAllTasks();
    final mixedTasks = await dbHelper.getMixedTasks();
    final groupTasks = mixedTasks.where((t) => t['isGroupTask'] == true).toList();

    List<Map<String, dynamic>> allData = [];
    for(var t in personalTasks) {
      allData.add({...t, 'isGroupTask': false});
    }
    allData.addAll(groupTasks);

    String myUid = _auth.currentUser?.uid ?? "";

    bool isArchived(Map<String, dynamic> t) {
      return t['isArchived'] == 1 || t['isArchived'] == true;
    }

    if (!mounted) return;
    setState(() {
      totalTasks = allData.where((t) => !isArchived(t)).length;
      completedTasks = allData.where((t) => isArchived(t)).length;
      pendingTasks = allData.where((t) {
        if (isArchived(t)) return false;

        if (t['isGroupTask'] == true) {
          List<dynamic> doneMembers = t['completedMembers'] ?? [];
          return t['isCompleted'] != true && !doneMembers.contains(myUid);
        }
        return t['isCompleted'] == 0 || t['isCompleted'] == false;
      }).length;
    });
  }

  void showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  Future<void> _pickAndUploadAvatar(User user) async {
    final ImagePicker picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    } catch (e) {
      return;
    }
    if (image == null) return;

    if (mounted) setState(() => isLoading = true);
    try {
      final ref = FirebaseStorage.instance.ref().child('avatars/${user.uid}.jpg');
      await ref.putFile(File(image.path));
      String downloadUrl = await ref.getDownloadURL();
      await user.updatePhotoURL(downloadUrl);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoURL': downloadUrl});

      await user.reload();
      setState(() {});
      showMsg("Profile picture updated successfully!");
    } catch (e) {
      showMsg("Error uploading image!");
    }
    if (mounted) setState(() => isLoading = false);
  }

  void _editDisplayName(User user) {
    TextEditingController nameController = TextEditingController(text: user.displayName);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Change Display Name"),
          content: TextField(controller: nameController, decoration: const InputDecoration(hintText: "Enter new name")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  setState(() => isLoading = true);
                  try {
                    await user.updateDisplayName(nameController.text.trim());
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'displayName': nameController.text.trim()});
                    await user.reload();
                    setState(() {});
                    showMsg("Display name updated successfully!");
                  } catch(e) { showMsg("Error changing name!"); }
                  if (mounted) setState(() => isLoading = false);
                },
                child: const Text("Save")
            )
          ],
        )
    );
  }

  Future<void> _onLoginSuccess(User user) async {
    try {
      MainScreen.isLoggingIn = true;

      String newSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_session_id', newSessionId);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? '',
        'displayName': user.displayName ?? '',
        'lastLogin': DateTime.now().toIso8601String(),
        'currentSessionId': newSessionId,
      }, SetOptions(merge: true));

      MainScreen.isLoggingIn = false;

      await dbHelper.syncLocalToCloud();
      await NotificationService().syncGroupTopics();
      _loadStats();
    } catch (e) {
      MainScreen.isLoggingIn = false;
      debugPrint("Cloud sync error: $e");
    }
  }

  void submitAuth() async {
    if (emailController.text.isEmpty || passController.text.isEmpty) { showMsg("Please enter Email and Password!"); return; }
    setState(() => isLoading = true);
    try {
      if (isLoginMode) {
        UserCredential cred = await _auth.signInWithEmailAndPassword(email: emailController.text.trim(), password: passController.text.trim());
        if (cred.user != null) await _onLoginSuccess(cred.user!);
      } else {
        UserCredential cred = await _auth.createUserWithEmailAndPassword(email: emailController.text.trim(), password: passController.text.trim());
        await cred.user?.sendEmailVerification();
        if (cred.user != null) await _onLoginSuccess(cred.user!);
        showMsg("Registration successful! Please check your email to verify.");
      }
    } catch (e) { showMsg("Authentication error!"); }
    if (mounted) setState(() => isLoading = false);
  }

  void resetPassword() async {
    if (emailController.text.isEmpty) { showMsg("Please enter your Email to reset password!"); return; }
    try { await _auth.sendPasswordResetEmail(email: emailController.text.trim()); showMsg("Password reset link sent to your email!"); } catch (e) { showMsg("Error sending email."); }
  }

  Future<void> signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      await GoogleSignIn().signOut();
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
        UserCredential cred = await _auth.signInWithCredential(credential);
        if (cred.user != null) await _onLoginSuccess(cred.user!);
      }
    } catch (e) { showMsg("Google sign-in error."); }
    if (mounted) setState(() => isLoading = false);
  }

  void signInWithPhone() {
    final phoneController = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("Enter phone number"), content: TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: "e.g., 0912345678", prefixIcon: Icon(Icons.phone))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")), ElevatedButton(onPressed: () async { String phone = phoneController.text.trim(); if (phone.isEmpty) return; if (phone.startsWith('0')) phone = '+84${phone.substring(1)}'; Navigator.pop(context); _verifyPhoneNumber(phone); }, child: const Text("Send OTP Code"))]));
  }

  void _verifyPhoneNumber(String phoneNumber) async {
    setState(() => isLoading = true);
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async { UserCredential cred = await _auth.signInWithCredential(credential); if (cred.user != null) await _onLoginSuccess(cred.user!); if (mounted) setState(() => isLoading = false); },
      verificationFailed: (FirebaseAuthException e) { if (mounted) setState(() => isLoading = false); showMsg("SMS error."); },
      codeSent: (String verificationId, int? resendToken) { if (mounted) setState(() => isLoading = false); _showOTPDialog(verificationId); },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  void _showOTPDialog(String verificationId) {
    final otpController = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(title: const Text("Enter OTP Code"), content: TextField(controller: otpController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, letterSpacing: 5), maxLength: 6), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")), ElevatedButton(onPressed: () async { try { PhoneAuthCredential credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otpController.text.trim()); UserCredential cred = await _auth.signInWithCredential(credential); if (cred.user != null) await _onLoginSuccess(cred.user!); if (context.mounted) Navigator.pop(context); } catch (e) { showMsg("Invalid OTP code!"); } }, child: const Text("Confirm"))]));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        User? user = FirebaseAuth.instance.currentUser;
        if (user == null) return buildAuthUI();
        if (!user.emailVerified && user.phoneNumber == null) return buildVerifyEmailUI(user);
        return buildProfileUI(user);
      },
    );
  }

  Widget buildAuthUI() {
    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? "Log In" : "Create New Account")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Icon(Icons.account_circle, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            TextField(controller: emailController, decoration: InputDecoration(labelText: "Email", prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            TextField(controller: passController, decoration: InputDecoration(labelText: "Password", prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), obscureText: true),
            const SizedBox(height: 20),
            if (isLoading) const CircularProgressIndicator()
            else SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: submitAuth, child: Text(isLoginMode ? "LOG IN" : "REGISTER", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: () => setState(() => isLoginMode = !isLoginMode), child: Text(isLoginMode ? "Create account" : "Back to Log In")), if (isLoginMode) TextButton(onPressed: resetPassword, child: const Text("Forgot password?"))]),
            const Divider(),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.g_mobiledata, color: Colors.red, size: 30), label: Text("Google", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)), onPressed: signInWithGoogle)),
                const SizedBox(width: 15),
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.phone_android, color: Colors.blue), label: Text("Phone No.", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)), onPressed: signInWithPhone)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget buildVerifyEmailUI(User user) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              Text("Please verify your email: ${user.email}.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text("Reload"), onPressed: () async { await user.reload(); setState(() {}); }),
              TextButton(onPressed: () async { await _auth.signOut(); setState(() => isLoginMode = true); }, child: const Text("Log Out", style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProfileUI(User user) {
    String displayName = (user.displayName != null && user.displayName!.isNotEmpty) ? user.displayName! : (user.phoneNumber ?? user.email ?? "Anonymous");

    return Scaffold(
      appBar: AppBar(title: const Text("Profile & Settings")),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _pickAndUploadAvatar(user),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                          radius: 50,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                          child: user.photoURL == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null
                      ),
                      const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.camera_alt, size: 18, color: Colors.blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: Icon(Icons.edit, size: 18, color: Theme.of(context).colorScheme.primary), onPressed: () => _editDisplayName(user)),
                  ],
                ),
                Text(user.email ?? user.phoneNumber ?? "", style: const TextStyle(color: Colors.grey, fontSize: 14)),

                const SizedBox(height: 25),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.manage_accounts, color: Colors.blue),
                    title: const Text("Account Details", style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountDetailScreen())),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.group, color: Colors.pink),
                    title: const Text("Friends & Contacts", style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen())),
                  ),
                ),
                const SizedBox(height: 25),

                Align(alignment: Alignment.centerLeft, child: Text("Task Statistics", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(child: _buildStatCard("All", totalTasks.toString(), Colors.blue, Icons.assignment, () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'ALL', title: "All Tasks"))).then((_) => _loadStats());
                    })),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard("Archived", completedTasks.toString(), Colors.green, Icons.inventory_2, () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'COMPLETED', title: "Archived (Completed)"))).then((_) => _loadStats());
                    })),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildStatCard("In Progress", pendingTasks.toString(), Colors.orange, Icons.pending_actions, () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'PENDING', title: "Tasks In Progress"))).then((_) => _loadStats());
                    })),
                  ],
                ),

                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text("LOG OUT ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: () async {
                      // CALL CLEANUP METHOD FROM NOTIFICATION SERVICE
                      await NotificationService().clearAllNotificationsOnLogout();

                      await GoogleSignIn().signOut();
                      await _auth.signOut();

                      if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (isLoading) Container(color: Colors.black.withAlpha(100), child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, VoidCallback onTap) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(isDark ? 0.3 : 0.5))
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(fontSize: 32, color: color, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}