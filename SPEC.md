# Nexus – Offline AI Assistant Specification & Plan

## 1. Overview
- **Platform**: Flutter (Android for RuStore; iOS support)
- **Project Path**: `E:\Projects\Nexus`
- **Theme**: Sci-fi cosmos (dark starfield, nebula gradients, neon-accented tesseract icon)
- **Offline AI Model**: Phi-3 Mini 4k Instruct (INT4 quantized, ~2.3 GB) via ONNX Runtime GenAI
- **RAG Engine**: Planned (currently stub implementation)
- **Target Metrics**: Response <5 s, accuracy ≥75–80%, offline-first, RuStore compliant

## 2. Architecture

### 2.1 Layering
- **Presentation**: Flutter UI (Riverpod for state; custom cosmos theme)
- **Domain**: Use cases for chat, RAG retrieval, calendar, notifications, games
- **Data**:
  - Local DB (sqflite) for chat history, settings
  - Secure storage for credentials/tokens
  - Optional remote sync (Firebase Auth when online)
- **Native Bridges**: MethodChannel for ONNX Runtime inference (Kotlin/Swift)

### 2.2 Core Modules
1. **Auth & Profile**
   - Email/password (offline stored hashed)
   - Optional Google/Yandex via Firebase Auth (online only)
   - Local user session persistence in `flutter_secure_storage`
2. **AI Engine**
   - ONNX Runtime GenAI wrapper via native MethodChannel
   - Phi-3 Mini 4k Instruct model (INT4-RTN-block-32)
   - Prompt builder supporting Russian Q&A domains
   - RAG service (stub, planned for future)
   - Online fallback (xAI API) with connectivity checks
3. **Chat Experience**
   - Conversation manager (history, search, filtering, clear)
   - Input modes: text, speech-to-text (speech_to_text package), file ingest (file_picker)
   - Response renderer with offline/online indicators
4. **Utilities**
   - Calendar (device_calendar) minimal offline agenda
   - Notifications & alarm handlers (flutter_local_notifications, alarm)
   - Mini-games module (Trivia, Guess the Word, Cosmic Story Weaver)
5. **Settings & Monetization**
   - Theme toggles (cosmos/dark/light)
   - App preferences (language, voice input toggle, offline/online mode)
   - RuStore billing placeholder hooks

### 2.3 Data Flow
- User input → Preprocessing → (Optional) Speech transcription
- RAG: Query → RagService (stub) → Context list
- Build prompt with system instructions + context + user question
- Native bridge → ONNX Runtime GenAI inference → Response sanitization → UI render
- If inference fails → fallback text or online API call
- Online mode: Call xAI API with same prompt

### 2.4 Storage Strategy
- **Sqflite**: Chat logs, settings, game scores
- **Application Support Dir**: Downloaded ONNX model (~2.3 GB)
- **Assets**: Tokenizer files, config JSONs (~few KB bundled)
- **Cache**: Transient audio/text files under app cache dir
- Model downloaded on first launch from HuggingFace with SHA256 verification

## 3. UI / UX Wireframe Notes

### 3.1 Splash & Auth
- **Splash Screen**: Animated nebula gradient, tesseract icon pulsing, model download progress
- **Login**: Email/password fields, "Войти оффлайн" button, "Google / Yandex" buttons (disabled offline)
- **Register**: Minimal form (email, password, confirm), offline hashed storage

### 3.2 Main Chat Screen
- Background: dark cosmos with subtle parallax stars
- Top: Greeting overlay `"Привет, что обсудим сегодня? :)"` semi-transparent
- Center: Chat bubbles (user right-aligned neon blue, assistant left purple/white)
- Bottom bar: 
  - Text field with placeholder "Введите вопрос…"
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
- Monetization placeholder tile ("Premium stories – coming soon")

### 3.5 Utilities
- **Calendar View**: Monthly view with add reminder modal
- **Notifications/Alarm UI**: Simple lists (title, time, toggle)
- **Games**:
  - Trivia: card with question + multiple choice
  - Guess the Word: word length indicator, input field, feedback
- **Cosmic Story Weaver**: Text area showing generated story, save/share buttons

## 4. AI & ONNX Runtime Integration

