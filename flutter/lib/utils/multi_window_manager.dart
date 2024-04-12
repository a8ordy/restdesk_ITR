import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/common.dart';

/// must keep the order
enum WindowType { Main, RemoteDesktop, FileTransfer, PortForward, Unknown }

extension Index on int {
  WindowType get windowType {
    switch (this) {
      case 0:
        return WindowType.Main;
      case 1:
        return WindowType.RemoteDesktop;
      case 2:
        return WindowType.FileTransfer;
      case 3:
        return WindowType.PortForward;
      default:
        return WindowType.Unknown;
    }
  }
}

class MultiWindowCallResult {
  int windowId;
  dynamic result;

  MultiWindowCallResult(this.windowId, this.result);
}

/// Window Manager
/// mainly use it in `Main Window`
/// use it in sub window is not recommended
class RustDeskMultiWindowManager {
  RustDeskMultiWindowManager._();

  static final instance = RustDeskMultiWindowManager._();

  final Set<int> _inactiveWindows = {};
  final Set<int> _activeWindows = {};
  final List<AsyncCallback> _windowActiveCallbacks = List.empty(growable: true);
  final List<int> _remoteDesktopWindows = List.empty(growable: true);
  final List<int> _fileTransferWindows = List.empty(growable: true);
  final List<int> _portForwardWindows = List.empty(growable: true);

  moveTabToNewWindow(int windowId, String peerId, String sessionId) async {
    var params = {
      'type': WindowType.RemoteDesktop.index,
      'id': peerId,
      'tab_window_id': windowId,
      'session_id': sessionId,
    };
    await _newSession(
      false,
      WindowType.RemoteDesktop,
      kWindowEventNewRemoteDesktop,
      peerId,
      _remoteDesktopWindows,
      jsonEncode(params),
    );
  }

  Future<int> newSessionWindow(
      WindowType type, String remoteId, String msg, List<int> windows) async {
    final windowController = await DesktopMultiWindow.createWindow(msg);
    final windowId = windowController.windowId;
    windowController
      ..setFrame(
          const Offset(0, 0) & Size(1280 + windowId * 20, 720 + windowId * 20))
      ..center()
      ..setTitle(getWindowNameWithId(
        remoteId,
        overrideType: type,
      ));
    if (Platform.isMacOS) {
      Future.microtask(() => windowController.show());
    }
    registerActiveWindow(windowId);
    windows.add(windowId);
    return windowId;
  }

  Future<MultiWindowCallResult> _newSession(
    bool openInTabs,
    WindowType type,
    String methodName,
    String remoteId,
    List<int> windows,
    String msg,
  ) async {
    if (openInTabs) {
      if (windows.isEmpty) {
        final windowId = await newSessionWindow(type, remoteId, msg, windows);
        return MultiWindowCallResult(windowId, null);
      } else {
        return call(type, methodName, msg);
      }
    } else {
      if (_inactiveWindows.isNotEmpty) {
        for (final windowId in windows) {
          if (_inactiveWindows.contains(windowId)) {
            await restoreWindowPosition(type,
                windowId: windowId, peerId: remoteId);
            await DesktopMultiWindow.invokeMethod(windowId, methodName, msg);
            WindowController.fromWindowId(windowId).show();
            registerActiveWindow(windowId);
            return MultiWindowCallResult(windowId, null);
          }
        }
      }
      final windowId = await newSessionWindow(type, remoteId, msg, windows);
      return MultiWindowCallResult(windowId, null);
    }
  }

  Future<MultiWindowCallResult> newSession(
    WindowType type,
    String methodName,
    String remoteId,
    List<int> windows, {
    String? password,
    bool? forceRelay,
    String? switchUuid,
    bool? isRDP,
  }) async {
    var params = {
      "type": type.index,
      "id": remoteId,
      "password": password,
      "forceRelay": forceRelay
    };
    if (switchUuid != null) {
      params['switch_uuid'] = switchUuid;
    }
    if (isRDP != null) {
      params['isRDP'] = isRDP;
    }
    final msg = jsonEncode(params);

    // separate window for file transfer is not supported
    bool openInTabs = type != WindowType.RemoteDesktop ||
        mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs);

    if (windows.length > 1 || !openInTabs) {
      for (final windowId in windows) {
        if (await DesktopMultiWindow.invokeMethod(
            windowId, kWindowEventActiveSession, remoteId)) {
          return MultiWindowCallResult(windowId, null);
        }
      }
    }

