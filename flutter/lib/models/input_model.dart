import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../common.dart';
import '../consts.dart';
import './state_model.dart';

/// Mouse button enum.
enum MouseButtons { left, right, wheel }

const _kMouseEventDown = 'mousedown';
const _kMouseEventUp = 'mouseup';
const _kMouseEventMove = 'mousemove';

extension ToString on MouseButtons {
  String get value {
    switch (this) {
      case MouseButtons.left:
        return 'left';
      case MouseButtons.right:
        return 'right';
      case MouseButtons.wheel:
        return 'wheel';
    }
  }
}

class PointerEventToRust {
  final String kind;
  final String type;
  final dynamic value;

  PointerEventToRust(this.kind, this.type, this.value);

  Map<String, dynamic> toJson() {
    return {
      'k': kind,
      'v': {
        't': type,
        'v': value,
      }
    };
  }
}

class InputModel {
  final WeakReference<FFI> parent;
  String keyboardMode = "legacy";

  // keyboard
  var shift = false;
  var ctrl = false;
  var alt = false;
  var command = false;

  // trackpad
  var _trackpadLastDelta = Offset.zero;
  var _stopFling = true;
  var _fling = false;
  Timer? _flingTimer;
  final _flingBaseDelay = 30;
  // trackpad, peer linux
  final _trackpadSpeed = 0.06;
  var _trackpadScrollUnsent = Offset.zero;

  var _lastScale = 1.0;

  // mouse
  final isPhysicalMouse = false.obs;
  int _lastButtons = 0;
  Offset lastMousePos = Offset.zero;

  late final SessionID sessionId;

  bool get keyboardPerm => parent.target!.ffiModel.keyboard;
  String get id => parent.target?.id ?? '';
  String? get peerPlatform => parent.target?.ffiModel.pi.platform;

  InputModel(this.parent) {
    sessionId = parent.target!.sessionId;
  }

