import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';
import 'home_page.dart';
import 'scan_page.dart';

class SettingsPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Settings");

  @override
  final icon = Icon(Icons.settings);

  @override
  final appBarActions = [ScanButton()];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

const url = 'https://rustdesk.com/';

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  final _hasIgnoreBattery = androidVersion >= 26;
  var _ignoreBatteryOpt = false;
  var _enableStartOnBoot = false;
  var _enableAbr = false;
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _enableDirectIPAccess = false;
  var _enableRecordSession = false;
  var _autoRecordIncomingSession = false;
  var _allowAutoDisconnect = false;
  var _localIP = "";
  var _directAccessPort = "";
  var _fingerprint = "";
  var _buildDate = "";
  var _autoDisconnectTimeout = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    () async {
      var update = false;

      if (_hasIgnoreBattery) {
        if (await checkAndUpdateIgnoreBatteryStatus()) {
          update = true;
        }
      }

      if (await checkAndUpdateStartOnBoot()) {
        update = true;
      }

      // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
      var enableStartOnBoot =
          await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
      if (enableStartOnBoot) {
        if (!await canStartOnBoot()) {
          enableStartOnBoot = false;
          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
        }
      }

      if (enableStartOnBoot != _enableStartOnBoot) {
        update = true;
        _enableStartOnBoot = enableStartOnBoot;
      }

      final enableAbrRes = option2bool(
          "enable-abr", await bind.mainGetOption(key: "enable-abr"));
      if (enableAbrRes != _enableAbr) {
        update = true;
        _enableAbr = enableAbrRes;
      }

      final denyLanDiscovery = !option2bool('enable-lan-discovery',
          await bind.mainGetOption(key: 'enable-lan-discovery'));
      if (denyLanDiscovery != _denyLANDiscovery) {
        update = true;
        _denyLANDiscovery = denyLanDiscovery;
      }

      final onlyWhiteList =
          (await bind.mainGetOption(key: 'whitelist')).isNotEmpty;
      if (onlyWhiteList != _onlyWhiteList) {
        update = true;
        _onlyWhiteList = onlyWhiteList;
      }

      final enableDirectIPAccess = option2bool(
          'direct-server', await bind.mainGetOption(key: 'direct-server'));
      if (enableDirectIPAccess != _enableDirectIPAccess) {
        update = true;
        _enableDirectIPAccess = enableDirectIPAccess;
      }

      final enableRecordSession = option2bool('enable-record-session',
          await bind.mainGetOption(key: 'enable-record-session'));
      if (enableRecordSession != _enableRecordSession) {
        update = true;
        _enableRecordSession = enableRecordSession;
      }

      final autoRecordIncomingSession = option2bool(
          'allow-auto-record-incoming',
          await bind.mainGetOption(key: 'allow-auto-record-incoming'));
      if (autoRecordIncomingSession != _autoRecordIncomingSession) {
        update = true;
        _autoRecordIncomingSession = autoRecordIncomingSession;
      }

      final localIP = await bind.mainGetOption(key: 'local-ip-addr');
      if (localIP != _localIP) {
        update = true;
        _localIP = localIP;
      }

      final directAccessPort =
          await bind.mainGetOption(key: 'direct-access-port');
      if (directAccessPort != _directAccessPort) {
        update = true;
        _directAccessPort = directAccessPort;
      }

      final fingerprint = await bind.mainGetFingerprint();
      if (_fingerprint != fingerprint) {
        update = true;
        _fingerprint = fingerprint;
      }

      final buildDate = await bind.mainGetBuildDate();
      if (_buildDate != buildDate) {
        update = true;
        _buildDate = buildDate;
      }

      final allowAutoDisconnect = option2bool('allow-auto-disconnect',
          await bind.mainGetOption(key: 'allow-auto-disconnect'));
      if (allowAutoDisconnect != _allowAutoDisconnect) {
        update = true;
        _allowAutoDisconnect = allowAutoDisconnect;
      }

      final autoDisconnectTimeout =
          await bind.mainGetOption(key: 'auto-disconnect-timeout');
      if (autoDisconnectTimeout != _autoDisconnectTimeout) {
        update = true;
        _autoDisconnectTimeout = autoDisconnectTimeout;
      }

      if (update) {
        setState(() {});
      }
    }();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      () async {
        final ibs = await checkAndUpdateIgnoreBatteryStatus();
        final sob = await checkAndUpdateStartOnBoot();
        if (ibs || sob) {
          setState(() {});
        }
      }();
    }
  }

  Future<bool> checkAndUpdateIgnoreBatteryStatus() async {
    final res = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    if (_ignoreBatteryOpt != res) {
      _ignoreBatteryOpt = res;
      return true;
    } else {
      return false;
    }
  }

  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      debugPrint(
          "checkAndUpdateStartOnBoot and set _enableStartOnBoot -> false");
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final List<AbstractSettingsTile> enhancementsTiles = [];
    final List<AbstractSettingsTile> shareScreenTiles = [
      SettingsTile.switchTile(
        title: Text(translate('Deny LAN Discovery')),
        initialValue: _denyLANDiscovery,
        onToggle: (v) async {
          await bind.mainSetOption(
              key: "enable-lan-discovery",
              value: bool2option("enable-lan-discovery", !v));
          final newValue = !option2bool('enable-lan-discovery',
              await bind.mainGetOption(key: 'enable-lan-discovery'));
          setState(() {
            _denyLANDiscovery = newValue;
          });
        },
      ),
      SettingsTile.switchTile(
        title: Row(children: [
          Expanded(child: Text(translate('Use IP Whitelisting'))),
          Offstage(
                  offstage: !_onlyWhiteList,
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Color.fromARGB(255, 255, 204, 0)))
              .marginOnly(left: 5)
        ]),
        initialValue: _onlyWhiteList,
        onToggle: (_) async {
          update() async {
            final onlyWhiteList =
                (await bind.mainGetOption(key: 'whitelist')).isNotEmpty;
            if (onlyWhiteList != _onlyWhiteList) {
              setState(() {
                _onlyWhiteList = onlyWhiteList;
              });
            }
          }

          changeWhiteList(callback: update);
        },
      ),
      SettingsTile.switchTile(
        title: Text('${translate('Adaptive bitrate')} (beta)'),
        initialValue: _enableAbr,
        onToggle: (v) async {
          await bind.mainSetOption(key: "enable-abr", value: v ? "" : "N");
          final newValue = await bind.mainGetOption(key: "enable-abr") != "N";
          setState(() {
            _enableAbr = newValue;
          });
        },
      ),
      SettingsTile.switchTile(
        title: Text(translate('Enable Recording Session')),
        initialValue: _enableRecordSession,
        onToggle: (v) async {
          await bind.mainSetOption(
              key: "enable-record-session", value: v ? "" : "N");
          final newValue =
              await bind.mainGetOption(key: "enable-record-session") != "N";
          setState(() {
            _enableRecordSession = newValue;
          });
        },
      ),
      SettingsTile.switchTile(
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(translate("Direct IP Access")),
                    Offstage(
                        offstage: !_enableDirectIPAccess,
                        child: Text(
                          '${translate("Local Address")}: $_localIP${_directAccessPort.isEmpty ? "" : ":$_directAccessPort"}',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ])),
              Offstage(
                  offstage: !_enableDirectIPAccess,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                      ),
                      onPressed: () async {
                        final port = await changeDirectAccessPort(
                            _localIP, _directAccessPort);
                        setState(() {
                          _directAccessPort = port;
                        });
                      }))
            ]),
        initialValue: _enableDirectIPAccess,
        onToggle: (_) async {
          _enableDirectIPAccess = !_enableDirectIPAccess;
          String value = bool2option('direct-server', _enableDirectIPAccess);
          await bind.mainSetOption(key: 'direct-server', value: value);
          setState(() {});
        },
      ),
      SettingsTile.switchTile(
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(translate("auto_disconnect_option_tip")),
                    Offstage(
                        offstage: !_allowAutoDisconnect,
                        child: Text(
                          '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ])),
              Offstage(
                  offstage: !_allowAutoDisconnect,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                      ),
                      onPressed: () async {
                        final timeout = await changeAutoDisconnectTimeout(
                            _autoDisconnectTimeout);
                        setState(() {
                          _autoDisconnectTimeout = timeout;
                        });
                      }))
            ]),
        initialValue: _allowAutoDisconnect,
        onToggle: (_) async {
          _allowAutoDisconnect = !_allowAutoDisconnect;
          String value =
              bool2option('allow-auto-disconnect', _allowAutoDisconnect);
          await bind.mainSetOption(key: 'allow-auto-disconnect', value: value);
          setState(() {});
        },
      )
    ];
    if (_hasIgnoreBattery) {
      enhancementsTiles.insert(
          0,
          SettingsTile.switchTile(
              initialValue: _ignoreBatteryOpt,
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('Keep RustDesk background service')),
                    Text('* ${translate('Ignore Battery Optimizations')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              onToggle: (v) async {
                if (v) {
                  await AndroidPermissionManager.request(
                      kRequestIgnoreBatteryOptimizations);
                } else {
                  final res = await gFFI.dialogManager.show<bool>(
                      (setState, close, context) => CustomAlertDialog(
                            title: Text(translate("Open System Setting")),
                            content: Text(translate(
                                "android_open_battery_optimizations_tip")),
                            actions: [
                              dialogButton("Cancel",
                                  onPressed: () => close(), isOutline: true),
                              dialogButton(
                                "Open System Setting",
                                onPressed: () => close(true),
                              ),
                            ],
                          ));
                  if (res == true) {
                    AndroidPermissionManager.startAction(
                        kActionApplicationDetailsSettings);
                  }
                }
              }));
    }
    enhancementsTiles.add(SettingsTile.switchTile(
        initialValue: _enableStartOnBoot,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("${translate('Start on Boot')} (beta)"),
          Text(
              '* ${translate('Start the screen sharing service on boot, requires special permissions')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        onToggle: (toValue) async {
          if (toValue) {
            // 1. request kIgnoreBatteryOptimizations
            if (!await AndroidPermissionManager.check(
                kRequestIgnoreBatteryOptimizations)) {
              if (!await AndroidPermissionManager.request(
                  kRequestIgnoreBatteryOptimizations)) {
                return;
              }
            }

            // 2. request kSystemAlertWindow
            if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
              if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
                return;
              }
            }

            // (Optional) 3. request input permission
          }
          setState(() => _enableStartOnBoot = toValue);

          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, toValue);
        }));

    return SettingsList(
      sections: [
        SettingsSection(
          title: Text(translate('Account')),
          tiles: [
            SettingsTile(
              title: Obx(() => Text(gFFI.userModel.userName.value.isEmpty
                  ? translate('Login')
                  : '${translate('Logout')} (${gFFI.userModel.userName.value})')),
              leading: Icon(Icons.person),
              onPressed: (context) {
                if (gFFI.userModel.userName.value.isEmpty) {
                  loginDialog();
                } else {
                  logOutConfirmDialog();
                }
              },
            ),
          ],
        ),
        SettingsSection(title: Text(translate("Settings")), tiles: [
          SettingsTile(
              title: Text(translate('ID/Relay Server')),
              leading: Icon(Icons.cloud),
              onPressed: (context) {
                showServerSettings(gFFI.dialogManager);
              }),
          SettingsTile(
              title: Text(translate('Language')),
              leading: Icon(Icons.translate),
              onPressed: (context) {
                showLanguageSettings(gFFI.dialogManager);
              }),
          SettingsTile(
            title: Text(translate(
                Theme.of(context).brightness == Brightness.light
                    ? 'Dark Theme'
                    : 'Light Theme')),
            leading: Icon(Theme.of(context).brightness == Brightness.light
                ? Icons.dark_mode
                : Icons.light_mode),
            onPressed: (context) {
              showThemeSettings(gFFI.dialogManager);
            },
          )
        ]),
        if (isAndroid)
          SettingsSection(
            title: Text(translate("Recording")),
            tiles: [
              SettingsTile.switchTile(
                title:
                    Text(translate('Automatically record incoming sessions')),
                leading: Icon(Icons.videocam),
                description: FutureBuilder(
                    builder: (ctx, data) => Offstage(
                        offstage: !data.hasData,
                        child: Text("${translate("Directory")}: ${data.data}")),
                    future: bind.mainDefaultVideoSaveDirectory()),
                initialValue: _autoRecordIncomingSession,
                onToggle: (v) async {
                  await bind.mainSetOption(
                      key: "allow-auto-record-incoming",
                      value: bool2option("allow-auto-record-incoming", v));
                  final newValue = option2bool(
                      'allow-auto-record-incoming',
                      await bind.mainGetOption(
                          key: 'allow-auto-record-incoming'));
                  setState(() {
                    _autoRecordIncomingSession = newValue;
                  });
                },
              ),
            ],
          ),
        if (isAndroid)
          SettingsSection(
            title: Text(translate("Share Screen")),
            tiles: shareScreenTiles,
          ),
        defaultDisplaySection(),
        if (isAndroid)
          SettingsSection(
            title: Text(translate("Enhancements")),
            tiles: enhancementsTiles,
          ),
        SettingsSection(
          title: Text(translate("About")),
          tiles: [
            SettingsTile(
                onPressed: (context) async {
                  if (await canLaunchUrl(Uri.parse(url))) {
                    await launchUrl(Uri.parse(url));
                  }
                },
                title: Text(translate("Version: ") + version),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('rustdesk.com',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                      )),
                ),
                leading: Icon(Icons.info)),
            SettingsTile(
                title: Text(translate("Build Date")),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(_buildDate),
                ),
                leading: Icon(Icons.query_builder)),
            if (isAndroid)
              SettingsTile(
                  onPressed: (context) => onCopyFingerprint(_fingerprint),
                  title: Text(translate("Fingerprint")),
                  value: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(_fingerprint),
                  ),
                  leading: Icon(Icons.fingerprint)),
            SettingsTile(
              title: Text(translate("Privacy Statement")),
              onPressed: (context) =>
                  launchUrlString('https://rustdesk.com/privacy.html'),
              leading: Icon(Icons.privacy_tip),
            )
          ],
        ),
      ],
    );
  }

  Future<bool> canStartOnBoot() async {
    // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
    if (_hasIgnoreBattery && !_ignoreBatteryOpt) {
      return false;
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      return false;
    }
    return true;
  }

  defaultDisplaySection() {
    return SettingsSection(
      title: Text(translate("Display Settings")),
      tiles: [
        SettingsTile(
            title: Text(translate('Display Settings')),
            leading: Icon(Icons.desktop_windows_outlined),
            trailing: Icon(Icons.arrow_forward_ios),
            onPressed: (context) {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return _DisplayPage();
              }));
            })
      ],
    );
  }
}

