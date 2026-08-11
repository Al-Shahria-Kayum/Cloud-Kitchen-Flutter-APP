import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/menu_item.dart';
import '../../providers/kitchen_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/network_food_image.dart';
import '../../widgets/photo_carousel.dart';

class _PendingPhoto {
  final Uint8List bytes;
  final String fileName;
  const _PendingPhoto({required this.bytes, required this.fileName});
}

class KitchenMenuScreen extends StatefulWidget {
  const KitchenMenuScreen({super.key});

  @override
  State<KitchenMenuScreen> createState() => _KitchenMenuScreenState();
}

class _KitchenMenuScreenState extends State<KitchenMenuScreen> {
  final ImagePicker _picker = ImagePicker();

  void _showItemForm([MenuItem? item]) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item?.name ?? '');
    final descController = TextEditingController(text: item?.description ?? '');
    final priceController = TextEditingController(text: item?.price.toString() ?? '');
    bool isAvailable = item?.isAvailable ?? true;
    final List<String> existingImageUrls = List.of(item?.imageUrls ?? const []);
    final List<_PendingPhoto> newPhotos = [];
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final text = Theme.of(modalCtx).textTheme;
            final scheme = Theme.of(modalCtx).colorScheme;
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: scheme.outline,
                            borderRadius: AppRadius.pillBr,
                          ),
                        ),
                      ),
                      Text(
                        item == null ? 'Add Menu Item' : 'Edit Menu Item',
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Photo gallery — multiple photos per item; the first
                      // one (existing or newly added) is used as the thumbnail
                      // everywhere else in the app (see MenuItem.imageUrl).
                      Text('Photos', style: text.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      SizedBox(
                        height: 88,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ...List.generate(existingImageUrls.length, (i) {
                              return Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.sm),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    NetworkFoodImage(url: existingImageUrls[i], width: 80, height: 80),
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: GestureDetector(
                                        onTap: () => setModalState(() => existingImageUrls.removeAt(i)),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            ...List.generate(newPhotos.length, (i) {
                              return Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.sm),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius: AppRadius.mdBr,
                                      child: Image.memory(newPhotos[i].bytes, width: 80, height: 80, fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: GestureDetector(
                                        onTap: () => setModalState(() => newPhotos.removeAt(i)),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            InkWell(
                              borderRadius: AppRadius.mdBr,
                              onTap: () async {
                                final files = await _picker.pickMultiImage();
                                if (files.isEmpty) return;
                                final picked = await Future.wait(
                                  files.map((f) async => _PendingPhoto(bytes: await f.readAsBytes(), fileName: f.name)),
                                );
                                setModalState(() => newPhotos.addAll(picked));
                              },
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  border: Border.all(color: scheme.outline),
                                  borderRadius: AppRadius.mdBr,
                                  color: scheme.primaryContainer.withValues(alpha: 0.25),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, size: 22, color: scheme.primary),
                                    const SizedBox(height: 2),
                                    Text('Add', style: text.labelSmall),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Fields
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Item Name'),
                        validator: (val) => val == null || val.isEmpty ? 'Enter item name' : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Description'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price (BDT)', prefixText: '৳ '),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Enter price';
                          if (double.tryParse(val) == null || double.parse(val) < 0) return 'Enter valid positive price';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outline),
                          borderRadius: AppRadius.mdBr,
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available for orders'),
                          subtitle: const Text('Customers can order this item while enabled'),
                          value: isAvailable,
                          onChanged: (val) => setModalState(() => isAvailable = val),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),

                      // Submit button
                      ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;

                                setModalState(() => isSaving = true);

                                final kitchenProvider = Provider.of<KitchenProvider>(context, listen: false);

                                // Upload every newly-picked photo; skip (don't fail the whole
                                // save over) any single upload that fails, but warn afterward.
                                final uploadedUrls = <String>[];
                                var anyUploadFailed = false;
                                for (final photo in newPhotos) {
                                  final url = await kitchenProvider.uploadMenuImage(photo.bytes, photo.fileName);
                                  if (url != null) {
                                    uploadedUrls.add(url);
                                  } else {
                                    anyUploadFailed = true;
                                  }
                                }
                                final finalImageUrls = [...existingImageUrls, ...uploadedUrls];

                                bool success;
                                if (item == null) {
                                  success = await kitchenProvider.addMenuItem(
                                    name: nameController.text.trim(),
                                    description: descController.text.trim(),
                                    price: double.parse(priceController.text.trim()),
                                    imageUrls: finalImageUrls,
                                    isAvailable: isAvailable,
                                  );
                                } else {
                                  success = await kitchenProvider.updateMenuItem(
                                    id: item.id,
                                    name: nameController.text.trim(),
                                    description: descController.text.trim(),
                                    price: double.parse(priceController.text.trim()),
                                    imageUrls: finalImageUrls,
                                    isAvailable: isAvailable,
                                  );
                                }

                                if (success && mounted) {
                                  final message = anyUploadFailed
                                      ? '${item == null ? "Item added" : "Item updated"} — but one or more photos failed to upload.'
                                      : (item == null ? 'Item added!' : 'Item updated!');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(message),
                                      backgroundColor: anyUploadFailed ? Colors.orange : Colors.green,
                                    ),
                                  );
                                  Navigator.pop(ctx);
                                } else if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Operation failed. Please try again.')),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                                setModalState(() => isSaving = false);
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(item == null ? 'Add Item' : 'Save Changes'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final kitchenProvider = context.watch<KitchenProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Management'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: kBrandGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemForm(),
        child: const Icon(Icons.add),
      ),
      body: kitchenProvider.menuItems.isEmpty
          ? const EmptyState(
              icon: Icons.restaurant_outlined,
              title: 'No menu items yet',
              message: 'Tap the + button to add your first dish.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: kitchenProvider.menuItems.length,
              itemBuilder: (context, index) {
                final item = kitchenProvider.menuItems[index];
                return _MenuItemCard(
                  item: item,
                  onEdit: () => _showItemForm(item),
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Item?'),
                        content: Text('Are you sure you want to delete ${item.name}?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true || !mounted) return;

                    final outcome = await kitchenProvider.deleteMenuItem(item.id);
                    if (!mounted) return;

                    switch (outcome) {
                      case MenuItemDeleteOutcome.success:
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${item.name} deleted.'), backgroundColor: context.appColors.success),
                        );
                        break;
                      case MenuItemDeleteOutcome.hasOrderHistory:
                        final markUnavailable = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Can\'t delete this item'),
                            content: Text(
                              '${item.name} has already been ordered, so it can\'t be permanently deleted — '
                              'this keeps past orders and receipts accurate. Mark it unavailable instead so '
                              'customers can no longer order it?',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Mark Unavailable'),
                              ),
                            ],
                          ),
                        );
                        if (markUnavailable == true && mounted) {
                          final ok = await kitchenProvider.setMenuItemAvailability(item.id, false);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? '${item.name} marked unavailable.' : friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Could not update this item. Please try again.')),
                              backgroundColor: ok ? context.appColors.success : Theme.of(context).colorScheme.error,
                            ),
                          );
                        }
                        break;
                      case MenuItemDeleteOutcome.error:
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Could not delete this item. Please try again.')),
                            backgroundColor: Theme.of(context).colorScheme.error,
                          ),
                        );
                        break;
                    }
                  },
                );
              },
            ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MenuItemCard({required this.item, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: PhotoCarousel(imageUrls: item.imageUrls, height: 68),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    item.description ?? 'Fresh and tasty.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        formatCurrency(item.price),
                        style: text.titleMedium?.copyWith(color: scheme.primary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.isAvailable ? appColors.successContainer : scheme.errorContainer,
                          borderRadius: AppRadius.pillBr,
                        ),
                        child: Text(
                          item.isAvailable ? 'Available' : 'Unavailable',
                          style: text.labelSmall?.copyWith(
                            color: item.isAvailable ? appColors.onSuccessContainer : scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: scheme.primary),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
