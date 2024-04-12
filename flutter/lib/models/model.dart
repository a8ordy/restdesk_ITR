import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/group_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/event.dart';
import 'package:flutter_hbb/plugin/manager.dart';
import 'package:flutter_hbb/plugin/widgets/desc_ui.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:tuple/tuple.dart';
import 'package:image/image.dart' as img2;
import 'package:flutter_custom_cursor/cursor_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../utils/image.dart' as img;
import '../common/widgets/dialog.dart';
import 'input_model.dart';
import 'platform_model.dart';

typedef HandleMsgBox = Function(Map<String, dynamic> evt, String id);
typedef ReconnectHandle = Function(OverlayDialogManager, SessionID, bool);
final _constSessionId = Uuid().v4obj();

class CachedPeerData {
  Map<String, dynamic> updatePrivacyMode = {};
  Map<String, dynamic> peerInfo = {};
  List<Map<String, dynamic>> cursorDataList = [];
  Map<String, dynamic> lastCursorId = {};
  bool secure = false;
  bool direct = false;

  CachedPeerData();

  @override
  String toString() {
    return jsonEncode({
      'updatePrivacyMode': updatePrivacyMode,
      'peerInfo': peerInfo,
      'cursorDataList': cursorDataList,
      'lastCursorId': lastCursorId,
      'secure': secure,
      'direct': direct,
    });
  }

  static CachedPeerData? fromString(String s) {
    try {
      final map = jsonDecode(s);
      final data = CachedPeerData();
      data.updatePrivacyMode = map['updatePrivacyMode'];
      data.peerInfo = map['peerInfo'];
      for (final cursorData in map['cursorDataList']) {
        data.cursorDataList.add(cursorData);
      }
      data.lastCursorId = map['lastCursorId'];
      data.secure = map['secure'];
      data.direct = map['direct'];
      return data;
    } catch (e) {
      debugPrint('Failed to parse CachedPeerData: $e');
      return null;
    }
  }
}

class FfiModel with ChangeNotifier {
  CachedPeerData cachedPeerData = CachedPeerData();
  PeerInfo _pi = PeerInfo();
  Display _display = Display();

  var _inputBlocked = false;
  final _permissions = <String, bool>{};
  bool? _secure;
  bool? _direct;
  bool _touchMode = false;
  Timer? _timer;
  var _reconnects = 1;
  bool _viewOnly = false;
  WeakReference<FFI> parent;
  late final SessionID sessionId;

  RxBool waitForImageDialogShow = true.obs;
  Timer? waitForImageTimer;
  RxBool waitForFirstImage = true.obs;

  Map<String, bool> get permissions => _permissions;

  Display get display => _display;

  bool? get secure => _secure;

  bool? get direct => _direct;

  PeerInfo get pi => _pi;

  bool get inputBlocked => _inputBlocked;

  bool get touchMode => _touchMode;

  bool get isPeerAndroid => _pi.platform == kPeerPlatformAndroid;

  bool get viewOnly => _viewOnly;

  set inputBlocked(v) {
    _inputBlocked = v;
  }

  FfiModel(this.parent) {
    clear();
    sessionId = parent.target!.sessionId;
  }

  toggleTouchMode() {
    if (!isPeerAndroid) {
      _touchMode = !_touchMode;
      notifyListeners();
    }
  }

  updatePermission(Map<String, dynamic> evt, String id) {
    evt.forEach((k, v) {
      if (k == 'name' || k.isEmpty) return;
      _permissions[k] = v == 'true';
    });
    // Only inited at remote page
    if (desktopType == DesktopType.remote) {
      KeyboardEnabledState.find(id).value = _permissions['keyboard'] != false;
    }
    debugPrint('$_permissions');
    notifyListeners();
  }

  bool get keyboard => _permissions['keyboard'] != false;

  clear() {
    _pi = PeerInfo();
    _display = Display();
    _secure = null;
    _direct = null;
    _inputBlocked = false;
    _timer?.cancel();
    _timer = null;
    clearPermissions();
    waitForImageTimer?.cancel();
  }

  setConnectionType(String peerId, bool secure, bool direct) {
    cachedPeerData.secure = secure;
    cachedPeerData.direct = direct;
    _secure = secure;
    _direct = direct;
    try {
      var connectionType = ConnectionTypeState.find(peerId);
      connectionType.setSecure(secure);
      connectionType.setDirect(direct);
    } catch (e) {
      //
    }
  }

  Widget? getConnectionImage() {
    if (secure == null || direct == null) {
      return null;
    } else {
      final icon =
          '${secure == true ? 'secure' : 'insecure'}${direct == true ? '' : '_relay'}';
      return SvgPicture.asset('assets/$icon.svg', width: 48, height: 48);
    }
  }

  clearPermissions() {
    _inputBlocked = false;
    _permissions.clear();
  }

  handleCachedPeerData(CachedPeerData data, String peerId) async {
    handleMsgBox({
      'type': 'success',
      'title': 'Successful',
      'text': 'Connected, waiting for image...',
      'link': '',
    }, sessionId, peerId);
    updatePrivacyMode(data.updatePrivacyMode, sessionId, peerId);
    setConnectionType(peerId, data.secure, data.direct);
    await handlePeerInfo(data.peerInfo, peerId);
    for (final element in data.cursorDataList) {
      updateLastCursorId(element);
      await handleCursorData(element);
    }
    updateLastCursorId(data.lastCursorId);
    handleCursorId(data.lastCursorId);
  }

  // todo: why called by two position
  StreamEventHandler startEventListener(SessionID sessionId, String peerId) {
    return (evt) async {
      var name = evt['name'];
      if (name == 'msgbox') {
        handleMsgBox(evt, sessionId, peerId);
      } else if (name == 'peer_info') {
        handlePeerInfo(evt, peerId);
      } else if (name == 'sync_peer_info') {
        handleSyncPeerInfo(evt, sessionId);
      } else if (name == 'connection_ready') {
        setConnectionType(
            peerId, evt['secure'] == 'true', evt['direct'] == 'true');
      } else if (name == 'switch_display') {
        handleSwitchDisplay(evt, sessionId, peerId);
      } else if (name == 'cursor_data') {
        updateLastCursorId(evt);
        await handleCursorData(evt);
      } else if (name == 'cursor_id') {
        updateLastCursorId(evt);
        handleCursorId(evt);
      } else if (name == 'cursor_position') {
        await parent.target?.cursorModel.updateCursorPosition(evt, peerId);
      } else if (name == 'clipboard') {
        Clipboard.setData(ClipboardData(text: evt['content']));
      } else if (name == 'permission') {
        updatePermission(evt, peerId);
      } else if (name == 'chat_client_mode') {
        parent.target?.chatModel
            .receive(ChatModel.clientModeID, evt['text'] ?? '');
      } else if (name == 'chat_server_mode') {
        parent.target?.chatModel
            .receive(int.parse(evt['id'] as String), evt['text'] ?? '');
      } else if (name == 'file_dir') {
        parent.target?.fileModel.receiveFileDir(evt);
      } else if (name == 'job_progress') {
        parent.target?.fileModel.jobController.tryUpdateJobProgress(evt);
      } else if (name == 'job_done') {
        parent.target?.fileModel.jobController.jobDone(evt);
        parent.target?.fileModel.refreshAll();
      } else if (name == 'job_error') {
        parent.target?.fileModel.jobController.jobError(evt);
      } else if (name == 'override_file_confirm') {
        parent.target?.fileModel.postOverrideFileConfirm(evt);
      } else if (name == 'load_last_job') {
        parent.target?.fileModel.jobController.loadLastJob(evt);
      } else if (name == 'update_folder_files') {
        parent.target?.fileModel.jobController.updateFolderFiles(evt);
      } else if (name == 'add_connection') {
        parent.target?.serverModel.addConnection(evt);
      } else if (name == 'on_client_remove') {
        parent.target?.serverModel.onClientRemove(evt);
      } else if (name == 'update_quality_status') {
        parent.target?.qualityMonitorModel.updateQualityStatus(evt);
      } else if (name == 'update_block_input_state') {
        updateBlockInputState(evt, peerId);
      } else if (name == 'update_privacy_mode') {
        updatePrivacyMode(evt, sessionId, peerId);
      } else if (name == 'show_elevation') {
        final show = evt['show'].toString() == 'true';
        parent.target?.serverModel.setShowElevation(show);
      } else if (name == 'cancel_msgbox') {
        cancelMsgBox(evt, sessionId);
      } else if (name == 'switch_back') {
        final peer_id = evt['peer_id'].toString();
        await bind.sessionSwitchSides(sessionId: sessionId);
        closeConnection(id: peer_id);
      } else if (name == 'portable_service_running') {
        parent.target?.elevationModel.onPortableServiceRunning(evt);
      } else if (name == 'on_url_scheme_received') {
        // currently comes from "_url" ipc of mac and dbus of linux
        onUrlSchemeReceived(evt);
      } else if (name == 'on_voice_call_waiting') {
        // Waiting for the response from the peer.
        parent.target?.chatModel.onVoiceCallWaiting();
      } else if (name == 'on_voice_call_started') {
        // Voice call is connected.
        parent.target?.chatModel.onVoiceCallStarted();
      } else if (name == 'on_voice_call_closed') {
        // Voice call is closed with reason.
        final reason = evt['reason'].toString();
        parent.target?.chatModel.onVoiceCallClosed(reason);
      } else if (name == 'on_voice_call_incoming') {
        // Voice call is requested by the peer.
        parent.target?.chatModel.onVoiceCallIncoming();
      } else if (name == 'update_voice_call_state') {
        parent.target?.serverModel.updateVoiceCallState(evt);
      } else if (name == 'fingerprint') {
        FingerprintState.find(peerId).value = evt['fingerprint'] ?? '';
      } else if (name == 'plugin_manager') {
        pluginManager.handleEvent(evt);
      } else if (name == 'plugin_event') {
        handlePluginEvent(evt,
            (Map<String, dynamic> e) => handleMsgBox(e, sessionId, peerId));
      } else if (name == 'plugin_reload') {
        handleReloading(evt);
      } else if (name == 'plugin_option') {
        handleOption(evt);
      } else if (name == "sync_peer_password_to_ab") {
        if (desktopType == DesktopType.main) {
          final id = evt['id'];
          final password = evt['password'];
          if (id != null && password != null) {
            if (gFFI.abModel
                .changePassword(id.toString(), password.toString())) {
              gFFI.abModel.pushAb(toastIfFail: false, toastIfSucc: false);
            }
          }
        }
      } else if (name == "cm_file_transfer_log") {
        if (isDesktop) {
          gFFI.cmFileModel.onFileTransferLog(evt['log']);
        }
      } else {
        debugPrint('Unknown event name: $name');
      }
    };
  }

