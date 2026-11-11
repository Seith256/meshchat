import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import 'chat_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshProvider>();
    final peers = mesh.contacts;

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Peers')),
      body: peers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No peers on this network yet.\n\n'
                  'Make sure everyone is on the same WiFi or hotspot '
                  'and the app is open on all phones.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: peers
                  .map((p) => ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(p.name),
                        subtitle: Text(p.id),
                        trailing: p.lastIp != null
                            ? Text(p.lastIp!)
                            : const Text('not reachable'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(peerId: p.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}
