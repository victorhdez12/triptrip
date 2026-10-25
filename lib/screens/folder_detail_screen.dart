// lib/screens/folder_detail_screen.dart
//
// Contenido de una carpeta de favoritos:
//   • Items ordenados por votos, con 👍 para votar (ideal en carpetas
//     compartidas con el grupo: "¿a cuál vamos?")
//   • Compartir / descompartir la carpeta con un grupo de viaje
//   • Tocar un item abre su detalle (sitio o itinerario)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/favorite_folder_service.dart';
import '../widgets/common_widgets.dart';
import 'itinerary_detail_screen.dart';
import 'place_detail_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final FavoriteFolder folder;
  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<FolderItemView> _items = [];
  bool _loading = true;
  late String? _groupId;

  @override
  void initState() {
    super.initState();
    _groupId = widget.folder.groupId;
    _load();
  }

  Future<void> _load() async {
    final items = await FavoriteFolderService.listFolderItems(widget.folder.id);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _vote(FolderItemView item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newVoted =
        await FavoriteFolderService.toggleVote(item.rowId, item.iVoted);
    if (!mounted) return;
    setState(() {
      if (newVoted && !item.iVoted) {
        item.iVoted = true;
        item.voters.add(uid);
      } else if (!newVoted && item.iVoted) {
        item.iVoted = false;
        item.voters.remove(uid);
      }
      _items.sort((a, b) => b.voters.length.compareTo(a.voters.length));
    });
  }

  Future<void> _shareWithGroup() async {
    final groups = await FavoriteFolderService.myGroups();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Share folder with a trip group',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                child: Text('You have no trip groups yet.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              )
            else
              ...groups.map((g) => ListTile(
                    leading:
                        const Icon(Icons.group_rounded, color: kPrimary),
                    title: Text(g.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: _groupId == g.id
                        ? const Icon(Icons.check, color: kPrimary)
                        : null,
                    onTap: () => Navigator.pop(context, g.id),
                  )),
            if (_groupId != null)
              ListTile(
                leading:
                    const Icon(Icons.link_off, color: Colors.redAccent),
                title: const Text('Stop sharing',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent)),
                onTap: () => Navigator.pop(context, '_unshare_'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    final newGroup = selected == '_unshare_' ? null : selected;
    final ok = await FavoriteFolderService.shareFolderWithGroup(
        widget.folder.id, newGroup);
    if (ok && mounted) {
      setState(() => _groupId = newGroup);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newGroup == null
            ? 'Folder is private again'
            : 'Folder shared with your group 🎉'),
        backgroundColor: kPrimary,
      ));
    }
  }

  void _openItem(FolderItemView item) async {
    if (item.kind == 'place') {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlaceDetailScreen(placeId: item.itemId)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ItineraryDetailScreen(itineraryId: item.itemId)),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        title: Text(widget.folder.name,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Share with group',
            icon: Icon(
              _groupId != null ? Icons.group : Icons.group_add_outlined,
              color: _groupId != null ? kPrimary : const Color(0xFF6B7280),
            ),
            onPressed: _shareWithGroup,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('This folder is empty.',
                        style: TextStyle(color: Color(0xFF9CA3AF))),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    return GestureDetector(
                      onTap: () => _openItem(item),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: const Color(0xFFEEF0F4)),
                        ),
                        child: Row(
                          children: [
                            Text(item.kind == 'place' ? '📍' : '🗺️',
                                style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                  if (item.subtitle.isNotEmpty)
                                    Text(item.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Botón de voto 👍
                            GestureDetector(
                              onTap: () => _vote(item),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: item.iVoted
                                      ? kPrimary.withOpacity(0.12)
                                      : const Color(0xFFF5F5F5),
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.iVoted
                                          ? Icons.thumb_up
                                          : Icons.thumb_up_outlined,
                                      size: 16,
                                      color: item.iVoted
                                          ? kPrimary
                                          : const Color(0xFF6B7280),
                                    ),
                                    const SizedBox(width: 6),
                                    Text('${item.voters.length}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: item.iVoted
                                            ? kPrimary
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