  onUrlSchemeReceived(Map<String, dynamic> evt) {
    final url = evt['url'].toString().trim();
    if (url.startsWith(kUniLinksPrefix) && handleUriLink(uriString: url)) {
      return;
    }
    switch (url) {
      case kUrlActionClose:
        debugPrint("closing all instances");
        Future.microtask(() async {
          await rustDeskWinManager.closeAllSubWindows();
          windowManager.close();
        });
        break;
      default:
        windowOnTop(null);
        break;
    }
  }

  /// Bind the event listener to receive events from the Rust core.
  updateEventListener(SessionID sessionId, String peerId) {
    platformFFI.setEventCallback(startEventListener(sessionId, peerId));
  }

  _updateCurDisplay(SessionID sessionId, Display newDisplay) {
    if (newDisplay != _display) {
      if (newDisplay.x != _display.x || newDisplay.y != _display.y) {
        parent.target?.cursorModel
            .updateDisplayOrigin(newDisplay.x, newDisplay.y);
      }
      _display = newDisplay;
      _updateSessionWidthHeight(sessionId);
    }
  }

  handleSwitchDisplay(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    _pi.currentDisplay = int.parse(evt['display']);
    var newDisplay = Display();
    newDisplay.x = double.tryParse(evt['x']) ?? newDisplay.x;
    newDisplay.y = double.tryParse(evt['y']) ?? newDisplay.y;
    newDisplay.width = int.tryParse(evt['width']) ?? newDisplay.width;
    newDisplay.height = int.tryParse(evt['height']) ?? newDisplay.height;
    newDisplay.cursorEmbedded = int.tryParse(evt['cursor_embedded']) == 1;
    newDisplay.originalWidth =
        int.tryParse(evt['original_width']) ?? kInvalidResolutionValue;
    newDisplay.originalHeight =
        int.tryParse(evt['original_height']) ?? kInvalidResolutionValue;

    _updateCurDisplay(sessionId, newDisplay);

    try {
      CurrentDisplayState.find(peerId).value = _pi.currentDisplay;
    } catch (e) {
      //
    }
    parent.target?.recordingModel.onSwitchDisplay();
    handleResolutions(peerId, evt['resolutions']);
    notifyListeners();
  }

  cancelMsgBox(Map<String, dynamic> evt, SessionID sessionId) {
    if (parent.target == null) return;
    final dialogManager = parent.target!.dialogManager;
    final tag = '$sessionId-${evt['tag']}';
    dialogManager.dismissByTag(tag);
  }

