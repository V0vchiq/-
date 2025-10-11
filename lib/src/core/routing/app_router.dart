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
import 'package:yandex_auth_sdk/yandex_auth_sdk.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/chat/presentation/chat_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: SplashScreen.routePath,
    refreshListenable: auth,
    routes: [
      GoRoute(
        path: SplashScreen.routePath,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: LoginScreen.routePath,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: ChatShell.routePath,
        builder: (context, state) => const ChatShell(),
      ),
    ],
    redirect: (context, state) {
      final status = auth.state.status;
      final path = state.fullPath;

      if (status == AuthStatus.loading) {
        return SplashScreen.routePath;
      }

      if (status == AuthStatus.unauthenticated && path != LoginScreen.routePath) {
        return LoginScreen.routePath;
      }

      if (status == AuthStatus.authenticated && path == LoginScreen.routePath) {
        return ChatShell.routePath;
      }

      return null;
    },
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
  AuthController(this._service) : super(AuthState.loading());

  final AuthService _service;

  Future<void> initialize() async {
    final state = await _service.restoreSession();
    update(state);
  }

  Future<void> signInWithEmail(String email, String password) async {
    update(AuthState.loading());
    final result = await _service.signInWithEmail(email, password);
    update(result);
  }

  Future<void> registerWithEmail(String email, String password) async {
    update(AuthState.loading());
    final result = await _service.registerWithEmail(email, password);
    update(result);
  }

  Future<void> signInWithGoogle() async {
    update(AuthState.loading());
    final result = await _service.signInWithGoogle();
    update(result);
  }

  Future<void> signInWithYandex() async {
    update(AuthState.loading());
    final result = await _service.signInWithYandex();
    update(result);
  }

  Future<void> signOut() async {
    update(AuthState.loading());
    await _service.signOut();
    update(AuthState.unauthenticated());
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

  static const _emailKey = 'starmind_email';
  static const _tokenKey = 'starmind_token';

  Future<AuthState> restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      return const AuthState.unauthenticated();
    }
    return AuthState.authenticated(token);
  }

  Future<AuthState> signInWithEmail(String email, String password) async {
    final hashed = _hash(password);
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _tokenKey, value: hashed);
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
    await _storage.write(key: _tokenKey, value: uid);
    return AuthState.authenticated(uid);
  }

  Future<AuthState> signInWithYandex() async {
    if (!await _hasConnectivity()) {
      return const AuthState.unauthenticated('Нет подключения к интернету');
    }
    final sdk = YandexAuthSdk();
    final result = await sdk.authenticate();
    if (result == null) {
      return const AuthState.unauthenticated();
    }
    await _storage.write(key: _tokenKey, value: result.accessToken.value);
    return AuthState.authenticated(result.accessToken.value);
  }

  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> _hasConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
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

