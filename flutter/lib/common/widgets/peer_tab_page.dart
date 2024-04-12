import 'dart:ui' as ui;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/address_book.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/my_group.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/ab_model.dart';

import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

class PeerTabPage extends StatefulWidget {
  const PeerTabPage({Key? key}) : super(key: key);
  @override
  State<PeerTabPage> createState() => _PeerTabPageState();
}

class _TabEntry {
  final Widget widget;
  final Function({dynamic hint}) load;
  _TabEntry(this.widget, this.load);
}

EdgeInsets? _menuPadding() {
  return isDesktop ? kDesktopMenuPadding : null;
}

class _PeerTabPageState extends State<PeerTabPage>
    with SingleTickerProviderStateMixin {
  final List<_TabEntry> entries = [
    _TabEntry(
        RecentPeersView(
          menuPadding: _menuPadding(),
        ),
        bind.mainLoadRecentPeers),
    _TabEntry(
        FavoritePeersView(
          menuPadding: _menuPadding(),
        ),
        bind.mainLoadFavPeers),
    _TabEntry(
        DiscoveredPeersView(
          menuPadding: _menuPadding(),
        ),
        bind.mainDiscover),
    _TabEntry(
        AddressBook(
          menuPadding: _menuPadding(),
        ),
        ({dynamic hint}) => gFFI.abModel.pullAb(force: hint == null)),
    _TabEntry(
      MyGroup(
        menuPadding: _menuPadding(),
      ),
      ({dynamic hint}) => gFFI.groupModel.pull(force: hint == null),
    ),
  ];
  RelativeRect? mobileTabContextMenuPos;

  @override
  void initState() {
    final uiType = bind.getLocalFlutterOption(k: 'peer-card-ui-type');
    if (uiType != '') {
      peerCardUiType.value = int.parse(uiType) == PeerUiType.list.index
          ? PeerUiType.list
          : PeerUiType.grid;
    }
    hideAbTagsPanel.value =
        bind.mainGetLocalOption(key: "hideAbTagsPanel").isNotEmpty;
    super.initState();
  }

  Future<void> handleTabSelection(int tabIndex) async {
    if (tabIndex < entries.length) {
      gFFI.peerTabModel.setCurrentTab(tabIndex);
      entries[tabIndex].load(hint: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    Widget selectionWrap(Widget widget) {
      return model.multiSelectionMode ? createMultiSelectionBar() : widget;
    }

    return Column(
      textBaseline: TextBaseline.ideographic,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: Container(
            padding: isDesktop ? null : EdgeInsets.symmetric(horizontal: 2),
            child: selectionWrap(Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                    child:
                        visibleContextMenuListener(_createSwitchBar(context))),
                if (isMobile)
                  ..._mobileRightActions(context)
                else
                  ..._desktopRightActions(context)
              ],
            )),
          ),
        ).paddingOnly(right: isDesktop ? 12 : 0),
        _createPeersView(),
      ],
    );
  }

  Widget _createSwitchBar(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);

    return ListView(
        scrollDirection: Axis.horizontal,
        physics: NeverScrollableScrollPhysics(),
        children: model.visibleIndexs.map((t) {
          final selected = model.currentTab == t;
          final color = selected
              ? MyTheme.tabbar(context).selectedTextColor
              : MyTheme.tabbar(context).unSelectedTextColor
            ?..withOpacity(0.5);
          final hover = false.obs;
          final deco = BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.circular(6));
          final decoBorder = BoxDecoration(
              border: Border(
            bottom: BorderSide(width: 2, color: color!),
          ));
          return Obx(() => InkWell(
                child: Container(
                  decoration: (hover.value
                      ? (selected ? decoBorder : deco)
                      : (selected ? decoBorder : null)),
                  child: Tooltip(
                    preferBelow: false,
                    message: model.tabTooltip(t),
                    onTriggered: isMobile ? mobileShowTabVisibilityMenu : null,
                    child: Icon(model.tabIcon(t), color: color),
                  ).paddingSymmetric(horizontal: 4),
                ).paddingSymmetric(horizontal: 4),
                onTap: () async {
                  await handleTabSelection(t);
                  await bind.setLocalFlutterOption(
                      k: 'peer-tab-index', v: t.toString());
                },
                onHover: (value) => hover.value = value,
              ));
        }).toList());
  }

  Widget _createPeersView() {
    final model = Provider.of<PeerTabModel>(context);
    Widget child;
    if (model.visibleIndexs.isEmpty) {
      child = visibleContextMenuListener(Row(
        children: [Expanded(child: InkWell())],
      ));
    } else {
      if (model.visibleIndexs.contains(model.currentTab)) {
        child = entries[model.currentTab].widget;
      } else {
        debugPrint("should not happen! currentTab not in visibleIndexs");
        Future.delayed(Duration.zero, () {
          model.setCurrentTab(model.indexs[0]);
        });
        child = entries[0].widget;
      }
    }
    return Expanded(
        child: child.marginSymmetric(vertical: isDesktop ? 12.0 : 6.0));
  }

  Widget _createRefresh(
      {required PeerTabIndex index, required RxBool loading}) {
    final model = Provider.of<PeerTabModel>(context);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Offstage(
      offstage: model.currentTab != index.index,
      child: RefreshWidget(
          onPressed: () {
            if (gFFI.peerTabModel.currentTab < entries.length) {
              entries[gFFI.peerTabModel.currentTab].load();
            }
          },
          spinning: loading,
          child: RotatedBox(
              quarterTurns: 2,
              child: Tooltip(
                  message: translate('Refresh'),
                  child: Icon(
                    Icons.refresh,
                    size: 18,
                    color: textColor,
                  )))),
    );
  }

  Widget _createPeerViewTypeSwitch(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final types = [PeerUiType.grid, PeerUiType.list];

    return Obx(() => _hoverAction(
        context: context,
        onTap: () async {
          final type = types
              .elementAt(peerCardUiType.value == types.elementAt(0) ? 1 : 0);
          await bind.setLocalFlutterOption(
              k: 'peer-card-ui-type', v: type.index.toString());
          peerCardUiType.value = type;
        },
        child: Tooltip(
            message: peerCardUiType.value == PeerUiType.grid
                ? translate('List View')
                : translate('Grid View'),
            child: Icon(
              peerCardUiType.value == PeerUiType.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              size: 18,
              color: textColor,
            ))));
  }

  Widget _createMultiSelection() {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
      context: context,
      onTap: () {
        model.setMultiSelectionMode(true);
        if (isMobile && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Tooltip(
          message: translate('Select'),
          child: SvgPicture.asset(
            "assets/checkbox-outline.svg",
            width: 18,
            height: 18,
            color: textColor,
          )),
    );
  }

  void mobileShowTabVisibilityMenu() {
    final model = gFFI.peerTabModel;
    final items = List<PopupMenuItem>.empty(growable: true);
    for (int i = 0; i < model.tabNames.length; i++) {
      items.add(PopupMenuItem(
        height: kMinInteractiveDimension * 0.8,
        onTap: () => model.setTabVisible(i, !model.isVisible[i]),
        child: Row(
          children: [
            Checkbox(
                value: model.isVisible[i],
                onChanged: (_) {
                  model.setTabVisible(i, !model.isVisible[i]);
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                }),
            Expanded(child: Text(model.tabTooltip(i))),
          ],
        ),
      ));
    }
    if (mobileTabContextMenuPos != null) {
      showMenu(
          context: context, position: mobileTabContextMenuPos!, items: items);
    }
  }

  Widget visibleContextMenuListener(Widget child) {
    if (isMobile) {
      return GestureDetector(
        onLongPressDown: (e) {
          final x = e.globalPosition.dx;
          final y = e.globalPosition.dy;
          mobileTabContextMenuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onLongPressUp: () {
          mobileShowTabVisibilityMenu();
        },
        child: child,
      );
    } else {
      return Listener(
          onPointerDown: (e) {
            if (e.kind != ui.PointerDeviceKind.mouse) {
              return;
            }
            if (e.buttons == 2) {
              showRightMenu(
                (CancelFunc cancelFunc) {
                  return visibleContextMenu(cancelFunc);
                },
                target: e.position,
              );
            }
          },
          child: child);
    }
  }

  Widget visibleContextMenu(CancelFunc cancelFunc) {
    final model = Provider.of<PeerTabModel>(context);
    final menu = List<MenuEntrySwitch>.empty(growable: true);
    for (int i = 0; i < model.tabNames.length; i++) {
      menu.add(MenuEntrySwitch(
          switchType: SwitchType.scheckbox,
          text: model.tabTooltip(i),
          getter: () async {
            return model.isVisible[i];
          },
          setter: (show) async {
            model.setTabVisible(i, show);
            cancelFunc();
          }));
    }
    return mod_menu.PopupMenu(
        items: menu
            .map((entry) => entry.build(
                context,
                const MenuConfig(
                  commonColor: MyTheme.accent,
                  height: 20.0,
                  dividerHeight: 12.0,
                )))
            .expand((i) => i)
            .toList());
  }

  Widget createMultiSelectionBar() {
    final model = Provider.of<PeerTabModel>(context);
    return Row(
      children: [
        deleteSelection(),
        addSelectionToFav(),
        addSelectionToAb(),
        editSelectionTags(),
        Expanded(child: Container()),
        selectionCount(model.selectedPeers.length),
        selectAll(),
        closeSelection(),
      ],
    );
  }

  Widget deleteSelection() {
    final model = Provider.of<PeerTabModel>(context);
    if (model.currentTab == PeerTabIndex.group.index) {
      return Offstage();
    }
    return _hoverAction(
        context: context,
        onTap: () {
          onSubmit() async {
            final peers = model.selectedPeers;
            switch (model.currentTab) {
              case 0:
                peers.map((p) async {
                  await bind.mainRemovePeer(id: p.id);
                }).toList();
                await bind.mainLoadRecentPeers();
                break;
              case 1:
                final favs = (await bind.mainGetFav()).toList();
                peers.map((p) {
                  favs.remove(p.id);
                }).toList();
                await bind.mainStoreFav(favs: favs);
                await bind.mainLoadFavPeers();
                break;
              case 2:
                peers.map((p) async {
                  await bind.mainRemoveDiscovered(id: p.id);
                }).toList();
                await bind.mainLoadLanPeers();
                break;
              case 3:
                {
                  bool hasSynced = false;
                  if (shouldSyncAb()) {
                    for (var p in peers) {
                      if (await bind.mainPeerExists(id: p.id)) {
                        hasSynced = true;
                      }
                    }
                  }
                  gFFI.abModel.deletePeers(peers.map((p) => p.id).toList());
                  final future = gFFI.abModel.pushAb();
                  if (hasSynced) {
                    gFFI.abModel.reSyncToast(future);
                  }
                }
                break;
              default:
                break;
            }
            gFFI.peerTabModel.setMultiSelectionMode(false);
            if (model.currentTab != 3) showToast(translate('Successful'));
          }

          deletePeerConfirmDialog(onSubmit, translate('Delete'));
        },
        child: Tooltip(
            message: translate('Delete'),
            child: Icon(Icons.delete, color: Colors.red)));
  }

  Widget addSelectionToFav() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          model.currentTab != PeerTabIndex.recent.index, // show based on recent
      child: _hoverAction(
        context: context,
        onTap: () async {
          final peers = model.selectedPeers;
          final favs = (await bind.mainGetFav()).toList();
          for (var p in peers) {
            if (!favs.contains(p.id)) {
              favs.add(p.id);
            }
          }
          await bind.mainStoreFav(favs: favs);
          model.setMultiSelectionMode(false);
          showToast(translate('Successful'));
        },
        child: Tooltip(
            message: translate('Add to Favorites'),
            child: Icon(model.icons[PeerTabIndex.fav.index])),
      ).marginOnly(left: isMobile ? 11 : 6),
    );
  }

  Widget addSelectionToAb() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          !gFFI.userModel.isLogin || model.currentTab == PeerTabIndex.ab.index,
      child: _hoverAction(
        context: context,
        onTap: () {
          if (gFFI.abModel.isFull(true)) {
            return;
          }
          final peers = model.selectedPeers;
          gFFI.abModel.addPeers(peers);
          final future = gFFI.abModel.pushAb();
          model.setMultiSelectionMode(false);
          Future.delayed(Duration.zero, () async {
            await future;
            await Future.delayed(Duration(seconds: 2)); // toast
            gFFI.abModel.isFull(true);
          });
        },
        child: Tooltip(
            message: translate('Add to Address Book'),
            child: Icon(model.icons[PeerTabIndex.ab.index])),
      ).marginOnly(left: isMobile ? 11 : 6),
    );
  }

  Widget editSelectionTags() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage: !gFFI.userModel.isLogin ||
          model.currentTab != PeerTabIndex.ab.index ||
          gFFI.abModel.tags.isEmpty,
      child: _hoverAction(
              context: context,
              onTap: () {
                editAbTagDialog(List.empty(), (selectedTags) async {
                  final peers = model.selectedPeers;
                  gFFI.abModel.changeTagForPeers(
                      peers.map((p) => p.id).toList(), selectedTags);
                  gFFI.abModel.pushAb();
                  model.setMultiSelectionMode(false);
                  showToast(translate('Successful'));
                });
              },
              child: Tooltip(
                  message: translate('Edit Tag'), child: Icon(Icons.tag)))
          .marginOnly(left: isMobile ? 11 : 6),
    );
  }

  Widget selectionCount(int count) {
    return Align(
      alignment: Alignment.center,
      child: Text('$count ${translate('Selected')}'),
    );
  }

  Widget selectAll() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          model.selectedPeers.length >= model.currentTabCachedPeers.length,
      child: _hoverAction(
        context: context,
        onTap: () {
          model.selectAll();
        },
        child: Tooltip(
            message: translate('Select All'), child: Icon(Icons.select_all)),
      ).marginOnly(left: 6),
    );
  }

  Widget closeSelection() {
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
            context: context,
            onTap: () {
              model.setMultiSelectionMode(false);
            },
            child:
                Tooltip(message: translate('Close'), child: Icon(Icons.clear)))
        .marginOnly(left: 6);
  }

  Widget _toggleTags() {
    return _hoverAction(
        context: context,
        hoverableWhenfalse: hideAbTagsPanel,
        child: Tooltip(
            message: translate('Toggle Tags'),
            child: Icon(
              Icons.tag_rounded,
              size: 18,
            )),
        onTap: () async {
          await bind.mainSetLocalOption(
              key: "hideAbTagsPanel", value: hideAbTagsPanel.value ? "" : "Y");
          hideAbTagsPanel.value = !hideAbTagsPanel.value;
        });
  }

  List<Widget> _desktopRightActions(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    return [
      const PeerSearchBar().marginOnly(right: isMobile ? 0 : 13),
      _createRefresh(index: PeerTabIndex.ab, loading: gFFI.abModel.abLoading),
      _createRefresh(
          index: PeerTabIndex.group, loading: gFFI.groupModel.groupLoading),
      Offstage(
        offstage: model.currentTabCachedPeers.isEmpty,
        child: _createMultiSelection(),
      ),
      _createPeerViewTypeSwitch(context),
      Offstage(
        offstage: model.currentTab == PeerTabIndex.recent.index,
        child: PeerSortDropdown(),
      ),
      Offstage(
        offstage: model.currentTab != PeerTabIndex.ab.index,
        child: _toggleTags(),
      ),
    ];
  }

  List<Widget> _mobileRightActions(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final leftIconSize = Theme.of(context).iconTheme.size ?? 24;
    final leftActionsSize =
        (leftIconSize + (4 + 4) * 2) * model.visibleIndexs.length;
    final availableWidth = screenWidth - 10 * 2 - leftActionsSize - 2 * 2;
    final searchWidth = 120;
    final otherActionWidth = 18 + 10;

    dropDown(List<Widget> menus) {
      final padding = 6.0;
      final textColor = Theme.of(context).textTheme.titleLarge?.color;
      return PullDownButton(
        buttonBuilder:
            (BuildContext context, Future<void> Function() showMenu) {
          return _hoverAction(
            context: context,
            child: Tooltip(
                message: translate('More'),
                child: SvgPicture.asset(
                  "assets/chevron_up_chevron_down.svg",
                  width: 18,
                  height: 18,
                  color: textColor,
                )),
            onTap: showMenu,
          );
        },
        routeTheme: PullDownMenuRouteTheme(
            width: menus.length * (otherActionWidth + padding * 2) * 1.0),
        itemBuilder: (context) => [
          PullDownMenuEntryImpl(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: menus
                  .map((e) =>
                      Material(child: e.paddingSymmetric(horizontal: padding)))
                  .toList(),
            ),
          )
        ],
      );
    }

    // Always show search, refresh
    List<Widget> actions = [
      const PeerSearchBar(),
      if (model.currentTab == PeerTabIndex.ab.index)
        _createRefresh(index: PeerTabIndex.ab, loading: gFFI.abModel.abLoading),
      if (model.currentTab == PeerTabIndex.group.index)
        _createRefresh(
            index: PeerTabIndex.group, loading: gFFI.groupModel.groupLoading),
    ];
    final List<Widget> dynamicActions = [
      if (model.currentTabCachedPeers.isNotEmpty) _createMultiSelection(),
      if (model.currentTab != PeerTabIndex.recent.index) PeerSortDropdown(),
      if (model.currentTab == PeerTabIndex.ab.index) _toggleTags()
    ];
    final rightWidth = availableWidth -
        searchWidth -
        (actions.length == 2 ? otherActionWidth : 0);
    final availablePositions = rightWidth ~/ otherActionWidth;
    debugPrint(
        "dynamic action count:${dynamicActions.length}, available positions: $availablePositions");

    if (availablePositions < dynamicActions.length &&
        dynamicActions.length > 1) {
      if (availablePositions < 2) {
        actions.addAll([
          dropDown(dynamicActions),
        ]);
      } else {
        actions.addAll([
          ...dynamicActions.sublist(0, availablePositions - 1),
          dropDown(dynamicActions.sublist(availablePositions - 1)),
        ]);
      }
    } else {
      actions.addAll(dynamicActions);
    }
    return actions;
  }
}