  /// Handle the message box event based on [evt] and [id].
  handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    if (parent.target == null) return;
    final dialogManager = parent.target!.dialogManager;
    final type = evt['type'];
    final title = evt['title'];
    final text = evt['text'];
    final link = evt['link'];
    if (type == 're-input-password') {
      wrongPasswordDialog(sessionId, dialogManager, type, title, text);
    } else if (type == 'input-password') {
      enterPasswordDialog(sessionId, dialogManager);
    } else if (type == 'session-login' || type == 'session-re-login') {
      enterUserLoginDialog(sessionId, dialogManager);
    } else if (type == 'session-login-password' ||
        type == 'session-login-password') {
      enterUserLoginAndPasswordDialog(sessionId, dialogManager);
    } else if (type == 'restarting') {
      showMsgBox(sessionId, type, title, text, link, false, dialogManager,
          hasCancel: false);
    } else if (type == 'wait-remote-accept-nook') {
      showWaitAcceptDialog(sessionId, type, title, text, dialogManager);
    } else if (type == 'on-uac' || type == 'on-foreground-elevated') {
      showOnBlockDialog(sessionId, type, title, text, dialogManager);
    } else if (type == 'wait-uac') {
      showWaitUacDialog(sessionId, dialogManager, type);
    } else if (type == 'elevation-error') {
      showElevationError(sessionId, type, title, text, dialogManager);
    } else if (type == 'relay-hint') {
      showRelayHintDialog(sessionId, type, title, text, dialogManager, peerId);
    } else if (text == 'Connected, waiting for image...') {
      showConnectedWaitingForImage(dialogManager, sessionId, type, title, text);
    } else {
      var hasRetry = evt['hasRetry'] == 'true';
      showMsgBox(sessionId, type, title, text, link, hasRetry, dialogManager);
    }
  }

  /// Show a message box with [type], [title] and [text].
  showMsgBox(SessionID sessionId, String type, String title, String text,
      String link, bool hasRetry, OverlayDialogManager dialogManager,
      {bool? hasCancel}) {
    msgBox(sessionId, type, title, text, link, dialogManager,
        hasCancel: hasCancel, reconnect: reconnect);
    _timer?.cancel();
    if (hasRetry) {
      _timer = Timer(Duration(seconds: _reconnects), () {
        reconnect(dialogManager, sessionId, false);
      });
      _reconnects *= 2;
    } else {
      _reconnects = 1;
    }
  }

  void reconnect(OverlayDialogManager dialogManager, SessionID sessionId,
      bool forceRelay) {
    bind.sessionReconnect(sessionId: sessionId, forceRelay: forceRelay);
    clearPermissions();
    dialogManager.showLoading(translate('Connecting...'),
        onCancel: closeConnection);
  }

  void showRelayHintDialog(SessionID sessionId, String type, String title,
      String text, OverlayDialogManager dialogManager, String peerId) {
    dialogManager.show(tag: '$sessionId-$type', (setState, close, context) {
      onClose() {
        closeConnection();
        close();
      }

      final style =
          ElevatedButton.styleFrom(backgroundColor: Colors.green[700]);
      var hint = "\n\n${translate('relay_hint_tip')}";
      if (text.contains("10054") || text.contains("104")) {
        hint = "";
      }
      final alreadyForceAlwaysRelay = bind
          .mainGetPeerOptionSync(id: peerId, key: 'force-always-relay')
          .isNotEmpty;
      return CustomAlertDialog(
        title: null,
        content: msgboxContent(type, title, "${translate(text)}$hint"),
        actions: [
          dialogButton('Close', onPressed: onClose, isOutline: true),
          dialogButton('Retry',
              onPressed: () => reconnect(dialogManager, sessionId, false)),
          if (!alreadyForceAlwaysRelay)
            dialogButton('Connect via relay',
                onPressed: () => reconnect(dialogManager, sessionId, true),
                buttonStyle: style),
        ],
        onCancel: onClose,
      );
    });
  }

  void showConnectedWaitingForImage(OverlayDialogManager dialogManager,
      SessionID sessionId, String type, String title, String text) {
    onClose() {
      closeConnection();
    }

    if (waitForFirstImage.isFalse) return;
    dialogManager.show(
      (setState, close, context) => CustomAlertDialog(
          title: null,
          content: SelectionArea(child: msgboxContent(type, title, text)),
          actions: [
            dialogButton("Cancel", onPressed: onClose, isOutline: true)
          ],
          onCancel: onClose),
      tag: '$sessionId-waiting-for-image',
    );
    waitForImageDialogShow.value = true;
    waitForImageTimer = Timer(Duration(milliseconds: 1500), () {
      if (waitForFirstImage.isTrue) {
        bind.sessionInputOsPassword(sessionId: sessionId, value: '');
      }
    });
    bind.sessionOnWaitingForImageDialogShow(sessionId: sessionId);
  }

  _updateSessionWidthHeight(SessionID sessionId) {
    parent.target?.canvasModel.updateViewStyle();
    if (display.width <= 0 || display.height <= 0) {
      debugPrintStack(
          label: 'invalid display size (${display.width},${display.height})');
    } else {
      bind.sessionSetSize(
          sessionId: sessionId, width: display.width, height: display.height);
    }
  }

  /// Handle the peer info event based on [evt].
  handlePeerInfo(Map<String, dynamic> evt, String peerId) async {
    cachedPeerData.peerInfo = evt;

    // recent peer updated by handle_peer_info(ui_session_interface.rs) --> handle_peer_info(client.rs) --> save_config(client.rs)
    bind.mainLoadRecentPeers();

    parent.target?.dialogManager.dismissAll();
    _pi.version = evt['version'];
    _pi.username = evt['username'];
    _pi.hostname = evt['hostname'];
    _pi.platform = evt['platform'];
    _pi.sasEnabled = evt['sas_enabled'] == 'true';
    _pi.currentDisplay = int.parse(evt['current_display']);

    try {
      CurrentDisplayState.find(peerId).value = _pi.currentDisplay;
    } catch (e) {
      //
    }

    final connType = parent.target?.connType;
    if (isPeerAndroid) {
      _touchMode = true;
    } else {
      _touchMode = await bind.sessionGetOption(
              sessionId: sessionId, arg: 'touch-mode') !=
          '';
    }
    if (connType == ConnType.fileTransfer) {
      parent.target?.fileModel.onReady();
    } else if (connType == ConnType.defaultConn) {
      _pi.displays = [];
      List<dynamic> displays = json.decode(evt['displays']);
      for (int i = 0; i < displays.length; ++i) {
        _pi.displays.add(evtToDisplay(displays[i]));
      }
      stateGlobal.displaysCount.value = _pi.displays.length;
      if (_pi.currentDisplay < _pi.displays.length) {
        _display = _pi.displays[_pi.currentDisplay];
        _updateSessionWidthHeight(sessionId);
      }
      if (displays.isNotEmpty) {
        _reconnects = 1;
        waitForFirstImage.value = true;
      }
      Map<String, dynamic> features = json.decode(evt['features']);
      _pi.features.privacyMode = features['privacy_mode'] == 1;
      handleResolutions(peerId, evt["resolutions"]);
      parent.target?.elevationModel.onPeerInfo(_pi);
    }
    if (connType == ConnType.defaultConn) {
      setViewOnly(
          peerId,
          bind.sessionGetToggleOptionSync(
              sessionId: sessionId, arg: 'view-only'));
    }
    if (connType == ConnType.defaultConn) {
      final platform_additions = evt['platform_additions'];
      if (platform_additions != null && platform_additions != '') {
        try {
          _pi.platform_additions = json.decode(platform_additions);
        } catch (e) {
          debugPrint('Failed to decode platform_additions $e');
        }
      }
    }

    _pi.isSet.value = true;
    stateGlobal.resetLastResolutionGroupValues(peerId);

    notifyListeners();
  }

  tryShowAndroidActionsOverlay({int delayMSecs = 10}) {
    if (isPeerAndroid) {
      if (parent.target?.connType == ConnType.defaultConn &&
          parent.target != null &&
          parent.target!.ffiModel.permissions['keyboard'] != false) {
        Timer(
            Duration(milliseconds: delayMSecs),
            () => parent.target!.dialogManager
                .showMobileActionsOverlay(ffi: parent.target!));
      }
    }
  }

  handleResolutions(String id, dynamic resolutions) {
    try {
      final List<dynamic> dynamicArray = jsonDecode(resolutions as String);
      List<Resolution> arr = List.empty(growable: true);
      for (int i = 0; i < dynamicArray.length; i++) {
        var width = dynamicArray[i]["width"];
        var height = dynamicArray[i]["height"];
        if (width is int && width > 0 && height is int && height > 0) {
          arr.add(Resolution(width, height));
        }
      }
      arr.sort((a, b) {
        if (b.width != a.width) {
          return b.width - a.width;
        } else {
          return b.height - a.height;
        }
      });
      _pi.resolutions = arr;
    } catch (e) {
      debugPrint("Failed to parse resolutions:$e");
    }
  }

  Display evtToDisplay(Map<String, dynamic> evt) {
    var d = Display();
    d.x = evt['x']?.toDouble() ?? d.x;
    d.y = evt['y']?.toDouble() ?? d.y;
    d.width = evt['width'] ?? d.width;
    d.height = evt['height'] ?? d.height;
    d.cursorEmbedded = evt['cursor_embedded'] == 1;
    d.originalWidth = evt['original_width'] ?? kInvalidResolutionValue;
    d.originalHeight = evt['original_height'] ?? kInvalidResolutionValue;
    return d;
  }

  updateLastCursorId(Map<String, dynamic> evt) {
    parent.target?.cursorModel.id = int.parse(evt['id']);
  }

  handleCursorId(Map<String, dynamic> evt) {
    cachedPeerData.lastCursorId = evt;
    parent.target?.cursorModel.updateCursorId(evt);
  }

  handleCursorData(Map<String, dynamic> evt) async {
    cachedPeerData.cursorDataList.add(evt);
    await parent.target?.cursorModel.updateCursorData(evt);
  }

  /// Handle the peer info synchronization event based on [evt].
  handleSyncPeerInfo(Map<String, dynamic> evt, SessionID sessionId) async {
    if (evt['displays'] != null) {
      cachedPeerData.peerInfo['displays'] = evt['displays'];
      List<dynamic> displays = json.decode(evt['displays']);
      List<Display> newDisplays = [];
      for (int i = 0; i < displays.length; ++i) {
        newDisplays.add(evtToDisplay(displays[i]));
      }
      _pi.displays = newDisplays;
      stateGlobal.displaysCount.value = _pi.displays.length;
      if (_pi.currentDisplay >= 0 && _pi.currentDisplay < _pi.displays.length) {
        _updateCurDisplay(sessionId, _pi.displays[_pi.currentDisplay]);
      }
    }
    notifyListeners();
  }

  updateBlockInputState(Map<String, dynamic> evt, String peerId) {
    _inputBlocked = evt['input_state'] == 'on';
    notifyListeners();
    try {
      BlockInputState.find(peerId).value = evt['input_state'] == 'on';
    } catch (e) {
      //
    }
  }

  updatePrivacyMode(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    notifyListeners();
    try {
      PrivacyModeState.find(peerId).value = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'privacy-mode');
    } catch (e) {
      //
    }
  }

  void setViewOnly(String id, bool value) {
    if (version_cmp(_pi.version, '1.2.0') < 0) return;
    // tmp fix for https://github.com/rustdesk/rustdesk/pull/3706#issuecomment-1481242389
    // because below rx not used in mobile version, so not initialized, below code will cause crash
    // current our flutter code quality is fucking shit now. !!!!!!!!!!!!!!!!
    try {
      if (value) {
        ShowRemoteCursorState.find(id).value = value;
      } else {
        ShowRemoteCursorState.find(id).value = bind.sessionGetToggleOptionSync(
            sessionId: sessionId, arg: 'show-remote-cursor');
      }
    } catch (e) {
      //
    }
    if (_viewOnly != value) {
      _viewOnly = value;
      notifyListeners();
    }
  }
}

class ImageModel with ChangeNotifier {
  ui.Image? _image;

  ui.Image? get image => _image;

  String id = '';

  late final SessionID sessionId;

  WeakReference<FFI> parent;

  final List<Function(String)> callbacksOnFirstImage = [];

  ImageModel(this.parent) {
    sessionId = parent.target!.sessionId;
  }

  addCallbackOnFirstImage(Function(String) cb) => callbacksOnFirstImage.add(cb);

  onRgba(Uint8List rgba) {
    final pid = parent.target?.id;
    img.decodeImageFromPixels(
        rgba,
        parent.target?.ffiModel.display.width ?? 0,
        parent.target?.ffiModel.display.height ?? 0,
        isWeb ? ui.PixelFormat.rgba8888 : ui.PixelFormat.bgra8888,
        onPixelsCopied: () {
      // Unlock the rgba memory from rust codes.
      platformFFI.nextRgba(sessionId);
    }).then((image) {
      if (parent.target?.id != pid) return;
      try {
        // my throw exception, because the listener maybe already dispose
        update(image);
      } catch (e) {
        debugPrint('update image: $e');
      }
    });
  }