    return _newSession(openInTabs, type, methodName, remoteId, windows, msg);
  }

  Future<MultiWindowCallResult> newRemoteDesktop(
    String remoteId, {
    String? password,
    String? switchUuid,
    bool? forceRelay,
  }) async {
    return await newSession(
      WindowType.RemoteDesktop,
      kWindowEventNewRemoteDesktop,
      remoteId,
      _remoteDesktopWindows,
      password: password,
      forceRelay: forceRelay,
      switchUuid: switchUuid,
    );
  }

  Future<MultiWindowCallResult> newFileTransfer(String remoteId,
      {String? password, bool? forceRelay}) async {
    return await newSession(
      WindowType.FileTransfer,
      kWindowEventNewFileTransfer,
      remoteId,
      _fileTransferWindows,
      password: password,
      forceRelay: forceRelay,
    );
  }

  Future<MultiWindowCallResult> newPortForward(String remoteId, bool isRDP,
      {String? password, bool? forceRelay}) async {
    return await newSession(
      WindowType.PortForward,
      kWindowEventNewPortForward,
      remoteId,
      _portForwardWindows,
      password: password,
      forceRelay: forceRelay,
      isRDP: isRDP,
    );
  }

  Future<MultiWindowCallResult> call(
      WindowType type, String methodName, dynamic args) async {
    final wnds = _findWindowsByType(type);
    if (wnds.isEmpty) {
      return MultiWindowCallResult(kInvalidWindowId, null);
    }
    for (final windowId in wnds) {
      if (_activeWindows.contains(windowId)) {
        final res =
            await DesktopMultiWindow.invokeMethod(windowId, methodName, args);
        return MultiWindowCallResult(windowId, res);
      }
    }
    final res =
        await DesktopMultiWindow.invokeMethod(wnds[0], methodName, args);
    return MultiWindowCallResult(wnds[0], res);
  }

  List<int> _findWindowsByType(WindowType type) {
    switch (type) {
      case WindowType.Main:
        return [kMainWindowId];
      case WindowType.RemoteDesktop:
        return _remoteDesktopWindows;
      case WindowType.FileTransfer:
        return _fileTransferWindows;
      case WindowType.PortForward:
        return _portForwardWindows;
      case WindowType.Unknown:
        break;
    }
    return [];
  }

  void clearWindowType(WindowType type) {
    switch (type) {
      case WindowType.Main:
        return;
      case WindowType.RemoteDesktop:
        _remoteDesktopWindows.clear();
        break;
      case WindowType.FileTransfer:
        _fileTransferWindows.clear();
        break;
      case WindowType.PortForward:
        _portForwardWindows.clear();
        break;
      case WindowType.Unknown:
        break;
    }
  }

  void setMethodHandler(
      Future<dynamic> Function(MethodCall call, int fromWindowId)? handler) {
    DesktopMultiWindow.setMethodHandler(handler);
  }

  Future<void> closeAllSubWindows() async {
    await Future.wait(WindowType.values.map((e) => closeWindows(e)));
  }

  Future<void> closeWindows(WindowType type) async {
    if (type == WindowType.Main) {
      // skip main window, use window manager instead
      return;
    }

    List<int> windows = [];
    try {
      windows = await DesktopMultiWindow.getAllSubWindowIds();
    } catch (e) {
      debugPrint('Failed to getAllSubWindowIds of $type, $e');
      return;
    }

    if (windows.isEmpty) {
      return;
    }
    for (final wId in windows) {
      debugPrint("closing multi window: ${type.toString()}");
      await saveWindowPosition(type, windowId: wId);
      try {
        // final ids = await DesktopMultiWindow.getAllSubWindowIds();
        // if (!ids.contains(wId)) {
        //   // no such window already
        //   return;
        // }
        await WindowController.fromWindowId(wId).setPreventClose(false);
        await WindowController.fromWindowId(wId).close();
        _activeWindows.remove(wId);
      } catch (e) {
        debugPrint("$e");
        return;
      }
    }
    await _notifyActiveWindow();
    clearWindowType(type);
  }

  Future<List<int>> getAllSubWindowIds() async {
    try {
      final windows = await DesktopMultiWindow.getAllSubWindowIds();
      return windows;
    } catch (err) {
      if (err is AssertionError) {
        return [];
      } else {
        rethrow;
      }
    }
  }

  Set<int> getActiveWindows() {
    return _activeWindows;
  }

  Future<void> _notifyActiveWindow() async {
    for (final callback in _windowActiveCallbacks) {
      await callback.call();
    }
  }

  Future<void> registerActiveWindow(int windowId) async {
    _activeWindows.add(windowId);
    _inactiveWindows.remove(windowId);
    await _notifyActiveWindow();
  }

  Future<void> destroyWindow(int windowId) async {
    await WindowController.fromWindowId(windowId).setPreventClose(false);
    await WindowController.fromWindowId(windowId).close();
    _remoteDesktopWindows.remove(windowId);
    _fileTransferWindows.remove(windowId);
    _portForwardWindows.remove(windowId);
  }

  /// Remove active window which has [`windowId`]
  ///
  /// [Availability]
  /// This function should only be called from main window.
  /// For other windows, please post a unregister(hide) event to main window handler:
  /// `rustDeskWinManager.call(WindowType.Main, kWindowEventHide, {"id": windowId!});`
  Future<void> unregisterActiveWindow(int windowId) async {
    _activeWindows.remove(windowId);
    if (windowId != kMainWindowId) {
      _inactiveWindows.add(windowId);
    }
    await _notifyActiveWindow();
  }

  void registerActiveWindowListener(AsyncCallback callback) {
    _windowActiveCallbacks.add(callback);
  }

  void unregisterActiveWindowListener(AsyncCallback callback) {
    _windowActiveCallbacks.remove(callback);
  }
}

final rustDeskWinManager = RustDeskMultiWindowManager.instance;
