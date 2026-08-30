import mongoose from 'mongoose';

// The Flutter client's slide-block/slide-item model (see SlideBlock/
// SlideItem/SlideQuiz.toMap() in
// jyamiti/lib/domain/models/slide_deck_models.dart) has grown a large,
// still-actively-growing set of optional per-type fields over time
// (backgroundColor/textColor/borderColor, borderWidth/borderRadius,
// padding/marginVertical, glass/glassStyle, width/selfAlign/
// selfAlignVertical, bold/italic/underline/strikethrough/fitContent,
// nested columns/container children encoded as JSON inside `content`,
// and more) across 16 block types (heading, subheading, paragraph,
// code, bulletList, callout, imageUrl, math, svg, table, video, card,
// columns, banner, text, container).
//
// A previous version of this schema rigidly enumerated only 8 much
// older block type names (list/image/latexMath instead of
// bulletList/imageUrl/math, no svg/table/video/card/columns/banner/
// text/container at all) and a handful of styling fields, under
// Mongoose's default `strict: true`. Since findOneAndUpdate casts its
// update document against the schema, that silently STRIPPED every
// field it didn't recognize -- and any block whose `type` didn't match
// the old enum still saved, just gutted of nearly all its real content
// -- on every single "Save Deck", with no error surfaced anywhere
// (POST /slide-decks always returned 200). SlideItem's `quiz` (a
// single object) was also never even declared -- only an unrelated
// `quizzes` array shape -- so quiz data was silently dropped on every
// save too.
//
// Deliberately permissive here instead of trying to keep re-enumerating
// every field: `blocks` and `quiz` are stored as whatever shape the
// client actually sends (Mixed), and slideItemSchema/slideDeckSchema
// use `strict: false` for the same reason -- so a new field added
// client-side (which has happened dozens of times across this model's
// history) just gets persisted, instead of silently vanishing on the
// next save the way this bug did.

const slideItemSchema = new mongoose.Schema(
  {
    id: { type: String, required: true },
    slideIndex: { type: Number, required: true },
    title: { type: String, required: true },
    theme: { type: String, default: 'darkGlass' },
    // Each block's own shape varies by type -- see the file-level
    // comment above. Mixed skips Mongoose's schema casting entirely,
    // so every field a block carries (present now or added later)
    // round-trips unchanged.
    blocks: { type: [mongoose.Schema.Types.Mixed], default: [] },
    // Singular, matching SlideQuiz.toMap()'s
    // {question, options, correctIndex, explanation} shape -- null
    // when the slide has no quiz.
    quiz: { type: mongoose.Schema.Types.Mixed, default: null },
    enableWhiteboard: { type: Boolean, default: true },
    // 'theme' | 'solidColor' | 'gradient' | 'image' -- see
    // SlideBackgroundType in slide_deck_models.dart.
    backgroundType: { type: String, default: 'theme' },
    backgroundColor: { type: String, default: null },
    backgroundColor2: { type: String, default: null },
    backgroundImageUrl: { type: String, default: null },
  },
  { _id: false, strict: false },
);

const slideDeckSchema = new mongoose.Schema(
  {
    id: { type: String, required: true, unique: true },
    courseId: { type: String, required: true },
    courseName: { type: String, required: true },
    title: { type: String, required: true },
    description: { type: String, default: '' },
    isPublished: { type: Boolean, default: true },
    isDownloadedOffline: { type: Boolean, default: false },
    slides: [slideItemSchema],
  },
  { timestamps: true, strict: false },
);

const slideProgressSchema = new mongoose.Schema(
  {
    deckId: { type: String, required: true },
    userId: { type: String, default: 'stu_current' },
    timeSpentPerSlide: { type: Map, of: Number, default: {} },
    completedSlides: { type: Map, of: Boolean, default: {} },
    bookmarkedSlides: { type: Map, of: Boolean, default: {} },
    quizAnswers: { type: Map, of: Number, default: {} },
    slideDrawings: { type: Map, of: String, default: {} },
    lastViewedSlideIndex: { type: Number, default: 0 },
  },
  { timestamps: true },
);

export const SlideDeck = mongoose.model('SlideDeck', slideDeckSchema);
export const SlideProgress = mongoose.model('SlideProgress', slideProgressSchema);