  update(ui.Image? image) async {
    if (_image == null && image != null) {
      if (isWebDesktop || isDesktop) {
        await parent.target?.canvasModel.updateViewStyle();
        await parent.target?.canvasModel.updateScrollStyle();
      } else {
        final size = MediaQueryData.fromWindow(ui.window).size;
        final canvasWidth = size.width;
        final canvasHeight = size.height;
        final xscale = canvasWidth / image.width;
        final yscale = canvasHeight / image.height;
        parent.target?.canvasModel.scale = min(xscale, yscale);
      }
      if (parent.target != null) {
        await initializeCursorAndCanvas(parent.target!);
      }
      if (parent.target?.ffiModel.isPeerAndroid ?? false) {
        bind.sessionSetViewStyle(sessionId: sessionId, value: 'adaptive');
        parent.target?.canvasModel.updateViewStyle();
      }
    }
    _image = image;
    if (image != null) notifyListeners();
  }

  // mobile only
  // for desktop, height should minus tabbar height
  double get maxScale {
    if (_image == null) return 1.5;
    final size = MediaQueryData.fromWindow(ui.window).size;
    final xscale = size.width / _image!.width;
    final yscale = size.height / _image!.height;
    return max(1.5, max(xscale, yscale));
  }

  // mobile only
  // for desktop, height should minus tabbar height
  double get minScale {
    if (_image == null) return 1.5;
    final size = MediaQueryData.fromWindow(ui.window).size;
    final xscale = size.width / _image!.width;
    final yscale = size.height / _image!.height;
    return min(xscale, yscale) / 1.5;
  }
}

enum ScrollStyle {
  scrollbar,
  scrollauto,
}

class ViewStyle {
  final String style;
  final double width;
  final double height;
  final int displayWidth;
  final int displayHeight;
  ViewStyle({
    required this.style,
    required this.width,
    required this.height,
    required this.displayWidth,
    required this.displayHeight,
  });

  static defaultViewStyle() {
    final desktop = (isDesktop || isWebDesktop);
    final w =
        desktop ? kDesktopDefaultDisplayWidth : kMobileDefaultDisplayWidth;
    final h =
        desktop ? kDesktopDefaultDisplayHeight : kMobileDefaultDisplayHeight;
    return ViewStyle(
      style: '',
      width: w.toDouble(),
      height: h.toDouble(),
      displayWidth: w,
      displayHeight: h,
    );
  }

  static int _double2Int(double v) => (v * 100).round().toInt();

  @override
  bool operator ==(Object other) =>
      other is ViewStyle &&
      other.runtimeType == runtimeType &&
      _innerEqual(other);

  bool _innerEqual(ViewStyle other) {
    return style == other.style &&
        ViewStyle._double2Int(other.width) == ViewStyle._double2Int(width) &&
        ViewStyle._double2Int(other.height) == ViewStyle._double2Int(height) &&
        other.displayWidth == displayWidth &&
        other.displayHeight == displayHeight;
  }

  @override
  int get hashCode => Object.hash(
        style,
        ViewStyle._double2Int(width),
        ViewStyle._double2Int(height),
        displayWidth,
        displayHeight,
      ).hashCode;

  double get scale {
    double s = 1.0;
    if (style == kRemoteViewStyleAdaptive) {
      if (width != 0 &&
          height != 0 &&
          displayWidth != 0 &&
          displayHeight != 0) {
        final s1 = width / displayWidth;
        final s2 = height / displayHeight;
        s = s1 < s2 ? s1 : s2;
      }
    }
    return s;
  }
}

class CanvasModel with ChangeNotifier {
  // image offset of canvas
  double _x = 0;
  // image offset of canvas
  double _y = 0;
  // image scale
  double _scale = 1.0;
  double _devicePixelRatio = 1.0;
  Size _size = Size.zero;
  // the tabbar over the image
  // double tabBarHeight = 0.0;
  // the window border's width
  // double windowBorderWidth = 0.0;
  // remote id
  String id = '';
  late final SessionID sessionId;
  // scroll offset x percent
  double _scrollX = 0.0;
  // scroll offset y percent
  double _scrollY = 0.0;
  ScrollStyle _scrollStyle = ScrollStyle.scrollauto;
  ViewStyle _lastViewStyle = ViewStyle.defaultViewStyle();

  final _imageOverflow = false.obs;

  WeakReference<FFI> parent;

  CanvasModel(this.parent) {
    sessionId = parent.target!.sessionId;
  }

  double get x => _x;
  double get y => _y;
  double get scale => _scale;
  double get devicePixelRatio => _devicePixelRatio;
  Size get size => _size;
  ScrollStyle get scrollStyle => _scrollStyle;
  ViewStyle get viewStyle => _lastViewStyle;
  RxBool get imageOverflow => _imageOverflow;

  _resetScroll() => setScrollPercent(0.0, 0.0);

  setScrollPercent(double x, double y) {
    _scrollX = x;
    _scrollY = y;
  }

  double get scrollX => _scrollX;
  double get scrollY => _scrollY;

  static double get leftToEdge => (isDesktop || isWebDesktop)
      ? windowBorderWidth + kDragToResizeAreaPadding.left
      : 0;
  static double get rightToEdge => (isDesktop || isWebDesktop)
      ? windowBorderWidth + kDragToResizeAreaPadding.right
      : 0;
  static double get topToEdge => (isDesktop || isWebDesktop)
      ? tabBarHeight + windowBorderWidth + kDragToResizeAreaPadding.top
      : 0;
  static double get bottomToEdge => (isDesktop || isWebDesktop)
      ? windowBorderWidth + kDragToResizeAreaPadding.bottom
      : 0;

  updateViewStyle() async {
    Size getSize() {
      final size = MediaQueryData.fromWindow(ui.window).size;
      // If minimized, w or h may be negative here.
      double w = size.width - leftToEdge - rightToEdge;
      double h = size.height - topToEdge - bottomToEdge;
      return Size(w < 0 ? 0 : w, h < 0 ? 0 : h);
    }

    final style = await bind.sessionGetViewStyle(sessionId: sessionId);
    if (style == null) {
      return;
    }

    _size = getSize();
    final displayWidth = getDisplayWidth();
    final displayHeight = getDisplayHeight();
    final viewStyle = ViewStyle(
      style: style,
      width: size.width,
      height: size.height,
      displayWidth: displayWidth,
      displayHeight: displayHeight,
    );
    if (_lastViewStyle == viewStyle) {
      return;
    }
    if (_lastViewStyle.style != viewStyle.style) {
      _resetScroll();
    }
    _lastViewStyle = viewStyle;
    _scale = viewStyle.scale;

    _devicePixelRatio = ui.window.devicePixelRatio;
    if (kIgnoreDpi && style == kRemoteViewStyleOriginal) {
      _scale = 1.0 / _devicePixelRatio;
    }
    _x = (size.width - displayWidth * _scale) / 2;
    _y = (size.height - displayHeight * _scale) / 2;
    _imageOverflow.value = _x < 0 || y < 0;
    notifyListeners();
    parent.target?.inputModel.refreshMousePos();
  }

  updateScrollStyle() async {
    final style = await bind.sessionGetScrollStyle(sessionId: sessionId);
    if (style == kRemoteScrollStyleBar) {
      _scrollStyle = ScrollStyle.scrollbar;
      _resetScroll();
    } else {
      _scrollStyle = ScrollStyle.scrollauto;
    }
    notifyListeners();
  }

  update(double x, double y, double scale) {
    _x = x;
    _y = y;
    _scale = scale;
    notifyListeners();
  }

  bool get cursorEmbedded =>
      parent.target?.ffiModel.display.cursorEmbedded ?? false;

  int getDisplayWidth() {
    final defaultWidth = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayWidth
        : kMobileDefaultDisplayWidth;
    return parent.target?.ffiModel.display.width ?? defaultWidth;
  }

  int getDisplayHeight() {
    final defaultHeight = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayHeight
        : kMobileDefaultDisplayHeight;
    return parent.target?.ffiModel.display.height ?? defaultHeight;
  }

  static double get windowBorderWidth => stateGlobal.windowBorderWidth.value;
  static double get tabBarHeight => stateGlobal.tabBarHeight;

  moveDesktopMouse(double x, double y) {
    if (size.width == 0 || size.height == 0) {
      return;
    }

    // On mobile platforms, move the canvas with the cursor.
    final dw = getDisplayWidth() * _scale;
    final dh = getDisplayHeight() * _scale;
    var dxOffset = 0;
    var dyOffset = 0;
    try {
      if (dw > size.width) {
        dxOffset = (x - dw * (x / size.width) - _x).toInt();
      }
      if (dh > size.height) {
        dyOffset = (y - dh * (y / size.height) - _y).toInt();
      }
    } catch (e) {
      debugPrintStack(
          label:
              '(x,y) ($x,$y), (_x,_y) ($_x,$_y), _scale $_scale, display size (${getDisplayWidth()},${getDisplayHeight()}), size $size, , $e');
      return;
    }

    _x += dxOffset;
    _y += dyOffset;
    if (dxOffset != 0 || dyOffset != 0) {
      notifyListeners();
    }

    // If keyboard is not permitted, do not move cursor when mouse is moving.
    if (parent.target != null && parent.target!.ffiModel.keyboard) {
      // Draw cursor if is not desktop.
      if (!isDesktop) {
        parent.target!.cursorModel.moveLocal(x, y);
      } else {
        try {
          RemoteCursorMovedState.find(id).value = false;
        } catch (e) {
          //
        }
      }
    }
  }

