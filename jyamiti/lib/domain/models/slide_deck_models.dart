import 'dart:convert';

enum SlideBlockType {
  heading,
  subheading,
  paragraph,
  code,
  bulletList,
  callout,
  imageUrl,
  math,
  svg,
  table,
  video,
  card,
  columns,
  banner,
}

class SlideBlock {
  final String id;
  final SlideBlockType type;
  final String content;
  final String? extra; // Language for code, callout type, list items comma separated
  final String? caption;

  // Advanced per-block styling -- all optional, all null by default so
  // existing decks render exactly as before. Hex strings (no leading '#',
  // e.g. "6366F1" or 8-digit "FF6366F1" with alpha) rather than Flutter
  // Color values -- this file deliberately has no Flutter dependency (see
  // SlideDeck's own doc comments elsewhere); parsing lives in
  // slide_color_utils.dart at the widget layer instead.
  final String? backgroundColor;
  final String? textColor;
  final String? borderColor;
  final double borderWidth;

  // Layout knobs -- currently only read by the `banner` block type's own
  // renderer (see SlideBlockRenderer._buildBannerBlock), kept on SlideBlock
  // generally rather than banner-specific so they're available to other
  // block types later without another migration. All null/default means
  // "use that block type's own hardcoded default" -- e.g. banner defaults
  // to horizontalAlign 'center' when this is null, not literally unaligned.
  final double? padding; // internal spacing on all sides
  final double? marginVertical; // spacing above/below the block
  final double? fontSize;
  final String? horizontalAlign; // 'left' | 'center' | 'right'
  final String? verticalAlign; // 'top' | 'center' | 'bottom'
  final double? minHeight; // lets verticalAlign do something beyond a tight fit

  SlideBlock({
    required this.id,
    required this.type,
    required this.content,
    this.extra,
    this.caption,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.borderWidth = 0,
    this.padding,
    this.marginVertical,
    this.fontSize,
    this.horizontalAlign,
    this.verticalAlign,
    this.minHeight,
  });

  SlideBlock copyWith({
    String? id,
    SlideBlockType? type,
    String? content,
    String? extra,
    bool clearExtra = false,
    String? caption,
    bool clearCaption = false,
    String? backgroundColor,
    bool clearBackgroundColor = false,
    String? textColor,
    bool clearTextColor = false,
    String? borderColor,
    bool clearBorderColor = false,
    double? borderWidth,
    double? padding,
    bool clearPadding = false,
    double? marginVertical,
    bool clearMarginVertical = false,
    double? fontSize,
    bool clearFontSize = false,
    String? horizontalAlign,
    bool clearHorizontalAlign = false,
    String? verticalAlign,
    bool clearVerticalAlign = false,
    double? minHeight,
    bool clearMinHeight = false,
  }) {
    return SlideBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      extra: clearExtra ? null : (extra ?? this.extra),
      caption: clearCaption ? null : (caption ?? this.caption),
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      textColor: clearTextColor ? null : (textColor ?? this.textColor),
      borderColor:
          clearBorderColor ? null : (borderColor ?? this.borderColor),
      borderWidth: borderWidth ?? this.borderWidth,
      padding: clearPadding ? null : (padding ?? this.padding),
      marginVertical: clearMarginVertical
          ? null
          : (marginVertical ?? this.marginVertical),
      fontSize: clearFontSize ? null : (fontSize ?? this.fontSize),
      horizontalAlign: clearHorizontalAlign
          ? null
          : (horizontalAlign ?? this.horizontalAlign),
      verticalAlign:
          clearVerticalAlign ? null : (verticalAlign ?? this.verticalAlign),
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'extra': extra,
      'caption': caption,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'borderColor': borderColor,
      'borderWidth': borderWidth,
      'padding': padding,
      'marginVertical': marginVertical,
      'fontSize': fontSize,
      'horizontalAlign': horizontalAlign,
      'verticalAlign': verticalAlign,
      'minHeight': minHeight,
    };
  }

  factory SlideBlock.fromMap(Map<String, dynamic> map) {
    final rawType = (map['type'] ?? '').toString().toLowerCase();
    return SlideBlock(
      id: map['id'] ?? '',
      type: SlideBlockType.values.firstWhere(
        (e) => e.name.toLowerCase() == rawType,
        orElse: () => SlideBlockType.paragraph,
      ),
      content: map['content'] ?? '',
      extra: map['extra'],
      caption: map['caption'],
      backgroundColor: map['backgroundColor'],
      textColor: map['textColor'],
      borderColor: map['borderColor'],
      borderWidth: (map['borderWidth'] as num?)?.toDouble() ?? 0,
      padding: (map['padding'] as num?)?.toDouble(),
      marginVertical: (map['marginVertical'] as num?)?.toDouble(),
      fontSize: (map['fontSize'] as num?)?.toDouble(),
      horizontalAlign: map['horizontalAlign'],
      verticalAlign: map['verticalAlign'],
      minHeight: (map['minHeight'] as num?)?.toDouble(),
    );
  }

  String toJson() => json.encode(toMap());
  factory SlideBlock.fromJson(String source) =>
      SlideBlock.fromMap(json.decode(source));
}

