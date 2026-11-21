import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../assistant/assistant_chat.dart';
import '../notifications/notifications_screen.dart';
import '../search/global_search.dart';
import '../shell/account_menu.dart';
import '../shell/app_shell.dart';
import '../shell/service_nav.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';
import 'art3d.dart';
import 'motion.dart';

/// Every page's frame: a frosted-glass app bar with the page blurred behind
/// it as it scrolls, over Health Pro's soft background. The content uses the
/// window's width (up to [wideWidth], so very wide screens stay readable);
/// pages lay themselves out for it with [ResponsiveGrid] and
/// [ResponsiveColumns]. Short forms pass [maxWidth] = [readableWidth].
///
/// Scrolling bodies should use [pagePadding] so their first and last items
/// clear the bars.
class AppPage extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;

  /// Extra buttons in the top bar. Pages don't use it: their own buttons go
  /// under the bar, at the top of their content ([PageActions]), so the bar
  /// keeps room for the title, search and the app's buttons.
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomBar;

  /// How wide the content may grow: [wideWidth] unless given.
  final double? maxWidth;

  const AppPage({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    required this.body,
    this.floatingActionButton,
    this.bottomBar,
    this.maxWidth,
  });

  /// Most pages: the whole window, up to this.
  static const wideWidth = 1600.0;

  /// A short form or a page of text: a column that's comfortable to read.
  static const readableWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    // In the app's frame on a phone, a page with nothing to go back to opens
    // the menu from its bar. In the frame (signed in), the bar ends with
    // light or dark, their notifications and their account.
    final scope = AppShellScope.maybeOf(context);
    final openMenu = scope?.openMenu;
    final service = scope?.service;
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    final lead = leading ??
        (openMenu != null && !canGoBack
            ? IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu_rounded), onPressed: openMenu)
            : null);
    // A service's page: its name over the title, and its shortcuts.
    final Widget? heading = titleWidget ??
        (title == null
            ? null
            : service == null
                ? Text(title!)
                : _ServiceTitle(service: service, title: title!));
    // The search: on a computer a field in the middle of the bar, after the
    // title; on a phone an icon before the title (close beside the menu
    // button). In the frame the bar's ends line up with the page's gutters
    // (the account's avatar has 6 of its own at the right).
    final openSearch = scope?.openSearch;
    final searchField = openSearch != null && GlobalSearchBox.shows(context);
    final gutter = pageGutter(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final askAi = AskAiScope.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: GlassAppBar(
        title: openSearch == null || searchField ? heading : TitleWithSearch(heading: heading, onSearch: openSearch),
        search: searchField ? GlobalSearchBox(onPressed: openSearch) : null,
        titleSpacing: openSearch == null
            ? null
            : lead == null
                ? gutter
                : GlobalSearchBox.shows(context)
                    ? null
                    : 0,
        endSpacing: scope == null ? 8 : gutter - 6,
        actions: [
          ...?actions,
          if (service != null && service.actionsInBar && service.actions.isNotEmpty) ServiceActionsButton(service: service),
          if (scope != null) ...[
            SizedBox(width: wide ? 10 : 4),
            // Ask AI before light or dark: its own button on a computer, an
            // icon with the others on a phone.
            if (wide && askAi != null) ...[AskAiBarButton(onPressed: askAi), const SizedBox(width: 10)],
            _BarTray(children: [
              if (!wide && askAi != null) AskAiBarButton(onPressed: askAi),
              const ThemeModeButton(),
              const NotificationBell(),
            ]),
            if (wide) const _BarDivider(),
            const AccountButton(),
          ] else if (askAi != null) ...[
            // Visitors: Ask AI at the end of the bar.
            SizedBox(width: wide ? 10 : 4),
            AskAiBarButton(onPressed: askAi),
          ],
        ],
        leading: lead,
      ),
      body: ScrollProgressOverlay(
        top: MediaQuery.paddingOf(context).top + kToolbarHeight - 2,
        child: BrandBackdrop(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth ?? wideWidth), child: body),
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null ? null : GlassBar(child: SafeArea(top: false, child: bottomBar!)),
    );
  }
}

/// A service page's title: the page's 3D icon (the side menu's) in a tile
/// ringed in the theme's two colours, the gym on a badge, the title in a
/// gradient. On a phone the badge and the title only.
class _ServiceTitle extends StatelessWidget {
  final ServiceNav service;
  final String title;

