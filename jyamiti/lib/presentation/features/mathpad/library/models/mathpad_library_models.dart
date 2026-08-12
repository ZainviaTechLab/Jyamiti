import 'dart:math';

/// Local (on-device only) id -- unique enough for a single tutor's single
/// device without pulling in a `uuid` dependency: a microsecond timestamp
/// is already unique per-process, the random suffix just guards against two
/// ids being minted within the same microsecond (e.g. a batch-create loop).
String newMathPadLibraryId() {
  final rand = Random().nextInt(0x7fffffff);
  return '${DateTime.now().microsecondsSinceEpoch}_$rand';
}

/// A Chapter/Topic/Sub-topic node resolved from a [MathPadLibraryIndex]
/// search (`findNodeById`/`findLatestNode`) -- everything needed to open
/// it directly in `MathPadPageEditorPage` without the tutor manually
/// drilling down through the library browser.
typedef MathPadFoundNode = ({
  String nodeId,
  String nodeTitle,
  List<MathPadPageRef> pages,
});

/// Where to pre-navigate a `MathPadLibraryTreeView` so a given node is
/// visible in its currently-shown list (as opposed to [MathPadFoundNode],
/// which resolves the node's own pages/breadcrumb) -- `chapterIndex`/
/// `topicIndex` null means "shown at the book/chapter level itself",
/// e.g. a Chapter node's path is just its book (chapters list visible);
/// a Sub-topic node's path drills to its chapter+topic (sub-topics list
/// visible).
typedef MathPadNodeContainerPath = ({
  MathPadBook book,
  int? chapterIndex,
  int? topicIndex,
});

/// Metadata for one saved Math Pad drawing. The actual canvas content
/// (strokes/instruments/labels/images) lives in its own file on disk,
/// addressed by [id] -- see `MathPadLibraryStorageService`.
class MathPadPageRef {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;