### 4.1 Model Details
- **Model**: `microsoft/Phi-3-mini-4k-instruct-onnx`
- **Variant**: `cpu-int4-rtn-block-32-acc-level-4`
- **Files**:
  - `phi3-mini-4k-instruct-cpu-int4-rtn-block-32-acc-level-4.onnx` (~385 MB)
  - `phi3-mini-4k-instruct-cpu-int4-rtn-block-32-acc-level-4.onnx.data` (~1.9 GB)
- **Source**: HuggingFace (downloaded on first launch)
- **Verification**: SHA256 checksums for integrity

### 4.2 ONNX Runtime Integration

#### Android (Kotlin)
```kotlin
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
    implementation(files("libs/onnxruntime-genai-android-0.11.2.aar"))
}
```
- Native bridge via `MethodChannel("nexus/phi")`
- Methods: `loadModel`, `generate`
- GeneratorParams: max_length=192, temperature=0.4, top_p=0.8, repetition_penalty=1.1

#### iOS (Swift)
```ruby
pod 'onnxruntime-mobile-c', '~> 1.18.0'
pod 'onnxruntime-genai-c', '~> 1.18.0'
```
- Native bridge via same MethodChannel
- Minimum iOS 13.0

### 4.3 Model Download Strategy
- **PhiModelDownloader** service handles:
  - Chunked parallel downloads (6 concurrent, 50MB chunks)
  - Resume support with SHA256 validation
  - Progress streaming to UI
  - Retry logic (3 attempts with backoff)
- **Bundled assets** (tokenizer configs) copied from Flutter assets

### 4.4 Prompt Template
```
Ты — русскоязычный ассистент Nexus. Отвечай строго на русском языке, 
дружелюбно и по существу. Не задавай встречных вопросов без необходимости 
и не выдумывай новые темы. Если данных недостаточно, честно сообщи об этом. 
Формат ответа — максимум 2-3 предложения.

[Контекст]
{contexts or "нет дополнительного контекста"}

[Вопрос]
{user_prompt}

[Ответ]
```

### 4.5 RAG Integration (Planned)
- `RagService` currently returns empty context list
- Future: embedding model + vector search integration
- Context injection into prompt template ready

### 4.6 Online Fallback (xAI API)
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
- Extract text and feed into RAG context or display as conversation attachment

### 5.3 Calendar & Notifications
- Request calendar/notification permissions on demand
- Use `device_calendar` for local events (no cloud sync)
- `flutter_local_notifications` + `alarm` for reminders/alarms

### 5.4 Mini-Games
- Trivia dataset stored locally (JSON); categories: history/science/sport
- Guess the Word uses offline word list tailored to Russian language
- Cosmic Story Weaver reuses AI engine with themed prompt instructions

### 5.5 Monetization Placeholder
- Add interface for RuStore Billing SDK integration hook (no active purchases)
- UI placeholder disabled by default

## 6. Security & Compliance

- Store credentials encrypted (`flutter_secure_storage` + salted hashing for offline auth)
- No personal data transmission offline; online sync optional and transparent
- Permissions: request minimal set with clear rationale dialogs
- Prepare RuStore compliance checklist (content rating, data safety form)
- Localization primarily Russian; ensure fonts support Cyrillic
- Logging: local debug logs only; scrub sensitive data

## 7. Build & Deployment

### 7.1 Android (RuStore)
- **minSdk**: 26
- **targetSdk**: 34
- Build flavors: `offline` (default), `online` (includes xAI fallback)
- Use `gradle` split by ABI if needed
- Pre-launch testing on mid-tier devices for performance validation

### 7.2 iOS
- **Minimum iOS**: 13.0
- CocoaPods for ONNX Runtime dependencies
- Native Swift bridge in `AppDelegate.swift`

### 7.3 Continuous Integration
- Local scripts: `flutter analyze`, `flutter test`, `flutter build aab`
- Plan CI pipeline (GitHub Actions/Azure DevOps) once repo established

## 8. Project Structure