  set scale(v) {
    _scale = v;
    notifyListeners();
  }

  panX(double dx) {
    _x += dx;
    notifyListeners();
  }

  resetOffset() {
    if (isWebDesktop) {
      updateViewStyle();
    } else {
      _x = (size.width - getDisplayWidth() * _scale) / 2;
      _y = (size.height - getDisplayHeight() * _scale) / 2;
    }
    notifyListeners();
  }

  panY(double dy) {
    _y += dy;
    notifyListeners();
  }

  updateScale(double v) {
    if (parent.target?.imageModel.image == null) return;
    final offset = parent.target?.cursorModel.offset ?? const Offset(0, 0);
    var r = parent.target?.cursorModel.getVisibleRect() ?? Rect.zero;
    final px0 = (offset.dx - r.left) * _scale;
    final py0 = (offset.dy - r.top) * _scale;
    _scale *= v;
    final maxs = parent.target?.imageModel.maxScale ?? 1;
    final mins = parent.target?.imageModel.minScale ?? 1;
    if (_scale > maxs) _scale = maxs;
    if (_scale < mins) _scale = mins;
    r = parent.target?.cursorModel.getVisibleRect() ?? Rect.zero;
    final px1 = (offset.dx - r.left) * _scale;
    final py1 = (offset.dy - r.top) * _scale;
    _x -= px1 - px0;
    _y -= py1 - py0;
    notifyListeners();
  }

  clear([bool notify = false]) {
    _x = 0;
    _y = 0;
    _scale = 1.0;
    if (notify) notifyListeners();
  }
}

// data for cursor
class CursorData {
  final String peerId;
  final int id;
  final img2.Image image;
  double scale;
  Uint8List? data;
  final double hotxOrigin;
  final double hotyOrigin;
  double hotx;
  double hoty;
  final int width;
  final int height;

  CursorData({
    required this.peerId,
    required this.id,
    required this.image,
    required this.scale,
    required this.data,
    required this.hotxOrigin,
    required this.hotyOrigin,
    required this.width,
    required this.height,
  })  : hotx = hotxOrigin * scale,
        hoty = hotxOrigin * scale;

  int _doubleToInt(double v) => (v * 10e6).round().toInt();

  double _checkUpdateScale(double scale) {
    double oldScale = this.scale;
    if (scale != 1.0) {
      // Update data if scale changed.
      final tgtWidth = (width * scale).toInt();
      final tgtHeight = (width * scale).toInt();
      if (tgtWidth < kMinCursorSize || tgtHeight < kMinCursorSize) {
        double sw = kMinCursorSize.toDouble() / width;
        double sh = kMinCursorSize.toDouble() / height;
        scale = sw < sh ? sh : sw;
      }
    }

    if (_doubleToInt(oldScale) != _doubleToInt(scale)) {
      if (Platform.isWindows) {
        data = img2
            .copyResize(
              image,
              width: (width * scale).toInt(),
              height: (height * scale).toInt(),
              interpolation: img2.Interpolation.average,
            )
            .getBytes(order: img2.ChannelOrder.bgra);
      } else {
        data = Uint8List.fromList(
          img2.encodePng(
            img2.copyResize(
              image,
              width: (width * scale).toInt(),
              height: (height * scale).toInt(),
              interpolation: img2.Interpolation.average,
            ),
          ),
        );
      }
    }

    this.scale = scale;
    hotx = hotxOrigin * scale;
    hoty = hotyOrigin * scale;
    return scale;
  }

  String updateGetKey(double scale) {
    scale = _checkUpdateScale(scale);
    return '${peerId}_${id}_${_doubleToInt(width * scale)}_${_doubleToInt(height * scale)}';
  }
}

const _forbiddenCursorPng =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAkZQTFRFAAAA2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4GWAwCAAAAAAAA2B4GAAAAMTExAAAAAAAA2B4G2B4G2B4GAAAAmZmZkZGRAQEBAAAA2B4G2B4G2B4G////oKCgAwMDag8D2B4G2B4G2B4Gra2tBgYGbg8D2B4G2B4Gubm5CQkJTwsCVgwC2B4GxcXFDg4OAAAAAAAA2B4G2B4Gz8/PFBQUAAAAAAAA2B4G2B4G2B4G2B4G2B4G2B4G2B4GDgIA2NjYGxsbAAAAAAAA2B4GFwMB4eHhIyMjAAAAAAAA2B4G6OjoLCwsAAAAAAAA2B4G2B4G2B4G2B4G2B4GCQEA4ODgv7+/iYmJY2NjAgICAAAA9PT0Ojo6AAAAAAAAAAAA+/v7SkpKhYWFr6+vAAAAAAAA8/PzOTk5ERER9fX1KCgoAAAAgYGBKioqAAAAAAAApqamlpaWAAAAAAAAAAAAAAAAAAAAAAAALi4u/v7+GRkZAAAAAAAAAAAAAAAAAAAAfn5+AAAAAAAAV1dXkJCQAAAAAAAAAQEBAAAAAAAAAAAA7Hz6BAAAAMJ0Uk5TAAIWEwEynNz6//fVkCAatP2fDUHs6cDD8d0mPfT5fiEskiIR584A0gejr3AZ+P4plfALf5ZiTL85a4ziD6697fzN3UYE4v/4TwrNHuT///tdRKZh///+1U/ZBv///yjb///eAVL//50Cocv//6oFBbPvpGZCbfT//7cIhv///8INM///zBEcWYSZmO7//////1P////ts/////8vBv//////gv//R/z///QQz9sevP///2waXhNO/+fc//8mev/5gAe2r90MAAAByUlEQVR4nGNggANGJmYWBpyAlY2dg5OTi5uHF6s0H78AJxRwCAphyguLgKRExcQlQLSkFLq8tAwnp6ycPNABjAqKQKNElVDllVU4OVVhVquJA81Q10BRoAkUUYbJa4Edoo0sr6PLqaePLG/AyWlohKTAmJPTBFnelAFoixmSAnNOTgsUeQZLTk4rJAXWnJw2EHlbiDyDPCenHZICe04HFrh+RydnBgYWPU5uJAWinJwucPNd3dw9GDw5Ob2QFHBzcnrD7ffx9fMPCOTkDEINhmC4+3x8Q0LDwlEDIoKTMzIKKg9SEBIdE8sZh6SAJZ6Tkx0qD1YQkpCYlIwclCng0AXLQxSEpKalZyCryATKZwkhKQjJzsnNQ1KQXwBUUVhUXBJYWgZREFJeUVmFpMKlWg+anmqgCkJq6+obkG1pLEBTENLU3NKKrIKhrb2js8u4G6Kgpze0r3/CRAZMAHbkpJDJU6ZMmTqtFbuC6TNmhsyaMnsOFlmwgrnzpsxfELJwEXZ5Bp/FS3yWLlsesmLlKuwKVk9Ys5Zh3foN0zduwq5g85atDAzbpqSGbN9RhV0FGOzctWH3lD14FOzdt3H/gQw8Cg4u2gQPAwBYDXXdIH+wqAAAAABJRU5ErkJggg==';
const _defaultCursorPng =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARzQklUCAgICHwIZIgAAAFmSURBVFiF7dWxSlxREMbx34QFDRowYBchZSxSCWlMCOwD5FGEFHap06UI7KPsAyyEEIQFqxRaCqYTsqCJFsKkuAeRXb17wrqV918dztw55zszc2fo6Oh47MR/e3zO1/iAHWmznHKGQwx9ip/LEbCfazbsoY8j/JLOhcC6sCW9wsjEwJf483AC9nPNc1+lFRwI13d+l3rYFS799rFGxJMqARv2pBXh+72XQ7gWvklPS7TmMl9Ak/M+DqrENvxAv/guKKApuKPWl0/TROK4+LbSqzhuB+OZ3fRSeFPWY+Fkyn56Y29hfgTSpnQ+s98cvorVey66uPlNFxKwZOYLCGfCs5n9NMYVrsp6mvXSoFqpqYFDvMBkStgJJe93dZOwVXxbqUnBENulydSReqUrDhcX0PT2EXarBYS3GNXMhboinBgIl9K71kg0L3+PvyYGdVpruT2MwrF0iotiXfIwus0Dj+OOjo6Of+e7ab74RkpgAAAAAElFTkSuQmCC';

