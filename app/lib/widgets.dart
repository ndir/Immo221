import 'package:flutter/material.dart';

import 'theme.dart';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Carte de la carte du Sénégal en filigrane derrière un écran.
class Watermarked extends StatelessWidget {
  final Widget child;
  final double top;
  const Watermarked({super.key, required this.child, this.top = 0.45});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return Stack(children: [
        Positioned(
          left: -c.maxWidth * 0.05,
          top: c.maxHeight * top,
          width: c.maxWidth * 1.1,
          child: IgnorePointer(
            child: Opacity(opacity: 0.07, child: Image.asset('assets/senegal.png', fit: BoxFit.contain)),
          ),
        ),
        Positioned.fill(child: child),
      ]);
    });
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const Pill(this.text, {super.key, this.background = DekkColors.ochre, this.foreground = DekkColors.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: foreground)),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: DekkColors.muted),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  const StatTile(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Cloche avec compteur de non-lus.
class BellButton extends StatelessWidget {
  final int unread;
  final VoidCallback onPressed;
  const BellButton({super.key, required this.unread, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: unread > 0 ? 'Notifications, $unread nouvelles' : 'Notifications',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: DekkColors.badge,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class LoadingOr extends StatelessWidget {
  final bool loading;
  final Widget child;
  const LoadingOr({super.key, required this.loading, required this.child});

  @override
  Widget build(BuildContext context) =>
      loading ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : child;
}

/// Champ « oui / non / non précisé » réutilisable.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;
  const InfoRow(this.label, this.value, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: warn ? DekkColors.warnBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 14, color: warn ? DekkColors.ochreInk : DekkColors.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: warn ? DekkColors.ochreInk : DekkColors.ink)),
        ),
      ]),
    );
  }
}