  MathPadPageRef({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MathPadPageRef.create(String title) {
    final now = DateTime.now();
    return MathPadPageRef(
      id: newMathPadLibraryId(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MathPadPageRef.fromJson(Map<String, dynamic> json) => MathPadPageRef(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class MathPadSubTopic {
  final String id;
  String title;
  final List<MathPadPageRef> pages;

  MathPadSubTopic({required this.id, required this.title, List<MathPadPageRef>? pages})
    : pages = pages ?? [];

  factory MathPadSubTopic.create(String title) =>
      MathPadSubTopic(id: newMathPadLibraryId(), title: title);

  MathPadPageRef addPage(String title) {
    final page = MathPadPageRef.create(title);
    pages.add(page);
    return page;
  }

  /// Removes the page with [pageId] if present, returning it (for the
  /// caller to also delete its on-disk content), or null if not found.
  MathPadPageRef? removePage(String pageId) {
    final idx = pages.indexWhere((p) => p.id == pageId);
    if (idx == -1) return null;
    return pages.removeAt(idx);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory MathPadSubTopic.fromJson(Map<String, dynamic> json) => MathPadSubTopic(
    id: json['id'] as String,
    title: json['title'] as String,
    pages: (json['pages'] as List? ?? [])
        .map((p) => MathPadPageRef.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

class MathPadTopic {
  final String id;
  String title;
  final List<MathPadSubTopic> subTopics;
  final List<MathPadPageRef> pages;

  MathPadTopic({
    required this.id,
    required this.title,
    List<MathPadSubTopic>? subTopics,
    List<MathPadPageRef>? pages,
  }) : subTopics = subTopics ?? [],
       pages = pages ?? [];

  factory MathPadTopic.create(String title) =>
      MathPadTopic(id: newMathPadLibraryId(), title: title);

  MathPadSubTopic addSubTopic(String title) {
    final subTopic = MathPadSubTopic.create(title);
    subTopics.add(subTopic);
    return subTopic;
  }

  MathPadPageRef addPage(String title) {
    final page = MathPadPageRef.create(title);
    pages.add(page);
    return page;
  }

  MathPadPageRef? removePage(String pageId) {
    final idx = pages.indexWhere((p) => p.id == pageId);
    if (idx == -1) return null;
    return pages.removeAt(idx);
  }

  /// Removes the sub-topic with [subTopicId] if present, returning every
  /// page it (recursively) held so the caller can delete their on-disk
  /// content, or an empty list if not found.
  List<MathPadPageRef> removeSubTopic(String subTopicId) {
    final idx = subTopics.indexWhere((s) => s.id == subTopicId);
    if (idx == -1) return const [];
    final removed = subTopics.removeAt(idx);
    return removed.pages;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subTopics': subTopics.map((s) => s.toJson()).toList(),
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory MathPadTopic.fromJson(Map<String, dynamic> json) => MathPadTopic(
    id: json['id'] as String,
    title: json['title'] as String,
    subTopics: (json['subTopics'] as List? ?? [])
        .map((s) => MathPadSubTopic.fromJson(s as Map<String, dynamic>))
        .toList(),
    pages: (json['pages'] as List? ?? [])
        .map((p) => MathPadPageRef.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

class MathPadChapter {
  final String id;
  String title;
  final List<MathPadTopic> topics;
  final List<MathPadPageRef> pages;

  MathPadChapter({
    required this.id,
    required this.title,
    List<MathPadTopic>? topics,
    List<MathPadPageRef>? pages,
  }) : topics = topics ?? [],
       pages = pages ?? [];

  factory MathPadChapter.create(String title) =>
      MathPadChapter(id: newMathPadLibraryId(), title: title);

  MathPadTopic addTopic(String title) {
    final topic = MathPadTopic.create(title);
    topics.add(topic);
    return topic;
  }

  MathPadPageRef addPage(String title) {
    final page = MathPadPageRef.create(title);
    pages.add(page);
    return page;
  }

  MathPadPageRef? removePage(String pageId) {
    final idx = pages.indexWhere((p) => p.id == pageId);
    if (idx == -1) return null;
    return pages.removeAt(idx);
  }

  /// Removes the topic with [topicId] if present, returning every page it
  /// (recursively, including its sub-topics') held, or an empty list if
  /// not found.
  List<MathPadPageRef> removeTopic(String topicId) {
    final idx = topics.indexWhere((t) => t.id == topicId);
    if (idx == -1) return const [];
    final removed = topics.removeAt(idx);
    return [
      ...removed.pages,
      for (final sub in removed.subTopics) ...sub.pages,
    ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'topics': topics.map((t) => t.toJson()).toList(),
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory MathPadChapter.fromJson(Map<String, dynamic> json) => MathPadChapter(
    id: json['id'] as String,
    title: json['title'] as String,
    topics: (json['topics'] as List? ?? [])
        .map((t) => MathPadTopic.fromJson(t as Map<String, dynamic>))
        .toList(),
    pages: (json['pages'] as List? ?? [])
        .map((p) => MathPadPageRef.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

/// A book never holds pages directly -- only chapters do (and their
/// topics/sub-topics) -- enforcing "no pages at the Book level" at the type
/// level: there is simply no `pages` field to put them in.
class MathPadBook {
  final String id;
  String title;
  final bool isDefault;
  final String? sourceCourseId;
  final List<MathPadChapter> chapters;

  MathPadBook({
    required this.id,
    required this.title,
    this.isDefault = false,
    this.sourceCourseId,
    List<MathPadChapter>? chapters,
  }) : chapters = chapters ?? [];

  factory MathPadBook.create(
    String title, {
    bool isDefault = false,
    String? sourceCourseId,
  }) => MathPadBook(
    id: newMathPadLibraryId(),
    title: title,
    isDefault: isDefault,
    sourceCourseId: sourceCourseId,
  );

  MathPadChapter addChapter(String title) {
    final chapter = MathPadChapter.create(title);
    chapters.add(chapter);
    return chapter;
  }

  /// Removes the chapter with [chapterId] if present, returning every page
  /// it (recursively) held, or an empty list if not found.
  List<MathPadPageRef> removeChapter(String chapterId) {
    final idx = chapters.indexWhere((c) => c.id == chapterId);
    if (idx == -1) return const [];
    final removed = chapters.removeAt(idx);
    return [
      ...removed.pages,
      for (final topic in removed.topics) ...[
        ...topic.pages,
        for (final sub in topic.subTopics) ...sub.pages,
      ],
    ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDefault': isDefault,
    'sourceCourseId': sourceCourseId,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };

  factory MathPadBook.fromJson(Map<String, dynamic> json) => MathPadBook(
    id: json['id'] as String,
    title: json['title'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
    sourceCourseId: json['sourceCourseId'] as String?,
    chapters: (json['chapters'] as List? ?? [])
        .map((c) => MathPadChapter.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

/// The full local library for one batch: every book (the auto-seeded
/// default course book, plus any custom books the tutor added).
class MathPadLibraryIndex {
  final String batchId;
  final List<MathPadBook> books;
  final List<String> recentPageIds;

  MathPadLibraryIndex({required this.batchId, List<MathPadBook>? books, List<String>? recentPageIds})
    : books = books ?? [],
      recentPageIds = recentPageIds ?? [];

  MathPadBook addBook(String title, {bool isDefault = false, String? sourceCourseId}) {
    final book = MathPadBook.create(
      title,
      isDefault: isDefault,
      sourceCourseId: sourceCourseId,
    );
    books.add(book);
    return book;
  }

  /// Removes the book with [bookId] if present, returning every page it
  /// (recursively) held, or an empty list if not found.
  List<MathPadPageRef> removeBook(String bookId) {
    final idx = books.indexWhere((b) => b.id == bookId);
    if (idx == -1) return const [];
    final removed = books.removeAt(idx);
    final pages = <MathPadPageRef>[];
    for (final chapter in removed.chapters) {
      pages.addAll(chapter.pages);
      for (final topic in chapter.topics) {
        pages.addAll(topic.pages);
        for (final sub in topic.subTopics) {
          pages.addAll(sub.pages);
        }
      }
    }
    return pages;
  }

  /// Searches every book for a Chapter/Topic/Sub-topic with [nodeId] --
  /// used to resume the tutor's last-worked-on node (which may since have
  /// been renamed, or deleted, in which case this returns null and the
  /// caller should fall back to [findLatestNode]).
  MathPadFoundNode? findNodeById(String nodeId) {
    for (final book in books) {
      for (final chapter in book.chapters) {
        if (chapter.id == nodeId) {
          return (
            nodeId: chapter.id,
            nodeTitle: '${book.title} › ${chapter.title}',
            pages: chapter.pages,
          );
        }
        for (final topic in chapter.topics) {
          if (topic.id == nodeId) {
            return (
              nodeId: topic.id,
              nodeTitle: '${book.title} › ${chapter.title} › ${topic.title}',
              pages: topic.pages,
            );
          }
          for (final subTopic in topic.subTopics) {
            if (subTopic.id == nodeId) {
              return (
                nodeId: subTopic.id,
                nodeTitle: '${book.title} › ${chapter.title} › ${topic.title} › ${subTopic.title}',
                pages: subTopic.pages,
              );
            }
          }
        }
      }
    }
    return null;
  }

  /// Same search as [findNodeById], but returns where to pre-navigate a
  /// tree browser so [nodeId] shows up in its visible list, instead of the
  /// node's own resolved pages/breadcrumb.
  MathPadNodeContainerPath? findNodeContainerPath(String nodeId) {
    for (final book in books) {
      for (int ci = 0; ci < book.chapters.length; ci++) {
        final chapter = book.chapters[ci];
        if (chapter.id == nodeId) {
          return (book: book, chapterIndex: null, topicIndex: null);
        }
        for (int ti = 0; ti < chapter.topics.length; ti++) {
          final topic = chapter.topics[ti];
          if (topic.id == nodeId) {
            return (book: book, chapterIndex: ci, topicIndex: null);
          }
          for (final subTopic in topic.subTopics) {
            if (subTopic.id == nodeId) {
              return (book: book, chapterIndex: ci, topicIndex: ti);
            }
          }
        }
      }
    }
    return null;
  }

  /// The most-recently-added node reachable by following the last book,
  /// its last chapter, its last topic, and its last sub-topic (each level
  /// only descends if that level has children -- e.g. a chapter with no
  /// topics is itself the latest node). Used to jump straight into a pad
  /// when there's no last-worked record yet but something has already
  /// been created. Returns null only if no book has any chapter at all
  /// (pages can't live at the bare Book level, so there's nothing to open).
  MathPadFoundNode? findLatestNode() {
    if (books.isEmpty) return null;
    final book = books.last;
    if (book.chapters.isEmpty) return null;
    final chapter = book.chapters.last;
    if (chapter.topics.isEmpty) {
      return (nodeId: chapter.id, nodeTitle: '${book.title} › ${chapter.title}', pages: chapter.pages);
    }
    final topic = chapter.topics.last;
    if (topic.subTopics.isEmpty) {
      return (
        nodeId: topic.id,
        nodeTitle: '${book.title} › ${chapter.title} › ${topic.title}',
        pages: topic.pages,
      );
    }
    final subTopic = topic.subTopics.last;
    return (
      nodeId: subTopic.id,
      nodeTitle: '${book.title} › ${chapter.title} › ${topic.title} › ${subTopic.title}',
      pages: subTopic.pages,
    );
  }

  void recordPageOpened(String pageId) {
    recentPageIds.remove(pageId);
    recentPageIds.insert(0, pageId);
    if (recentPageIds.length > 5) {
      recentPageIds.removeLast();
    }
  }

  MathPadFoundNode? findNodeForPage(String pageId) {
    for (final book in books) {
      for (final chapter in book.chapters) {
        for (final topic in chapter.topics) {
          for (final subTopic in topic.subTopics) {
            for (final page in subTopic.pages) {
              if (page.id == pageId) {
                return (
                  nodeId: subTopic.id,
                  nodeTitle: '${book.title} › ${chapter.title} › ${topic.title} › ${subTopic.title}',
                  pages: subTopic.pages,
                );
              }
            }
          }
          for (final page in topic.pages) {
            if (page.id == pageId) {
              return (
                nodeId: topic.id,
                nodeTitle: '${book.title} › ${chapter.title} › ${topic.title}',
                pages: topic.pages,
              );
            }
          }
        }
        for (final page in chapter.pages) {
          if (page.id == pageId) {
            return (
              nodeId: chapter.id,
              nodeTitle: '${book.title} › ${chapter.title}',
              pages: chapter.pages,
            );
          }
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'batchId': batchId,
    'books': books.map((b) => b.toJson()).toList(),
    'recentPageIds': recentPageIds,
  };

  factory MathPadLibraryIndex.fromJson(Map<String, dynamic> json) => MathPadLibraryIndex(
    batchId: json['batchId'] as String,
    books: (json['books'] as List? ?? [])
        .map((b) => MathPadBook.fromJson(b as Map<String, dynamic>))
        .toList(),
    recentPageIds: (json['recentPageIds'] as List?)?.map((e) => e as String).toList(),
  );
}