  const _ServiceTitle({required this.service, required this.title});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final brand = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The theme's two colours (Account -> Appearance): the primary (orange
    // until picked) for the gym, the accent (navy until picked, deep into a
    // brighter shade of it) for the title. Text is white under the shader.
    final warm = brand.accent;
    final ink = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
    final cool = ink
        .withLightness((ink.lightness + (dark ? 0.12 : 0.22)).clamp(0.0, dark ? 0.9 : 0.5))
        .withSaturation((ink.saturation + 0.15).clamp(0.0, 1.0))
        .toColor();
    Widget gradient(List<Color> colors, Widget child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(colors: colors).createShader(bounds),
          child: child,
        );

    final name = gradient(
      [brand.accentText, warm],
      Text(
        (service.scope?.label ?? service.name).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.2, height: 1.3),
      ),
    );
    // On a computer the gym sits on a badge with a glowing dot; a phone's bar
    // has no room for it, so there the name alone.
    final badge = Container(
      padding: const EdgeInsets.fromLTRB(7, 2.5, 9, 2.5),
      decoration: BoxDecoration(
        color: warm.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: warm.withValues(alpha: dark ? 0.32 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [warm, brand.accentText]),
              boxShadow: [BoxShadow(color: warm.withValues(alpha: 0.6), blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: name),
        ],
      ),
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide) badge else name,
        const SizedBox(height: 3),
        gradient(
          [ink.toColor(), cool],
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.1)),
        ),
      ],
    );
    if (!wide) return text;

    // The page's own 3D icon, as in the side menu; the service's where it has none.
    final location = GoRouter.maybeOf(context)?.routerDelegate.currentConfiguration.uri.path;
    final art = location == null ? null : service.openAt(location)?.art;
    final surface = brand.card;
    final mark = art == null ? Icon(service.icon, size: 21, color: brand.accentText) : Art3DIcon(art, size: 26, fallback: service.icon);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A ring that is the primary at one corner and the accent at the
        // other, fading through the bar between; a glow of each beneath.
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [warm, warm.withValues(alpha: 0.15), cool.withValues(alpha: 0.15), cool],
              stops: const [0, 0.45, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(color: warm.withValues(alpha: dark ? 0.2 : 0.22), blurRadius: 16, offset: const Offset(-3, 4)),
              BoxShadow(color: cool.withValues(alpha: dark ? 0.2 : 0.16), blurRadius: 16, offset: const Offset(4, 6)),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(warm.withValues(alpha: dark ? 0.18 : 0.12), surface),
                  Color.alphaBlend(cool.withValues(alpha: dark ? 0.16 : 0.08), surface),
                ],
              ),
            ),
            // Pops in with each page, still when they ask for less motion.
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(art?.name ?? service.key),
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion(context) ? Duration.zero : Motion.card,
                curve: Motion.pop,
                builder: (context, t, child) => Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
                ),
                child: mark,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(child: text),
      ],
    );
  }
}

/// The bar's small buttons (light or dark, notifications): on a computer one
/// rounded tray, a hairline between them, as tall as New; loose on a phone.
class _BarTray extends StatelessWidget {
  final List<Widget> children;

  const _BarTray({required this.children});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 700) return Row(mainAxisSize: MainAxisSize.min, children: children);
    final brand = context.brand;
    final line = brand.pick(LightColors.border, brand.glassBorder);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: brand.pick(LightColors.card, brand.surfaceAlt),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: IconButtonTheme(
        // Smaller buttons, keeping the bar's icon colour.
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 34),
            fixedSize: const Size(36, 34),
            padding: EdgeInsets.zero,
            iconSize: 20,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ).merge(IconButtonTheme.of(context).style),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 2), color: line),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// A hairline in the bar, before the account.
class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.only(left: 12, right: 6),
        color: context.brand.pick(context.brand.fieldBorder, context.brand.glassBorder),
      );
}

/// New: the shortcuts of the service the page belongs to (Register member,
/// Check in...). A labelled button on a computer, an icon on a phone.
class ServiceActionsButton extends StatelessWidget {
  final ServiceNav service;

  /// In the top bar (an icon on a phone), or on a page under it, where it's
  /// always the New button.
  final bool inBar;

  const ServiceActionsButton({super.key, required this.service, this.inBar = true});