class PeerSearchBar extends StatefulWidget {
  const PeerSearchBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PeerSearchBarState();
}

class _PeerSearchBarState extends State<PeerSearchBar> {
  var drawer = false;

  @override
  Widget build(BuildContext context) {
    return drawer
        ? _buildSearchBar()
        : _hoverAction(
            context: context,
            padding: const EdgeInsets.only(right: 2),
            onTap: () {
              setState(() {
                drawer = true;
              });
            },
            child: Tooltip(
                message: translate('Search'),
                child: Icon(
                  Icons.search_rounded,
                  color: Theme.of(context).hintColor,
                )));
  }

  Widget _buildSearchBar() {
    RxBool focused = false.obs;
    FocusNode focusNode = FocusNode();
    focusNode.addListener(() {
      focused.value = focusNode.hasFocus;
      peerSearchTextController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: peerSearchTextController.value.text.length);
    });
    return Container(
      width: isMobile ? 120 : 140,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Obx(() => Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).hintColor,
                    ).marginSymmetric(horizontal: 4),
                    Expanded(
                      child: TextField(
                        autofocus: true,
                        controller: peerSearchTextController,
                        onChanged: (searchText) {
                          peerSearchText.value = searchText;
                        },
                        focusNode: focusNode,
                        textAlign: TextAlign.start,
                        maxLines: 1,
                        cursorColor: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.5),
                        cursorHeight: 18,
                        cursorWidth: 1,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          hintText:
                              focused.value ? null : translate("Search ID"),
                          hintStyle: TextStyle(
                              fontSize: 14, color: Theme.of(context).hintColor),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    // Icon(Icons.close),
                    IconButton(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 2),
                      onPressed: () {
                        setState(() {
                          peerSearchTextController.clear();
                          peerSearchText.value = "";
                          drawer = false;
                        });
                      },
                      icon: Tooltip(
                          message: translate('Close'),
                          child: Icon(
                            Icons.close,
                            color: Theme.of(context).hintColor,
                          )),
                    ),
                  ],
                ),
              )
            ],
          )),
    );
  }
}

