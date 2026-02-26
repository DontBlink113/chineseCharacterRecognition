# Chinese Character Writing App

A comprehensive iOS application for learning Chinese characters through spaced repetition and handwriting practice, built with SwiftUI.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Features](#core-features)
- [Data Models](#data-models)
- [Key Components](#key-components)
- [How It Works](#how-it-works)
- [Technical Details](#technical-details)

---

## Overview

This application helps users learn Chinese characters through two primary methods:

1. **Flashcard Practice** - Traditional flip cards with spaced repetition
2. **Handwriting Practice** - Draw characters with real-time stroke analysis and feedback

The app uses the **FSRS-6 (Free Spaced Repetition Scheduler)** algorithm to optimize review timing based on individual learning patterns.

---

## Architecture

### Project Structure

```
Chinese Language Character Writer/
├── Models/
│   ├── FlashcardModels.swift       # Flashcard data structures & FSRS data
│   ├── FSRSScheduler.swift         # FSRS-6 spaced repetition algorithm
│   ├── FSRSOptimizer.swift         # Parameter optimization for FSRS
│   ├── LearningSetsStore.swift     # Learning set management & persistence
│   ├── StrokeModels.swift          # Stroke & character drawing models
│   ├── StrokeAnalyzer.swift        # Handwriting analysis engine
│   ├── CharacterModels.swift       # Character data structures
│   ├── DictionaryService.swift     # Chinese-English dictionary lookup
│   └── BenchmarkModels.swift       # Stroke analysis benchmarking
├── Views/
│   ├── HomeView.swift              # Main navigation hub
│   ├── FlashcardPracticeView.swift # Primary practice interface
│   ├── FlashcardReviewView.swift   # Review progress & statistics
│   ├── CharacterSetsView.swift     # Learning set management
│   ├── FlashcardSetCreationView.swift # Create new flashcard sets
│   ├── AddDefinitionsView.swift    # Add definitions to characters
│   ├── FSRSSettingsView.swift      # FSRS parameter configuration
│   ├── BenchmarkTestView.swift     # Stroke analysis testing
│   ├── SettingsView.swift          # App settings
│   └── FeedbackView.swift          # User feedback
├── NetworkManager.swift            # API communication (placeholder)
└── Chinese_Language_Character_WriterApp.swift # App entry point
```

### Design Pattern: MVVM + Store

- **Models**: Pure data structures (Codable, Equatable)
- **ViewModels**: `DrawingViewModel` manages drawing state
- **Store**: `LearningSetsStore` (ObservableObject) manages global state
- **Views**: SwiftUI views that observe state changes

---

## Core Features

### 1. Flashcard Practice

**Two Practice Modes:**

#### Flip Mode

- Shows Chinese character → tap to reveal definition
- Rate difficulty: Very Difficult, Difficult, Medium, Easy
- FSRS automatically schedules next review based on performance

#### Draw Mode

- Shows definition → draw the character
- Real-time stroke analysis compares your drawing to reference strokes
- Provides visual feedback on stroke accuracy
- Supports multi-character terms (draws each character sequentially)

**Bidirectional Learning:**

- **Prompt → Character**: See definition, recall character
- **Character → Prompt**: See character, recall definition
- Each direction has independent FSRS scheduling

### 2. Spaced Repetition (FSRS-6)

The app implements the **FSRS-6 algorithm**, a modern alternative to SM-2/Anki:

**Key Concepts:**

- **Stability**: How long you can remember a card
- **Difficulty**: Inherent difficulty of the card (1-10)
- **Retrievability**: Current probability of recall
- **States**: New → Learning → Review (or Relearning if forgotten)

**Scheduling Logic:**

- Cards are scheduled based on due dates
- Priority given to overdue cards
- Difficulty ratings update stability and difficulty parameters
- Algorithm adapts to individual learning patterns

**Parameter Optimization:**

- Built-in optimizer trains FSRS parameters on your review history
- Requires minimum 100 reviews for meaningful optimization
- Validates trained parameters before applying

### 3. Handwriting Analysis

**Stroke Recognition System:**

1. **Input Capture**: Records touch points with timestamps, pressure, and speed
2. **Stroke Extraction**: Converts raw input into normalized stroke data
3. **Reference Matching**: Compares against reference strokes from `graphics.txt`
4. **Probabilistic Scoring**: Uses DTW (Dynamic Time Warping) and shape analysis
5. **Feedback Generation**: Visual overlay showing correct vs. user strokes

**Analysis Features:**

- Bounding box normalization
- Speed and pressure sensitivity
- Stroke order detection
- Multi-character support
- Configurable error thresholds

### 4. Learning Set Management

**Learning Sets:**

- Create sets of characters to study
- Add definitions (manual or from dictionary)
- Track progress per set
- Switch between sets
- Default "Example Set" for new users

**Data Persistence:**

- All data stored in UserDefaults (JSON encoding)
- Automatic save on changes
- Active set remembered between sessions

---

## Data Models

### FlashcardItem

```swift
struct FlashcardItem {
    let id: UUID
    var hanzi: String           // Chinese character(s)
    var definition: String      // English definition
    var promptToChar: FSRSData  // Definition → Character direction
    var charToPrompt: FSRSData  // Character → Definition direction
}
```

### FSRSData

```swift
struct FSRSData {
    var due: Date               // Next review date
    var state: FSRSState        // new/learning/review/relearning
    var stability: Double       // Memory stability
    var difficulty: Double      // Card difficulty (1-10)
    var scheduledDays: Int      // Days until next review
    var reps: Int               // Total repetitions
    var lapses: Int             // Times forgotten
    var reviewHistory: [FSRSReviewLog]  // For optimization
}
```

### LearningSet

```swift
struct LearningSet {
    let id: UUID
    var name: String
    var characters: String      // All characters in set
    var items: [FlashcardItem]? // Flashcard data
}
```

### Stroke & CharacterDrawing

```swift
struct Stroke {
    let id: UUID
    var points: [StrokePoint]        // Analysis points (sampled)
    var displayPoints: [StrokePoint] // Rendering points (all)
    var startTime: TimeInterval
    var endTime: TimeInterval
}

struct CharacterDrawing {
    let id: UUID
    var strokes: [Stroke]
    var startTime: TimeInterval
    var endTime: TimeInterval
}
```

---

## Key Components

### LearningSetsStore (State Management)

**Responsibilities:**

- Manages all learning sets
- Tracks active set
- Persists data to UserDefaults
- Provides CRUD operations

**Key Methods:**

- `add(name:characters:)` - Create character-only set
- `addFlashcardSet(name:cards:)` - Create flashcard set
- `update(_:)` - Update existing set
- `remove(at:)` - Delete sets
- `setActive(_:)` - Change active set

### FSRSScheduler (Spaced Repetition Engine)

**Responsibilities:**

- Implements FSRS-6 algorithm
- Schedules card reviews
- Updates card state after reviews
- Optimizes parameters based on history

**Key Methods:**

- `updateAfterReview(_:rating:)` - Update card after review
- `getNextCard(_:direction:exclude:)` - Get next due card
- `shouldReview(_:)` - Check if card is due
- `optimizeParameters(_:)` - Train FSRS parameters
- `getReviewStats(_:)` - Get review statistics

### StrokeAnalyzer (Handwriting Recognition)

**Responsibilities:**

- Loads reference stroke data from `graphics.txt`
- Analyzes user strokes against reference
- Calculates similarity scores
- Provides visual feedback

**Key Methods:**

- `loadGraphicsData()` - Parse reference data
- `analyzeCharacter(userStrokes:character:boundingBox:)` - Analyze drawing
- `calculateStrokeError(_:_:)` - Compare strokes using DTW
- Probabilistic matching with Bayesian priors

### DrawingViewModel (Drawing State)

**Responsibilities:**

- Manages current stroke and character
- Handles touch input
- Provides undo/clear functionality
- Optimizes point sampling for performance

**Key Methods:**

- `beginStroke(at:)` / `continueStroke(at:)` / `endStroke()` - Touch handling
- `undo()` - Remove last stroke
- `clear()` - Clear all strokes
- Point sampling with time/distance thresholds

### DictionaryService (Definition Lookup)

**Responsibilities:**

- Loads Chinese-English dictionary CSV
- Provides definition lookup by character
- Singleton pattern for efficient memory use

**Data Source:**

- CSV format: hanzi, pinyin, tone, definition
- Loaded lazily on first use
- Cached in memory

---

## How It Works

### User Flow

1. **App Launch**
   - `Chinese_Language_Character_WriterApp` creates `NavigationStack`
   - Injects `LearningSetsStore` as environment object
   - Shows `HomeView`

2. **Home Screen**
   - Three main navigation options:
     - **Flashcards** → `FlashcardPracticeView`
     - **Review Progress** → `FlashcardReviewView`
     - **Set Characters** → `CharacterSetsView`

3. **Creating a Learning Set**
   - Navigate to `CharacterSetsView`
   - Tap "+" to create new set
   - Enter characters (Hanzi extraction filters non-Chinese)
   - Optionally add definitions via `AddDefinitionsView`
   - Set saved to `LearningSetsStore`

4. **Flashcard Practice Session**
   - Select learning sets to practice
   - Choose mode: Flip or Draw
   - Choose direction: Prompt→Char or Char→Prompt
   - Optional: Use original order vs. FSRS scheduling

   **Flip Mode:**
   - Card shows character (or definition based on direction)
   - Tap to flip and see answer
   - Rate difficulty (4 options)
   - FSRS updates scheduling
   - Next card automatically loaded

   **Draw Mode:**
   - Prompt shown at top
   - Draw character in canvas
   - Submit for analysis
   - View feedback with stroke comparison
   - Rate difficulty
   - Next card loaded

5. **Review Progress**
   - `FlashcardReviewView` shows statistics:
     - Total cards
     - Cards due for review
     - Direction-specific due counts
     - Individual card details with next review dates

### FSRS Scheduling Flow

```
New Card
  ↓ (First review)
  ├─ Again → Learning State
  └─ Hard/Good/Easy → Review State

Learning/Relearning
  ↓
  ├─ Again → Stay in Learning (increment steps)
  └─ Hard/Good/Easy → Review State

Review State
  ↓
  ├─ Again → Relearning State (lapse++)
  └─ Hard/Good/Easy → Update stability & difficulty
```

**After Each Review:**

1. Calculate elapsed days since last review
2. Calculate current retrievability (forgetting curve)
3. Update difficulty based on rating
4. Update stability based on difficulty, retrievability, and rating
5. Calculate next interval from stability
6. Set due date = today + interval
7. Log review for parameter optimization

### Stroke Analysis Flow

```
User Drawing
  ↓
1. Capture touch points (location, time, pressure, speed)
  ↓
2. Create Stroke objects with sampled points
  ↓
3. Build CharacterDrawing from strokes
  ↓
4. Load reference strokes for target character
  ↓
5. Normalize both user & reference to bounding box
  ↓
6. For each user stroke:
   - Calculate DTW distance to each reference stroke
   - Apply Bayesian prior (prefer sequential order)
   - Generate probability distribution
   - Select best match above threshold
  ↓
7. Generate CharacterAnalysisResult
  ↓
8. Display visual feedback overlay
```

**Stroke Matching Algorithm:**

- **DTW (Dynamic Time Warping)**: Aligns strokes of different lengths
- **Shape Features**: Direction, curvature, length
- **Bayesian Prior**: Encourages correct stroke order
- **Error Threshold**: Configurable cutoff for "matched" vs "unmatched"

---

## Technical Details

### Data Persistence

**Storage Method:** UserDefaults (JSON encoding)

**Keys:**

- `learning_sets_store_sets` - Array of LearningSet
- `learning_sets_store_active` - Active set UUID
- `boundingBoxSize` - Draw mode guide box size
- `secondsPerStroke` - Animation speed
- `enableStrokeRemoval` - Mark bad strokes
- `strokeSpeedSensitivity` - Speed influence factor
- `strokePressureSensitivity` - Pressure influence factor

### External Data Files

**graphics.txt** (~30MB)

- Contains reference stroke data for Chinese characters
- Format: Character, stroke count, SVG paths, median points
- Loaded on-demand for stroke analysis

**dictionary.txt** (~2.5MB)

- Chinese-English dictionary
- CSV format with hanzi, pinyin, tone, definition
- Loaded lazily by DictionaryService

### Performance Optimizations

**Drawing:**

- Point sampling: 50ms minimum time interval, 6pt minimum distance
- Separate display points (smooth rendering) vs. analysis points (performance)
- Stroke simplification for analysis

**FSRS:**

- Efficient date calculations
- Cached review statistics
- Incremental parameter updates

**Memory:**

- Lazy loading of reference data
- Dictionary singleton
- Efficient Codable encoding

### Color Scheme

Custom color palette defined in Assets.xcassets:

- **Blue shades**: Primary UI (300, 500, 600, 700, 900)
- **Sand shades**: Backgrounds (100, 200, 300, 500, 700)
- **Neutral shades**: Text/borders (400, 700, 900)
- **Orange**: Accents (200)

### Accessibility

- Dynamic type support
- VoiceOver compatible
- High contrast colors
- Minimum touch targets

---

## Future Enhancements

Based on code structure, potential areas for expansion:

1. **Network Integration** - `NetworkManager.swift` is a placeholder for:
   - Cloud sync
   - Shared decks
   - Analytics

2. **Advanced Analytics** - `BenchmarkModels.swift` suggests:
   - Stroke analysis benchmarking
   - Performance metrics
   - A/B testing different algorithms

3. **Parameter Optimization** - `FSRSOptimizer.swift` enables:
   - Personalized FSRS parameters
   - Machine learning improvements
   - Export/import optimization data

4. **Validation Datasets** - `ValidationDatasetView.swift` for:
   - Testing stroke recognition accuracy
   - Collecting training data
   - Algorithm validation

---

## Development Notes

**Platform:** iOS (SwiftUI)
**Minimum iOS Version:** iOS 15+ (inferred from SwiftUI features)
**Language:** Swift 5+
**Architecture:** MVVM with centralized state management
**Dependencies:** None (pure SwiftUI/Foundation)

**Key Design Decisions:**

- UserDefaults for simplicity (could migrate to CoreData/CloudKit)
- FSRS-6 over traditional SM-2 for better scheduling
- Separate FSRS data per direction for bidirectional learning
- Probabilistic stroke matching over rigid rule-based systems
- ObservableObject pattern for reactive UI updates

---

## License

See `Licenses/` directory for third-party license information.
