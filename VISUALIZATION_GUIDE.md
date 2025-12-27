# Stroke Visualization After Normalization

## What You'll See

When you press "Check" on a flashcard, you'll now see **two side-by-side boxes** showing the normalized strokes:

```
┌─────────────────┐  ┌─────────────────┐
│  Your Strokes   │  │   Reference     │
│                 │  │                 │
│   (blue lines)  │  │ (green lines +  │
│                 │  │  green dots)    │
└─────────────────┘  └─────────────────┘
```

### Left Box: Your Strokes (Blue)
- Shows your drawn strokes **after normalization**
- Blue lines represent your pen strokes
- All strokes centered in [0,1] square space
- Aspect ratio preserved

### Right Box: Reference (Green)
- Shows reference strokes from `graphics.txt` **after normalization**
- Green lines connect the median points
- Green dots show the actual median points
- Same [0,1] normalized space

## What This Helps You See

### 1. **Normalization is Working**
Both boxes should show strokes in the same coordinate space. If they look wildly different in size or position, normalization has a bug.

### 2. **Aspect Ratio Preservation**
- A vertical stroke (丨) should look vertical in both boxes
- A horizontal stroke (一) should look horizontal in both boxes
- If strokes are stretched or squashed, aspect ratio is broken

### 3. **Alignment Issues**
Both should be centered in their boxes. If one is off to a corner, centering offset is wrong.

### 4. **Stroke Density**
- Your strokes (blue) will have many points (dense lines)
- Reference strokes (green) will have few points (sparse, with visible dots)
- This is normal - reference only has median points

### 5. **Y-Axis Flip Issues**
If your stroke looks upside-down compared to reference, Y-axis needs flipping.

## Example Scenarios

### ✅ Good Normalization
```
Your Strokes:        Reference:
    |                    |
    |                    •
    |                    •
    |                    •
    |                    |
```
Both vertical, centered, same size → normalization working!

### ❌ Aspect Ratio Problem
```
Your Strokes:        Reference:
────────             ────────
```
You drew vertical but it shows horizontal → aspect ratio broken!

### ❌ Y-Axis Flip Problem
```
Your Strokes:        Reference:
    |                    |
    |                    |
    |                    |
   ╱                     ╲
  ╱                       ╲
```
Your stroke goes down-left, reference goes down-right → Y-axis flipped!

### ❌ Centering Problem
```
Your Strokes:        Reference:
|                           |
|                           |
|                           |
```
Your stroke in corner, reference centered → offset calculation wrong!

## Technical Details

### User Strokes (Blue Box)
```swift
NormalizedStrokeView
├─ Takes: result.userStrokes (original coordinates)
├─ Calls: StrokeAnalyzer.normalizeUserStrokes()
├─ Draws: Blue lines connecting all points
└─ Shows: Normalized [0,1] space
```

### Reference Strokes (Green Box)
```swift
ReferenceStrokeView
├─ Takes: result.referenceStrokes (already normalized)
├─ Draws: Green lines connecting median points
├─ Draws: Green dots at each median point
└─ Shows: Same [0,1] space as user strokes
```

## What to Check

### Test 1: Single Horizontal Stroke (一)
1. Draw a horizontal line
2. Press "Check"
3. **Expected**: Both boxes show horizontal lines, centered
4. **If not**: Aspect ratio or normalization broken

### Test 2: Single Vertical Stroke (丨)
1. Draw a vertical line
2. Press "Check"
3. **Expected**: Both boxes show vertical lines, centered
4. **If not**: Aspect ratio or normalization broken

### Test 3: Complex Character (十)
1. Draw a cross (horizontal then vertical)
2. Press "Check"
3. **Expected**: Both boxes show crosses, aligned
4. **Check**: Are the strokes in similar positions?

### Test 4: Off-Center Drawing
1. Draw a stroke in the corner of the canvas
2. Press "Check"
3. **Expected**: Stroke should be centered in the box
4. **If not**: Centering offset calculation wrong

## Debugging with Visualization

### Problem: Strokes Don't Match Well
**Look at boxes:**
- Are they similar shapes? → Good normalization
- Completely different shapes? → Normalization broken
- Similar but rotated? → Possible Y-axis flip
- Similar but different sizes? → Aspect ratio issue

### Problem: High Error Values
**Look at boxes:**
- Strokes look similar? → Error calculation too sensitive
- Strokes look different? → User drew poorly (expected)
- Reference has very few points? → Sparse median data

### Problem: Wrong Stroke Matching
**Look at boxes:**
- User stroke 1 looks like reference stroke 2? → Prior too weak
- Shapes completely different? → Algorithm confused
- Check stroke counts in text output

## Color Coding

- **Blue**: Your strokes (many points, dense)
- **Green**: Reference strokes (few points, sparse)
- **Green dots**: Median points from graphics.txt
- **Gray border**: Bounding box of [0,1] space

## Size Information

Each box is **120x120 pixels**, showing the full [0,1] normalized coordinate space.

Strokes are drawn with:
- User strokes: 2px blue lines
- Reference strokes: 2px green lines
- Median points: 4px green circles

## Next Steps

If you see issues in the visualization:

1. **Shapes don't match** → Check normalization code
2. **Y-axis flipped** → Add Y-flip in normalization
3. **Sizes different** → Check aspect ratio preservation
4. **Off-center** → Check offset calculation
5. **Reference too sparse** → Might need interpolation

The visualization makes it immediately obvious if normalization is working correctly!
