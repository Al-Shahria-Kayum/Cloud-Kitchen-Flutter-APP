import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../utils/error_mapper.dart';
import '../../theme/app_theme.dart';

class _PickedPhoto {
  final Uint8List bytes;
  final String fileName;
  const _PickedPhoto({required this.bytes, required this.fileName});
}

class RatingsScreen extends StatefulWidget {
  final Order order;
  const RatingsScreen({super.key, required this.order});

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  int _kitchenScore = 5;
  int _riderScore = 5;
  final TextEditingController _kitchenReviewController = TextEditingController();
  final TextEditingController _riderReviewController = TextEditingController();

  final List<_PickedPhoto> _kitchenPhotos = [];
  final List<_PickedPhoto> _riderPhotos = [];

  bool _hasRatedKitchen = false;
  bool _hasRatedRider = false;
  bool _checkingRatings = true;

  bool _submittingKitchen = false;
  bool _submittingRider = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRatings();
  }

  @override
  void dispose() {
    _kitchenReviewController.dispose();
    _riderReviewController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingRatings() async {
    try {
      final existing = await _client
          .from('ratings')
          .select('rating_type')
          .eq('order_id', widget.order.id);

      final List ratings = existing as List;
      for (var r in ratings) {
        if (r['rating_type'] == 'kitchen') {
          _hasRatedKitchen = true;
        } else if (r['rating_type'] == 'rider') {
          _hasRatedRider = true;
        }
      }
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) {
        setState(() {
          _checkingRatings = false;
        });
      }
    }
  }

  void _showSnack(String message, {required bool success}) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? appColors.success : scheme.error,
      ),
    );
  }

  Future<void> _pickPhotos(List<_PickedPhoto> target) async {
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    final picked = await Future.wait(files.map((f) async => _PickedPhoto(bytes: await f.readAsBytes(), fileName: f.name)));
    setState(() => target.addAll(picked));
  }

  /// Uploads every picked photo, skipping (not failing the whole review
  /// over) any single upload that fails — consistent with how the app
  /// treats other best-effort uploads (e.g. avatar/cover photo timeouts).
  Future<List<String>> _uploadPhotos(List<_PickedPhoto> photos, CustomerProvider customerProvider, String raterId) async {
    final urls = <String>[];
    for (final photo in photos) {
      final url = await customerProvider.uploadReviewPhoto(photo.bytes, photo.fileName, raterId);
      if (url != null) urls.add(url);
    }
    return urls;
  }

  Future<void> _submitKitchenRating() async {
    setState(() => _submittingKitchen = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    try {
      final kitchenData = await _client
          .from('kitchens')
          .select('owner_id')
          .eq('id', widget.order.kitchenId)
          .single();

      final kitchenOwnerId = kitchenData['owner_id'] as String;
      final photoUrls = await _uploadPhotos(_kitchenPhotos, customerProvider, authProvider.user!.id);

      final success = await customerProvider.submitRating(
        orderId: widget.order.id,
        raterId: authProvider.user!.id,
        rateeId: kitchenOwnerId,
        ratingType: 'kitchen',
        score: _kitchenScore,
        review: _kitchenReviewController.text.trim(),
        photoUrls: photoUrls,
      );

      if (!mounted) return;
      if (success) {
        _showSnack('Kitchen rated successfully!', success: true);
        setState(() => _hasRatedKitchen = true);
      } else {
        _showSnack(friendlyErrorMessage(customerProvider.errorMessage, fallback: 'Failed to submit rating. Please try again.'), success: false);
      }
    } finally {
      if (mounted) setState(() => _submittingKitchen = false);
    }
  }

  Future<void> _submitRiderRating() async {
    if (widget.order.riderId == null) return;
    setState(() => _submittingRider = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    try {
      final photoUrls = await _uploadPhotos(_riderPhotos, customerProvider, authProvider.user!.id);

      final success = await customerProvider.submitRating(
        orderId: widget.order.id,
        raterId: authProvider.user!.id,
        rateeId: widget.order.riderId!,
        ratingType: 'rider',
        score: _riderScore,
        review: _riderReviewController.text.trim(),
        photoUrls: photoUrls,
      );

      if (!mounted) return;
      if (success) {
        _showSnack('Rider rated successfully!', success: true);
        setState(() => _hasRatedRider = true);
      } else {
        _showSnack(friendlyErrorMessage(customerProvider.errorMessage, fallback: 'Failed to submit rating. Please try again.'), success: false);
      }
    } finally {
      if (mounted) setState(() => _submittingRider = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Rate Your Experience')),
      body: _checkingRatings
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(Icons.star_rounded, size: 36, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('We value your feedback!', textAlign: TextAlign.center, style: text.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Let us know how the kitchen and rider did on this order.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _RatingBlock(
                    title: 'Rate Kitchen',
                    subtitle: widget.order.kitchenName ?? 'Kitchen',
                    isRated: _hasRatedKitchen,
                    submitting: _submittingKitchen,
                    score: _kitchenScore,
                    reviewController: _kitchenReviewController,
                    photos: _kitchenPhotos,
                    onScoreChanged: (val) => setState(() => _kitchenScore = val),
                    onAddPhotos: () => _pickPhotos(_kitchenPhotos),
                    onRemovePhoto: (i) => setState(() => _kitchenPhotos.removeAt(i)),
                    onSubmit: _submitKitchenRating,
                  ),
                  if (widget.order.riderId != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _RatingBlock(
                      title: 'Rate Rider',
                      subtitle: widget.order.riderName ?? 'Rider',
                      isRated: _hasRatedRider,
                      submitting: _submittingRider,
                      score: _riderScore,
                      reviewController: _riderReviewController,
                      photos: _riderPhotos,
                      onScoreChanged: (val) => setState(() => _riderScore = val),
                      onAddPhotos: () => _pickPhotos(_riderPhotos),
                      onRemovePhoto: (i) => setState(() => _riderPhotos.removeAt(i)),
                      onSubmit: _submitRiderRating,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RatingBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isRated;
  final bool submitting;
  final int score;
  final TextEditingController reviewController;
  final List<_PickedPhoto> photos;
  final ValueChanged<int> onScoreChanged;
  final VoidCallback onAddPhotos;
  final void Function(int index) onRemovePhoto;
  final VoidCallback onSubmit;

  const _RatingBlock({
    required this.title,
    required this.subtitle,
    required this.isRated,
    required this.submitting,
    required this.score,
    required this.reviewController,
    required this.photos,
    required this.onScoreChanged,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final appColors = context.appColors;

    if (isRated) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: appColors.successContainer, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: appColors.onSuccessContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title · $subtitle', style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text('Thanks — your feedback has been submitted.', style: text.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleLarge),
            const SizedBox(height: 2),
            Text(subtitle, style: text.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNum = index + 1;
                return _AnimatedStar(
                  filled: starNum <= score,
                  onTap: () => onScoreChanged(starNum),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: reviewController,
              decoration: const InputDecoration(labelText: 'Write a review (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...List.generate(photos.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: AppRadius.mdBr,
                            child: Image.memory(photos[i].bytes, width: 64, height: 64, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => onRemovePhoto(i),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  InkWell(
                    onTap: onAddPhotos,
                    borderRadius: AppRadius.mdBr,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        borderRadius: AppRadius.mdBr,
                      ),
                      child: Icon(Icons.add_photo_alternate_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Feedback'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single star that pops with a quick scale animation whenever the score
/// changes across it, so tapping a rating reads as a tactile response.
class _AnimatedStar extends StatefulWidget {
  final bool filled;
  final VoidCallback onTap;
  const _AnimatedStar({required this.filled, required this.onTap});

  @override
  State<_AnimatedStar> createState() => _AnimatedStarState();
}

class _AnimatedStarState extends State<_AnimatedStar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.fast);
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));
  }

  @override
  void didUpdateWidget(covariant _AnimatedStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filled != oldWidget.filled) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return IconButton(
      onPressed: widget.onTap,
      icon: ScaleTransition(
        scale: _scale,
        child: Icon(
          widget.filled ? Icons.star_rounded : Icons.star_border_rounded,
          color: appColors.ratingStar,
          size: 34,
        ),
      ),
    );
  }
}
