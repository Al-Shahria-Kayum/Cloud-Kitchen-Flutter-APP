import 'package:flutter/material.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/network_food_image.dart';

/// Generic reviews list — used both for a kitchen's reviews and a rider's
/// reviews, reached by tapping the "Reviews" number on their dashboard.
class ReviewsScreen extends StatefulWidget {
  final String title;
  final double avgRating;
  final int reviewCount;
  final Future<List<Review>> Function() loadReviews;

  const ReviewsScreen({
    super.key,
    required this.title,
    required this.avgRating,
    required this.reviewCount,
    required this.loadReviews,
  });

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Review> _reviews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _hasError = false);
    try {
      final reviews = await widget.loadReviews();
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  /// The count shown updates to the freshly-loaded list once available,
  /// rather than staying frozen at the snapshot value passed in at open time.
  int get _displayedCount => _isLoading ? widget.reviewCount : _reviews.length;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: AppRadius.lgBr,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, color: appColors.ratingStar, size: 32),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          widget.avgRating > 0 ? widget.avgRating.toStringAsFixed(1) : '—',
                          style: text.displaySmall,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '· $_displayedCount review${_displayedCount == 1 ? '' : 's'}',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_hasError)
                    EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Couldn\'t load reviews',
                      message: 'Check your connection and pull down to try again.',
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  else if (_reviews.isEmpty)
                    const EmptyState(
                      icon: Icons.reviews_outlined,
                      title: 'No reviews yet',
                      message: 'Reviews left by customers will show up here.',
                    )
                  else
                    ..._reviews.map((r) => _ReviewCard(review: r)),
                ],
              ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final appColors = context.appColors;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(review.raterName ?? 'Anonymous', style: text.titleMedium),
                ),
                Text(
                  '${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}',
                  style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < review.score ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 18,
                  color: appColors.ratingStar,
                ),
              ),
            ),
            if (review.review != null && review.review!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(review.review!, style: text.bodyMedium),
            ],
            if (review.photoUrls.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) => NetworkFoodImage(
                    url: review.photoUrls[i],
                    width: 72,
                    height: 72,
                    enableFullScreenTap: true,
                    galleryUrls: review.photoUrls,
                    galleryIndex: i,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
