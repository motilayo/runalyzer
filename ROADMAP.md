# Runalyst Roadmap

## V3 — Future Features

### Multi-Turn Coaching Sessions
- **Status:** Proposed
- **Complexity:** Medium-High
- **Description:** Persist `LanguageModelSession` across follow-up questions so users can ask their coach clarifying questions (e.g., "Why was my HR so high today?") without re-injecting all metric data.
- **Key Challenges:**
  - Session lifetime management (ephemeral per view vs. durable)
  - Apple's 4,096-token ceiling applies to entire conversation window — need truncation strategy after 3–4 turns
  - Structured (`@Generable`) → unstructured (`String`) transition for follow-up responses
  - Topic guardrails to prevent hallucinated medical/nutrition advice
- **Prerequisite:** Stable V2 release + real user feedback on what follow-up questions people actually ask

### Prompt A/B Testing
- **Status:** Proposed
- **Complexity:** Medium
- **Description:** Instrument prompt variants and measure coaching quality against user satisfaction signals (e.g., drill completion rates, thumbs-up/down on insights).
- **Key Challenges:**
  - Requires a lightweight telemetry/analytics pipeline
  - Need sufficient TestFlight/production volume for statistical significance
  - Privacy-preserving design (no raw biometric data leaves the device)

### Cloud Model Fallback
- **Status:** Proposed
- **Complexity:** High
- **Description:** For complex edge cases where the on-device model produces low-quality output, optionally route to a cloud model (e.g., GPT-4, Claude) for higher-fidelity coaching.
- **Key Challenges:**
  - Contradicts Runalyst's offline-first, privacy-first philosophy
  - Requires explicit user opt-in and clear data handling disclosures
  - Latency and cost management
  - May not be necessary if on-device models continue improving

### Apple Adaptation / Fine-Tuning
- **Status:** Watching
- **Complexity:** Unknown (depends on Apple API availability)
- **Description:** If Apple exposes model adaptation or fine-tuning APIs for on-device Foundation Models, use accumulated `TrainingCorrection` data to personalize the coaching model per user.
