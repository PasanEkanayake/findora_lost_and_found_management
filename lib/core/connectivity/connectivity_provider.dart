import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where to knock to find out whether Findora's backend is reachable: the
/// host and port of [supabaseUrl] (`SUPABASE_URL` in `.env`). Null when the
/// URL is missing or malformed — then there is nothing to check and the app
/// simply assumes it is online.
({String host, int port})? reachabilityTarget(String? supabaseUrl) {
  if (supabaseUrl == null || supabaseUrl.trim().isEmpty) return null;
  final uri = Uri.tryParse(supabaseUrl.trim());
  if (uri == null || uri.host.isEmpty) return null;
  // `Uri.port` is 443 for https / 80 for http when the URL names no port.
  return (host: uri.host, port: uri.port);
}

/// True while the phone can reach the backend. Drives the offline banner.
///
/// This asks "can I actually open a connection to Supabase?" rather than "is
/// Wi-Fi or mobile data switched on?", because a phone can be connected to a
/// network with no internet behind it, and that is exactly when the app
/// can't do anything. It needs no extra package or permission: a plain TCP
/// connection to the Supabase host, every 15 seconds while online (every
/// few seconds while offline, so the banner goes away promptly), and again
/// whenever the app returns to the foreground.
///
/// To avoid a flickering banner on one dropped packet it takes two failed
/// checks in a row to go offline; one success is enough to come back.
class ConnectivityController extends Notifier<bool> with WidgetsBindingObserver {
  static const _onlineInterval = Duration(seconds: 15);
  static const _retryInterval = Duration(seconds: 3);
  static const _offlineInterval = Duration(seconds: 5);
  static const _connectTimeout = Duration(seconds: 4);

  Timer? _timer;
  bool _checking = false;
  bool _disposed = false;
  int _failures = 0;

  @override
  bool build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });
    _schedule(const Duration(seconds: 1));
    // Assume online until a check says otherwise, so the banner never flashes
    // at launch.
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // (`state` here is the app's lifecycle, not this notifier's online flag.)
    if (state == AppLifecycleState.resumed) _schedule(Duration.zero);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (_checking || _disposed) return;
    _checking = true;
    final reachable = await _canReachBackend();
    _checking = false;
    if (_disposed) return;

    if (reachable) {
      _failures = 0;
      if (!state) state = true;
      _schedule(_onlineInterval);
    } else {
      _failures++;
      if (_failures >= 2 && state) state = false;
      _schedule(_failures < 2 ? _retryInterval : _offlineInterval);
    }
  }

  Future<bool> _canReachBackend() async {
    final target = reachabilityTarget(dotenv.maybeGet('SUPABASE_URL'));
    if (target == null) return true;
    try {
      final socket = await Socket.connect(target.host, target.port, timeout: _connectTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final connectivityProvider = NotifierProvider<ConnectivityController, bool>(
  ConnectivityController.new,
);