class SlideQuiz {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  SlideQuiz({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
    };
  }

  factory SlideQuiz.fromMap(Map<String, dynamic> map) {
    return SlideQuiz(
      question: map['question'] ?? '',
      options: List<String>.from(map['options'] ?? []),
      correctIndex: map['correctIndex']?.toInt() ?? 0,
      explanation: map['explanation'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());
  factory SlideQuiz.fromJson(String source) =>
      SlideQuiz.fromMap(json.decode(source));
}

/// What a slide's background actually is. `theme` (the default) keeps the
/// existing behavior -- one of the named palettes in `SlideItem.theme`,
/// applied by whatever's rendering the slide. The other three let a
/// specific slide override that with its own solid color, two-color
/// gradient, or background image.
enum SlideBackgroundType { theme, solidColor, gradient, image }

class SlideItem {
  final String id;
  final int slideIndex;
  final String title;
  final List<SlideBlock> blocks;
  final String theme; // 'darkGlass', 'midnightNeon', 'emeraldSlate', 'sunsetViolet', 'cleanLight'
  final SlideQuiz? quiz;
  final bool enableWhiteboard;

  // Advanced per-slide background -- backgroundType defaults to `theme`
  // (existing behavior: render via the named `theme` palette above), so
  // every existing deck keeps rendering exactly as before. The other
  // fields only matter when backgroundType picks them.
  final SlideBackgroundType backgroundType;
  final String? backgroundColor; // solidColor, or gradient's first stop
  final String? backgroundColor2; // gradient's second stop
  final String? backgroundImageUrl;

  // Where the slide's whole content column (header badge + blocks + quiz,
  // as one unit) sits within the available vertical space -- 'top' (the
  // default, existing behavior: content starts right below the header
  // like a normal scrollable document) | 'center' | 'bottom'. This is
  // what actually makes "a banner centered on an otherwise-blank slide"
  // possible: a block's OWN horizontalAlign/verticalAlign (see
  // SlideBlock) only position that block's content within its own box --
  // they say nothing about where the block sits on the slide as a whole,
  // which is a slide-level layout question, not a block-level one.
  final String contentVerticalAlign;

  SlideItem({
    required this.id,
    required this.slideIndex,
    required this.title,
    required this.blocks,
    this.theme = 'darkGlass',
    this.quiz,
    this.enableWhiteboard = true,
    this.backgroundType = SlideBackgroundType.theme,
    this.backgroundColor,
    this.backgroundColor2,
    this.backgroundImageUrl,
    this.contentVerticalAlign = 'top',
  });

  SlideItem copyWith({
    String? id,
    int? slideIndex,
    String? title,
    List<SlideBlock>? blocks,
    String? theme,
    SlideQuiz? quiz,
    bool clearQuiz = false,
    bool? enableWhiteboard,
    SlideBackgroundType? backgroundType,
    String? backgroundColor,
    bool clearBackgroundColor = false,
    String? backgroundColor2,
    bool clearBackgroundColor2 = false,
    String? backgroundImageUrl,
    bool clearBackgroundImageUrl = false,
    String? contentVerticalAlign,
  }) {
    return SlideItem(
      id: id ?? this.id,
      slideIndex: slideIndex ?? this.slideIndex,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      theme: theme ?? this.theme,
      quiz: clearQuiz ? null : (quiz ?? this.quiz),
      enableWhiteboard: enableWhiteboard ?? this.enableWhiteboard,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      backgroundColor2: clearBackgroundColor2
          ? null
          : (backgroundColor2 ?? this.backgroundColor2),
      backgroundImageUrl: clearBackgroundImageUrl
          ? null
          : (backgroundImageUrl ?? this.backgroundImageUrl),
      contentVerticalAlign: contentVerticalAlign ?? this.contentVerticalAlign,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slideIndex': slideIndex,
      'title': title,
      'blocks': blocks.map((x) => x.toMap()).toList(),
      'theme': theme,
      'quiz': quiz?.toMap(),
      'enableWhiteboard': enableWhiteboard,
      'backgroundType': backgroundType.name,
      'backgroundColor': backgroundColor,
      'backgroundColor2': backgroundColor2,
      'backgroundImageUrl': backgroundImageUrl,
      'contentVerticalAlign': contentVerticalAlign,
    };
  }

  factory SlideItem.fromMap(Map<String, dynamic> map) {
    final rawBgType = (map['backgroundType'] ?? '').toString().toLowerCase();
    return SlideItem(
      id: map['id'] ?? '',
      slideIndex: map['slideIndex']?.toInt() ?? 0,
      title: map['title'] ?? '',
      blocks: List<SlideBlock>.from(
        (map['blocks'] as List<dynamic>? ?? []).map(
          (x) => SlideBlock.fromMap(x as Map<String, dynamic>),
        ),
      ),
      theme: map['theme'] ?? 'darkGlass',
      quiz: map['quiz'] != null ? SlideQuiz.fromMap(map['quiz']) : null,
      enableWhiteboard: map['enableWhiteboard'] ?? true,
      backgroundType: SlideBackgroundType.values.firstWhere(
        (e) => e.name.toLowerCase() == rawBgType,
        orElse: () => SlideBackgroundType.theme,
      ),
      backgroundColor: map['backgroundColor'],
      backgroundColor2: map['backgroundColor2'],
      backgroundImageUrl: map['backgroundImageUrl'],
      contentVerticalAlign: map['contentVerticalAlign'] ?? 'top',
    );
  }

  String toJson() => json.encode(toMap());
  factory SlideItem.fromJson(String source) =>
      SlideItem.fromMap(json.decode(source));
}

class SlideDeck {
  final String id;
  final String courseId;
  final String courseName;
  final String title;
  final String description;
  final List<SlideItem> slides;
  final DateTime createdAt;
  final bool isPublished;
  final bool isDownloadedOffline;

  SlideDeck({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.description,
    required this.slides,
    required this.createdAt,
    this.isPublished = true,
    this.isDownloadedOffline = false,
  });

  SlideDeck copyWith({
    String? id,
    String? courseId,
    String? courseName,
    String? title,
    String? description,
    List<SlideItem>? slides,
    DateTime? createdAt,
    bool? isPublished,
    bool? isDownloadedOffline,
  }) {
    return SlideDeck(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      title: title ?? this.title,
      description: description ?? this.description,
      slides: slides ?? this.slides,
      createdAt: createdAt ?? this.createdAt,
      isPublished: isPublished ?? this.isPublished,
      isDownloadedOffline: isDownloadedOffline ?? this.isDownloadedOffline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'courseId': courseId,
      'courseName': courseName,
      'title': title,
      'description': description,
      'slides': slides.map((x) => x.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isPublished': isPublished,
      'isDownloadedOffline': isDownloadedOffline,
    };
  }

  factory SlideDeck.fromMap(Map<String, dynamic> map) {
    return SlideDeck(
      id: map['id'] ?? '',
      courseId: map['courseId'] ?? '',
      courseName: map['courseName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      slides: List<SlideItem>.from(
        (map['slides'] as List<dynamic>? ?? []).map(
          (x) => SlideItem.fromMap(x as Map<String, dynamic>),
        ),
      ),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      isPublished: map['isPublished'] ?? true,
      isDownloadedOffline: map['isDownloadedOffline'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());
  factory SlideDeck.fromJson(String source) =>
      SlideDeck.fromMap(json.decode(source));
}

class SlideProgress {
  final String deckId;
  final Map<int, int> timeSpentPerSlide; // slideIndex -> seconds
  final Set<int> completedSlides; // slideIndex set
  final Set<int> bookmarkedSlides; // slideIndex set
  final Map<int, int> quizAnswers; // slideIndex -> selectedOptionIndex
  final Map<int, String> slideDrawings; // slideIndex -> drawing Json string
  final int lastViewedSlideIndex;
  final DateTime lastUpdated;

  SlideProgress({
    required this.deckId,
    required this.timeSpentPerSlide,
    required this.completedSlides,
    required this.bookmarkedSlides,
    required this.quizAnswers,
    required this.slideDrawings,
    this.lastViewedSlideIndex = 0,
    required this.lastUpdated,
  });

  double calculateCompletionPercent(int totalSlides) {
    if (totalSlides == 0) return 0.0;
    return (completedSlides.length / totalSlides).clamp(0.0, 1.0);
  }

  int calculateTotalTimeSpentSeconds() {
    int total = 0;
    for (var seconds in timeSpentPerSlide.values) {
      total += seconds;
    }
    return total;
  }

  Map<String, dynamic> toMap() {
    return {
      'deckId': deckId,
      'timeSpentPerSlide': timeSpentPerSlide.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'completedSlides': completedSlides.toList(),
      'bookmarkedSlides': bookmarkedSlides.toList(),
      'quizAnswers': quizAnswers.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'slideDrawings': slideDrawings.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'lastViewedSlideIndex': lastViewedSlideIndex,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory SlideProgress.fromMap(Map<String, dynamic> map) {
    Map<int, int> parsedTime = {};
    if (map['timeSpentPerSlide'] != null) {
      (map['timeSpentPerSlide'] as Map<String, dynamic>).forEach((k, v) {
        parsedTime[int.parse(k)] = (v as num).toInt();
      });
    }

    Map<int, int> parsedQuizzes = {};
    if (map['quizAnswers'] != null) {
      (map['quizAnswers'] as Map<String, dynamic>).forEach((k, v) {
        parsedQuizzes[int.parse(k)] = (v as num).toInt();
      });
    }

    Map<int, String> parsedDrawings = {};
    if (map['slideDrawings'] != null) {
      (map['slideDrawings'] as Map<String, dynamic>).forEach((k, v) {
        parsedDrawings[int.parse(k)] = v.toString();
      });
    }

    return SlideProgress(
      deckId: map['deckId'] ?? '',
      timeSpentPerSlide: parsedTime,
      completedSlides: Set<int>.from(
        (map['completedSlides'] as List<dynamic>? ?? []).map((x) => (x as num).toInt()),
      ),
      bookmarkedSlides: Set<int>.from(
        (map['bookmarkedSlides'] as List<dynamic>? ?? []).map((x) => (x as num).toInt()),
      ),
      quizAnswers: parsedQuizzes,
      slideDrawings: parsedDrawings,
      lastViewedSlideIndex: map['lastViewedSlideIndex']?.toInt() ?? 0,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.parse(map['lastUpdated'])
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory SlideProgress.fromJson(String source) =>
      SlideProgress.fromMap(json.decode(source));
}

class SlideAnalyticsReport {
  final String studentId;
  final String studentName;
  final String deckId;
  final String deckTitle;
  final double completionPercent;
  final int totalTimeSpentSeconds;
  final Map<int, int> slideTimeSpent;
  final int quizScore;
  final int totalQuizzes;
  final DateTime lastActive;

  SlideAnalyticsReport({
    required this.studentId,
    required this.studentName,
    required this.deckId,
    required this.deckTitle,
    required this.completionPercent,
    required this.totalTimeSpentSeconds,
    required this.slideTimeSpent,
    required this.quizScore,
    required this.totalQuizzes,
    required this.lastActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'deckId': deckId,
      'deckTitle': deckTitle,
      'completionPercent': completionPercent,
      'totalTimeSpentSeconds': totalTimeSpentSeconds,
      'slideTimeSpent': slideTimeSpent.map((k, v) => MapEntry(k.toString(), v)),
      'quizScore': quizScore,
      'totalQuizzes': totalQuizzes,
      'lastActive': lastActive.toIso8601String(),
    };
  }

  factory SlideAnalyticsReport.fromMap(Map<String, dynamic> map) {
    Map<int, int> parsedTimes = {};
    if (map['slideTimeSpent'] != null) {
      (map['slideTimeSpent'] as Map<String, dynamic>).forEach((k, v) {
        parsedTimes[int.parse(k)] = (v as num).toInt();
      });
    }

    return SlideAnalyticsReport(
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      deckId: map['deckId'] ?? '',
      deckTitle: map['deckTitle'] ?? '',
      completionPercent: (map['completionPercent'] as num?)?.toDouble() ?? 0.0,
      totalTimeSpentSeconds: map['totalTimeSpentSeconds']?.toInt() ?? 0,
      slideTimeSpent: parsedTimes,
      quizScore: map['quizScore']?.toInt() ?? 0,
      totalQuizzes: map['totalQuizzes']?.toInt() ?? 0,
      lastActive: map['lastActive'] != null
          ? DateTime.parse(map['lastActive'])
          : DateTime.now(),
    );
  }
}
