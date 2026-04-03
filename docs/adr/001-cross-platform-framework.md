# ADR-001: Cross-Platform Mobile Framework

**Date:** 2026-04  
**Status:** Accepted  
**Deciders:** Product Lead, Jarvis (AI Copilot)

---

## Context

ecopal starts as an Android app but must not foreclose an iOS release. The MVP requires:
- Real-time camera frame capture and processing
- On-device TFLite model inference
- Custom overlay rendering (bounding boxes) on top of the camera preview
- Multi-language support

The framework choice will determine the entire mobile development stack.

---

## Options Considered

### Option A: Flutter
- AOT-compiled Dart; no JS bridge
- `camera` plugin supports raw YUV frame access for ML pipelines
- `tflite_flutter` uses Dart FFI → native; supports GPU and NNAPI delegates
- `CustomPainter` enables pixel-accurate overlay rendering on camera preview
- Single codebase for Android and iOS
- Smaller ecosystem than React Native; Dart is a less common language

### Option B: React Native
- `react-native-vision-camera` supports frame processors (JSI-based, fast)
- `react-native-fast-tflite` supports GPU delegates via C++ JSI bridge
- Large JS/TypeScript ecosystem
- Slight overhead from JS bridge even with Nitro Modules; more configuration for ML pipelines
- Strong community; more hiring pool

### Option C: Native Android (Kotlin) + Native iOS (Swift) — separate codebases
- Maximum performance and access to platform APIs
- Double the development effort; no code sharing
- Ruled out: cost and time prohibitive for a startup-phase product

---

## Decision

**Flutter** is selected.

### Rationale
1. The camera → frame → TFLite → overlay pipeline is a first-class pattern in Flutter with minimal configuration.
2. `CustomPainter` renders overlays directly on the camera preview widget with no additional libraries.
3. AOT compilation eliminates JS bridge latency, which matters for real-time ML inference feedback.
4. Single codebase from day one means the iOS version costs almost nothing once Android is ready.
5. Flutter's performance advantage is meaningful specifically for the continuous frame-processing use case.

---

## Consequences

- Development language is **Dart**.
- Flutter version pinned in `pubspec.yaml`; managed via `fvm` (Flutter Version Management).
- Key packages: `camera`, `tflite_flutter`, `sqflite`, `http`, `flutter_localizations`.
- Android minimum SDK: **21** (Android 5.0) to cover 99%+ of active devices.
- iOS minimum deployment target: **13.0** (when iOS build is added).
