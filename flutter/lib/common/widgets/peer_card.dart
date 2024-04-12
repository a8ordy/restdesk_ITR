import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import '../../desktop/widgets/popup_menu.dart';
import 'dart:math' as math;

typedef PopupMenuEntryBuilder = Future<List<mod_menu.PopupMenuEntry<String>>>
    Function(BuildContext);

enum PeerUiType { grid, list }

final peerCardUiType = PeerUiType.grid.obs;

class _PeerCard extends StatefulWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final Function(BuildContext, String) connect;
  final PopupMenuEntryBuilder popupMenuEntryBuilder;

  const _PeerCard(
      {required this.peer,
      required this.tab,
      required this.connect,
      required this.popupMenuEntryBuilder,
      Key? key})
      : super(key: key);

  @override
  _PeerCardState createState() => _PeerCardState();
}

/// State for the connection page.
class _PeerCardState extends State<_PeerCard>
    with AutomaticKeepAliveClientMixin {
  var _menuPos = RelativeRect.fill;
  final double _cardRadius = 16;
  final double _tileRadius = 5;
  final double _borderWidth = 2;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isDesktop) {
      return _buildDesktop();
    } else {
      return _buildMobile();
    }
  }

  Widget _buildMobile() {
    final peer = super.widget.peer;
    final PeerTabModel peerTabModel = Provider.of(context);
    return Card(
        margin: EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: () {
            if (peerTabModel.multiSelectionMode) {
              peerTabModel.select(peer);
            } else {
              if (!isWebDesktop) {
                connectInPeerTab(context, peer.id, widget.tab);
              }
            }
          },
          onDoubleTap: isWebDesktop
              ? () => connectInPeerTab(context, peer.id, widget.tab)
              : null,
          onLongPress: () {
            peerTabModel.select(peer);
          },
          child: Container(
              padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
              child: _buildPeerTile(context, peer, null)),
        ));
  }

  Widget _buildDesktop() {
    final PeerTabModel peerTabModel = Provider.of(context);
    final peer = super.widget.peer;
    var deco = Rx<BoxDecoration?>(
      BoxDecoration(
        border: Border.all(color: Colors.transparent, width: _borderWidth),
        borderRadius: BorderRadius.circular(
          peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
        ),
      ),
    );
    return MouseRegion(
      onEnter: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      onExit: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(color: Colors.transparent, width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      child: GestureDetector(
          onDoubleTap:
              peerTabModel.multiSelectionMode || peerTabModel.isShiftDown
                  ? null
                  : () => widget.connect(context, peer.id),
          onTap: () => peerTabModel.select(peer),
          onLongPress: () => peerTabModel.select(peer),
          child: Obx(() => peerCardUiType.value == PeerUiType.grid
              ? _buildPeerCard(context, peer, deco)
              : _buildPeerTile(context, peer, deco))),
    );
  }

  Widget _buildPeerTile(
      BuildContext context, Peer peer, Rx<BoxDecoration?>? deco) {
    final name =
        '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final greyStyle = TextStyle(
        fontSize: 11,
        color: Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.6));
    final child = Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          decoration: BoxDecoration(
            color: str2color('${peer.id}${peer.platform}', 0x7f),
            borderRadius: isMobile
                ? BorderRadius.circular(_tileRadius)
                : BorderRadius.only(
                    topLeft: Radius.circular(_tileRadius),
                    bottomLeft: Radius.circular(_tileRadius),
                  ),
          ),
          alignment: Alignment.center,
          width: isMobile ? 50 : 42,
          height: isMobile ? 50 : null,
          child: getPlatformImage(peer.platform, size: isMobile ? 38 : 30)
              .paddingAll(6),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(_tileRadius),
                bottomRight: Radius.circular(_tileRadius),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(children: [
                        getOnline(isMobile ? 4 : 8, peer.online),
                        Expanded(
                            child: Text(
                          peer.alias.isEmpty ? formatID(peer.id) : peer.alias,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        )),
                      ]).marginOnly(top: isMobile ? 0 : 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          style: isMobile ? null : greyStyle,
                          textAlign: TextAlign.start,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ).marginOnly(top: 2),
                ),
                isMobile
                    ? checkBoxOrActionMoreMobile(peer)
                    : checkBoxOrActionMoreDesktop(peer, isTile: true),
              ],
            ).paddingOnly(left: 10.0, top: 3.0),
          ),
        )
      ],
    );
    final colors =
        _frontN(peer.tags, 25).map((e) => gFFI.abModel.getTagColor(e)).toList();
    return Tooltip(
      message: isMobile
          ? ''
          : peer.tags.isNotEmpty
              ? '${translate('Tags')}: ${peer.tags.join(', ')}'
              : '',
      child: Stack(children: [
        deco == null
            ? child
            : Obx(
                () => Container(
                  foregroundDecoration: deco.value,
                  child: child,
                ),
              ),
        if (colors.isNotEmpty)
          Positioned(
            top: 2,
            right: isMobile ? 20 : 10,
            child: CustomPaint(
              painter: TagPainter(radius: 3, colors: colors),
            ),
          )
      ]),
    );
  }

  Widget _buildPeerCard(
      BuildContext context, Peer peer, Rx<BoxDecoration?> deco) {
    final name =
        '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final child = Card(
      color: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Obx(
        () => Container(
          foregroundDecoration: deco.value,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_cardRadius - _borderWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    color: str2color('${peer.id}${peer.platform}', 0x7f),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                child:
                                    getPlatformImage(peer.platform, size: 60),
                              ).marginOnly(top: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Tooltip(
                                      message: name,
                                      waitDuration: const Duration(seconds: 1),
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ).paddingAll(4.0),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: Theme.of(context).colorScheme.background,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Row(children: [
                        getOnline(8, peer.online),
                        Expanded(
                            child: Text(
                          peer.alias.isEmpty ? formatID(peer.id) : peer.alias,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        )),
                      ]).paddingSymmetric(vertical: 8)),
                      checkBoxOrActionMoreDesktop(peer, isTile: false),
                    ],
                  ).paddingSymmetric(horizontal: 12.0),
                )
              ],
            ),
          ),
        ),
      ),
    );

    final colors =
        _frontN(peer.tags, 25).map((e) => gFFI.abModel.getTagColor(e)).toList();
    return Tooltip(
      message: peer.tags.isNotEmpty
          ? '${translate('Tags')}: ${peer.tags.join(', ')}'
          : '',
      child: Stack(children: [
        child,
        if (colors.isNotEmpty)
          Positioned(
            top: 4,
            right: 12,
            child: CustomPaint(
              painter: TagPainter(radius: 4, colors: colors),
            ),
          )
      ]),
    );
  }

  List _frontN<T>(List list, int n) {
    if (list.length <= n) {
      return list;
    } else {
      return list.sublist(0, n);
    }
  }

  Widget checkBoxOrActionMoreMobile(Peer peer) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: selected
            ? Icon(
                Icons.check_box,
                color: MyTheme.accent,
              )
            : Icon(Icons.check_box_outline_blank),
      );
    } else {
      return InkWell(
          child: const Padding(
              padding: EdgeInsets.all(12), child: Icon(Icons.more_vert)),
          onTapDown: (e) {
            final x = e.globalPosition.dx;
            final y = e.globalPosition.dy;
            _menuPos = RelativeRect.fromLTRB(x, y, x, y);
          },
          onTap: () {
            _showPeerMenu(peer.id);
          });
    }
  }

  Widget checkBoxOrActionMoreDesktop(Peer peer, {required bool isTile}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      final icon = selected
          ? Icon(
              Icons.check_box,
              color: MyTheme.accent,
            )
          : Icon(Icons.check_box_outline_blank);
      bool last = peerTabModel.isShiftDown && peer.id == peerTabModel.lastId;
      double right = isTile ? 4 : 0;
      if (last) {
        return Container(
          decoration: BoxDecoration(
              border: Border.all(color: MyTheme.accent, width: 1)),
          child: icon,
        ).marginOnly(right: right);
      } else {
        return icon.marginOnly(right: right);
      }
    } else {
      return _actionMore(peer);
    }
  }

  Widget _actionMore(Peer peer) => Listener(
      onPointerDown: (e) {
        final x = e.position.dx;
        final y = e.position.dy;
        _menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onPointerUp: (_) => _showPeerMenu(peer.id),
      child: build_more(context));

  /// Show the peer menu and handle user's choice.
  /// User might remove the peer or send a file to the peer.
  void _showPeerMenu(String id) async {
    await mod_menu.showMenu(
      context: context,
      position: _menuPos,
      items: await super.widget.popupMenuEntryBuilder(context),
      elevation: 8,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

abstract class BasePeerCard extends StatelessWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final EdgeInsets? menuPadding;

  BasePeerCard(
      {required this.peer, required this.tab, this.menuPadding, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _PeerCard(
      peer: peer,
      tab: tab,
      connect: (BuildContext context, String id) =>
          connectInPeerTab(context, id, tab),
      popupMenuEntryBuilder: _buildPopupMenuEntry,
    );
  }

  Future<List<mod_menu.PopupMenuEntry<String>>> _buildPopupMenuEntry(
          BuildContext context) async =>
      (await _buildMenuItems(context))
          .map((e) => e.build(
              context,
              const MenuConfig(
                  commonColor: CustomPopupMenuTheme.commonColor,
                  height: CustomPopupMenuTheme.height,
                  dividerHeight: CustomPopupMenuTheme.dividerHeight)))
          .expand((i) => i)
          .toList();

  @protected
  Future<List<MenuEntryBase<String>>> _buildMenuItems(BuildContext context);

  MenuEntryBase<String> _connectCommonAction(
    BuildContext context,
    String id,
    String title, {
    bool isFileTransfer = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        title,
        style: style,
      ),
      proc: () {
        connectInPeerTab(
          context,
          peer.id,
          tab,
          isFileTransfer: isFileTransfer,
          isTcpTunneling: isTcpTunneling,
          isRDP: isRDP,
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _connectAction(BuildContext context, Peer peer) {
    return _connectCommonAction(
      context,
      peer.id,
      (peer.alias.isEmpty
          ? translate('Connect')
          : '${translate('Connect')} ${peer.id}'),
    );
  }

  @protected
  MenuEntryBase<String> _transferFileAction(BuildContext context, String id) {
    return _connectCommonAction(
      context,
      id,
      translate('Transfer File'),
      isFileTransfer: true,
    );
  }

  @protected
  MenuEntryBase<String> _tcpTunnelingAction(BuildContext context, String id) {
    return _connectCommonAction(
      context,
      id,
      translate('TCP Tunneling'),
      isTcpTunneling: true,
    );
  }

  @protected
  MenuEntryBase<String> _rdpAction(BuildContext context, String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Container(
          alignment: AlignmentDirectional.center,
          height: CustomPopupMenuTheme.height,
          child: Row(
            children: [
              Text(
                translate('RDP'),
                style: style,
              ),
              Expanded(
                  child: Align(
                alignment: Alignment.centerRight,
                child: Transform.scale(
                    scale: 0.8,
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        _rdpDialog(id);
                      },
                    )),
              ))
            ],
          )),
      proc: () {
        connectInPeerTab(context, id, tab, isRDP: true);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _wolAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('WOL'),
        style: style,
      ),
      proc: () {
        bind.mainWol(id: id);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  /// Only available on Windows.
  @protected
  MenuEntryBase<String> _createShortCutAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Create Desktop Shortcut'),
        style: style,
      ),
      proc: () {
        bind.mainCreateShortcut(id: id);
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  Future<MenuEntryBase<String>> _openNewConnInAction(
      String id, String label, String key) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate(label),
      getter: () async => mainGetPeerBoolOptionSync(id, key),
      setter: (bool v) async {
        await bind.mainSetPeerOption(
            id: id, key: key, value: bool2option(key, v));
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  _openInTabsAction(String id) async =>
      await _openNewConnInAction(id, 'Open in New Tab', kOptionOpenInTabs);

  _openInWindowsAction(String id) async => await _openNewConnInAction(
      id, 'Open in New Window', kOptionOpenInWindows);

  _openNewConnInOptAction(String id) async =>
      mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs)
          ? await _openInWindowsAction(id)
          : await _openInTabsAction(id);

  @protected
  Future<bool> _isForceAlwaysRelay(String id) async {
    return (await bind.mainGetPeerOption(id: id, key: kOptionForceAlwaysRelay))
        .isNotEmpty;
  }

  @protected
  Future<MenuEntryBase<String>> _forceAlwaysRelayAction(String id) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate('Always connect via relay'),
      getter: () async {
        return await _isForceAlwaysRelay(id);
      },
      setter: (bool v) async {
        await bind.mainSetPeerOption(
            id: id,
            key: kOptionForceAlwaysRelay,
            value: bool2option(kOptionForceAlwaysRelay, v));
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _renameAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Rename'),
        style: style,
      ),
      proc: () async {
        String oldName = await _getAlias(id);
        renameDialog(
            oldName: oldName,
            onSubmit: (String newName) async {
              if (newName != oldName) {
                if (tab == PeerTabIndex.ab) {
                  gFFI.abModel.changeAlias(id: id, alias: newName);
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                  gFFI.abModel.pushAb();
                } else {
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                  showToast(translate('Successful'));
                  _update();
                }
              }
            });
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _removeAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Delete'),
            style: style?.copyWith(color: Colors.red),
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.delete_forever, color: Colors.red),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        onSubmit() async {
          switch (tab) {
            case PeerTabIndex.recent:
              await bind.mainRemovePeer(id: id);
              await bind.mainLoadRecentPeers();
              break;
            case PeerTabIndex.fav:
              final favs = (await bind.mainGetFav()).toList();
              if (favs.remove(id)) {
                await bind.mainStoreFav(favs: favs);
                await bind.mainLoadFavPeers();
              }
              break;
            case PeerTabIndex.lan:
              await bind.mainRemoveDiscovered(id: id);
              await bind.mainLoadLanPeers();
              break;
            case PeerTabIndex.ab:
              gFFI.abModel.deletePeer(id);
              final future = gFFI.abModel.pushAb();
              if (await bind.mainPeerExists(id: peer.id)) {
                gFFI.abModel.reSyncToast(future);
              }
              break;
            case PeerTabIndex.group:
              break;
          }
          if (tab != PeerTabIndex.ab) {
            showToast(translate('Successful'));
          }
        }

        deletePeerConfirmDialog(onSubmit,
            '${translate('Delete')} "${peer.alias.isEmpty ? formatID(peer.id) : peer.alias}"?');
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _unrememberPasswordAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Forget Password'),
        style: style,
      ),
      proc: () async {
        bool result = gFFI.abModel.changePassword(id, '');
        await bind.mainForgetPassword(id: id);
        bool toast = false;
        if (result) {
          toast = tab == PeerTabIndex.ab;
          gFFI.abModel.pushAb(toastIfFail: toast, toastIfSucc: toast);
        }
        if (!toast) showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addFavAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Add to Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star_outline),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (!favs.contains(id)) {
            favs.add(id);
            await bind.mainStoreFav(favs: favs);
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _rmFavAction(
      String id, Future<void> Function() reloadFunc) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Remove from Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (favs.remove(id)) {
            await bind.mainStoreFav(favs: favs);
            await reloadFunc();
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addToAb(Peer peer) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Add to Address Book'),
        style: style,
      ),
      proc: () {
        () async {
          if (gFFI.abModel.isFull(true)) {
            return;
          }
          if (!gFFI.abModel.idContainBy(peer.id)) {
            gFFI.abModel.addPeer(peer);
            gFFI.abModel.pushAb();
          }
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  Future<String> _getAlias(String id) async =>
      await bind.mainGetPeerOption(id: id, key: 'alias');

  @protected
  void _update();
}

class RecentPeerCard extends BasePeerCard {
  RecentPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.recent,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context, peer),
      _transferFileAction(context, peer.id),
    ];

    final List favs = (await bind.mainGetFav()).toList();

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context, peer.id));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    menuItems.add(await _forceAlwaysRelayAction(peer.id));
    if (Platform.isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (Platform.isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    menuItems.add(_renameAction(peer.id));
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      if (!gFFI.abModel.idContainBy(peer.id)) {
        menuItems.add(_addToAb(peer));
      }
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadRecentPeers();
}

class FavoritePeerCard extends BasePeerCard {
  FavoritePeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.fav,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context, peer),
      _transferFileAction(context, peer.id),
    ];
    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context, peer.id));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    menuItems.add(await _forceAlwaysRelayAction(peer.id));
    if (Platform.isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (Platform.isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    menuItems.add(_renameAction(peer.id));
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }
    menuItems.add(_rmFavAction(peer.id, () async {
      await bind.mainLoadFavPeers();
    }));

    if (gFFI.userModel.userName.isNotEmpty) {
      if (!gFFI.abModel.idContainBy(peer.id)) {
        menuItems.add(_addToAb(peer));
      }
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadFavPeers();
}

class DiscoveredPeerCard extends BasePeerCard {
  DiscoveredPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.lan,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context, peer),
      _transferFileAction(context, peer.id),
    ];

    final List favs = (await bind.mainGetFav()).toList();

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context, peer.id));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    menuItems.add(await _forceAlwaysRelayAction(peer.id));
    if (Platform.isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    menuItems.add(_wolAction(peer.id));
    if (Platform.isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      if (!gFFI.abModel.idContainBy(peer.id)) {
        menuItems.add(_addToAb(peer));
      }
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadLanPeers();
}

class AddressBookPeerCard extends BasePeerCard {
  AddressBookPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.ab,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context, peer),
      _transferFileAction(context, peer.id),
    ];
    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context, peer.id));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    menuItems.add(await _forceAlwaysRelayAction(peer.id));
    if (Platform.isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (Platform.isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    menuItems.add(_renameAction(peer.id));
    if (peer.hash.isNotEmpty) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }
    if (gFFI.abModel.tags.isNotEmpty) {
      menuItems.add(_editTagAction(peer.id));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => gFFI.abModel.pullAb(quiet: true);

  @protected
  MenuEntryBase<String> _editTagAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Edit Tag'),
        style: style,
      ),
      proc: () {
        editAbTagDialog(gFFI.abModel.getPeerTags(id), (selectedTag) async {
          gFFI.abModel.changeTagForPeer(id, selectedTag);
          gFFI.abModel.pushAb();
        });
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  @override
  Future<String> _getAlias(String id) async =>
      gFFI.abModel.find(id)?.alias ?? '';
}

class MyGroupPeerCard extends BasePeerCard {
  MyGroupPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.group,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context, peer),
      _transferFileAction(context, peer.id),
    ];
    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context, peer.id));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    // menuItems.add(await _forceAlwaysRelayAction(peer.id));
    if (Platform.isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (Platform.isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    // menuItems.add(MenuEntryDivider());
    // menuItems.add(_renameAction(peer.id));
    // if (await bind.mainPeerHasPassword(id: peer.id)) {
    //   menuItems.add(_unrememberPasswordAction(peer.id));
    // }
    if (gFFI.userModel.userName.isNotEmpty) {
      if (!gFFI.abModel.idContainBy(peer.id)) {
        menuItems.add(_addToAb(peer));
      }
    }
    return menuItems;
  }

  @protected
  @override
  void _update() => gFFI.groupModel.pull();
}

