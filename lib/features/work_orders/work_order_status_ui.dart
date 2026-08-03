/// İş Emirleri — kanonik durum sunum katmanı.
///
/// Faz 1 denetimi 7 farklı, birbiriyle çelişen durum etiket/renk kaynağı
/// tespit etti (bkz. docs/design-system/is-emirleri-critique-and-concepts.md
/// §A.1): aynı "done" durumu üç farklı yazıyla gösteriliyordu; kanban board,
/// kanban kartı ve detay sayfası ise `approval_pending`/`cancelled`
/// durumlarını hiç tanımıyordu (o iş emirleri kanban'da kayboluyor,
/// detay sayfasında "Bilinmiyor" görünüyordu).
///
/// Bu dosya TEK kaynaktır — liste, kanban ve detay sayfası artık buradan
/// okur. Durum kodları (`open`/`in_progress`/`approval_pending`/`done`/
/// `cancelled`, yazılan/okunan veri) değişmedi; yalnızca görsel sunum
/// birleştirildi. Business logic'e dokunulmadı.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_system/status_tone.dart';

class WorkOrderStatusInfo {
  const WorkOrderStatusInfo({
    required this.label,
    required this.compactLabel,
    required this.tone,
    required this.icon,
  });

  /// Uzun etiket — filtre pili, sekme, detay sayfası başlığı.
  final String label;

  /// Kısa/yoğun etiket — kart rozeti, dar tablo hücresi.
  final String compactLabel;
  final DsStatusTone tone;
  final IconData icon;
}

const Map<String, WorkOrderStatusInfo> _kWorkOrderStatuses = {
  'open': WorkOrderStatusInfo(
    label: 'Açık',
    compactLabel: 'AÇIK',
    tone: DsStatusTone.warning,
    icon: LucideIcons.circle,
  ),
  'in_progress': WorkOrderStatusInfo(
    label: 'Yapılıyor',
    compactLabel: 'YAPILIYOR',
    tone: DsStatusTone.info,
    icon: LucideIcons.refreshCw,
  ),
  'approval_pending': WorkOrderStatusInfo(
    label: 'Onay Bekliyor',
    compactLabel: 'ONAY BEKLİYOR',
    tone: DsStatusTone.info,
    icon: LucideIcons.hourglass,
  ),
  'done': WorkOrderStatusInfo(
    label: 'Tamamlandı',
    compactLabel: 'TAMAMLANDI',
    tone: DsStatusTone.success,
    icon: LucideIcons.circleCheck,
  ),
  'cancelled': WorkOrderStatusInfo(
    label: 'İptal',
    compactLabel: 'İPTAL',
    tone: DsStatusTone.danger,
    icon: LucideIcons.circleX,
  ),
};

/// Görüntülenme sırası — hem liste ekranının durum filtresi hem kanban'ın
/// kolon/tab sırası bu listeden türetilir; hiçbir gerçek durum bir yerde
/// görünüp diğerinde kaybolmaz.
const List<String> kWorkOrderStatusOrder = [
  'open',
  'in_progress',
  'approval_pending',
  'done',
  'cancelled',
];

/// Bilinmeyen bir durum kodu gelirse (ör. ileride eklenecek yeni bir durum)
/// gizlenmez — nötr fallback ile, ham koddan üretilmiş okunur bir etiketle
/// gösterilir.
WorkOrderStatusInfo workOrderStatusInfo(String status) {
  final known = _kWorkOrderStatuses[status];
  if (known != null) return known;
  final fallbackLabel = status.trim().isEmpty
      ? 'Bilinmiyor'
      : status.toUpperCase();
  return WorkOrderStatusInfo(
    label: fallbackLabel,
    compactLabel: fallbackLabel,
    tone: DsStatusTone.neutral,
    icon: LucideIcons.circleHelp,
  );
}

Color workOrderStatusColor(String status) =>
    dsStatusToneColor(workOrderStatusInfo(status).tone);

/// Standart durum rozeti — `DsStatusBadge`'i (design_system) bu domain'e
/// bağlar. `dense=true` kısa/yoğun etiketi kullanır (kart rozeti),
/// `dense=false` uzun etiketi kullanır (filtre pili, detay başlığı).
Widget workOrderStatusBadge(String status, {bool dense = false}) {
  final info = workOrderStatusInfo(status);
  return DsStatusBadge(
    label: dense ? info.compactLabel : info.label,
    tone: info.tone,
    dense: dense,
  );
}
