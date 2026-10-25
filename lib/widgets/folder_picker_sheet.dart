// lib/widgets/folder_picker_sheet.dart
//
// Selector de carpetas reutilizable (itinerarios y sitios).
// Se abre al tocar el ❤. Permite marcar varias carpetas, crear nuevas,
// y guardar / quitar de favoritos.
//
// Uso:
//   final fav = await showFolderPicker(context, kind: 'place', itemId: id);
//   if (fav != null) setState(() => /* actualizar ❤ con `fav` */);
//
// Devuelve:
//   true  → el item quedó como favorito
//   false → se quitó de favoritos (ninguna carpeta marcada)
//   null  → se cerró sin guardar (no cambiar estado)

import 'package:flutter/material.dart';

import '../services/favorite_folder_service.dart';
import 'common_widgets.dart';

Future<bool?> showFolderPicker(
  BuildContext context, {
  required String kind, // 'itinerary' | 'place'
  required String itemId,
  String? suggestedFolderName, // pre-rellena el nombre de "nueva carpeta"
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _FolderPickerSheet(
      kind: kind,
      itemId: itemId,
      suggestedFolderName: suggestedFolderName,
    ),
  );
}

class _FolderPickerSheet extends StatefulWidget {
  final String kind;
  final String itemId;
  final String? suggestedFolderName;
  const _FolderPickerSheet({
    required this.kind,
    required this.itemId,
    this.suggestedFolderName,
  });

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  final _newCtrl = TextEditingController();
  List<FavoriteFolder> _folders = [];
  Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedFolderName != null) {
      _newCtrl.text = widget.suggestedFolderName!.trim();
    }
    _load();
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final folders = await FavoriteFolderService.listFolders(widget.kind);
    final current =
        await FavoriteFolderService.foldersForItem(widget.kind, widget.itemId);
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _selected = current;
      _loading = false;
    });
  }

  Future<void> _createFolder() async {
    final name = _newCtrl.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    final id = await FavoriteFolderService.createFolder(name, widget.kind);
    if (!mounted) return;
    if (id != null) {
      _newCtrl.clear();
      final folders = await FavoriteFolderService.listFolders(widget.kind);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _selected.add(id); // recién creada queda marcada
        _creating = false;
      });
    } else {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not create folder'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final fav = await FavoriteFolderService.saveItemToFolders(
      kind: widget.kind,
      itemId: widget.itemId,
      folderIds: _selected,
    );
    if (!mounted) return;
    Navigator.pop(context, fav);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Save to folders',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator(color: kPrimary)),
                )
              else ...[
                if (_folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No folders yet — create one below.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _folders.length,
                      itemBuilder: (_, i) {
                        final f = _folders[i];
                        final checked = _selected.contains(f.id);
                        return InkWell(
                          onTap: () => setState(() {
                            if (checked) {
                              _selected.remove(f.id);
                            } else {
                              _selected.add(f.id);
                            }
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  checked
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  color: checked ? kPrimary : const Color(0xFFD1D5DB),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.folder_rounded,
                                    color: kOrange, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(f.name,
                                    style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                ),
                                Text('${f.itemCount}',
                                  style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 10),
                // Crear nueva carpeta
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _createFolder(),
                        decoration: InputDecoration(
                          hintText: 'New folder name',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _creating ? null : _createFolder,
                      icon: _creating
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: kPrimary),
                            )
                          : const Icon(Icons.add_circle, color: kPrimary, size: 30),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(
                            _selected.isEmpty
                                ? 'Remove from favourites'
                                : 'Save',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
