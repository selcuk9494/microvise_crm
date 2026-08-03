/// Servis kayıtları — kanonik durum sunum katmanı.
///
/// Bu modülde aynı beş durum (`open`/`waiting`, `in_progress`/`approval`,
/// `ready`, `done`, `cancelled`) için beş bağımsız, birbiriyle çelişen
/// etiket/renk kaynağı tespit edildi: liste kartı "Teslim" derken detay
/// panelinin filtre pili "Tamamlandı" diyordu; "waiting" durumu bir yerde
/// "Bekliyor", filtre pilinde "Beklemede" idi. Daha ciddisi: `cancelled`
/// durumu üç yerden ikisinde hiç tanınmıyordu — detay panelinde ham
/// "cancelled" (İngilizce, çevrilmemiş) metniyle, liste kartında ise sadece
/// "—" ile gösteriliyor, kullanıcı iptal edilmiş bir servisi normal bir
/// kayıttan ayırt edemiyordu.
///
/// Bu dosya TEK kaynaktır — liste kartı, detay paneli ve detay ekranı
/// artık buradan okur. Durum kodları ve business logic değişmedi; yalnızca
/// görsel sunum birleştirildi.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/status_tone.dart';

class ServiceStatusInfo {
  const ServiceStatusInfo({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final DsStatusTone tone;
  final IconData icon;
}

const List<String> kServiceStatusOrder = [
  'waiting',
  'approval',
  'ready',
  'done',
  'cancelled',
];

/// Bilinmeyen bir durum kodu gelirse gizlenmez — nötr fallback ile, ham
/// koddan üretilmiş okunur bir etiketle gösterilir.
ServiceStatusInfo serviceStatusInfo(String status) {
  switch (status) {
    case 'open':
    case 'waiting':
      return const ServiceStatusInfo(
        label: 'Bekliyor',
        tone: DsStatusTone.warning,
        icon: LucideIcons.hourglass,
      );
    case 'in_progress':
    case 'approval':
      return const ServiceStatusInfo(
        label: 'Onayda',
        tone: DsStatusTone.info,
        icon: LucideIcons.hourglass,
      );
    case 'ready':
      return const ServiceStatusInfo(
        label: 'Hazır',
        tone: DsStatusTone.success,
        icon: LucideIcons.package,
      );
    case 'done':
      return const ServiceStatusInfo(
        label: 'Teslim',
        tone: DsStatusTone.success,
        icon: LucideIcons.circleCheck,
      );
    case 'cancelled':
      return const ServiceStatusInfo(
        label: 'İptal',
        tone: DsStatusTone.danger,
        icon: LucideIcons.circleX,
      );
    default:
      final fallbackLabel = status.trim().isEmpty
          ? 'Bilinmiyor'
          : status.toUpperCase();
      return ServiceStatusInfo(
        label: fallbackLabel,
        tone: DsStatusTone.neutral,
        icon: LucideIcons.circleHelp,
      );
  }
}

Color serviceStatusColor(String status) =>
    dsStatusToneColor(serviceStatusInfo(status).tone);

Widget serviceStatusBadge(String status, {bool dense = false}) {
  final info = serviceStatusInfo(status);
  return DsStatusBadge(label: info.label, tone: info.tone, dense: dense);
}
