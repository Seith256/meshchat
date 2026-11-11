import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import 'chat_screen.dart';
import 'discover_screen.dart';
import 'mesh_map_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshProvider>();
    final contacts = mesh.contacts;

    return Scaffold(
      appBar: AppBar(
        title: Text('MeshChat • ${mesh.myName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'Mesh map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MeshMapScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Discover nearby',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiscoverScreen()),
            ),
          ),
        ],
      ),
      body: contacts.isEmpty
          ? const Center(
              child: Text(
                'No contacts yet.\nTap the search icon to find nearby phones.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (_, i) {
                final u = contacts[i];
                final msgs = mesh.messagesWith(u.id);
                final last = msgs.isEmpty ? null : msgs.last;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(u.name.isNotEmpty
                        ? u.name[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(u.name),
                  subtitle: Text(last?.body ?? 'No messages yet',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: u.lastSeen > 0
                      ? const Icon(Icons.wifi,
                          size: 16, color: Colors.green)
                      : const Icon(Icons.wifi_off,
                          size: 16, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(peerId: u.id)),
                  ),
                );
              },
            ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Icon(Icons.sync, size: 16),
              const SizedBox(width: 8),
              Text(
                '${mesh.relayQueue.length} message(s) queued for relay',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
