import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';

class MeshMapScreen extends StatelessWidget {
  const MeshMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshProvider>();
    final peers = mesh.contacts;
    final relay = mesh.relayQueue;

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Network')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub),
                title: Text('You: ${mesh.myName} (${mesh.myId})'),
                subtitle: Text('TCP port ${mesh.myPort}'),
              ),
            ),
            const SizedBox(height: 12),
            Text('Peers (${peers.length})',
                style: Theme.of(context).textTheme.titleMedium),
            ...peers.map((p) => ListTile(
                  leading: const Icon(Icons.circle, size: 10),
                  title: Text('${p.name}  (${p.id})'),
                  subtitle: Text(p.lastIp ?? 'unknown ip'),
                )),
            const Divider(),
            Text('Relay queue (${relay.length})',
                style: Theme.of(context).textTheme.titleMedium),
            ...relay.map((m) => ListTile(
                  leading: const Icon(Icons.outbox),
                  title: Text('${m.from} -> ${m.to}'),
                  subtitle: Text('ttl ${m.ttl} - ${m.status}'),
                )),
          ],
        ),
      ),
    );
  }
}