void showServerSettings(OverlayDialogManager dialogManager) async {
  Map<String, dynamic> options = jsonDecode(await bind.mainGetOptions());
  showServerSettingsWithValue(ServerConfig.fromOptions(options), dialogManager);
}

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final langs = json.decode(await bind.mainGetLangs()) as List<dynamic>;
    var lang = bind.mainGetLocalOption(key: "lang");
    dialogManager.show((setState, close, context) {
      setLang(v) async {
        if (lang != v) {
          setState(() {
            lang = v;
          });
          await bind.mainSetLocalOption(key: "lang", value: v);
          HomePage.homeKey.currentState?.refreshPages();
          Future.delayed(Duration(milliseconds: 200), close);
        }
      }

      return CustomAlertDialog(
        content: Column(
          children: [
                getRadio(Text(translate('Default')), '', lang, setLang),
                Divider(color: MyTheme.border),
              ] +
              langs.map((e) {
                final key = e[0] as String;
                final name = e[1] as String;
                return getRadio(Text(translate(name)), key, lang, setLang);
              }).toList(),
        ),
      );
    }, backDismiss: true, clickMaskDismiss: true);
  } catch (e) {
    //
  }
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();

  dialogManager.show((setState, close, context) {
    setTheme(v) {
      if (themeMode != v) {
        setState(() {
          themeMode = v;
        });
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(Duration(milliseconds: 200), close);
      }
    }

    return CustomAlertDialog(
      content: Column(children: [
        getRadio(
            Text(translate('Light')), ThemeMode.light, themeMode, setTheme),
        getRadio(Text(translate('Dark')), ThemeMode.dark, themeMode, setTheme),
        getRadio(Text(translate('Follow System')), ThemeMode.system, themeMode,
            setTheme)
      ]),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showAbout(OverlayDialogManager dialogManager) {
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text('${translate('About')} RustDesk'),
      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        Text('Version: $version'),
        InkWell(
            onTap: () async {
              const url = 'https://rustdesk.com/';
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('rustdesk.com',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  )),
            )),
      ]),
      actions: [],
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.qr_code_scanner),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => ScanPage(),
          ),
        );
      },
    );
  }
}