class PeerSortDropdown extends StatefulWidget {
  const PeerSortDropdown({super.key});

  @override
  State<PeerSortDropdown> createState() => _PeerSortDropdownState();
}

class _PeerSortDropdownState extends State<PeerSortDropdown> {
  @override
  void initState() {
    if (!PeerSortType.values.contains(peerSort.value)) {
      peerSort.value = PeerSortType.remoteId;
      bind.setLocalFlutterOption(
        k: "peer-sorting",
        v: peerSort.value,
      );
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.fontSize,
        fontWeight: FontWeight.normal);
    List<PopupMenuEntry> items = List.empty(growable: true);
    items.add(PopupMenuItem(
        height: 36,
        enabled: false,
        child: Text(translate("Sort by"), style: style)));
    for (var e in PeerSortType.values) {
      items.add(PopupMenuItem(
          height: 36,
          child: Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio(
                      Text(translate(e), style: style), e, peerSort.value,
                      dense: true, (String? v) async {
                    if (v != null) {
                      peerSort.value = v;
                      await bind.setLocalFlutterOption(
                        k: "peer-sorting",
                        v: peerSort.value,
                      );
                    }
                  }),
                ),
              ))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return _hoverAction(
      context: context,
      child: Tooltip(
          message: translate('Sort by'),
          child: Icon(
            Icons.sort_rounded,
            size: 18,
          )),
      onTapDown: (details) {
        final x = details.globalPosition.dx;
        final y = details.globalPosition.dy;
        menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onTap: () => showMenu(
        context: context,
        position: menuPos,
        items: items,
        elevation: 8,
      ),
    );
  }
}

class RefreshWidget extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final RxBool? spinning;
  const RefreshWidget(
      {super.key, required this.onPressed, required this.child, this.spinning});

