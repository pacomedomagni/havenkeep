import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';

/// Full-screen search over the user's entire warranty catalog.
///
/// One-tap from the dashboard app bar so power users aren't forced to tab
/// into Warranties and then focus the search field.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<Item> _filter(List<Item> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return items.where((item) {
      final haystack = [
        item.name,
        item.brand ?? '',
        item.modelNumber ?? '',
        item.store ?? '',
        item.warrantyProvider ?? '',
        item.category.displayLabel,
        item.room?.displayLabel ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search warranties, brands, stores…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: HavenColors.textTertiary),
          ),
          style: const TextStyle(
            color: HavenColors.textPrimary,
            fontSize: 16,
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () {
                setState(() {
                  _controller.clear();
                  _query = '';
                });
                _focusNode.requestFocus();
              },
            ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: HavenLoader()),
        error: (e, _) => const Center(
          child: Text(
            'Could not load warranties',
            style: TextStyle(color: HavenColors.textSecondary),
          ),
        ),
        data: (items) {
          if (_query.isEmpty) {
            return _EmptyHint(count: items.length);
          }
          final results = _filter(items);
          if (results.isEmpty) {
            return Center(
              child: Text(
                'No matches for "$_query"',
                style: const TextStyle(color: HavenColors.textSecondary),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(HavenSpacing.md),
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: HavenSpacing.sm),
            itemBuilder: (context, i) => _SearchResultTile(item: results[i]),
          );
        },
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final int count;
  const _EmptyHint({required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HavenIllustration(
            kind: HavenIllustrationKind.searchIdle,
            size: 160,
          ),
          const SizedBox(height: HavenSpacing.sm),
          Text(
            'Search across your $count warrant${count == 1 ? 'y' : 'ies'}',
            style: HavenText.bodySecondary,
          ),
          const SizedBox(height: HavenSpacing.xs),
          const Text(
            'Try a brand, store, or model number',
            style: HavenText.caption,
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Item item;
  const _SearchResultTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final displayName = [item.brand, item.name]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    return InkWell(
      borderRadius: BorderRadius.circular(HavenRadius.card),
      onTap: () => context.push('/items/${item.id}'),
      child: Container(
        padding: const EdgeInsets.all(HavenSpacing.md),
        decoration: BoxDecoration(
          color: HavenColors.surface,
          borderRadius: BorderRadius.circular(HavenRadius.card),
          border: Border.all(color: HavenColors.border),
        ),
        child: Row(
          children: [
            Hero(
              tag: 'item-icon-${item.id}',
              child: CategoryIcon.widget(item.category),
            ),
            const SizedBox(width: HavenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName.isEmpty ? item.name : displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      item.category.displayLabel,
                      if (item.room != null) item.room!.displayLabel,
                      if (item.price != null) Money.format(item.price),
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HavenColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: HavenColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
