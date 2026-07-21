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
}

class SlideBlock {
  final String id;
  final SlideBlockType type;
  final String content;
  final String? extra; // Language for code, callout type, list items comma separated
  final String? caption;

  SlideBlock({
    required this.id,
    required this.type,
    required this.content,
    this.extra,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'extra': extra,
      'caption': caption,
    };
  }

  factory SlideBlock.fromMap(Map<String, dynamic> map) {
    return SlideBlock(
      id: map['id'] ?? '',
      type: SlideBlockType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => SlideBlockType.paragraph,
      ),
      content: map['content'] ?? '',
      extra: map['extra'],
      caption: map['caption'],
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

class SlideItem {
  final String id;
  final int slideIndex;
  final String title;
  final List<SlideBlock> blocks;
  final String theme; // 'darkGlass', 'midnightNeon', 'emeraldSlate', 'sunsetViolet', 'cleanLight'
  final SlideQuiz? quiz;
  final bool enableWhiteboard;

  SlideItem({
    required this.id,
    required this.slideIndex,
    required this.title,
    required this.blocks,
    this.theme = 'darkGlass',
    this.quiz,
    this.enableWhiteboard = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slideIndex': slideIndex,
      'title': title,
      'blocks': blocks.map((x) => x.toMap()).toList(),
      'theme': theme,
      'quiz': quiz?.toMap(),
      'enableWhiteboard': enableWhiteboard,
    };
  }

  factory SlideItem.fromMap(Map<String, dynamic> map) {
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
