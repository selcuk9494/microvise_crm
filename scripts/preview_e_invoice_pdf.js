#!/usr/bin/env node
// Maliye referans çıktısıyla karşılaştırmak için örnek arşiv PDF'i üretir.
const fs = require('fs');
const path = require('path');

const { buildEInvoiceArchivePdf } = require('../api/_lib/e_invoice_pdf');

const officialData = {
  fatura: {
    faturaNo: '620009058-2026-1-00000000008',
    faturaTarihi: '2026-07-27T21:00:00Z',
    paraBirimi: 'TRY',
    tedarikci: {
      unvan: 'MICROVISE INNOVATION LİMİTED',
      adresSatir1: 'ATATÜRK CAD YENİŞEHİR EMEK 2 APT. DIŞ KAPI NO:1',
      sehir: 'LEFKOŞA',
      ulke: 'Kuzey Kıbrıs Türk Cumhuriyeti',
      vkn: '620009058',
      belgeNo: 'MŞ19660',
      belgeTipi: 'VERGI_SICILNO',
    },
    musteri: {
      unvan: 'WORLDLINE ÖDEME SİSTEMLERİ AŞ.',
      adresSatir1: 'BOĞAZİÇİ KURUMLAR MASLAK, İTÜ AYAZAĞA KAMPÜSÜ TEKNOKENT ARI BİNAK:8 No:802-804',
      adresSatir2: '34469 SARIYER/ İSTANBUL TÜRKİYE (TURKEY)',
      sehir: 'LEFKOŞA',
      ulke: 'Türkiye',
      belgeNo: '7300286201',
      belgeTipi: 'YABANCI_KIMLIKNO',
    },
    malHizmetler: [
      {
        adi: 'INGENICO BANKA UYGULAMASI',
        aciklama: 'INGENICO BANKA UYGULAMASI',
        birimMiktari: 1,
        birimTurKod: 'C62',
        fiyat: 46576.32,
        vergiler: [{ vergiOrani: 0, vergiTutari: 0 }],
      },
      {
        adi: 'PAX BANKA UYGULAMASI',
        aciklama: 'PAX BANKA UYGULAMASI',
        birimMiktari: 1,
        birimTurKod: 'C62',
        fiyat: 5684,
        vergiler: [{ vergiOrani: 0, vergiTutari: 0 }],
      },
    ],
    faturaToplami: 52260.32,
    iskontoToplami: 0,
    kdvToplami: 0,
    odenecekToplam: 52260.32,
    aciklama:
      'Banka Hesap Bilgileri\nTürkiye İş Bankası\nMicrovise Innovation Ltd\nTL IBAN: TR57 0006 4000 0016 8010 3409 94\nUSD IBAN: TR41 0006 4000 0026 8010 4107 29',
  },
};

async function main() {
  const pdf = await buildEInvoiceArchivePdf({
    invoice: {
      e_invoice_number: officialData.fatura.faturaNo,
      invoice_date: '2026-07-28',
      currency: 'TRY',
      subtotal: 52260.32,
      discount_total: 0,
      tax_total: 0,
      grand_total: 52260.32,
      customer: {},
      items: [],
    },
    settings: { seller_title: 'MICROVISE INNOVATION LİMİTED' },
    officialData,
    verificationCode: '019faa0e-cec6-735a-9604-ffbcbd026c3f',
    environment: 'production',
  });

  const target = path.resolve(process.cwd(), process.argv[2] || 'output/pdf/e_invoice_preview.pdf');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, pdf);
  process.stdout.write(`${target}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exit(1);
});
