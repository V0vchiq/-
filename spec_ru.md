# Nexus — Офлайн ИИ-ассистент

## 1. Обзор

- **Платформа**: Flutter (Android для RuStore/Google Play; перспектива iOS)
- **Путь проекта**: `E:\Projects\Nexus`
- **Тема интерфейса**: научно-фантастический космос (звёздный фон, анимированные падающие звёзды, нейросетевая заставка)
- **Движок инференса**: llama.cpp через JNI-мост
- **Формат моделей**: GGUF (квантованные модели Q4_K_M, Q5_K_M, Q6_K, Q8_0)
- **Онлайн-режим**: DeepSeek API (V3.2)
- **Целевые метрики**: 
  - Скорость генерации: 5–12 токенов/сек на устройствах среднего сегмента
  - Поддержка устройств с 4–12 ГБ ОЗУ
  - Работа полностью офлайн

## 2. Архитектура

### 2.1 Слоистая структура (Clean Architecture)

```
lib/
├── main.dart
└── src/
    ├── app.dart
    ├── core/
    │   ├── bootstrap/app_bootstrap.dart
    │   ├── routing/app_router.dart
    │   └── theme/
    │       ├── app_theme.dart
    │       └── theme_controller.dart
    ├── features/
    │   ├── chat/
    │   │   ├── application/chat_controller.dart
    │   │   ├── data/chat_repository.dart
    │   │   ├── domain/
    │   │   │   ├── chat_message.dart
    │   │   │   └── chat_session.dart
    │   │   └── presentation/
    │   │       ├── chat_shell.dart
    │   │       ├── screens/
    │   │       └── widgets/
    │   ├── settings/application/settings_controller.dart
    │   └── splash/presentation/splash_screen.dart
    ├── services/
    │   ├── ai/
    │   │   ├── model_service.dart
    │   │   ├── online_ai_service.dart
    │   │   └── phi_service.dart
    │   ├── connectivity/connectivity_service.dart
    │   └── files/file_ingest_service.dart
    └── utils/
```

### 2.2 Ключевые компоненты

| Компонент | Технология | Назначение |
|-----------|------------|------------|
| Фреймворк | Flutter (Dart) | Кроссплатформенный UI |
| Движок инференса | llama.cpp | Локальный запуск LLM |
| Формат моделей | GGUF | Квантованные модели |
| Нативный мост | JNI (C++/Kotlin) | Связь Flutter ↔ llama.cpp |
| Онлайн-режим | DeepSeek API | Резервный облачный режим |
| State management | Riverpod | Управление состоянием |
| Навигация | go_router | Декларативная маршрутизация |
| База данных | SQLite (sqflite) | История чатов и сессий |
| Хранилище моделей | Selectel S3 | Облачное хранение GGUF-файлов |

### 2.3 Нативный мост llama.cpp

```
Flutter (PhiService)
    ↓ MethodChannel "nexus/llama"
    ↓ EventChannel "nexus/llama/stream"
Kotlin (MainActivity → LlamaBridge)
    ↓ JNI
C++ (llama.cpp)
```

**Нативные библиотеки** (`android/app/src/main/jniLibs/arm64-v8a/`):
- `libggml-base.so` — базовые тензорные операции
- `libggml-cpu.so` — оптимизации для ARM (NEON)
- `libggml.so` — интерфейс GGML
- `libllama.so` — основная библиотека инференса

**Компилируется при сборке** (`android/app/src/main/cpp/`):
- `libllama-android.so` — JNI-обёртка (из `llama_jni.cpp`)

### 2.4 Потоки данных

1. **Офлайн-режим**:
   - Ввод пользователя → ChatController → PhiService
   - PhiService → MethodChannel → LlamaBridge → llama.cpp
   - Потоковый вывод токенов через EventChannel → UI

2. **Онлайн-режим**:
   - Ввод пользователя → ChatController → OnlineAiService
   - HTTP POST к DeepSeek API (SSE streaming)
   - Потоковый вывод токенов → UI

## 3. Каталог моделей

### 3.1 Офлайн-модели

| ID | Модель | Параметры | Размер | Квантование | Описание |
|----|--------|-----------|--------|-------------|----------|
| `llama32-1b-q8` | Llama 3.2 1B | 1B | 1.3 ГБ | Q8_0 | Быстрые ответы на простые вопросы |
| `qwen25-coder-15b` | Qwen 2.5 Coder 1.5B | 1.5B | 1.3 ГБ | Q6_K | Простой код: скрипты, функции |
| `gemma2-2b-q5km` | Gemma 2 2B | 2B | 1.9 ГБ | Q5_K_M | Тексты, переводы, диалоги |
| `ministral3-3b-q5km` | Ministral 3 3B | 3B | 2.1 ГБ | Q5_K_M | Анализ текста, понимание контекста |
| `phi35-mini-q4km` | Phi 3.5 Mini | 3.8B | 2.2 ГБ | Q4_K_M | Логические задачи, математика |
| `llama32-3b-q5km` | Llama 3.2 3B | 3B | 2.5 ГБ | Q5_K_M | Диалоги, советы, объяснения |
| `deepseek-coder-67b` | DeepSeek Coder | 6.7B | 4.0 ГБ | Q4_K_M | Профессиональный код |
| `llama31-8b-q4km` | Llama 3.1 8B | 8B | 4.9 ГБ | Q4_K_M | Сложные вопросы, анализ |
| `saiga-yandexgpt-8b` | Saiga YandexGPT | 8B | 5.0 ГБ | Q4_K_M | Лучшая для русского языка |

