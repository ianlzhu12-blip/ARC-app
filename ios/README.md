# ARC Flight Optimizer iPhone App

Native SwiftUI version of the ARC launch-day flight optimizer.

## Open In Xcode

Open:

```text
ios/ARCFlightOptimizer/ARCFlightOptimizer.xcodeproj
```

Choose an iPhone simulator or a connected iPhone, then press Run.

## Included

- SwiftUI tab app optimized for iPhone.
- Local-first storage with `UserDefaults` JSON snapshots.
- Quick flight logging with large field-friendly controls.
- Open-Meteo weather lookup by launch-site location.
- Apple Charts altitude and mass visualizations.
- Explainable ridge-regression altitude prediction.
- Smart recommendations for mass, motor choice, and descent tuning.
- Nationals Mode with countdown and best-two target matching.

## Notes

The app requires iOS 17 or newer because it uses Swift Charts and modern SwiftUI styling. The weather lookup needs network access, but all saved teams, rockets, and flights remain available offline.
