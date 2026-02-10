# Lottie Animations

This directory contains Lottie animation files for HavenKeep.

## Required Animations

Download these free animations from LottieFiles (https://lottiefiles.com/):

1. **protection_shield.json** - For "Your warranties are protected" preview screen
   - Search: "shield protection" or "security shield"
   - Recommended: Simple, modern shield animation with checkmark

2. **search_scan.json** - For "Find items instantly" preview screen
   - Search: "barcode scan" or "search documents"
   - Recommended: Scanning/search animation

3. **clock_reminder.json** - For "Never miss expiration" preview screen
   - Search: "notification bell" or "alarm clock"
   - Recommended: Bell or clock with alert

4. **confetti_celebration.json** - For item added success
   - Search: "confetti" or "celebration"
   - Recommended: Colorful confetti burst

5. **success_checkmark.json** - For general success states
   - Search: "success checkmark" or "done"
   - Recommended: Animated checkmark with circle

## Usage

```dart
import 'package:lottie/lottie.dart';

Lottie.asset(
  'assets/lottie/protection_shield.json',
  width: 200,
  height: 200,
)
```

## License

Ensure all downloaded animations have appropriate licenses for commercial use.
Most LottieFiles animations are free for commercial use, but always verify.
