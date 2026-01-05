# ONNX Runtime - keep all classes
-keep class ai.onnxruntime.** { *; }
-keep class com.microsoft.onnxruntime.** { *; }

# JSON parsing
-keep class org.json.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