final preForbiddenCursor = PredefinedCursor(
  png: _forbiddenCursorPng,
  id: -2,
);
final preDefaultCursor = PredefinedCursor(
  png: _defaultCursorPng,
  id: -1,
  hotxGetter: (double w) => w / 2,
  hotyGetter: (double h) => h / 2,
);

class PredefinedCursor {
  ui.Image? _image;
  img2.Image? _image2;
  CursorData? _cache;
  String png;
  int id;
  double Function(double)? hotxGetter;
  double Function(double)? hotyGetter;

  PredefinedCursor(
      {required this.png, required this.id, this.hotxGetter, this.hotyGetter}) {
    init();
  }

  ui.Image? get image => _image;
  CursorData? get cache => _cache;

  init() {
    _image2 = img2.decodePng(base64Decode(png));
    if (_image2 != null) {
      () async {
        final defaultImg = _image2!;
        // This function is called only one time, no need to care about the performance.
        Uint8List data = defaultImg.getBytes(order: img2.ChannelOrder.rgba);
        _image = await img.decodeImageFromPixels(
            data, defaultImg.width, defaultImg.height, ui.PixelFormat.rgba8888);

        double scale = 1.0;
        if (Platform.isWindows) {
          data = _image2!.getBytes(order: img2.ChannelOrder.bgra);
        } else {
          data = Uint8List.fromList(img2.encodePng(_image2!));
        }

        _cache = CursorData(
          peerId: '',
          id: id,
          image: _image2!.clone(),
          scale: scale,
          data: data,
          hotxOrigin:
              hotxGetter != null ? hotxGetter!(_image2!.width.toDouble()) : 0,
          hotyOrigin:
              hotyGetter != null ? hotyGetter!(_image2!.height.toDouble()) : 0,
          width: _image2!.width,
          height: _image2!.height,
        );
      }();
    }
  }
}

class CursorModel with ChangeNotifier {
  ui.Image? _image;
  final _images = <int, Tuple3<ui.Image, double, double>>{};
  CursorData? _cache;
  final _cacheMap = <int, CursorData>{};
  final _cacheKeys = <String>{};
  double _x = -10000;
  double _y = -10000;
  int _id = -1;
  double _hotx = 0;
  double _hoty = 0;
  double _displayOriginX = 0;
  double _displayOriginY = 0;
  DateTime? _firstUpdateMouseTime;
  bool gotMouseControl = true;
  DateTime _lastPeerMouse = DateTime.now()
      .subtract(Duration(milliseconds: 3000 * kMouseControlTimeoutMSec));
  String peerId = '';
  WeakReference<FFI> parent;

  ui.Image? get image => _image;
  CursorData? get cache => _cache;

  double get x => _x - _displayOriginX;
  double get y => _y - _displayOriginY;

  Offset get offset => Offset(_x, _y);

  double get hotx => _hotx;
  double get hoty => _hoty;

  set id(int id) => _id = id;

  bool get isPeerControlProtected =>
      DateTime.now().difference(_lastPeerMouse).inMilliseconds <
      kMouseControlTimeoutMSec;

  bool isConnIn2Secs() {
    if (_firstUpdateMouseTime == null) {
      _firstUpdateMouseTime = DateTime.now();
      return true;
    } else {
      return DateTime.now().difference(_firstUpdateMouseTime!).inSeconds < 2;
    }
  }

  CursorModel(this.parent);

  Set<String> get cachedKeys => _cacheKeys;
  addKey(String key) => _cacheKeys.add(key);

  // remote physical display coordinate
  Rect getVisibleRect() {
    final size = MediaQueryData.fromWindow(ui.window).size;
    final xoffset = parent.target?.canvasModel.x ?? 0;
    final yoffset = parent.target?.canvasModel.y ?? 0;
    final scale = parent.target?.canvasModel.scale ?? 1;
    final x0 = _displayOriginX - xoffset / scale;
    final y0 = _displayOriginY - yoffset / scale;
    return Rect.fromLTWH(x0, y0, size.width / scale, size.height / scale);
  }

  double adjustForKeyboard() {
    final m = MediaQueryData.fromWindow(ui.window);
    var keyboardHeight = m.viewInsets.bottom;
    final size = m.size;
    if (keyboardHeight < 100) return 0;
    final s = parent.target?.canvasModel.scale ?? 1.0;
    final thresh = (size.height - keyboardHeight) / 2;
    var h = (_y - getVisibleRect().top) * s; // local physical display height
    return h - thresh;
  }

  move(double x, double y) {
    moveLocal(x, y);
    parent.target?.inputModel.moveMouse(_x, _y);
  }

  moveLocal(double x, double y) {
    final scale = parent.target?.canvasModel.scale ?? 1.0;
    final xoffset = parent.target?.canvasModel.x ?? 0;
    final yoffset = parent.target?.canvasModel.y ?? 0;
    _x = (x - xoffset) / scale + _displayOriginX;
    _y = (y - yoffset) / scale + _displayOriginY;
    notifyListeners();
  }

  reset() {
    _x = _displayOriginX;
    _y = _displayOriginY;
    parent.target?.inputModel.moveMouse(_x, _y);
    parent.target?.canvasModel.clear(true);
    notifyListeners();
  }

  updatePan(double dx, double dy, bool touchMode) {
    if (touchMode) {
      final scale = parent.target?.canvasModel.scale ?? 1.0;
      _x += dx / scale;
      _y += dy / scale;
      parent.target?.inputModel.moveMouse(_x, _y);
      notifyListeners();
      return;
    }
    if (parent.target?.imageModel.image == null) return;
    final scale = parent.target?.canvasModel.scale ?? 1.0;
    dx /= scale;
    dy /= scale;
    final r = getVisibleRect();
    var cx = r.center.dx;
    var cy = r.center.dy;
    var tryMoveCanvasX = false;
    if (dx > 0) {
      final maxCanvasCanMove = _displayOriginX +
          (parent.target?.imageModel.image!.width ?? 1280) -
          r.right.roundToDouble();
      tryMoveCanvasX = _x + dx > cx && maxCanvasCanMove > 0;
      if (tryMoveCanvasX) {
        dx = min(dx, maxCanvasCanMove);
      } else {
        final maxCursorCanMove = r.right - _x;
        dx = min(dx, maxCursorCanMove);
      }
    } else if (dx < 0) {
      final maxCanvasCanMove = _displayOriginX - r.left.roundToDouble();
      tryMoveCanvasX = _x + dx < cx && maxCanvasCanMove < 0;
      if (tryMoveCanvasX) {
        dx = max(dx, maxCanvasCanMove);
      } else {
        final maxCursorCanMove = r.left - _x;
        dx = max(dx, maxCursorCanMove);
      }
    }
    var tryMoveCanvasY = false;
    if (dy > 0) {
      final mayCanvasCanMove = _displayOriginY +
          (parent.target?.imageModel.image!.height ?? 720) -
          r.bottom.roundToDouble();
      tryMoveCanvasY = _y + dy > cy && mayCanvasCanMove > 0;
      if (tryMoveCanvasY) {
        dy = min(dy, mayCanvasCanMove);
      } else {
        final mayCursorCanMove = r.bottom - _y;
        dy = min(dy, mayCursorCanMove);
      }
    } else if (dy < 0) {
      final mayCanvasCanMove = _displayOriginY - r.top.roundToDouble();
      tryMoveCanvasY = _y + dy < cy && mayCanvasCanMove < 0;
      if (tryMoveCanvasY) {
        dy = max(dy, mayCanvasCanMove);
      } else {
        final mayCursorCanMove = r.top - _y;
        dy = max(dy, mayCursorCanMove);
      }
    }

    if (dx == 0 && dy == 0) return;
    _x += dx;
    _y += dy;
    if (tryMoveCanvasX && dx != 0) {
      parent.target?.canvasModel.panX(-dx);
    }
    if (tryMoveCanvasY && dy != 0) {
      parent.target?.canvasModel.panY(-dy);
    }

    parent.target?.inputModel.moveMouse(_x, _y);
    notifyListeners();
  }

  updateCursorData(Map<String, dynamic> evt) async {
    final id = int.parse(evt['id']);
    final hotx = double.parse(evt['hotx']);
    final hoty = double.parse(evt['hoty']);
    final width = int.parse(evt['width']);
    final height = int.parse(evt['height']);
    List<dynamic> colors = json.decode(evt['colors']);
    final rgba = Uint8List.fromList(colors.map((s) => s as int).toList());
    final image = await img.decodeImageFromPixels(
        rgba, width, height, ui.PixelFormat.rgba8888);
    if (await _updateCache(rgba, image, id, hotx, hoty, width, height)) {
      _images[id] = Tuple3(image, hotx, hoty);
    }

    // Update last cursor data.
    // Do not use the previous `image` and `id`, because `_id` may be changed.
    _updateCurData();
  }

