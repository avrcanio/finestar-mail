import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// In-app PDF preview for mail attachments (mobile/desktop); web falls back to message only.
class PdfAttachmentViewerScreen extends StatefulWidget {
  const PdfAttachmentViewerScreen({
    super.key,
    required this.file,
    required this.title,
  });

  final File file;
  final String title;

  @override
  State<PdfAttachmentViewerScreen> createState() =>
      _PdfAttachmentViewerScreenState();
}

class _PdfAttachmentViewerScreenState extends State<PdfAttachmentViewerScreen> {
  late final PdfViewerController _pdfController;
  PdfTextSearchResult? _searchResult;
  bool _searchListenerAttached = false;
  String _lastSearchQuery = '';

  void _onSearchResultChanged() {
    if (!mounted) {
      return;
    }
    // Defer rebuild: Syncfusion may notify while the viewer subtree is updating;
    // scheduling avoids setState during sensitive layout/unmount windows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _detachSearchListener() {
    if (_searchListenerAttached && _searchResult != null) {
      _searchResult!.removeListener(_onSearchResultChanged);
      _searchListenerAttached = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
  }

  @override
  void dispose() {
    _detachSearchListener();
    // Do not call PdfTextSearchResult.clear() here: it notifies the viewer during
    // unmount and can trigger framework.dart _dependents assertion failures.
    super.dispose();
  }

  void _runSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _detachSearchListener();
      _searchResult?.clear();
      _searchResult = null;
      _lastSearchQuery = '';
      setState(() {});
      return;
    }

    _lastSearchQuery = trimmed;
    final result = _pdfController.searchText(trimmed);
    _searchResult = result;

    if (!kIsWeb && !_searchListenerAttached) {
      result.addListener(_onSearchResultChanged);
      _searchListenerAttached = true;
    }
    setState(() {});
  }

  Future<void> _openSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _PdfSearchSheetContent(
          initialQuery: _lastSearchQuery,
          onSearch: (value) {
            _runSearch(value);
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text('PDF preview is not available on web.'),
        ),
      );
    }

    final result = _searchResult;
    final hasHits = result != null && result.hasResult;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _detachSearchListener();
        if (context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (hasHits) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Text(
                    result.isSearchCompleted
                        ? '${result.currentInstanceIndex}/${result.totalInstanceCount}'
                        : '…',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(Icons.navigate_before),
                onPressed: () => result.previousInstance(),
              ),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(Icons.navigate_next),
                onPressed: () => result.nextInstance(),
              ),
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () => _runSearch(''),
              ),
            ],
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: _openSearchSheet,
            ),
          ],
        ),
        body: SfPdfViewer.file(
          widget.file,
          controller: _pdfController,
        ),
      ),
    );
  }
}

/// Owns [TextEditingController] for the search sheet so it is disposed only after
/// the route has torn down the [TextField] (avoids "used after being disposed").
class _PdfSearchSheetContent extends StatefulWidget {
  const _PdfSearchSheetContent({
    required this.initialQuery,
    required this.onSearch,
  });

  final String initialQuery;
  final void Function(String query) onSearch;

  @override
  State<_PdfSearchSheetContent> createState() => _PdfSearchSheetContentState();
}

class _PdfSearchSheetContentState extends State<_PdfSearchSheetContent> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search in document',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter text…',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSearch,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => widget.onSearch(_textController.text),
              child: const Text('Search'),
            ),
          ],
        ),
      ),
    );
  }
}
