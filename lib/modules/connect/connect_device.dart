import 'package:auto_route/auto_route.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:openmusic/collections/routes.gr.dart';
import 'package:openmusic/collections/openmusic_icons.dart';
import 'package:openmusic/extensions/constrains.dart';
import 'package:openmusic/extensions/context.dart';
import 'package:openmusic/provider/connect/clients.dart';

class ConnectDeviceButton extends HookConsumerWidget {
  final bool _sidebar;
  const ConnectDeviceButton({super.key}) : _sidebar = false;
  const ConnectDeviceButton.sidebar({super.key}) : _sidebar = true;

  @override
  Widget build(BuildContext context, ref) {
    final connectClients = ref.watch(connectClientsProvider);

    final hasServices =
        connectClients.asData?.value.services.isNotEmpty == true;

    if (_sidebar) {
      final mediaQuery = MediaQuery.sizeOf(context);

      if (mediaQuery.mdAndDown) {
        return IconButton.ghost(
          icon: const Icon(OpenMusicIcons.speaker),
          onPressed: () {
            context.navigateTo(const ConnectRoute());
          },
        );
      }

      return SizedBox(
        width: double.infinity,
        child: Button.primary(
          onPressed: () {
            context.navigateTo(const ConnectRoute());
          },
          trailing: const Icon(OpenMusicIcons.speaker),
          child: Text(
            "${context.l10n.devices}"
            "${hasServices ? " (${connectClients.asData?.value.services.length})" : ""}",
          ),
        ),
      );
    }

    return Row(
      children: [
        SecondaryBadge(
          onPressed: () {
            context.navigateTo(const ConnectRoute());
          },
          style: const ButtonStyle.secondary(size: ButtonSize(.8)),
          leading: connectClients.asData?.value.resolvedService != null
              ? const Center(
                  child: DotItem(
                    size: 6,
                    borderRadius: 10,
                    color: Colors.green,
                  ),
                )
              : null,
          child: Text(
            "${context.l10n.devices}"
            "${hasServices ? " (${connectClients.asData?.value.services.length})" : ""}",
          ),
        ),
        IconButton.primary(
          icon: const Icon(OpenMusicIcons.speaker),
          onPressed: () {
            context.navigateTo(const ConnectRoute());
          },
        ),
      ],
    );
  }
}