  Future<bool> _updateCache(
    Uint8List rgba,
    ui.Image image,
    int id,
    double hotx,
    double hoty,
    int w,
    int h,
  ) async {
    Uint8List? data;
    img2.Image imgOrigin = img2.Image.fromBytes(
        width: w, height: h, bytes: rgba.buffer, order: img2.ChannelOrder.rgba);
    if (Platform.isWindows) {
      data = imgOrigin.getBytes(order: img2.ChannelOrder.bgra);
    } else {
      ByteData? imgBytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (imgBytes == null) {
        return false;
      }
      data = imgBytes.buffer.asUint8List();
    }
    final cache = CursorData(
      peerId: peerId,
      id: id,
      image: imgOrigin,
      scale: 1.0,
      data: data,
      hotxOrigin: hotx,
      hotyOrigin: hoty,
      width: w,
      height: h,
    );
    _cacheMap[id] = cache;
    return true;
  }

  bool _updateCurData() {
    _cache = _cacheMap[_id];
    final tmp = _images[_id];
    if (tmp != null) {
      _image = tmp.item1;
      _hotx = tmp.item2;
      _hoty = tmp.item3;
      try {
        // may throw exception, because the listener maybe already dispose
        notifyListeners();
      } catch (e) {
        debugPrint(
            'WARNING: updateCursorId $_id, without notifyListeners(). $e');
      }
      return true;
    } else {
      return false;
    }
  }

  updateCursorId(Map<String, dynamic> evt) {
    if (!_updateCurData()) {
      debugPrint(
          'WARNING: updateCursorId $_id, cache is ${_cache == null ? "null" : "not null"}. without notifyListeners()');
    }
  }

  /// Update the cursor position.
  updateCursorPosition(Map<String, dynamic> evt, String id) async {
    if (!isConnIn2Secs()) {
      gotMouseControl = false;
      _lastPeerMouse = DateTime.now();
    }
    _x = double.parse(evt['x']);
    _y = double.parse(evt['y']);
    try {
      RemoteCursorMovedState.find(id).value = true;
    } catch (e) {
      //
    }
    notifyListeners();
  }

  updateDisplayOrigin(double x, double y) {
    _displayOriginX = x;
    _displayOriginY = y;
    _x = x + 1;
    _y = y + 1;
    parent.target?.inputModel.moveMouse(x, y);
    parent.target?.canvasModel.resetOffset();
    notifyListeners();
  }

  updateDisplayOriginWithCursor(
      double x, double y, double xCursor, double yCursor) {
    _displayOriginX = x;
    _displayOriginY = y;
    _x = xCursor;
    _y = yCursor;
    parent.target?.inputModel.moveMouse(x, y);
    notifyListeners();
  }

  clear() {
    _x = -10000;
    _x = -10000;
    _image = null;
    _images.clear();

    _clearCache();
    _cache = null;
    _cacheMap.clear();
  }

  _clearCache() {
    final keys = {...cachedKeys};
    for (var k in keys) {
      debugPrint("deleting cursor with key $k");
      CursorManager.instance.deleteCursor(k);
    }
  }
}

class QualityMonitorData {
  String? speed;
  String? fps;
  String? delay;
  String? targetBitrate;
  String? codecFormat;
}

class QualityMonitorModel with ChangeNotifier {
  WeakReference<FFI> parent;

  QualityMonitorModel(this.parent);
  var _show = false;
  final _data = QualityMonitorData();

  bool get show => _show;
  QualityMonitorData get data => _data;

  checkShowQualityMonitor(SessionID sessionId) async {
    final show = await bind.sessionGetToggleOption(
            sessionId: sessionId, arg: 'show-quality-monitor') ==
        true;
    if (_show != show) {
      _show = show;
      notifyListeners();
    }
  }

  updateQualityStatus(Map<String, dynamic> evt) {
    try {
      if ((evt['speed'] as String).isNotEmpty) _data.speed = evt['speed'];
      if ((evt['fps'] as String).isNotEmpty) _data.fps = evt['fps'];
      if ((evt['delay'] as String).isNotEmpty) _data.delay = evt['delay'];
      if ((evt['target_bitrate'] as String).isNotEmpty) {
        _data.targetBitrate = evt['target_bitrate'];
      }
      if ((evt['codec_format'] as String).isNotEmpty) {
        _data.codecFormat = evt['codec_format'];
      }
      notifyListeners();
    } catch (e) {
      //
    }
  }
}

class RecordingModel with ChangeNotifier {
  WeakReference<FFI> parent;
  RecordingModel(this.parent);
  bool _start = false;
  get start => _start;

  onSwitchDisplay() {
    if (isIOS || !_start) return;
    final sessionId = parent.target?.sessionId;
    int? width = parent.target?.canvasModel.getDisplayWidth();
    int? height = parent.target?.canvasModel.getDisplayHeight();
    if (sessionId == null || width == null || height == null) return;
    bind.sessionRecordScreen(
        sessionId: sessionId, start: true, width: width, height: height);
  }

  toggle() async {
    if (isIOS) return;
    final sessionId = parent.target?.sessionId;
    if (sessionId == null) return;
    _start = !_start;
    notifyListeners();
    await bind.sessionRecordStatus(sessionId: sessionId, status: _start);
    if (_start) {
      bind.sessionRefresh(sessionId: sessionId);
    } else {
      bind.sessionRecordScreen(
          sessionId: sessionId, start: false, width: 0, height: 0);
    }
  }

  onClose() {
    if (isIOS) return;
    final sessionId = parent.target?.sessionId;
    if (sessionId == null) return;
    _start = false;
    bind.sessionRecordScreen(
        sessionId: sessionId, start: false, width: 0, height: 0);
  }
}

class ElevationModel with ChangeNotifier {
  WeakReference<FFI> parent;
  ElevationModel(this.parent);
  bool _running = false;
  bool _canElevate = false;
  bool get showRequestMenu => _canElevate && !_running;
  onPeerInfo(PeerInfo pi) {
    _canElevate = pi.platform == kPeerPlatformWindows && pi.sasEnabled == false;
    _running = false;
  }

  onPortableServiceRunning(Map<String, dynamic> evt) {
    _running = evt['running'] == 'true';
  }
}

enum ConnType { defaultConn, fileTransfer, portForward, rdp }

/// Flutter state manager and data communication with the Rust core.
class FFI {
  var id = '';
  var version = '';
  var connType = ConnType.defaultConn;
  var closed = false;
  var auditNote = '';

  /// dialogManager use late to ensure init after main page binding [globalKey]
  late final dialogManager = OverlayDialogManager();

  late final SessionID sessionId;
  late final ImageModel imageModel; // session
  late final FfiModel ffiModel; // session
  late final CursorModel cursorModel; // session
  late final CanvasModel canvasModel; // session
  late final ServerModel serverModel; // global
  late final ChatModel chatModel; // session
  late final FileModel fileModel; // session
  late final AbModel abModel; // global
  late final GroupModel groupModel; // global
  late final UserModel userModel; // global
  late final PeerTabModel peerTabModel; // global
  late final QualityMonitorModel qualityMonitorModel; // session
  late final RecordingModel recordingModel; // session
  late final InputModel inputModel; // session
  late final ElevationModel elevationModel; // session
  late final CmFileModel cmFileModel; // cm

  FFI(SessionID? sId) {
    sessionId = sId ?? (isDesktop ? Uuid().v4obj() : _constSessionId);
    imageModel = ImageModel(WeakReference(this));
    ffiModel = FfiModel(WeakReference(this));
    cursorModel = CursorModel(WeakReference(this));
    canvasModel = CanvasModel(WeakReference(this));
    serverModel = ServerModel(WeakReference(this));
    chatModel = ChatModel(WeakReference(this));
    fileModel = FileModel(WeakReference(this));
    userModel = UserModel(WeakReference(this));
    peerTabModel = PeerTabModel(WeakReference(this));
    abModel = AbModel(WeakReference(this));
    groupModel = GroupModel(WeakReference(this));
    qualityMonitorModel = QualityMonitorModel(WeakReference(this));
    recordingModel = RecordingModel(WeakReference(this));
    inputModel = InputModel(WeakReference(this));
    elevationModel = ElevationModel(WeakReference(this));
    cmFileModel = CmFileModel(WeakReference(this));
  }

  /// Mobile reuse FFI
  void mobileReset() {
    ffiModel.waitForFirstImage.value = true;
    ffiModel.waitForImageDialogShow.value = true;
    ffiModel.waitForImageTimer?.cancel();
    ffiModel.waitForImageTimer = null;
  }

