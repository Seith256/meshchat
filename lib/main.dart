import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/mesh_provider.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('identity');
  await Hive.openBox('users');
  await Hive.openBox('messages');
  await Hive.openBox('relay');
  runApp(const MeshChatApp());
}

class MeshChatApp extends StatelessWidget {
  const MeshChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MeshProvider()..init(),
      child: MaterialApp(
        title: 'MeshChat',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: Consumer<MeshProvider>(
          builder: (context, mesh, _) {
            if (mesh.loading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return mesh.myId == null
                ? const SetupScreen()
                : const HomeScreen();
          },
        ),
      ),
    );
  }
}