### 3.2 Онлайн-модель

| ID | Модель | Описание |
|----|--------|----------|
| `deepseek` | DeepSeek V3.2 | Сложные задачи, проверка фактов, развёрнутые ответы |

### 3.3 Хранение моделей

- **Источник**: Selectel S3 (Россия)
- **Локальный путь**: `filesDir/models/{modelId}.gguf`
- **Загрузка**: Foreground Service с прогрессом и возобновлением

## 4. UI/UX

### 4.1 Экран заставки (Splash)

- Анимированная нейронная сеть (18–25 нейронов с рандомными связями)
- Адаптивная длительность: расширенная при первом запуске, сокращённая при последующих
- Градиентный космический фон

### 4.2 Главный экран чата

- **Фон**: анимированные падающие звёзды (до 8 одновременно)
- **Верхняя панель**: название модели (кликабельно → выбор модели), кнопки очистки и настроек
- **Центр**: пузыри сообщений с потоковым выводом
- **Нижняя панель**: поле ввода, кнопки прикрепления файла и отправки
- **Боковая панель**: история сессий с автогенерируемыми заголовками

### 4.3 Экран выбора модели

- Информация об устройстве (RAM, хранилище)
- Предупреждение о совместимости
- Категории: лёгкие, средние, тяжёлые, онлайн
- Статус каждой модели: загружена / не загружена / загружается
- Действия: выбрать, загрузить, удалить

### 4.4 Настройки

- Переключатель темы (светлая/тёмная)

## 5. Функциональность

### 5.1 Генерация ответов

- **Потоковый вывод**: токены отображаются по мере генерации (throttle 50 мс)
- **История диалога**: 2 сообщения для офлайн, 5 для онлайн
- **Автоматическая остановка**: по стоп-токенам модели
- **Отмена генерации**: по нажатию пользователя

### 5.2 Управление сессиями

- Создание новых чатов
- Переключение между сессиями
- Удаление сессий
- Очистка текущего чата
- Автоматическая генерация заголовков сессий

### 5.3 Прикрепление файлов

**Поддерживаемые форматы**:
- Документы: txt, md, log
- Код: dart, py, java, kt, swift, js, c, cpp, h
- Веб: html, css
- Данные: json, csv, xml, yml, yaml
- Конфигурации: toml, ini, conf

### 5.4 Загрузка моделей

- Foreground Service для фоновой загрузки
- Отображение прогресса в системном уведомлении
- Возобновление при обрыве соединения
- Повторные попытки с экспоненциальной задержкой

## 6. Формат промптов

### 6.1 Формат для моделей (Gemma-style)

```
<start_of_turn>user
{предыдущее сообщение пользователя}<end_of_turn>
<start_of_turn>model
{предыдущий ответ модели}<end_of_turn>
<start_of_turn>user
{текущий вопрос}<end_of_turn>
<start_of_turn>model
```

### 6.2 Стоп-токены

```
<end_of_turn>, <|eot_id|>, <|im_end|>, <|end|>, <|endoftext|>,
</s>, [INST], <start_of_turn>, <|start_header_id|>, <|im_start|>,
<|user|>, Пользователь:, Ты — русскоязычный
```

## 7. Безопасность

- API-ключ DeepSeek хранится в `flutter_secure_storage` (AES-256)
- Офлайн-режим: данные не покидают устройство
- Все модели проходят проверку на безопасные ответы

## 8. Технические требования

### 8.1 Android

- **minSdk**: 26 (Android 8.0)
- **targetSdk**: 34 (Android 14)
- **Архитектура**: ARM64-v8a
- **RAM**: 4–12 ГБ (в зависимости от модели)

### 8.2 Разрешения

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

## 9. Зависимости

### 9.1 Flutter-пакеты

```yaml
dependencies:
  flutter_riverpod: ^2.5.1
  hooks_riverpod: ^2.5.1
  go_router: ^14.2.0
  flutter_secure_storage: ^9.2.2
  dio: ^5.4.3+1
  connectivity_plus: ^6.0.3
  file_picker: ^8.1.2
  sqflite: ^2.3.3
  path_provider: ^2.1.3
  path: ^1.9.0
  shared_preferences: ^2.3.1
  crypto: ^3.0.3
  intl: ^0.20.2
  uuid: ^4.4.0
  json_annotation: ^4.9.0
  package_info_plus: ^8.1.0
  url_launcher: ^6.3.0
```

### 9.2 Нативные библиотеки

- llama.cpp (ggml-base, ggml-cpu, ggml, llama, llama-android)

## 10. Сборка и публикация

### 10.1 Сборка релиза

```bash
flutter build apk --release
```

Выходной файл: `build/app/outputs/apk/release/app-release.apk` (~29 МБ)

### 10.2 Публикация

- **RuStore**: Опубликовано ✓
- **Google Play**: Планируется

---

*Последнее обновление: январь 2026*