  /// Start with the given [id]. Only transfer file if [isFileTransfer], only port forward if [isPortForward].
  void start(String id,
      {bool isFileTransfer = false,
      bool isPortForward = false,
      bool isRdp = false,
      String? switchUuid,
      String? password,
      bool? forceRelay,
      int? tabWindowId}) {
    closed = false;
    auditNote = '';
    if (isMobile) mobileReset();
    assert(!(isFileTransfer && isPortForward), 'more than one connect type');
    if (isFileTransfer) {
      connType = ConnType.fileTransfer;
    } else if (isPortForward) {
      connType = ConnType.portForward;
    } else {
      chatModel.resetClientMode();
      connType = ConnType.defaultConn;
      canvasModel.id = id;
      imageModel.id = id;
      cursorModel.peerId = id;
    }
    // If tabWindowId != null, this session is a "tab -> window" one.
    // Else this session is a new one.
    if (tabWindowId == null) {
      // ignore: unused_local_variable
      final addRes = bind.sessionAddSync(
        sessionId: sessionId,
        id: id,
        isFileTransfer: isFileTransfer,
        isPortForward: isPortForward,
        isRdp: isRdp,
        switchUuid: switchUuid ?? '',
        forceRelay: forceRelay ?? false,
        password: password ?? '',
      );
    }
    final stream = bind.sessionStart(sessionId: sessionId, id: id);
    final cb = ffiModel.startEventListener(sessionId, id);
    final useTextureRender = bind.mainUseTextureRender();

    final SimpleWrapper<bool> isToNewWindowNotified = SimpleWrapper(false);
    // Preserved for the rgba data.
    stream.listen((message) {
      if (closed) return;
      if (tabWindowId != null && !isToNewWindowNotified.value) {
        // Session is read to be moved to a new window.
        // Get the cached data and handle the cached data.
        Future.delayed(Duration.zero, () async {
          final cachedData = await DesktopMultiWindow.invokeMethod(
              tabWindowId, kWindowEventGetCachedSessionData, id);
          if (cachedData == null) {
            // unreachable
            debugPrint('Unreachable, the cached data is empty.');
            return;
          }
          final data = CachedPeerData.fromString(cachedData);
          if (data == null) {
            debugPrint('Unreachable, the cached data cannot be decoded.');
            return;
          }
          await ffiModel.handleCachedPeerData(data, id);
          await bind.sessionRefresh(sessionId: sessionId);
        });
        isToNewWindowNotified.value = true;
      }
      () async {
        if (message is EventToUI_Event) {
          if (message.field0 == "close") {
            closed = true;
            debugPrint('Exit session event loop');
            return;
          }

          Map<String, dynamic>? event;
          try {
            event = json.decode(message.field0);
          } catch (e) {
            debugPrint('json.decode fail1(): $e, ${message.field0}');
          }
          if (event != null) {
            await cb(event);
          }
        } else if (message is EventToUI_Rgba) {
          if (useTextureRender) {
            onEvent2UIRgba();
          } else {
            // Fetch the image buffer from rust codes.
            final sz = platformFFI.getRgbaSize(sessionId);
            if (sz == 0) {
              return;
            }
            final rgba = platformFFI.getRgba(sessionId, sz);
            if (rgba != null) {
              onEvent2UIRgba();
              imageModel.onRgba(rgba);
            }
          }
        }
      }();
    });
    // every instance will bind a stream
    this.id = id;
  }

  void onEvent2UIRgba() async {
    if (ffiModel.waitForImageDialogShow.isTrue) {
      ffiModel.waitForImageDialogShow.value = false;
      ffiModel.waitForImageTimer?.cancel();
      clearWaitingForImage(dialogManager, sessionId);
    }
    if (ffiModel.waitForFirstImage.value == true) {
      ffiModel.waitForFirstImage.value = false;
      dialogManager.dismissAll();
      await canvasModel.updateViewStyle();
      await canvasModel.updateScrollStyle();
      for (final cb in imageModel.callbacksOnFirstImage) {
        cb(id);
      }
    }
  }

  /// Login with [password], choose if the client should [remember] it.
  void login(String osUsername, String osPassword, SessionID sessionId,
      String password, bool remember) {
    bind.sessionLogin(
        sessionId: sessionId,
        osUsername: osUsername,
        osPassword: osPassword,
        password: password,
        remember: remember);
  }

  /// Close the remote session.
  Future<void> close({bool closeSession = true}) async {
    closed = true;
    chatModel.close();
    if (imageModel.image != null && !isWebDesktop) {
      await setCanvasConfig(
          sessionId,
          cursorModel.x,
          cursorModel.y,
          canvasModel.x,
          canvasModel.y,
          canvasModel.scale,
          ffiModel.pi.currentDisplay);
    }
    imageModel.update(null);
    cursorModel.clear();
    ffiModel.clear();
    canvasModel.clear();
    inputModel.resetModifiers();
    if (closeSession) {
      await bind.sessionClose(sessionId: sessionId);
    }
    debugPrint('model $id closed');
    id = '';
  }

  void setMethodCallHandler(FMethod callback) {
    platformFFI.setMethodCallHandler(callback);
  }

  Future<bool> invokeMethod(String method, [dynamic arguments]) async {
    return await platformFFI.invokeMethod(method, arguments);
  }
}

const kInvalidResolutionValue = -1;
const kVirtualDisplayResolutionValue = 0;

class Display {
  double x = 0;
  double y = 0;
  int width = 0;
  int height = 0;
  bool cursorEmbedded = false;
  int originalWidth = kInvalidResolutionValue;
  int originalHeight = kInvalidResolutionValue;

  Display() {
    width = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayWidth
        : kMobileDefaultDisplayWidth;
    height = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayHeight
        : kMobileDefaultDisplayHeight;
  }

  @override
  bool operator ==(Object other) =>
      other is Display &&
      other.runtimeType == runtimeType &&
      _innerEqual(other);

  bool _innerEqual(Display other) =>
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.cursorEmbedded == cursorEmbedded;

  bool get isOriginalResolutionSet =>
      originalWidth != kInvalidResolutionValue &&
      originalHeight != kInvalidResolutionValue;
  bool get isVirtualDisplayResolution =>
      originalWidth == kVirtualDisplayResolutionValue &&
      originalHeight == kVirtualDisplayResolutionValue;
  bool get isOriginalResolution =>
      width == originalWidth && height == originalHeight;
}

class Resolution {
  int width = 0;
  int height = 0;
  Resolution(this.width, this.height);

  @override
  String toString() {
    return 'Resolution($width,$height)';
  }
}

class Features {
  bool privacyMode = false;
}

class PeerInfo with ChangeNotifier {
  String version = '';
  String username = '';
  String hostname = '';
  String platform = '';
  bool sasEnabled = false;
  int currentDisplay = 0;
  List<Display> displays = [];
  Features features = Features();
  List<Resolution> resolutions = [];
  Map<String, dynamic> platform_additions = {};

  RxBool isSet = false.obs;

  bool get is_wayland => platform_additions['is_wayland'] == true;
  bool get is_headless => platform_additions['headless'] == true;
}

const canvasKey = 'canvas';

Future<void> setCanvasConfig(
    SessionID sessionId,
    double xCursor,
    double yCursor,
    double xCanvas,
    double yCanvas,
    double scale,
    int currentDisplay) async {
  final p = <String, dynamic>{};
  p['xCursor'] = xCursor;
  p['yCursor'] = yCursor;
  p['xCanvas'] = xCanvas;
  p['yCanvas'] = yCanvas;
  p['scale'] = scale;
  p['currentDisplay'] = currentDisplay;
  await bind.sessionSetFlutterOption(
      sessionId: sessionId, k: canvasKey, v: jsonEncode(p));
}

Future<Map<String, dynamic>?> getCanvasConfig(SessionID sessionId) async {
  if (!isWebDesktop) return null;
  var p =
      await bind.sessionGetFlutterOption(sessionId: sessionId, k: canvasKey);
  if (p == null || p.isEmpty) return null;
  try {
    Map<String, dynamic> m = json.decode(p);
    return m;
  } catch (e) {
    return null;
  }
}

Future<void> initializeCursorAndCanvas(FFI ffi) async {
  var p = await getCanvasConfig(ffi.sessionId);
  int currentDisplay = 0;
  if (p != null) {
    currentDisplay = p['currentDisplay'];
  }
  if (p == null || currentDisplay != ffi.ffiModel.pi.currentDisplay) {
    ffi.cursorModel
        .updateDisplayOrigin(ffi.ffiModel.display.x, ffi.ffiModel.display.y);
    return;
  }
  double xCursor = p['xCursor'];
  double yCursor = p['yCursor'];
  double xCanvas = p['xCanvas'];
  double yCanvas = p['yCanvas'];
  double scale = p['scale'];
  ffi.cursorModel.updateDisplayOriginWithCursor(
      ffi.ffiModel.display.x, ffi.ffiModel.display.y, xCursor, yCursor);
  ffi.canvasModel.update(xCanvas, yCanvas, scale);
}

clearWaitingForImage(OverlayDialogManager? dialogManager, SessionID sessionId) {
  dialogManager?.dismissByTag('$sessionId-waiting-for-image');
}
