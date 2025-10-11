# StarMind – Offline AI Assistant Specification & Plan

## 1. Overview
- **Platform**: Flutter (Android primary for RuStore; future iOS support)
- **Project Path**: `E:\Projects\StarMind`
- **Theme**: Sci-fi cosmos (dark starfield, nebula gradients, neon-accented tesseract icon)
- **Offline AI Model**: Quantized Phi-3.5 Mini (~1 GB) via TFLite
- **RAG Engine**: FAISS with ~1 000+ embeddings
- **Target Metrics**: App footprint 1.2–1.5 GB, AAB <1.2 GB, response <5 s, accuracy ≥75–80%, offline-first, RuStore compliant

## 2. Architecture

### 2.1 Layering
- **Presentation**: Flutter UI (Riverpod/Bloc for state; custom cosmos theme)
- **Domain**: Use cases for chat, RAG retrieval, calendar, notifications, games
- **Data**:
  - Local DB (sqflite) for chat history, settings, cached embeddings metadata
  - FAISS index stored in app sandbox
  - Secure storage for credentials/tokens
  - Optional remote sync (Firebase Auth + Firestore when online)

### 2.2 Core Modules
1. **Auth & Profile**
   - Email/password (offline stored hashed)
   - Optional Google/Yandex via Firebase Auth (online only)
   - Local user session persistence in `flutter_secure_storage`
2. **AI Engine**
   - TFLite interpreter wrapper for Phi-3.5
   - Prompt builder supporting Russian Q&A domains
   - RAG pipeline (embedding generator → FAISS search → context injection)
   - Online fallback (xAI API) with connectivity checks
3. **Chat Experience**
   - Conversation manager (history, search, filtering, clear)
   - Input modes: text, speech-to-text (speech_to_text package), file ingest (file_picker)
   - Response renderer (streaming UI, offline/online indicators)
4. **Utilities**
   - Calendar (device_calendar) minimal offline agenda
   - Notifications & alarm handlers (flutter_local_notifications, alarm)
   - Mini-games module (Trivia, Guess the Word, Cosmic Story Weaver)
5. **Settings & Monetization**
   - Theme toggles (cosmos/dark/light)
   - App preferences (language, voice input toggle, offline/online mode)
   - RuStore billing placeholder hooks

