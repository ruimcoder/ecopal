# ADR-002: ML Inference Strategy for Fish Species Identification

**Date:** 2026-04  
**Status:** Accepted  
**Deciders:** Product Lead, Jarvis (AI Copilot)

---

## Context

The Fish Scanner skill must identify fish species from a live camera feed pointed at a supermarket fish counter. The challenge is significant:

- Fish are **dead, potentially gutted, on ice, under artificial lighting** — very different from live underwater photos that most public models train on.
- The app must be fast enough to feel real-time (<500ms overlay latency).
- Network may not always be available.
- Camera images must not be stored or unnecessarily transmitted (privacy).

---

## Options Considered

### Option A: Cloud-only (send every frame to a cloud ML API)
- Highest accuracy potential
- Requires constant network; high latency (500ms–2s round trip)
- Camera frames transmitted to third party — privacy concern
- Ongoing API cost at scale
- **Rejected**: latency and privacy requirements not met

### Option B: On-device only (TFLite bundled in APK)
- Fast (~50–150ms), works offline, fully private
- Limited to species in the bundled model (~50–200 common commercial fish)
- Model staleness requires app update
- **Accepted for primary path**

### Option C: iNaturalist `score_image` endpoint as cloud fallback
- `POST https://api.inaturalist.org/v1/computervision/score_image`
- Covers 30,000+ species; free; no API key required (currently)
- Undocumented/unofficial — may change without notice
- 500ms–2s latency; requires network
- **Accepted for fallback path only**

### Option D: Azure Custom Vision / AWS Rekognition Custom Labels
- High accuracy with custom training data
- Vendor lock-in; per-inference cost
- Requires cloud connectivity
- **Not selected for MVP**; revisit if on-device accuracy insufficient at scale

---

## Decision

**Two-stage hybrid inference:**

```
Camera frame
    │
    ▼
On-device TFLite model  ──── confidence ≥ threshold ──► species identified
    │
    └── confidence < threshold AND network available
            │
            ▼
        iNaturalist score_image API  ──► species identified (or "unknown")
```

### Confidence Threshold
Default: **0.75**. Species below threshold trigger cloud fallback. Configurable via remote config (future).

### On-Device Model

**Base model:** Fine-tuned from [Fishial.ai](https://fishial.ai) open model or EfficientNet-V2 backbone.  
**Training data priority:**
1. Fishial.ai curated dataset (175k images, most realistic for non-live fish)
2. LILA Community Fish Detection dataset (1.9M frames)
3. Self-collected supermarket fish photos (target: 100–200 per common species)

**Target species for v1 model:** Top 80 commercially traded fish species in EU/UK/US markets (Atlantic Salmon, Cod, Tuna species, Sea Bass, Hake, Mackerel, Herring, Sardine, Swordfish, etc.)

**Format:** TensorFlow Lite FlatBuffer (`.tflite`)  
**Delegates:** GPU delegate (Android, via `tflite_flutter`) → NNAPI delegate → CPU fallback  
**Input:** 224×224 RGB  
**Output:** Softmax probabilities over N species classes

### Model Update Strategy
- Model bundled in initial APK.
- Future: remote model delivery via Firebase ML or direct CDN download — allows model updates without full app release. Introduce when v2 model is ready.

---

## Consequences

- A labelled training dataset must be assembled before v1 model can be trained.
- iNaturalist API dependency is not guaranteed stable; monitor for ToS changes.
- Frame rate for inference: **5 fps** (configurable). Full 30fps preview continues unaffected.
- ML inference runs in a **Dart isolate** to avoid blocking the UI thread.
- Privacy: frames are only sent to iNaturalist when the user's confidence threshold is not met AND the user has accepted the privacy policy (explicit opt-in for cloud fallback).
