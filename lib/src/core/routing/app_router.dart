import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';

import '../../features/chat/presentation/chat_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: SplashScreen.routePath,
    routes: [
      GoRoute(
        path: SplashScreen.routePath,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: ChatShell.routePath,
        builder: (context, state) => const ChatShell(),
      ),
    ],
  );
});

class AuthListenable extends ChangeNotifier {
  AuthListenable(this.state);

  AuthState state;

  void update(AuthState value) {
    if (value == state) return;
    state = value;
    notifyListeners();
  }
}

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final authService = ref.watch(authServiceProvider);
  final controller = AuthController(authService);
  controller.initialize();
  return controller;
});

class AuthController extends AuthListenable {
  AuthController(this._service) : super(const AuthState.loading());

  final AuthService _service;

  AuthStatus get status => state.status;
  String? get error => state.error;
  String? get userId => state.userId;

  Future<void> initialize() async {
    final state = await _service.restoreSession();
    update(state);
  }

  Future<void> signInWithEmail(String email, String password) async {
    update(const AuthState.loading());
    final result = await _service.signInWithEmail(email, password);
    update(result);
  }

  Future<void> registerWithEmail(String email, String password) async {
    update(const AuthState.loading());
    final result = await _service.registerWithEmail(email, password);
    update(result);
  }

  Future<void> signInWithGoogle() async {
    update(const AuthState.loading());
    final result = await _service.signInWithGoogle();
    update(result);
  }

  Future<void> signInWithYandex() async {
    update(const AuthState.loading());
    final result = await _service.signInWithYandex();
    update(result);
  }

  Future<void> signOut() async {
    update(const AuthState.loading());
    await _service.signOut();
    update(const AuthState.unauthenticated());
  }
}

@immutable
class AuthState {
  const AuthState._(this.status, this.userId, this.error);

  const AuthState.loading() : this._(AuthStatus.loading, null, null);
  const AuthState.authenticated(String userId)
      : this._(AuthStatus.authenticated, userId, null);
  const AuthState.unauthenticated([String? error])
      : this._(AuthStatus.unauthenticated, null, error);

  final AuthStatus status;
  final String? userId;
  final String? error;
}

enum AuthStatus { loading, authenticated, unauthenticated }

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

class AuthService {
  AuthService(this.ref);

  final Ref ref;
  final _storage = const FlutterSecureStorage();
  FirebaseAuth? _firebase;

  static const _emailKey = 'nexus_email';
  static const _tokenKey = 'nexus_token';

  Future<AuthState> restoreSession() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        return const AuthState.unauthenticated();
      }
      return AuthState.authenticated(token);
    } on PlatformException catch (_) {
      return const AuthState.unauthenticated();
    } catch (_) {
      return const AuthState.unauthenticated();
    }
  }

  Future<AuthState> signInWithEmail(String email, String password) async {
    final hashed = _hash(password);
    await _safeWrite(_emailKey, email);
    await _safeWrite(_tokenKey, hashed);
    return AuthState.authenticated(hashed);
  }

  Future<AuthState> registerWithEmail(String email, String password) async {
    return signInWithEmail(email, password);
  }

  Future<AuthState> signInWithGoogle() async {
    if (!await _hasConnectivity()) {
      return const AuthState.unauthenticated('Нет подключения к интернету');
    }
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      return const AuthState.unauthenticated();
    }
    final googleAuth = await googleUser.authentication;
    final firebase = await _ensureFirebase();
    if (firebase == null) {
      return const AuthState.unauthenticated('Firebase не настроен');
    }
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    await firebase.signInWithCredential(credential);
    final uid = firebase.currentUser?.uid ?? googleUser.id;
    await _safeWrite(_tokenKey, uid);
    return AuthState.authenticated(uid);
  }

  Future<AuthState> signInWithYandex() async {
    // TODO: Интегрировать после публикации в магазине
    return const AuthState.unauthenticated('Yandex ID будет доступен после релиза');
  }

  Future<void> signOut() async {
    await _safeDelete(_tokenKey);
  }

  Future<bool> _hasConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  String _hash(String value) {
    final bytes = utf8.encode(value);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<FirebaseAuth?> _ensureFirebase() async {
    if (_firebase != null) {
      return _firebase;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebase = FirebaseAuth.instance;
      return _firebase;
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (_) {
      // ignore storage errors in offline mode
    } catch (_) {
      // ignore storage errors in offline mode
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (_) {
      // ignore storage errors in offline mode
    } catch (_) {
      // ignore storage errors in offline mode
    }
  }

}