  /// The open service's New menu, for a page to show under the bar (in its
  /// [PageActions]); null when the service has no shortcuts.
  static Widget? onPage(BuildContext context) {
    final service = AppShellScope.maybeOf(context)?.service;
    if (service == null || service.actions.isEmpty) return null;
    return ServiceActionsButton(service: service, inBar: false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = !inBar || MediaQuery.sizeOf(context).width >= 700;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: context.brand.glassBorder)),
        ),
      ),
      menuChildren: [
        for (final a in service.actions)
          MenuItemButton(
            leadingIcon: Icon(a.icon, size: 20, color: context.brand.themed(service.color)),
            onPressed: () => GoRouter.of(context).go(a.route),
            child: Padding(padding: const EdgeInsets.only(right: 16), child: Text(a.label)),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (!wide) {
          return IconButton(tooltip: 'New', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: toggle);
        }
        return Padding(
          padding: EdgeInsets.only(left: inBar ? 8 : 0),
          child: Pressable(
            child: FilledButton.icon(
              onPressed: toggle,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              // The plus turns a quarter while its menu is open.
              icon: AnimatedRotation(
                turns: controller.isOpen ? 0.125 : 0,
                duration: Motion.of(context, Motion.dropdown),
                curve: Motion.ease,
                child: const Icon(Icons.add_rounded, size: 20),
              ),
              label: const Text('New'),
            ),
          ),
        );
      },
    );
  }
}

/// Room for the bars above and below a scrolling page, plus a gutter.
///
/// Works from either side of the [AppPage]: a screen building one has a
/// [context] above its Scaffold, whose padding doesn't count the app bar yet;
/// a widget inside the body already has the app bar in its padding.
/// The gutter grows on wide windows (28) from a phone's (16), unless
/// [horizontal] is given.
EdgeInsets pagePadding(BuildContext context, {double? horizontal, double top = 12, double bottom = 24}) {
  final insets = MediaQuery.paddingOf(context);
  final appBar = context.findAncestorWidgetOfExactType<AppPage>() == null ? kToolbarHeight : 0.0;
  final gutter = horizontal ?? pageGutter(context);
  return EdgeInsets.fromLTRB(gutter, insets.top + appBar + top, gutter, insets.bottom + bottom);
}

/// The page's side gutter: 28 on a wide window, 16 on a phone.
double pageGutter(BuildContext context) => MediaQuery.sizeOf(context).width >= 900 ? 28.0 : 16.0;

/// A translucent app bar that blurs what scrolls under it.
///
/// With [search]: the title at the left, the search in the middle of the bar
/// (moved aside only when the actions need the room), the actions at the
/// right.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;

  /// The search field, centred in the bar.
  final Widget? search;

  /// Room between [leading] and [title]; the theme's when null.
  final double? titleSpacing;

  /// Room after the last action.
  final double endSpacing;

  const GlassAppBar(
      {super.key, this.title, this.actions, this.leading, this.search, this.titleSpacing, this.endSpacing = 8});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final glass = GlassBar(border: Border(bottom: BorderSide(color: context.brand.glassBorder)));
    final trailing = [...?actions, SizedBox(width: endSpacing)];
    if (search == null) {
      return AppBar(title: title, leading: leading, titleSpacing: titleSpacing, actions: trailing, flexibleSpace: glass);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final searchWidth = (width * 0.42).clamp(300.0, 560.0);
        // The title has everything left of the search, less a gap.
        final start = ((width - searchWidth) / 2 - 24).clamp(0.0, width);
        // AppBar's own back button, as it would have put it.
        final route = ModalRoute.of(context);
        final lead = leading ??
            (route?.impliesAppBarDismissal ?? false
                ? (route is PageRoute && route.fullscreenDialog ? const CloseButton() : const BackButton())
                : null);
        final theme = Theme.of(context);
        return AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: start,
          leading: Row(
            children: [
              if (lead != null) ...[SizedBox(width: kToolbarHeight, child: Center(child: lead)), const SizedBox(width: 4)]
              else SizedBox(width: titleSpacing ?? NavigationToolbar.kMiddleSpacing),
              if (title != null)
                Expanded(
                  child: Semantics(
                    header: true,
                    child: DefaultTextStyle(
                      style: theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: Align(alignment: AlignmentDirectional.centerStart, child: title),
                    ),
                  ),
                ),
            ],
          ),
          centerTitle: true,
          title: SizedBox(width: searchWidth, child: search),
          actions: trailing,
          flexibleSpace: glass,
        );
      },
    );
  }
}

/// Frosted glass: the page behind is blurred and lightened (or darkened).
class GlassBar extends StatelessWidget {
  final Widget? child;
  final BoxBorder? border;

  const GlassBar({super.key, this.child, this.border});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: brand.glass,
            border: border ?? Border(top: BorderSide(color: brand.glassBorder)),
          ),
          child: child ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The soft background: the page colour with two wide glows, navy-blue and
/// orange, for the glass to blur.
class BrandBackdrop extends StatelessWidget {
  final Widget child;

  const BrandBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DecoratedBox(
      decoration: BoxDecoration(color: brand.background),
      child: Stack(
        children: [
          Positioned(top: -140, right: -120, child: _Glow(color: brand.glowA, size: 420)),
          Positioned(bottom: -160, left: -140, child: _Glow(color: brand.glowB, size: 460)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