### 2.3 Data Flow
- User input → Preprocessing → (Optional) Speech transcription → Tokenized request
- RAG: Generate embedding → FAISS nearest neighbors → Assemble context
- Execute TFLite inference → Post-process output → UI render
- If inference confidence low/unsupported → fallback text “Не могу ответить оффлайн :(”
- Online mode: Call xAI API with same prompt; merge response

### 2.4 Storage Strategy
- **Sqflite**: Chat logs, settings, game scores
- **FAISS files**: Embedding index (~200 MB)
- **Assets**: TFLite model (~1 GB), tokenizer files, trivia datasets
- **Cache**: Transient audio/text files under app cache dir
- Ensure total ≤1.5 GB via asset compression & deferred download if needed

## 3. UI / UX Wireframe Notes

### 3.1 Splash & Auth
- **Splash Screen**: Animated nebula gradient, tesseract icon pulsing
- **Login**: Email/password fields, “Войти оффлайн” button, “Google / Yandex” buttons (disabled offline), info tooltip re: local storage
- **Register**: Minimal form (email, password, confirm), offline hashed storage

### 3.2 Main Chat Screen
- Background: dark cosmos with subtle parallax stars
- Top: Greeting overlay `“Привет, что обсудим сегодня? :)”` semi-transparent
- Center: Chat bubbles (user right-aligned neon blue, assistant left purple/white)
- Bottom bar: 
  - Text field with placeholder “Введите вопрос…”
  - Icon buttons: microphone, attach file, send
  - Online/offline indicator badge
- Floating action: Quick actions (Trivia, Cosmic Story Weaver, Calendar)

### 3.3 History Panel
- Accessible via drawer/tab
- List with timestamps, preview text
- Search bar + filter chips (daily, history, translation, etc.)
- Clear history button with confirm dialog

### 3.4 Settings Screen
- Theme selection cards (cosmos/dark/light)
- Toggles: voice input default, notifications, calendar sync
- Account section: manage logins, logout
- Monetization placeholder tile (“Premium stories – coming soon”)

### 3.5 Utilities
- **Calendar View**: Monthly view with add reminder modal
- **Notifications/Alarm UI**: Simple lists (title, time, toggle)
- **Games**:
  - Trivia: card with question + multiple choice
  - Guess the Word: word length indicator, input field, feedback
- **Cosmic Story Weaver**: Text area showing generated story, save/share buttons

## 4. AI & RAG Integration Steps

### 4.1 Model Preparation
1. Download Phi-3.5 Mini quantized TFLite (~1 GB)
2. Verify license compliance for offline redistribution
3. Store under `assets/models/phi35mini_quant.tflite` with `pubspec.yaml` asset mapping

### 4.2 TensorFlow Lite Integration
- Add `tflite_flutter` + `tflite_flutter_helper`
- Initialize interpreter with NNAPI / GPU delegate fallback
- Implement streaming token generation to keep latency <5 s
- Optimize: set thread count per device core & reduce precision if needed

### 4.3 Embedding + FAISS
- Use lightweight embedding model (e.g., MiniLM converted to TFLite)
- Generate embeddings for curated knowledge base (~1000 docs)
- Bundle FAISS index (`assets/faiss/index.faiss`)
- Integrate `faiss` via FFI wrapper (build Android .so; plan iOS port with `faiss-metal` or on-device alternative)
- Pipeline: user query embedding → FAISS search → retrieve top-k passages → context chunking

### 4.4 RAG Context Management
- Use sliding window summarizer to keep prompt within model context limit
- Score retrieved passages; drop low confidence
- Build final prompt template (system + retrieved + user question)
- Add guard for unsupported categories → offline fallback message

### 4.5 Online Fallback (xAI API)
- Connectivity check via `connectivity_plus`
- Securely store API key (if provided) in secure storage
- Rate limit to preserve privacy; explicit toggle in settings

## 5. Feature Implementation Notes

### 5.1 Voice Input
- Package: `speech_to_text`
- Russian locale default
- Handle permission prompts gracefully
- Convert transcription → chat input field with edit before send

### 5.2 File Attachment
- Package: `file_picker` (restrict to text, PDF, DOC)
- Extract text via `flutter_archive`/`pdf_text`/`docx` parser; feed into RAG context or display as conversation attachment

### 5.3 Calendar & Notifications
- Request calendar/notification permissions on demand
- Use `device_calendar` for local events (no cloud sync)
- `flutter_local_notifications` + `alarm` for reminders/alarms; ensure background execution compliance

### 5.4 Mini-Games
- Trivia dataset stored locally (JSON); categories: history/science/sport
- Guess the Word uses offline word list tailored to Russian language
- Cosmic Story Weaver reuses AI engine with themed prompt instructions

### 5.5 Monetization Placeholder
- Add interface for RuStore Billing SDK integration hook (no active purchases)
- UI placeholder disabled by default; compliance notes for future release

## 6. Security & Compliance

- Store credentials encrypted (`flutter_secure_storage` + salted hashing for offline auth)
- No personal data transmission offline; online sync optional and transparent
- Permissions: request minimal set with clear rationale dialogs
- Prepare RuStore compliance checklist (content rating, data safety form)
- Localization primarily Russian; ensure fonts support Cyrillic
- Logging: local debug logs only; scrub sensitive data

## 7. Build & Deployment

### 7.1 Android (RuStore)
- Target API Level per RuStore requirement (≥34)
- Build flavors: `offline` (default), `online` (includes xAI fallback)
- Use `gradle` split by ABI to reduce AAB <1.2 GB (split model if necessary)
- Pre-launch testing on mid-tier devices for performance validation

### 7.2 iOS (Future)
- Ensure packages support iOS (check FAISS alternative)
- Plan for `xcframework` embedding of FAISS or switch to Apple Core ML index
- IPA generation instructions for later phase (Fastlane optional)

### 7.3 Continuous Integration
- Local scripts: `flutter analyze`, `flutter test`, `flutter build aab`
- Plan CI pipeline (GitHub Actions/Azure DevOps) once repo established

## 8. Phase Plan

### Phase 1 – UI/UX (Weeks 1–2)
- Finalize cosmos theme, wireframes, design tokens
- Implement Splash, Auth, Main Chat, History, Settings scaffolding
- Integrate base navigation/state management
- Placeholder data for chat/messages

### Phase 2 – AI Integration (Weeks 3–4)
- Embed TFLite Phi-3.5 model + inference service
- Build embedding pipeline & FAISS index integration
- Implement RAG workflow & offline fallback messaging
- Optimize performance (profiling, delegate tuning)

### Phase 3 – Auth & Core Features (Weeks 5–6)
- Complete email/password auth with secure storage
- Implement Google/Yandex login via Firebase (online task gating)
- Connect voice input, file attachments, offline calendar, notifications, alarm
- Develop Trivia, Guess the Word, Cosmic Story Weaver modules
- Add monetization placeholder

### Phase 4 – Testing & Offline Hardening (Weeks 7–8)
- Unit/widget tests for chat, AI service, utilities
- Offline stress tests (no connectivity scenarios)
- Localization QA (Russian prompts, error messages)
- Profile app size; optimize assets, enable ABI splits
- Prepare RuStore submission package; draft iOS port checklist

## 9. Risks & Mitigations
- **Model Size Constraints**: Use optional download or split by ABI; compress assets
- **FAISS iOS Port**: Research metal support early; keep abstraction for swap
- **Voice Recognition Accuracy**: Provide manual edit before send; fallback to text
- **Offline Storage Limits**: Monitor device storage; add warning when space low
- **Compliance**: Regular check against RuStore privacy/security requirements

## 10. Deliverables
- Complete Flutter project at `E:\Projects\StarMind`
- Markdown documentation of architecture & integration steps (internal, not for distribution)
- Build scripts for AAB (Android) and project configuration for future IPA
- Test reports demonstrating offline functionality & performance metrics

---
