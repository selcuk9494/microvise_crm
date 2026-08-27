import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/tsm_log/tsm_log_parser.dart';

void main() {
  group('TsmLogParser', () {
    test('onaylanan ve eslesmeyen TermSeriNo degerlerini cikarir', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı'],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
        ],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>2D10041612</TermSeriNo>',
        ],
        [
          'BASKA_ISLEM',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041613</TermSeriNo>',
        ],
        [
          'TERMINAL_SORGU',
          'İŞLEM REDDEDİLDİ <TermSeriNo>2D10041614</TermSeriNo>',
        ],
      ]);

      expect(result.error, isNull);
      expect(
        result.uniqueSerials.map((item) => item.serialNumber),
        ['2D10041611', '2D10041612', '2D10041614'],
      );
      expect(
        result.uniqueSerials.first.resultKinds,
        {TsmLogResultKind.approved},
      );
      expect(
        result.uniqueSerials[1].resultKinds,
        {TsmLogResultKind.serialMismatch},
      );
      expect(
        result.uniqueSerials.last.resultKinds,
        {TsmLogResultKind.other},
      );
      expect(
        result.uniqueSerials.last.resultMessages,
        {'İŞLEM REDDEDİLDİ'},
      );
    });

    test('html kacisli TermSeriNo etiketini okur', () {
      final serials = extractTermSeriNos(
        'İŞLEM ONAYLANDI &lt;TermSeriNo&gt;2D10041611&lt;/TermSeriNo&gt;',
      );
      expect(serials, ['2D10041611']);
    });

    test('yalnizca 2 ile baslayan terminal numaralarini alir', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı'],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
        ],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>1A10041611</TermSeriNo>',
        ],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>PAX123</TermSeriNo>',
        ],
      ]);

      expect(
        result.uniqueSerials.map((item) => item.serialNumber),
        ['2D10041611'],
      );
    });

    test('ayni sicili islem ve sonuc bazinda birlestirir', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı'],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
        ],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>2D10041611</TermSeriNo>',
        ],
      ]);

      expect(result.uniqueSerials.length, 1);
      expect(result.uniqueSerials.first.count, 2);
      expect(result.uniqueSerials.first.operations, {
        TsmLogOperation.terminalSorgu,
        TsmLogOperation.isemriAcma,
      });
      expect(result.uniqueSerials.first.resultKinds, {
        TsmLogResultKind.approved,
        TsmLogResultKind.serialMismatch,
      });
    });

    test('eklenme tarihi ve saati kolonundan occurredAt okur', () {
      final result = parseTsmLogRows([
        const [
          'Eklenme Tarihi',
          'Ekleme Saati',
          'İşlem',
          'Sonuç Mesajı',
        ],
        [
          '2026-06-05',
          '17:04:33',
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
        ],
      ]);
      expect(result.uniqueSerials.single.serialNumber, '2D10041611');
      expect(result.uniqueSerials.single.occurredAt, DateTime(2026, 6, 5, 17, 4, 33));
    });

    test('ISO datetime metninden occurredAt okur', () {
      final parsed = parseTsmLogDateTime('2026-06-05T14:04:33.000Z');
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 6);
      expect(parsed.day, 5);
    });

    test('excel baytlarindan sicil numaralarini okur', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        excel.TextCellValue('İşlem'),
        excel.TextCellValue('Sonuç Mesajı'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('TERMINAL_SORGU'),
        excel.TextCellValue(
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
        ),
      ]);
      final bytes = book.encode();
      expect(bytes, isNotNull);

      final result = parseTsmLogExcel(
        Uint8List.fromList(bytes!),
        fileName: 'tsm.xlsx',
      );
      expect(result.uniqueSerials.single.serialNumber, '2D10041611');
    });

    test('giris parametreleri kolonundaki TermSeriNo degerini okur', () {
      final result = parseTsmLogRows([
        const [
          'İşlem',
          'Sonuç Mesajı',
          'Giriş Parametreleri',
        ],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI',
          '<BKM_TerminalInquiryIn><TermSeriNo>2D10041611</TermSeriNo></BKM_TerminalInquiryIn>',
        ],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ.',
          '<BKM_OpenTaskIn><TermSeriNo>2D10049472</TermSeriNo></BKM_OpenTaskIn>',
        ],
      ]);
      expect(
        result.uniqueSerials.map((item) => item.serialNumber),
        ['2D10041611', '2D10049472'],
      );
    });

    test('html olarak kaydedilmis xls dosyasini okur', () {
      const html = '''
<html>
<table>
<tr><td>İşlem</td><td>Sonuç Mesajı</td></tr>
<tr><td>TERMINAL_SORGU</td><td>İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo></td></tr>
</table>
</html>
''';
      final result = parseTsmLogExcel(
        Uint8List.fromList(utf8.encode(html)),
        fileName: 'tsm.xls',
      );
      expect(result.error, isNull);
      expect(result.uniqueSerials.single.serialNumber, '2D10041611');
    });

    test('isemri acma onay xmlinden banka isyeri ve kurulum tipini okur', () {
      const xml = '''
<BKM_OpenTaskIn>
  <IsEmriGiris>
    <IsEmriKodu>K</IsEmriKodu>
    <Aciklama>TechPos Acquirer WS Tarafından Gönderilen Kurulum Emridir</Aciklama>
    <AcquirerEkranAdi>HALKBANK</AcquirerEkranAdi>
    <AcquirerId>12</AcquirerId>
    <TermId>02844878</TermId>
    <TermSeriNo>2D10041482</TermSeriNo>
    <IsyeriAdi>ATLILAR ELEKTRONIK</IsyeriAdi>
    <IsyeriNo>000000004226297</IsyeriNo>
    <BkmMerchantId>21846347</BkmMerchantId>
    <IsyeriAdres1>ATLILAR ELEKTRONIK ZIYA RIZKI CADDESI PO</IsyeriAdres1>
    <IsyeriAdres4>GIRNE (392) 1111111</IsyeriAdres4>
    <IsyeriSehir>GIRNE</IsyeriSehir>
    <IsyeriIlce>MERKEZ</IsyeriIlce>
    <IsyeriTel>3921111111</IsyeriTel>
    <KurumToken>SECRET-TOKEN</KurumToken>
  </IsEmriGiris>
</BKM_OpenTaskIn>
''';
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı', 'Giriş Parametreleri'],
        ['ISEMRI_ACMA', 'İŞLEM ONAYLANDI', xml],
      ]);
      final order = result.uniqueSerials.single.workOrder;
      expect(result.uniqueSerials.single.serialNumber, '2D10041482');
      expect(order?.bankName, 'HALKBANK');
      expect(order?.acquirerId, '12');
      expect(
        tsmDisplayBankName(order, const {'12': 'Halk Bankası'}),
        'Halk Bankası',
      );
      expect(order?.terminalId, '02844878');
      expect(order?.merchantName, 'ATLILAR ELEKTRONIK');
      expect(order?.merchantNo, '000000004226297');
      expect(order?.bkmMerchantId, '21846347');
      expect(order?.city, 'GIRNE');
      expect(order?.district, 'MERKEZ');
      expect(order?.phone, '3921111111');
      expect(order?.orderKind, TsmOrderKind.kurulum);
      expect(order?.displayAddress, contains('ZIYA RIZKI'));
      expect(order?.merchantLine, contains('ATLILAR'));
      expect(order?.description, contains('Kurulum Emridir'));
      expect(jsonEncode(order?.merchantName), isNot(contains('SECRET-TOKEN')));
    });

    test('silme aciklamasini geri alim olarak siniflar', () {
      const xml = '''
<BKM_OpenTaskIn>
  <IsEmriKodu>TS</IsEmriKodu>
  <Aciklama>Terminal Silme Bildirimidir</Aciklama>
  <AcquirerEkranAdi>ZIRAAT BANKASI</AcquirerEkranAdi>
  <TermSeriNo>2D10049472</TermSeriNo>
</BKM_OpenTaskIn>
''';
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı', 'Giriş Parametreleri'],
        ['ISEMRI_ACMA', 'İŞLEM ONAYLANDI', xml],
      ]);
      expect(
        result.uniqueSerials.single.workOrder?.orderKind,
        TsmOrderKind.geriAlim,
      );
      expect(
        tsmOrderKindLabel(result.uniqueSerials.single.workOrder!.orderKind),
        'Geri Alım',
      );
      expect(
        result.uniqueSerials.single.workOrder?.bankName,
        'ZIRAAT BANKASI',
      );
    });

    test('tanimsiz acquirerId icin xml banka adini kullanir', () {
      expect(
        tsmDisplayBankName(
          const TsmWorkOrderDetails(
            bankName: 'HALKBANK',
            acquirerId: '12',
          ),
          const {},
        ),
        'HALKBANK',
      );
      expect(
        tsmDisplayBankName(
          const TsmWorkOrderDetails(acquirerId: '12'),
          const {},
        ),
        'BKM 12',
      );
    });

    test('bos banka filtresi yalnizca bankasi olmayan kayitlari gosterir', () {
      const withBank = TsmLogSerial(
        serialNumber: '2D10040010',
        operations: {TsmLogOperation.terminalSorgu},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
        workOrder: TsmWorkOrderDetails(bankName: 'HALKBANK', acquirerId: '12'),
      );
      const emptyBank = TsmLogSerial(
        serialNumber: '2D10040011',
        operations: {TsmLogOperation.terminalSorgu},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
      );
      expect(
        tsmLogSerialMatchesFilters(
          withBank,
          bankFilter: kTsmBankFilterEmpty,
        ),
        isFalse,
      );
      expect(
        tsmLogSerialMatchesFilters(
          emptyBank,
          bankFilter: kTsmBankFilterEmpty,
        ),
        isTrue,
      );
    });

    test('bos is emri filtresi sadece turu olmayan kayitlari birakir', () {
      const emptyKind = TsmLogSerial(
        serialNumber: '2D10040003',
        operations: {TsmLogOperation.terminalSorgu},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
      );
      const kurulum = TsmLogSerial(
        serialNumber: '2D10040004',
        operations: {TsmLogOperation.isemriAcma},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
        workOrder: TsmWorkOrderDetails(orderKind: TsmOrderKind.kurulum),
      );
      expect(
        tsmLogSerialMatchesFilters(
          emptyKind,
          orderKindFilter: kTsmOrderKindFilterEmpty,
        ),
        isTrue,
      );
      expect(
        tsmLogSerialMatchesFilters(
          kurulum,
          orderKindFilter: kTsmOrderKindFilterEmpty,
        ),
        isFalse,
      );
    });

    test('kurulum filtresi geri alim kayitlarini disarida birakir', () {
      const kurulum = TsmLogSerial(
        serialNumber: '2D10040001',
        operations: {TsmLogOperation.isemriAcma},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
        workOrder: TsmWorkOrderDetails(orderKind: TsmOrderKind.kurulum),
      );
      const geriAlim = TsmLogSerial(
        serialNumber: '2D10040002',
        operations: {TsmLogOperation.isemriAcma},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
        workOrder: TsmWorkOrderDetails(orderKind: TsmOrderKind.geriAlim),
      );
      expect(
        tsmLogSerialMatchesFilters(
          kurulum,
          resultFilter: 'ONAY',
          orderKindFilter: 'KURULUM',
        ),
        isTrue,
      );
      expect(
        tsmLogSerialMatchesFilters(
          geriAlim,
          resultFilter: 'ONAY',
          orderKindFilter: 'KURULUM',
        ),
        isFalse,
      );
    });

    test('tarih filtresi baska gundeki kayitlari gizler', () {
      final item = TsmLogSerial(
        serialNumber: '2D10040003',
        operations: {TsmLogOperation.terminalSorgu},
        resultKinds: {TsmLogResultKind.approved},
        count: 1,
        occurredAt: DateTime(2026, 8, 20, 14, 30),
      );
      expect(
        tsmLogSerialMatchesFilters(
          item,
          dateFilter: DateTime(2026, 8, 27),
          fileHasDates: true,
        ),
        isFalse,
      );
      expect(
        tsmLogSerialMatchesFilters(
          item,
          dateFilter: DateTime(2026, 8, 20),
          fileHasDates: true,
        ),
        isTrue,
      );
      expect(
        tsmLogSerialMatchesFilters(
          item,
          dateFrom: DateTime(2026, 8, 18),
          dateTo: DateTime(2026, 8, 21),
          fileHasDates: true,
        ),
        isTrue,
      );
      expect(
        tsmLogSerialMatchesFilters(
          item,
          dateFrom: DateTime(2026, 8, 21),
          dateTo: DateTime(2026, 8, 27),
          fileHasDates: true,
        ),
        isFalse,
      );
    });

    test('terminal ekleme aciklamasini ekleme olarak siniflar', () {
      expect(
        classifyTsmOrderKind(
          'TE',
          'TechPos Acquirer WS Tarafından Gönderilen Terminal Ekleme Bildirimidir',
        ),
        TsmOrderKind.ekleme,
      );
      expect(classifyTsmOrderKind('K', ''), TsmOrderKind.kurulum);
      expect(classifyTsmOrderKind('TS', ''), TsmOrderKind.geriAlim);
    });

    test('ana islem secildikten sonra sonuc mesaji ile filtreler', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı'],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041001</TermSeriNo>',
        ],
        [
          'TERMINAL_SORGU',
          'Acquirera ait Lisans Yok <TermSeriNo>2D10041002</TermSeriNo>',
        ],
        [
          'ISEMRI_ACMA',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041003</TermSeriNo>',
        ],
      ]);
      expect(
        result.resultMessageOptions,
        containsAll(['Acquirera ait Lisans Yok', 'İŞLEM ONAYLANDI']),
      );
      expect(
        tsmResultMessagesForOperation(
          result.uniqueSerials,
          TsmLogOperation.terminalSorgu,
        ),
        ['Acquirera ait Lisans Yok', 'İŞLEM ONAYLANDI'],
      );
      expect(
        result.uniqueSerials
            .where(
              (item) => tsmLogSerialMatchesFilters(
                item,
                resultMessageFilter: 'Acquirera ait Lisans Yok',
              ),
            )
            .map((item) => item.serialNumber),
        ['2D10041002'],
      );
      expect(
        result.uniqueSerials
            .where(
              (item) => tsmLogSerialMatchesFilters(
                item,
                operationFilter: 'ISEMRI_ACMA',
                resultMessageFilter: 'İŞLEM ONAYLANDI',
              ),
            )
            .map((item) => item.serialNumber),
        ['2D10041003'],
      );
    });

    test('onay filtresi ayni sicildeki eslesmedi sonucunu gizler', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı'],
        [
          'TERMINAL_SORGU',
          'İŞLEM ONAYLANDI <TermSeriNo>2D10041999</TermSeriNo>',
        ],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>2D10041999</TermSeriNo>',
        ],
      ]);
      final item = result.uniqueSerials.single;
      expect(
        tsmLogSerialMatchesFilters(
          item,
          operationFilter: 'TERMINAL_SORGU',
          resultMessageFilter: 'İŞLEM ONAYLANDI',
        ),
        isTrue,
      );
      expect(
        tsmLogSerialMatchesFilters(
          item,
          operationFilter: 'ISEMRI_ACMA',
          resultMessageFilter: 'İŞLEM ONAYLANDI',
        ),
        isFalse,
      );
      expect(
        item.outcomes.any(
          (outcome) =>
              outcome.operation == TsmLogOperation.terminalSorgu &&
              tsmOutcomeMatchesResultMessage(outcome, 'İŞLEM ONAYLANDI'),
        ),
        isTrue,
      );
      expect(
        item.outcomes
            .where(
              (outcome) => tsmOutcomeMatchesResultMessage(
                outcome,
                'İŞLEM ONAYLANDI',
              ),
            )
            .every(
              (outcome) =>
                  parseTsmLogResultKind(outcome.resultMessage) ==
                  TsmLogResultKind.approved,
            ),
        isTrue,
      );
    });

    test('onaylanmayan isemri satirinda is emri detayi tutmaz', () {
      final result = parseTsmLogRows([
        const ['İşlem', 'Sonuç Mesajı', 'Giriş Parametreleri'],
        [
          'ISEMRI_ACMA',
          'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ.',
          '<BKM_OpenTaskIn><IsEmriKodu>K</IsEmriKodu><AcquirerEkranAdi>HALKBANK</AcquirerEkranAdi><TermSeriNo>2D10041482</TermSeriNo></BKM_OpenTaskIn>',
        ],
      ]);
      expect(result.uniqueSerials.single.workOrder, isNull);
    });

    test('html entity olarak kacisli TermSeriNo degerini okur', () {
      const html = '''
<table>
<tr><th>İşlem</th><th>Sonuç Mesajı</th></tr>
<tr><td>ISEMRI_ACMA</td><td>SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. &lt;TermSeriNo&gt;2D10041612&lt;/TermSeriNo&gt;</td></tr>
</table>
''';
      final result = parseTsmLogExcel(
        Uint8List.fromList(utf8.encode(html)),
        fileName: 'tsm.xls',
      );
      expect(result.uniqueSerials.single.serialNumber, '2D10041612');
      expect(
        result.uniqueSerials.single.resultKinds,
        {TsmLogResultKind.serialMismatch},
      );
    });
  });
}
