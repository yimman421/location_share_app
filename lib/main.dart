import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'package:provider/provider.dart';
import 'providers/locations_provider.dart';
import 'providers/shop_provider.dart';
import 'providers/user_message_provider.dart';
import 'providers/shops_map_provider.dart';
import 'dart:io';

// ✅ SSL 검증 비활성
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides(); // SSL 검증 비활성
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ✅ 기존 Provider
        ChangeNotifierProvider(create: (_) => LocationsProvider()),
        
        // ✅ 새로 추가하는 Providers
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(create: (_) => UserMessageProvider()),
        ChangeNotifierProvider(create: (_) => ShopsMapProvider()), // ✅ 새로 추가
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '실시간 위치공유',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
        ),
        home: const LoginPage(),
      ),
    );
  }
}