```
lib/
├── main.dart
├── core/
│   └── tflite_helper.dart          # Deprecated, kept for reference (PhiOnnxAssets)
└── src/
    ├── app.dart
    ├── core/
    │   ├── bootstrap/app_bootstrap.dart
    │   ├── routing/app_router.dart
    │   └── theme/
    │       ├── app_theme.dart
    │       └── theme_controller.dart
    ├── features/
    │   ├── auth/presentation/login_screen.dart
    │   ├── calendar/presentation/calendar_screen.dart
    │   ├── chat/
    │   │   ├── application/chat_controller.dart
    │   │   ├── data/chat_repository.dart
    │   │   ├── domain/chat_message.dart
    │   │   └── presentation/
    │   │       ├── chat_shell.dart
    │   │       └── widgets/message_bubble.dart
    │   ├── games/presentation/game_screens.dart
    │   ├── reminders/presentation/reminder_screen.dart
    │   ├── settings/application/settings_controller.dart
    │   └── splash/presentation/splash_screen.dart
    └── services/
        ├── ai/
        │   ├── online_ai_service.dart
        │   ├── phi_model_downloader.dart
        │   ├── phi_service.dart
        │   └── rag_service.dart
        ├── alarm/alarm_service.dart
        ├── calendar/calendar_service.dart
        ├── connectivity/connectivity_service.dart
        ├── files/file_ingest_service.dart
        ├── notifications/notification_service.dart
        └── speech/speech_service.dart

android/app/
├── build.gradle.kts                 # ONNX Runtime dependencies
├── libs/onnxruntime-genai-android-0.11.2.aar
└── src/main/kotlin/.../MainActivity.kt   # PhiOnnxBridge

ios/
├── Podfile                          # onnxruntime-mobile-c, onnxruntime-genai-c
└── Runner/
    ├── AppDelegate.swift            # Native ONNX bridge
    └── Runner-Bridging-Header.h     # ort_genai_c.h import
```

## 9. Phase Plan

### Phase 1 – UI/UX ✅
- Cosmos theme, wireframes, design tokens
- Splash, Auth, Main Chat, History, Settings scaffolding
- Base navigation/state management (Riverpod + GoRouter)

### Phase 2 – AI Integration ✅
- ONNX Runtime GenAI integration (Android + iOS)
- Model download with progress tracking
- Native bridges via MethodChannel
- Prompt template and response sanitization

### Phase 3 – Auth & Core Features (In Progress)
- Complete email/password auth with secure storage
- Implement Google/Yandex login via Firebase
- Voice input, file attachments, calendar, notifications
- Mini-games modules

### Phase 4 – Testing & Polish
- Unit/widget tests for chat, AI service, utilities
- Offline stress tests
- Localization QA (Russian prompts, error messages)
- RuStore submission preparation

## 10. Risks & Mitigations
- **Model Download Size**: Chunked parallel download with resume; progress UI
- **Device Compatibility**: INT4 quantization for CPU; test on mid-tier devices
- **Voice Recognition Accuracy**: Provide manual edit before send; fallback to text
- **Offline Storage Limits**: Monitor device storage; add warning when space low
- **Compliance**: Regular check against RuStore privacy/security requirements

## 11. Dependencies

### Flutter Packages
```yaml
dependencies:
  flutter_riverpod: ^2.5.1
  hooks_riverpod: ^2.5.1
  go_router: ^14.2.0
  firebase_core: ^3.4.1
  firebase_auth: ^5.1.4
  google_sign_in: ^6.2.1
  flutter_secure_storage: ^9.2.2
  dio: ^5.4.3+1
  connectivity_plus: ^6.0.3
  speech_to_text: ^7.3.0
  file_picker: ^8.1.2
  device_calendar: ^4.3.1
  flutter_local_notifications: ^17.1.2
  alarm: ^3.0.5
  timezone: ^0.9.2
  sqflite: ^2.3.3
  path_provider: ^2.1.3
  crypto: ^3.0.3
  intl: ^0.19.0
  uuid: ^4.4.0
```

### Native Dependencies
- **Android**: `onnxruntime-android:1.18.0`, `onnxruntime-genai-android-0.11.2.aar`
- **iOS**: `onnxruntime-mobile-c ~1.18.0`, `onnxruntime-genai-c ~1.18.0`

---