void _rdpDialog(String id) async {
  final port = await bind.mainGetPeerOption(id: id, key: 'rdp_port');
  final username = await bind.mainGetPeerOption(id: id, key: 'rdp_username');
  final portController = TextEditingController(text: port);
  final userController = TextEditingController(text: username);
  final passwordController = TextEditingController(
      text: await bind.mainGetPeerOption(id: id, key: 'rdp_password'));
  RxBool secure = true.obs;

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      String port = portController.text.trim();
      String username = userController.text;
      String password = passwordController.text;
      await bind.mainSetPeerOption(id: id, key: 'rdp_port', value: port);
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_username', value: username);
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_password', value: password);
      showToast(translate('Successful'));
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('RDP Settings')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isDesktop
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: Text(
                          "${translate('Port')}:",
                          textAlign: TextAlign.right,
                        ).marginOnly(right: 10))
                    : SizedBox.shrink(),
                Expanded(
                  child: TextField(
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
                    ],
                    decoration: InputDecoration(
                        labelText: isDesktop ? null : translate('Port'),
                        hintText: '3389'),
                    controller: portController,
                    autofocus: true,
                  ),
                ),
              ],
            ).marginOnly(bottom: isDesktop ? 8 : 0),
            Row(
              children: [
                isDesktop
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: Text(
                          "${translate('Username')}:",
                          textAlign: TextAlign.right,
                        ).marginOnly(right: 10))
                    : SizedBox.shrink(),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                        labelText: isDesktop ? null : translate('Username')),
                    controller: userController,
                  ),
                ),
              ],
            ).marginOnly(bottom: isDesktop ? 8 : 0),
            Row(
              children: [
                isDesktop
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: Text(
                          "${translate('Password')}:",
                          textAlign: TextAlign.right,
                        ).marginOnly(right: 10))
                    : SizedBox.shrink(),
                Expanded(
                  child: Obx(() => TextField(
                        obscureText: secure.value,
                        decoration: InputDecoration(
                            labelText: isDesktop ? null : translate('Password'),
                            suffixIcon: IconButton(
                                onPressed: () => secure.value = !secure.value,
                                icon: Icon(secure.value
                                    ? Icons.visibility_off
                                    : Icons.visibility))),
                        controller: passwordController,
                      )),
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

Widget getOnline(double rightPadding, bool online) {
  return Tooltip(
      message: translate(online ? 'Online' : 'Offline'),
      waitDuration: const Duration(seconds: 1),
      child: Padding(
          padding: EdgeInsets.fromLTRB(0, 4, rightPadding, 4),
          child: CircleAvatar(
              radius: 3, backgroundColor: online ? Colors.green : kColorWarn)));
}

Widget build_more(BuildContext context, {bool invert = false}) {
  final RxBool hover = false.obs;
  return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {},
      onHover: (value) => hover.value = value,
      child: Obx(() => CircleAvatar(
          radius: 14,
          backgroundColor: hover.value
              ? (invert
                  ? Theme.of(context).colorScheme.background
                  : Theme.of(context).scaffoldBackgroundColor)
              : (invert
                  ? Theme.of(context).scaffoldBackgroundColor
                  : Theme.of(context).colorScheme.background),
          child: Icon(Icons.more_vert,
              size: 18,
              color: hover.value
                  ? Theme.of(context).textTheme.titleLarge?.color
                  : Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.color
                      ?.withOpacity(0.5)))));
}

class TagPainter extends CustomPainter {
  final double radius;
  late final List<Color> colors;

  TagPainter({required this.radius, required List<Color> colors}) {
    this.colors = colors.reversed.toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    double x = 0;
    double y = radius;
    for (int i = 0; i < colors.length; i++) {
      Paint paint = Paint();
      paint.color = colors[i];
      x -= radius + 1;
      if (i == colors.length - 1) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      } else {
        Path path = Path();
        path.addArc(Rect.fromCircle(center: Offset(x, y), radius: radius),
            math.pi * 4 / 3, math.pi * 4 / 3);
        path.addArc(
            Rect.fromCircle(center: Offset(x - radius, y), radius: radius),
            math.pi * 5 / 3,
            math.pi * 2 / 3);
        path.fillType = PathFillType.evenOdd;
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

void connectInPeerTab(BuildContext context, String id, PeerTabIndex tab,
    {bool isFileTransfer = false,
    bool isTcpTunneling = false,
    bool isRDP = false}) async {
  if (tab == PeerTabIndex.ab) {
    // If recent peer's alias is empty, set it to ab's alias
    // Because the platform is not set, it may not take effect, but it is more important not to display if the connection is not successful
    Peer? p = gFFI.abModel.find(id);
    if (p != null &&
        p.alias.isNotEmpty &&
        (await bind.mainGetPeerOption(id: id, key: "alias")).isEmpty) {
      await bind.mainSetPeerAlias(
        id: id,
        alias: p.alias,
      );
    }
  }
  connect(context, id,
      isFileTransfer: isFileTransfer,
      isTcpTunneling: isTcpTunneling,
      isRDP: isRDP);
}