  KeyEventResult handleRawKeyEvent(FocusNode data, RawKeyEvent e) {
    if (isDesktop && !stateGlobal.grabKeyboard) {
      return KeyEventResult.handled;
    }

    // * Currently mobile does not enable map mode
    if (isDesktop) {
      bind.sessionGetKeyboardMode(sessionId: sessionId).then((result) {
        keyboardMode = result.toString();
      });
    }

    final key = e.logicalKey;
    if (e is RawKeyDownEvent) {
      if (!e.repeat) {
        if (e.isAltPressed && !alt) {
          alt = true;
        } else if (e.isControlPressed && !ctrl) {
          ctrl = true;
        } else if (e.isShiftPressed && !shift) {
          shift = true;
        } else if (e.isMetaPressed && !command) {
          command = true;
        }
      }
    }
    if (e is RawKeyUpEvent) {
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        alt = false;
      } else if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        ctrl = false;
      } else if (key == LogicalKeyboardKey.shiftRight ||
          key == LogicalKeyboardKey.shiftLeft) {
        shift = false;
      } else if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight ||
          key == LogicalKeyboardKey.superKey) {
        command = false;
      }
    }

    // * Currently mobile does not enable map mode
    if (isDesktop && keyboardMode == 'map') {
      mapKeyboardMode(e);
    } else {
      legacyKeyboardMode(e);
    }

    return KeyEventResult.handled;
  }

  void mapKeyboardMode(RawKeyEvent e) {
    int positionCode = -1;
    int platformCode = -1;
    bool down;

    if (e.data is RawKeyEventDataMacOs) {
      RawKeyEventDataMacOs newData = e.data as RawKeyEventDataMacOs;
      positionCode = newData.keyCode;
      platformCode = newData.keyCode;
    } else if (e.data is RawKeyEventDataWindows) {
      RawKeyEventDataWindows newData = e.data as RawKeyEventDataWindows;
      positionCode = newData.scanCode;
      platformCode = newData.keyCode;
    } else if (e.data is RawKeyEventDataLinux) {
      RawKeyEventDataLinux newData = e.data as RawKeyEventDataLinux;
      // scanCode and keyCode of RawKeyEventDataLinux are incorrect.
      // 1. scanCode means keycode
      // 2. keyCode means keysym
      positionCode = newData.scanCode;
      platformCode = newData.keyCode;
    } else if (e.data is RawKeyEventDataAndroid) {
      RawKeyEventDataAndroid newData = e.data as RawKeyEventDataAndroid;
      positionCode = newData.scanCode + 8;
      platformCode = newData.keyCode;
    } else {}

    if (e is RawKeyDownEvent) {
      down = true;
    } else {
      down = false;
    }
    inputRawKey(e.character ?? '', platformCode, positionCode, down);
  }

  /// Send raw Key Event
  void inputRawKey(String name, int platformCode, int positionCode, bool down) {
    const capslock = 1;
    const numlock = 2;
    const scrolllock = 3;
    int lockModes = 0;
    if (HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock)) {
      lockModes |= (1 << capslock);
    }
    if (HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.numLock)) {
      lockModes |= (1 << numlock);
    }
    if (HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.scrollLock)) {
      lockModes |= (1 << scrolllock);
    }
    bind.sessionHandleFlutterKeyEvent(
        sessionId: sessionId,
        name: name,
        platformCode: platformCode,
        positionCode: positionCode,
        lockModes: lockModes,
        downOrUp: down);
  }

  void legacyKeyboardMode(RawKeyEvent e) {
    if (e is RawKeyDownEvent) {
      if (e.repeat) {
        sendRawKey(e, press: true);
      } else {
        sendRawKey(e, down: true);
      }
    }
    if (e is RawKeyUpEvent) {
      sendRawKey(e);
    }
  }

  void sendRawKey(RawKeyEvent e, {bool? down, bool? press}) {
    // for maximum compatibility
    final label = physicalKeyMap[e.physicalKey.usbHidUsage] ??
        logicalKeyMap[e.logicalKey.keyId] ??
        e.logicalKey.keyLabel;
    inputKey(label, down: down, press: press ?? false);
  }

  /// Send key stroke event.
  /// [down] indicates the key's state(down or up).
  /// [press] indicates a click event(down and up).
  void inputKey(String name, {bool? down, bool? press}) {
    if (!keyboardPerm) return;
    bind.sessionInputKey(
        sessionId: sessionId,
        name: name,
        down: down ?? false,
        press: press ?? true,
        alt: alt,
        ctrl: ctrl,
        shift: shift,
        command: command);
  }

  Map<String, dynamic> _getMouseEvent(PointerEvent evt, String type) {
    final Map<String, dynamic> out = {};

    // Check update event type and set buttons to be sent.
    int buttons = _lastButtons;
    if (type == _kMouseEventMove) {
      // flutter may emit move event if one button is pressed and another button
      // is pressing or releasing.
      if (evt.buttons != _lastButtons) {
        // For simplicity
        // Just consider 3 - 1 ((Left + Right buttons) - Left button)
        // Do not consider 2 - 1 (Right button - Left button)
        // or 6 - 5 ((Right + Mid buttons) - (Left + Mid buttons))
        // and so on
        buttons = evt.buttons - _lastButtons;
        if (buttons > 0) {
          type = _kMouseEventDown;
        } else {
          type = _kMouseEventUp;
          buttons = -buttons;
        }
      }
    } else {
      if (evt.buttons != 0) {
        buttons = evt.buttons;
      }
    }
    _lastButtons = evt.buttons;

    out['buttons'] = buttons;
    out['type'] = type;
    return out;
  }

  /// Send a mouse tap event(down and up).
  void tap(MouseButtons button) {
    sendMouse('down', button);
    sendMouse('up', button);
  }

  void tapDown(MouseButtons button) {
    sendMouse('down', button);
  }

  void tapUp(MouseButtons button) {
    sendMouse('up', button);
  }

  /// Send scroll event with scroll distance [y].
  void scroll(int y) {
    bind.sessionSendMouse(
        sessionId: sessionId,
        msg: json
            .encode(modify({'id': id, 'type': 'wheel', 'y': y.toString()})));
  }

  /// Reset key modifiers to false, including [shift], [ctrl], [alt] and [command].
  void resetModifiers() {
    shift = ctrl = alt = command = false;
  }

  /// Modify the given modifier map [evt] based on current modifier key status.
  Map<String, dynamic> modify(Map<String, dynamic> evt) {
    if (ctrl) evt['ctrl'] = 'true';
    if (shift) evt['shift'] = 'true';
    if (alt) evt['alt'] = 'true';
    if (command) evt['command'] = 'true';
    return evt;
  }

  /// Send mouse press event.
  void sendMouse(String type, MouseButtons button) {
    if (!keyboardPerm) return;
    bind.sessionSendMouse(
        sessionId: sessionId,
        msg: json.encode(modify({'type': type, 'buttons': button.value})));
  }

  void enterOrLeave(bool enter) {
    // Fix status
    if (!enter) {
      resetModifiers();
    }
    _flingTimer?.cancel();
    bind.sessionEnterOrLeave(sessionId: sessionId, enter: enter);
  }

  /// Send mouse movement event with distance in [x] and [y].
  void moveMouse(double x, double y) {
    if (!keyboardPerm) return;
    var x2 = x.toInt();
    var y2 = y.toInt();
    bind.sessionSendMouse(
        sessionId: sessionId,
        msg: json.encode(modify({'x': '$x2', 'y': '$y2'})));
  }

  void onPointHoverImage(PointerHoverEvent e) {
    _stopFling = true;
    if (e.kind != ui.PointerDeviceKind.mouse) return;
    if (!isPhysicalMouse.value) {
      isPhysicalMouse.value = true;
    }
    if (isPhysicalMouse.value) {
      handleMouse(_getMouseEvent(e, _kMouseEventMove), e.position);
    }
  }

  void onPointerPanZoomStart(PointerPanZoomStartEvent e) {
    _lastScale = 1.0;
    _stopFling = true;

    if (peerPlatform == kPeerPlatformAndroid) {
      handlePointerEvent('touch', 'pan_start', e.position);
    }
  }

  // https://docs.flutter.dev/release/breaking-changes/trackpad-gestures
  void onPointerPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (peerPlatform != kPeerPlatformAndroid) {
      final scale = ((e.scale - _lastScale) * 1000).toInt();
      _lastScale = e.scale;

      if (scale != 0) {
        bind.sessionSendPointer(
            sessionId: sessionId,
            msg: json.encode(
                PointerEventToRust(kPointerEventKindTouch, 'scale', scale)
                    .toJson()));
        return;
      }
    }

    final delta = e.panDelta;
    _trackpadLastDelta = delta;

    var x = delta.dx.toInt();
    var y = delta.dy.toInt();
    if (peerPlatform == kPeerPlatformLinux) {
      _trackpadScrollUnsent += (delta * _trackpadSpeed);
      x = _trackpadScrollUnsent.dx.truncate();
      y = _trackpadScrollUnsent.dy.truncate();
      _trackpadScrollUnsent -= Offset(x.toDouble(), y.toDouble());
    } else {
      if (x == 0 && y == 0) {
        final thr = 0.1;
        if (delta.dx.abs() > delta.dy.abs()) {
          x = delta.dx > thr ? 1 : (delta.dx < -thr ? -1 : 0);
        } else {
          y = delta.dy > thr ? 1 : (delta.dy < -thr ? -1 : 0);
        }
      }
    }
    if (x != 0 || y != 0) {
      if (peerPlatform == kPeerPlatformAndroid) {
        handlePointerEvent('touch', 'pan_update', Offset(x.toDouble(), y.toDouble()));
      } else {
        bind.sessionSendMouse(
            sessionId: sessionId,
            msg: '{"type": "trackpad", "x": "$x", "y": "$y"}');
      }
    }
  }

  void _scheduleFling(double x, double y, int delay) {
    if ((x == 0 && y == 0) || _stopFling) {
      _fling = false;
      return;
    }

    _flingTimer = Timer(Duration(milliseconds: delay), () {
      if (_stopFling) {
        _fling = false;
        return;
      }

      final d = 0.97;
      x *= d;
      y *= d;

      // Try set delta (x,y) and delay.
      var dx = x.toInt();
      var dy = y.toInt();
      if (parent.target?.ffiModel.pi.platform == kPeerPlatformLinux) {
        dx = (x * _trackpadSpeed).toInt();
        dy = (y * _trackpadSpeed).toInt();
      }

      var delay = _flingBaseDelay;

      if (dx == 0 && dy == 0) {
        _fling = false;
        return;
      }

      bind.sessionSendMouse(
          sessionId: sessionId,
          msg: '{"type": "trackpad", "x": "$dx", "y": "$dy"}');
      _scheduleFling(x, y, delay);
    });
  }

  void waitLastFlingDone() {
    if (_fling) {
      _stopFling = true;
    }
    for (var i = 0; i < 5; i++) {
      if (!_fling) {
        break;
      }
      sleep(Duration(milliseconds: 10));
    }
    _flingTimer?.cancel();
  }

  void onPointerPanZoomEnd(PointerPanZoomEndEvent e) {
    if (peerPlatform == kPeerPlatformAndroid) {
      handlePointerEvent('touch', 'pan_end', e.position);
      return;
    }

    bind.sessionSendPointer(
        sessionId: sessionId,
        msg: json.encode(
            PointerEventToRust(kPointerEventKindTouch, 'scale', 0).toJson()));

    waitLastFlingDone();
    _stopFling = false;

    // 2.0 is an experience value
    double minFlingValue = 2.0;
    if (_trackpadLastDelta.dx.abs() > minFlingValue ||
        _trackpadLastDelta.dy.abs() > minFlingValue) {
      _fling = true;
      _scheduleFling(
          _trackpadLastDelta.dx, _trackpadLastDelta.dy, _flingBaseDelay);
    }
    _trackpadLastDelta = Offset.zero;
  }

  void onPointDownImage(PointerDownEvent e) {
    debugPrint("onPointDownImage ${e.kind}");
    _stopFling = true;
    if (e.kind != ui.PointerDeviceKind.mouse) {
      if (isPhysicalMouse.value) {
        isPhysicalMouse.value = false;
      }
    }
    if (isPhysicalMouse.value) {
      handleMouse(_getMouseEvent(e, _kMouseEventDown), e.position);
    }
  }

  void onPointUpImage(PointerUpEvent e) {
    if (e.kind != ui.PointerDeviceKind.mouse) return;
    if (isPhysicalMouse.value) {
      handleMouse(_getMouseEvent(e, _kMouseEventUp), e.position);
    }
  }

  void onPointMoveImage(PointerMoveEvent e) {
    if (e.kind != ui.PointerDeviceKind.mouse) return;
    if (isPhysicalMouse.value) {
      handleMouse(_getMouseEvent(e, _kMouseEventMove), e.position);
    }
  }

  void onPointerSignalImage(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      var dx = e.scrollDelta.dx.toInt();
      var dy = e.scrollDelta.dy.toInt();
      if (dx > 0) {
        dx = -1;
      } else if (dx < 0) {
        dx = 1;
      }
      if (dy > 0) {
        dy = -1;
      } else if (dy < 0) {
        dy = 1;
      }
      bind.sessionSendMouse(
          sessionId: sessionId,
          msg: '{"type": "wheel", "x": "$dx", "y": "$dy"}');
    }
  }

  void refreshMousePos() => handleMouse({
        'buttons': 0,
        'type': _kMouseEventMove,
      }, lastMousePos);

  void tryMoveEdgeOnExit(Offset pos) => handleMouse(
        {
          'buttons': 0,
          'type': _kMouseEventMove,
        },
        pos,
        onExit: true,
      );

  int trySetNearestRange(int v, int min, int max, int n) {
    if (v < min && v >= min - n) {
      v = min;
    }
    if (v > max && v <= max + n) {
      v = max;
    }
    return v;
  }

  Offset setNearestEdge(double x, double y, Display d) {
    double left = x - d.x;
    double right = d.x + d.width - 1 - x;
    double top = y - d.y;
    double bottom = d.y + d.height - 1 - y;
    if (left < right && left < top && left < bottom) {
      x = d.x;
    }
    if (right < left && right < top && right < bottom) {
      x = d.x + d.width - 1;
    }
    if (top < left && top < right && top < bottom) {
      y = d.y;
    }
    if (bottom < left && bottom < right && bottom < top) {
      y = d.y + d.height - 1;
    }
    return Offset(x, y);
  }

  void handlePointerEvent(String kind, String type, Offset offset) {
    double x = offset.dx;
    double y = offset.dy;
    if (_checkPeerControlProtected(x, y)) {
      return;
    }
    // Only touch events are handled for now. So we can just ignore buttons.
    // to-do: handle mouse events

    late final dynamic evtValue;
    if (type == 'pan_update') {
      evtValue = {
        'x': x.toInt(),
        'y': y.toInt(),
      };
    } else {
      final isMoveTypes = ['pan_start', 'pan_end'];
      final pos = handlePointerDevicePos(
        kPointerEventKindTouch,
        x,
        y,
        isMoveTypes.contains(type),
        type,
      );
      if (pos == null) {
        return;
      }
      evtValue = {
        'x': pos.x,
        'y': pos.y,
      };
    }

    final evt = PointerEventToRust(kind, type, evtValue).toJson();
    bind.sessionSendPointer(
        sessionId: sessionId, msg: json.encode(modify(evt)));
  }

  bool _checkPeerControlProtected(double x, double y) {
    final cursorModel = parent.target!.cursorModel;
    if (cursorModel.isPeerControlProtected) {
      lastMousePos = ui.Offset(x, y);
      return true;
    }

    if (!cursorModel.gotMouseControl) {
      bool selfGetControl =
          (x - lastMousePos.dx).abs() > kMouseControlDistance ||
              (y - lastMousePos.dy).abs() > kMouseControlDistance;
      if (selfGetControl) {
        cursorModel.gotMouseControl = true;
      } else {
        lastMousePos = ui.Offset(x, y);
        return true;
      }
    }
    lastMousePos = ui.Offset(x, y);
    return false;
  }

  void handleMouse(
    Map<String, dynamic> evt,
    Offset offset, {
    bool onExit = false,
  }) {
    double x = offset.dx;
    double y = max(0.0, offset.dy);
    if (_checkPeerControlProtected(x, y)) {
      return;
    }

    var type = '';
    var isMove = false;
    switch (evt['type']) {
      case _kMouseEventDown:
        type = 'down';
        break;
      case _kMouseEventUp:
        type = 'up';
        break;
      case _kMouseEventMove:
        isMove = true;
        break;
      default:
        return;
    }
    evt['type'] = type;

    final pos = handlePointerDevicePos(
      kPointerEventKindMouse,
      x,
      y,
      isMove,
      type,
      onExit: onExit,
      buttons: evt['buttons'],
    );
    if (pos == null) {
      return;
    }
    if (type != '') {
      evt['x'] = '0';
      evt['y'] = '0';
    } else {
      evt['x'] = '${pos.x}';
      evt['y'] = '${pos.y}';
    }

    Map<int, String> mapButtons = {
      kPrimaryMouseButton: 'left',
      kSecondaryMouseButton: 'right',
      kMiddleMouseButton: 'wheel',
      kBackMouseButton: 'back',
      kForwardMouseButton: 'forward'
    };
    evt['buttons'] = mapButtons[evt['buttons']] ?? '';
    bind.sessionSendMouse(sessionId: sessionId, msg: json.encode(modify(evt)));
  }

  Point? handlePointerDevicePos(
    String kind,
    double x,
    double y,
    bool isMove,
    String evtType, {
    bool onExit = false,
    int buttons = kPrimaryMouseButton,
  }) {
    y -= CanvasModel.topToEdge;
    x -= CanvasModel.leftToEdge;
    final canvasModel = parent.target!.canvasModel;
    final ffiModel = parent.target!.ffiModel;
    if (isMove) {
      canvasModel.moveDesktopMouse(x, y);
    }

    final nearThr = 3;
    var nearRight = (canvasModel.size.width - x) < nearThr;
    var nearBottom = (canvasModel.size.height - y) < nearThr;
    final d = ffiModel.display;
    final imageWidth = d.width * canvasModel.scale;
    final imageHeight = d.height * canvasModel.scale;
    if (canvasModel.scrollStyle == ScrollStyle.scrollbar) {
      x += imageWidth * canvasModel.scrollX;
      y += imageHeight * canvasModel.scrollY;

      // boxed size is a center widget
      if (canvasModel.size.width > imageWidth) {
        x -= ((canvasModel.size.width - imageWidth) / 2);
      }
      if (canvasModel.size.height > imageHeight) {
        y -= ((canvasModel.size.height - imageHeight) / 2);
      }
    } else {
      x -= canvasModel.x;
      y -= canvasModel.y;
    }

    x /= canvasModel.scale;
    y /= canvasModel.scale;
    if (canvasModel.scale > 0 && canvasModel.scale < 1) {
      final step = 1.0 / canvasModel.scale - 1;
      if (nearRight) {
        x += step;
      }
      if (nearBottom) {
        y += step;
      }
    }
    x += d.x;
    y += d.y;

    if (onExit) {
      final pos = setNearestEdge(x, y, d);
      x = pos.dx;
      y = pos.dy;
    }

    var evtX = 0;
    var evtY = 0;
    try {
      evtX = x.round();
      evtY = y.round();
    } catch (e) {
      debugPrintStack(
          label: 'canvasModel.scale value ${canvasModel.scale}, $e');
      return null;
    }

    int minX = d.x.toInt();
    int maxX = (d.x + d.width).toInt() - 1;
    int minY = d.y.toInt();
    int maxY = (d.y + d.height).toInt() - 1;
    evtX = trySetNearestRange(evtX, minX, maxX, 5);
    evtY = trySetNearestRange(evtY, minY, maxY, 5);
    if (kind == kPointerEventKindMouse) {
      if (evtX < minX || evtY < minY || evtX > maxX || evtY > maxY) {
        // If left mouse up, no early return.
        if (!(buttons == kPrimaryMouseButton && evtType == 'up')) {
          return null;
        }
      }
    }

    return Point(evtX, evtY);
  }

  /// Web only
  void listenToMouse(bool yesOrNo) {
    if (yesOrNo) {
      platformFFI.startDesktopWebListener();
    } else {
      platformFFI.stopDesktopWebListener();
    }
  }
}