  @override
  State<RefreshWidget> createState() => RefreshWidgetState();
}

class RefreshWidgetState extends State<RefreshWidget> {
  double turns = 0.0;
  bool hover = false;

  @override
  void initState() {
    super.initState();
    widget.spinning?.listen((v) {
      if (v && mounted) {
        setState(() {
          turns += 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: Theme.of(context).colorScheme.background,
      borderRadius: BorderRadius.circular(6),
    );
    return AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          if (widget.spinning?.value == true && mounted) {
            setState(() => turns += 1.0);
          }
        },
        child: Container(
          padding: EdgeInsets.all(4.0),
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration: hover ? deco : null,
          child: InkWell(
              onTap: () {
                if (mounted) setState(() => turns += 1.0);
                widget.onPressed();
              },
              onHover: (value) {
                if (mounted) {
                  setState(() {
                    hover = value;
                  });
                }
              },
              child: widget.child),
        ));
  }
}

Widget _hoverAction(
    {required BuildContext context,
    required Widget child,
    required Function() onTap,
    GestureTapDownCallback? onTapDown,
    RxBool? hoverableWhenfalse,
    EdgeInsetsGeometry padding = const EdgeInsets.all(4.0)}) {
  final hover = false.obs;
  final deco = BoxDecoration(
    color: Theme.of(context).colorScheme.background,
    borderRadius: BorderRadius.circular(6),
  );
  return Obx(
    () => Container(
        margin: EdgeInsets.symmetric(horizontal: 1),
        decoration:
            (hover.value || hoverableWhenfalse?.value == false) ? deco : null,
        child: InkWell(
            onHover: (value) => hover.value = value,
            onTap: onTap,
            onTapDown: onTapDown,
            child: Container(padding: padding, child: child))),
  );
}

class PullDownMenuEntryImpl extends StatelessWidget
    implements PullDownMenuEntry {
  final Widget child;
  const PullDownMenuEntryImpl({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
