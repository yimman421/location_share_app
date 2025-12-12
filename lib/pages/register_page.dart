import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../appwriteClient.dart';
import '../constants/appwrite_config.dart';
import 'map_page.dart';
import '../providers/auth_provider.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _showVerifyButton = false;

  Account get account => appwriteAccount;
  Databases get db => appwriteDB;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final nickname = _nicknameController.text.trim();

    setState(() {
      _errorMessage = null;
      _successMessage = null;
      _showVerifyButton = false;
    });

    if (email.isEmpty || password.isEmpty || nickname.isEmpty) {
      setState(() => _errorMessage = '이메일, 비밀번호, 닉네임을 입력하세요.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = '비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}

      final userId = ID.unique();
      final newUser = await account.create(
        userId: userId,
        email: email,
        password: password,
        name: nickname,
      );

      await account.createEmailPasswordSession(email: email, password: password);

      try {
        // ignore: deprecated_member_use
        await db.createDocument(
          databaseId: AppwriteConstants.databaseId,
          collectionId: AppwriteConstants.usersCollectionId,
          documentId: newUser.$id,
          data: {
            'userId': newUser.$id,
            'nickname': nickname,
            'email': email,
          },
          permissions: [
            Permission.read(Role.user(newUser.$id)),
            Permission.update(Role.user(newUser.$id)),
            Permission.delete(Role.user(newUser.$id)),
          ],
        );
      } catch (_) {}

      // ignore: deprecated_member_use
      await account.createVerification(
        url: AppwriteConstants.emailverification,
      );

      setState(() {
        _successMessage = '인증 메일을 발송했습니다. 메일 확인 후 "인증 완료했어요"를 눌러주세요.';
        _showVerifyButton = true;
      });
    } on AppwriteException catch (e) {
      final msg = e.message ?? e.toString();
      if (msg.contains('already exists')) {
        setState(() => _errorMessage = '이미 존재하는 계정입니다. 로그인 해보세요.');
      } else if (msg.contains('user_session_already_exists') || msg.contains('session')) {
        setState(() => _errorMessage = '이미 활성화된 세션이 있습니다. 앱을 재시작하거나 로그아웃 후 시도하세요.');
      } else {
        setState(() => _errorMessage = '회원가입 실패: $msg');
      }
    } catch (e) {
      setState(() => _errorMessage = '알 수 없는 오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = '이메일/비밀번호 입력 후 재전송하세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}
      await account.createEmailPasswordSession(email: email, password: password);
      // ignore: deprecated_member_use
      await account.createVerification(url: 'http://172.20.64.126/email_verification.html');
      setState(() => _successMessage = '인증 메일을 재전송했습니다.');
    } on AppwriteException catch (e) {
      setState(() => _errorMessage = '재전송 실패: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = '재전송 중 오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkVerificationStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = await account.get();
      if (user.emailVerification == true) {
        setState(() {
          _successMessage = '이메일 인증 완료. 자동 로그인 처리합니다.';
          _showVerifyButton = false;
        });

        // ✅ users 컬렉션 확인 및 생성
        final auth = AuthProvider();
        final user = await auth.account.get();
        await auth.ensureUserProfile(user.toMap());

        // ✅ 바로 MapPage로 이동 (groups/peoples 생성 X)
        Navigator.pushReplacement(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(builder: (_) => MapPage(userId: user.$id)),
        );
      } else {
        setState(() => _errorMessage = '아직 이메일 인증이 완료되지 않았습니다.');
      }
    } on AppwriteException catch (e) {
      setState(() => _errorMessage = '인증 상태 확인 실패: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = '오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fa),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('회원가입', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '이메일로 계정을 생성하세요.',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: '이메일',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: '비밀번호 확인',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),

                  // Nickname
                  TextFormField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      labelText: '닉네임',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isLoading)
                    const CircularProgressIndicator()
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff4a6cf7),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '회원가입',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _resendVerification,
                      child: const Text(
                        '인증메일 재전송',
                        style: TextStyle(color: Color(0xff4a6cf7)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_showVerifyButton)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _checkVerificationStatus,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xff4a6cf7)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            '인증 완료했어요',
                            style: TextStyle(color: Color(0xff4a6cf7)),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    Text(_errorMessage!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 13)),
                  if (_successMessage != null)
                    Text(_successMessage!,
                        style:
                            const TextStyle(color: Colors.green, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