class _DisplayPage extends StatefulWidget {
  const _DisplayPage({super.key});

  @override
  State<_DisplayPage> createState() => __DisplayPageState();
}

class __DisplayPageState extends State<_DisplayPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    var codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265')
    ];
    RxBool showCustomImageQuality = false.obs;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios)),
        title: Text(translate('Display Settings')),
        centerTitle: true,
      ),
      body: SettingsList(sections: [
        SettingsSection(
          tiles: [
            _getPopupDialogRadioEntry(
              title: 'Default View Style',
              list: [
                _RadioEntry('Scale original', kRemoteViewStyleOriginal),
                _RadioEntry('Scale adaptive', kRemoteViewStyleAdaptive)
              ],
              getter: () => bind.mainGetUserDefaultOption(key: 'view_style'),
              asyncSetter: (value) async {
                await bind.mainSetUserDefaultOption(
                    key: 'view_style', value: value);
              },
            ),
            _getPopupDialogRadioEntry(
              title: 'Default Image Quality',
              list: [
                _RadioEntry('Good image quality', kRemoteImageQualityBest),
                _RadioEntry('Balanced', kRemoteImageQualityBalanced),
                _RadioEntry('Optimize reaction time', kRemoteImageQualityLow),
                _RadioEntry('Custom', kRemoteImageQualityCustom),
              ],
              getter: () {
                final v = bind.mainGetUserDefaultOption(key: 'image_quality');
                showCustomImageQuality.value = v == kRemoteImageQualityCustom;
                return v;
              },
              asyncSetter: (value) async {
                await bind.mainSetUserDefaultOption(
                    key: 'image_quality', value: value);
                showCustomImageQuality.value =
                    value == kRemoteImageQualityCustom;
              },
              tail: customImageQualitySetting(),
              showTail: showCustomImageQuality,
              notCloseValue: kRemoteImageQualityCustom,
            ),
            _getPopupDialogRadioEntry(
              title: 'Default Codec',
              list: codecList,
              getter: () =>
                  bind.mainGetUserDefaultOption(key: 'codec-preference'),
              asyncSetter: (value) async {
                await bind.mainSetUserDefaultOption(
                    key: 'codec-preference', value: value);
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(translate('Other Default Options')),
          tiles: [
            otherRow('Show remote cursor', 'show_remote_cursor'),
            otherRow('Show quality monitor', 'show_quality_monitor'),
            otherRow('Mute', 'disable_audio'),
            otherRow('Disable clipboard', 'disable_clipboard'),
            otherRow('Lock after session end', 'lock_after_session_end'),
            otherRow('Privacy mode', 'privacy_mode'),
            otherRow('Touch mode', 'touch-mode'),
          ],
        ),
      ]),
    );
  }

  otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    return SettingsTile.switchTile(
      initialValue: value,
      title: Text(translate(label)),
      onToggle: (b) async {
        await bind.mainSetUserDefaultOption(key: key, value: b ? 'Y' : '');
        setState(() {});
      },
    );
  }
}

class _RadioEntry {
  final String label;
  final String value;
  _RadioEntry(this.label, this.value);
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

_getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  RxString groupValue = ''.obs;
  RxString valueText = ''.obs;

  init() {
    groupValue.value = getter();
    final e = list.firstWhereOrNull((e) => e.value == groupValue.value);
    if (e != null) {
      valueText.value = e.label;
    }
  }

  init();

  void showDialog() async {
    gFFI.dialogManager.show((setState, close, context) {
      onChanged(String? value) async {
        if (value == null) return;
        await asyncSetter(value);
        init();
        if (value != notCloseValue) {
          close();
        }
      }

      return CustomAlertDialog(
          content: Obx(
        () => Column(children: [
          ...list
              .map((e) => getRadio(Text(translate(e.label)), e.value,
                  groupValue.value, (String? value) => onChanged(value)))
              .toList(),
          Offstage(
            offstage:
                !(tail != null && showTail != null && showTail.value == true),
            child: tail,
          ),
        ]),
      ));
    }, backDismiss: true, clickMaskDismiss: true);
  }

  return SettingsTile(
    title: Text(translate(title)),
    onPressed: (context) => showDialog(),
    value: Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Obx(() => Text(translate(valueText.value))),
    ),
  );
}
