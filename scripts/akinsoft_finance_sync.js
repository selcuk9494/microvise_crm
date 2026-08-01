/**
 * Akınsoft (Wolvox) banka / kasa / transfer / masraf senkronu.
 * Tablolar: BANKA_ADI, BANKA_HESAP, BANKAHR, KASA, KASAHR, FATURA (MSF / durum=7).
 */

function createAkinsoftFinanceHandlers(ctx) {
  const {
    sql,
    buildAkinsoftSqlConfig,
    connectAkinsoftPool,
    akinsoftTableExists,
    akinsoftTableColumnSet,
    akinsoftNextBlkoduSafe,
    insertAkinsoftRowWithRequest,
    setFirstColumn,
    setAllColumns,
    readJson,
    send,
    textOrNull,
    numberOrZero,
    toSqlDate,
  } = ctx;

  function jsonOk(res, payload) {
    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: true, ...payload }),
    );
  }

  function jsonErr(res, status, error) {
    return send(
      res,
      status,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: String(error || 'Bilinmeyen hata') }),
    );
  }

  async function withPool(body, fn) {
    const built = buildAkinsoftSqlConfig(body || {});
    const config = built.config || built;
    config.requestTimeout = Math.max(Number(config.requestTimeout) || 90000, 120000);
    const pool = await connectAkinsoftPool(config);
    try {
      return await fn(pool);
    } finally {
      try {
        await pool.close();
      } catch (_) {
        /* ignore */
      }
    }
  }

  function accountLabel(bankName, tanimi, hesapNo, hesapTuru) {
    const parts = [
      textOrNull(bankName),
      textOrNull(tanimi) || textOrNull(hesapNo),
      textOrNull(hesapTuru),
    ].filter(Boolean);
    return parts.join(' - ');
  }

  function currencyFromHesapTuru(tur) {
    const t = String(tur || '').trim().toUpperCase();
    if (t === 'TL' || t === 'TRY' || t === '') return 'TRY';
    if (t === '$' || t === 'USD' || t === 'US$') return 'USD';
    if (t === '€' || t === 'EUR') return 'EUR';
    if (t === '£' || t === 'GBP') return 'GBP';
    return t.slice(0, 3) || 'TRY';
  }

  async function nextEvrakNo(pool, tableName, prefix) {
    const safe = String(tableName).replace(/[^A-Za-z0-9_]/g, '');
    const result = await pool
      .request()
      .input('prefix', sql.VarChar(16), `${prefix}%`)
      .query(`
        select top 1 convert(nvarchar(32), EVRAK_NO) as evrak
        from dbo.${safe}
        where EVRAK_NO like @prefix
        order by BLKODU desc
      `);
    const last = textOrNull(result.recordset?.[0]?.evrak) || '';
    const match = last.match(/(\d+)\s*$/);
    const next = (match ? Number(match[1]) : 0) + 1;
    const width = match ? match[1].length : 5;
    return `${prefix}${String(next).padStart(width, '0')}`;
  }

  async function nextMasrafNo(pool) {
    const result = await pool.request().query(`
      select top 1 convert(nvarchar(32), FATURA_NO) as no
      from dbo.FATURA
      where FATURA_NO like N'MSF%'
      order by BLKODU desc
    `);
    const last = textOrNull(result.recordset?.[0]?.no) || 'MSF00000';
    const match = last.match(/(\d+)\s*$/);
    const next = (match ? Number(match[1]) : 0) + 1;
    return `MSF${String(next).padStart(5, '0')}`;
  }

  async function loadBanks(pool) {
    const banks = await pool.request().query(`
      select
        cast(b.BLKODU as nvarchar(32)) as sourceId,
        convert(nvarchar(80), b.BANKA_ADI) as bankName,
        convert(nvarchar(80), b.SUBESI) as branch,
        convert(nvarchar(40), b.TELEFON_1) as phone,
        convert(nvarchar(120), b.ADRESI) as address,
        convert(nvarchar(40), b.HESAP_NO) as hesapNo,
        convert(nvarchar(40), b.SUBE_KODU) as subeKodu,
        b.KAYIT_TARIHI as createdAt
      from dbo.BANKA_ADI b
      order by b.BANKA_ADI, b.BLKODU
    `);
    return (banks.recordset || []).map((row) => ({
      sourceId: String(row.sourceId),
      bankName: textOrNull(row.bankName) || '',
      branch: textOrNull(row.branch),
      phone: textOrNull(row.phone),
      address: textOrNull(row.address),
      hesapNo: textOrNull(row.hesapNo),
      subeKodu: textOrNull(row.subeKodu),
      createdAt: row.createdAt || null,
    }));
  }

  async function loadAccounts(pool) {
    const accounts = await pool.request().query(`
      select
        cast(h.BLKODU as nvarchar(32)) as sourceId,
        cast(h.BLBNKODU as nvarchar(32)) as bankSourceId,
        convert(nvarchar(80), a.BANKA_ADI) as bankName,
        convert(nvarchar(40), h.HESAP_NO) as hesapNo,
        convert(nvarchar(8), h.HESAP_TURU) as hesapTuru,
        convert(nvarchar(40), h.TANIMI) as tanimi,
        convert(nvarchar(40), h.IBAN_NO) as iban,
        convert(nvarchar(40), h.MUH_KODU) as muhKodu,
        convert(nvarchar(40), h.SWIFT) as swift,
        h.ACILIS_TARIHI as openedAt,
        h.KAPANIS_TARIHI as closedAt,
        coalesce((
          select sum(isnull(hr.TUTAR_BORC, 0) - isnull(hr.TUTAR_ALACAK, 0))
          from dbo.BANKAHR hr
          where hr.BLHSKODU = h.BLKODU and coalesce(hr.SILINDI, 0) = 0
        ), 0) as balance
      from dbo.BANKA_HESAP h
      left join dbo.BANKA_ADI a on a.BLKODU = h.BLBNKODU
      order by a.BANKA_ADI, h.TANIMI, h.BLKODU
    `);
    return (accounts.recordset || []).map((row) => ({
      sourceId: String(row.sourceId),
      bankSourceId: textOrNull(row.bankSourceId),
      bankName: textOrNull(row.bankName) || '',
      hesapNo: textOrNull(row.hesapNo),
      hesapTuru: textOrNull(row.hesapTuru) || 'TL',
      currency: currencyFromHesapTuru(row.hesapTuru),
      tanimi: textOrNull(row.tanimi) || '',
      label: accountLabel(row.bankName, row.tanimi, row.hesapNo, row.hesapTuru),
      iban: textOrNull(row.iban),
      muhKodu: textOrNull(row.muhKodu),
      swift: textOrNull(row.swift),
      openedAt: row.openedAt || null,
      closedAt: row.closedAt || null,
      balance: numberOrZero(row.balance),
      isActive: !row.closedAt,
    }));
  }

  async function loadKasas(pool) {
    const kasas = await pool.request().query(`
      select
        cast(k.BLKODU as nvarchar(32)) as sourceId,
        convert(nvarchar(40), k.KASA_ADI) as kasaAdi,
        convert(nvarchar(80), k.YETKILISI) as yetkilisi,
        convert(nvarchar(80), k.ACIKLAMA1) as aciklama1,
        convert(nvarchar(40), k.MUH_KODU) as muhKodu,
        convert(nvarchar(40), k.OZEL_KODU) as ozelKodu,
        convert(nvarchar(40), k.SUBE_KODU) as subeKodu,
        cast(coalesce(k.AKTIF, 1) as int) as aktif,
        k.KAYIT_TARIHI as createdAt,
        coalesce((
          select sum(isnull(hr.KPB_GLTUT, 0) - isnull(hr.KPB_GDTUT, 0))
          from dbo.KASAHR hr
          where hr.KASA_ADI = k.KASA_ADI and coalesce(hr.SILINDI, 0) = 0
        ), 0) as balance
      from dbo.KASA k
      order by k.KASA_ADI
    `);
    return (kasas.recordset || []).map((row) => ({
      sourceId: String(row.sourceId),
      kasaAdi: textOrNull(row.kasaAdi) || '',
      yetkilisi: textOrNull(row.yetkilisi),
      aciklama1: textOrNull(row.aciklama1),
      muhKodu: textOrNull(row.muhKodu),
      ozelKodu: textOrNull(row.ozelKodu),
      subeKodu: textOrNull(row.subeKodu),
      isActive: Number(row.aktif) !== 0,
      createdAt: row.createdAt || null,
      balance: numberOrZero(row.balance),
      currency: 'TRY',
    }));
  }

  async function loadTransfers(pool, limit = 80) {
    const lim = Math.min(Math.max(Number(limit) || 80, 1), 300);
    const bankBank = await pool.request().query(`
      select top ${lim}
        cast(a.BLKODU as nvarchar(32)) as sourceId,
        cast(a.BLTRSKODU as nvarchar(32)) as pairSourceId,
        convert(nvarchar(32), a.EVRAK_NO) as evrakNo,
        a.TARIHI as tarihi,
        convert(nvarchar(80), a.ACIKLAMA) as aciklama,
        cast(a.BLHSKODU as nvarchar(32)) as fromAccountId,
        cast(b.BLHSKODU as nvarchar(32)) as toAccountId,
        cast(isnull(a.TUTAR_ALACAK, a.KPB_TUTARI) as float) as amount
      from dbo.BANKAHR a
      join dbo.BANKAHR b on b.BLKODU = a.BLTRSKODU
      where coalesce(a.SILINDI, 0) = 0
        and a.BLTRSKODU is not null
        and isnull(a.TUTAR_ALACAK, 0) > 0
      order by a.TARIHI desc, a.BLKODU desc
    `);

    const kasaBank = await pool.request().query(`
      select top ${lim}
        cast(k.BLKODU as nvarchar(32)) as kasaHrId,
        cast(b.BLKODU as nvarchar(32)) as bankHrId,
        convert(nvarchar(32), k.EVRAK_NO) as evrakNo,
        k.TARIHI as tarihi,
        convert(nvarchar(80), k.ACIKLAMA) as aciklama,
        convert(nvarchar(40), k.KASA_ADI) as kasaAdi,
        cast(k.BLBNHSKODU as nvarchar(32)) as accountId,
        convert(nvarchar(80), k.BANKA_ADI) as bankLabel,
        cast(isnull(k.KPB_GDTUT, 0) as float) as kasaOut,
        cast(isnull(k.KPB_GLTUT, 0) as float) as kasaIn,
        cast(isnull(b.TUTAR_BORC, 0) as float) as bankIn,
        cast(isnull(b.TUTAR_ALACAK, 0) as float) as bankOut
      from dbo.KASAHR k
      join dbo.BANKAHR b on b.EVRAK_NO = k.EVRAK_NO and coalesce(b.SILINDI, 0) = 0
      where coalesce(k.SILINDI, 0) = 0
        and k.BLBNHSKODU is not null
        and (
          upper(isnull(k.ACIKLAMA, '')) like N'%TRANSFER%'
          or upper(isnull(k.OZEL_KODU, '')) like N'%KASA%BANKA%'
          or upper(isnull(k.OZEL_KODU, '')) like N'%BANKA%KASA%'
        )
      order by k.TARIHI desc, k.BLKODU desc
    `);

    const accounts = await loadAccounts(pool);
    const byId = new Map(accounts.map((a) => [a.sourceId, a]));

    const transfers = [];
    for (const row of bankBank.recordset || []) {
      const from = byId.get(String(row.fromAccountId));
      const to = byId.get(String(row.toAccountId));
      transfers.push({
        sourceId: String(row.sourceId),
        pairSourceId: textOrNull(row.pairSourceId),
        type: 'bank_bank',
        typeLabel: 'Banka → Banka',
        evrakNo: textOrNull(row.evrakNo),
        date: row.tarihi || null,
        amount: numberOrZero(row.amount),
        description: textOrNull(row.aciklama),
        fromLabel: from?.label || `Hesap #${row.fromAccountId}`,
        toLabel: to?.label || `Hesap #${row.toAccountId}`,
        fromAccountId: textOrNull(row.fromAccountId),
        toAccountId: textOrNull(row.toAccountId),
      });
    }
    for (const row of kasaBank.recordset || []) {
      const account = byId.get(String(row.accountId));
      const kasaOut = numberOrZero(row.kasaOut);
      const kasaIn = numberOrZero(row.kasaIn);
      const isKasaToBank = kasaOut > 0;
      transfers.push({
        sourceId: `kasa:${row.kasaHrId}`,
        pairSourceId: textOrNull(row.bankHrId),
        type: isKasaToBank ? 'kasa_bank' : 'bank_kasa',
        typeLabel: isKasaToBank ? 'Kasa → Banka' : 'Banka → Kasa',
        evrakNo: textOrNull(row.evrakNo),
        date: row.tarihi || null,
        amount: isKasaToBank ? kasaOut : kasaIn || numberOrZero(row.bankOut),
        description: textOrNull(row.aciklama),
        fromLabel: isKasaToBank
          ? textOrNull(row.kasaAdi) || 'Kasa'
          : account?.label || textOrNull(row.bankLabel) || 'Banka',
        toLabel: isKasaToBank
          ? account?.label || textOrNull(row.bankLabel) || 'Banka'
          : textOrNull(row.kasaAdi) || 'Kasa',
        kasaAdi: textOrNull(row.kasaAdi),
        accountId: textOrNull(row.accountId),
      });
    }
    transfers.sort((a, b) => {
      const da = a.date ? new Date(a.date).getTime() : 0;
      const db = b.date ? new Date(b.date).getTime() : 0;
      return db - da;
    });
    return transfers.slice(0, lim);
  }

  async function loadMasraf(pool, limit = 60) {
    const lim = Math.min(Math.max(Number(limit) || 60, 1), 200);
    const headers = await pool.request().query(`
      select top ${lim}
        cast(f.BLKODU as nvarchar(32)) as sourceId,
        convert(nvarchar(40), f.FATURA_NO) as faturaNo,
        f.TARIHI as tarihi,
        convert(nvarchar(120), f.TICARI_UNVANI) as cariUnvan,
        convert(nvarchar(40), f.CARIKODU) as cariKodu,
        cast(f.BLCRKODU as nvarchar(32)) as cariSourceId,
        cast(isnull(f.TOPLAM_GENEL_KPB, 0) as float) as toplam,
        cast(isnull(f.TOPLAM_KDV_KPB, 0) as float) as kdv,
        cast(isnull(f.FATURA_DURUMU, 0) as int) as durum,
        convert(nvarchar(80), f.ACIKLAMA) as aciklama
      from dbo.FATURA f
      where coalesce(f.SILINDI, 0) = 0
        and (
          f.FATURA_DURUMU = 7
          or f.FATURA_NO like N'MSF%'
        )
      order by f.TARIHI desc, f.BLKODU desc
    `);

    const list = [];
    for (const row of headers.recordset || []) {
      const lineReq = pool.request();
      lineReq.input('fid', sql.BigInt, Number(row.sourceId));
      const lines = await lineReq.query(`
        select top 20
          cast(hr.BLKODU as nvarchar(32)) as sourceId,
          convert(nvarchar(120), hr.STOK_ADI) as name,
          cast(isnull(hr.MIKTARI, 1) as float) as qty,
          cast(isnull(hr.KPB_FIYATI, 0) as float) as unitPrice,
          cast(isnull(hr.KDV_ORANI, 0) as float) as taxRate,
          cast(isnull(hr.KPB_TOPLAM_TUTAR, hr.KPB_KDVLI_TUTAR) as float) as total,
          cast(hr.BLHZMKODU as nvarchar(32)) as hizmetId,
          cast(hr.BLSTKODU as nvarchar(32)) as stokId
        from dbo.FATURAHR hr
        where hr.BLFTKODU = @fid
        order by hr.BLKODU
      `);
      list.push({
        sourceId: String(row.sourceId),
        faturaNo: textOrNull(row.faturaNo),
        date: row.tarihi || null,
        cariUnvan: textOrNull(row.cariUnvan),
        cariKodu: textOrNull(row.cariKodu),
        cariSourceId: textOrNull(row.cariSourceId),
        toplam: numberOrZero(row.toplam),
        kdv: numberOrZero(row.kdv),
        durum: Number(row.durum) || 0,
        aciklama: textOrNull(row.aciklama),
        items: (lines.recordset || []).map((line) => ({
          sourceId: String(line.sourceId),
          name: textOrNull(line.name) || 'Masraf',
          qty: numberOrZero(line.qty) || 1,
          unitPrice: numberOrZero(line.unitPrice),
          taxRate: numberOrZero(line.taxRate),
          total: numberOrZero(line.total),
          hizmetId: textOrNull(line.hizmetId),
          stokId: textOrNull(line.stokId),
        })),
      });
    }
    return list;
  }

  async function handleFinancePull(req, res) {
    if (req.method !== 'POST' && req.method !== 'GET') {
      return jsonErr(res, 405, 'GET veya POST gerekli.');
    }
    const body = req.method === 'POST' ? await readJson(req) : {};
    try {
      const data = await withPool(body, async (pool) => {
        const hasBankaAdi = await akinsoftTableExists(pool, 'BANKA_ADI');
        const hasBankaHesap = await akinsoftTableExists(pool, 'BANKA_HESAP');
        const hasKasa = await akinsoftTableExists(pool, 'KASA');
        if (!hasBankaAdi || !hasBankaHesap || !hasKasa) {
          throw Object.assign(
            new Error('Akınsoft BANKA_ADI / BANKA_HESAP / KASA tabloları bulunamadı.'),
            { statusCode: 400 },
          );
        }
        const [banks, accounts, kasas, transfers, masraf] = await Promise.all([
          loadBanks(pool),
          loadAccounts(pool),
          loadKasas(pool),
          loadTransfers(pool, body.transferLimit || 80),
          loadMasraf(pool, body.masrafLimit || 60),
        ]);
        return {
          banks,
          accounts,
          kasas,
          transfers,
          masraf,
          pulledAt: new Date().toISOString(),
          tables: {
            BANKA_ADI: true,
            BANKA_HESAP: true,
            BANKAHR: await akinsoftTableExists(pool, 'BANKAHR'),
            KASA: true,
            KASAHR: await akinsoftTableExists(pool, 'KASAHR'),
            FATURA: await akinsoftTableExists(pool, 'FATURA'),
          },
        };
      });
      return jsonOk(res, data);
    } catch (error) {
      return jsonErr(res, error.statusCode || 500, error.message || error);
    }
  }

  async function upsertBank(pool, body) {
    const columns = await akinsoftTableColumnSet(pool, 'BANKA_ADI');
    const bankName = textOrNull(body.bankName || body.banka_adi);
    if (!bankName) throw Object.assign(new Error('Banka adı zorunlu.'), { statusCode: 400 });
    const sourceId = textOrNull(body.sourceId || body.blkodu);
    const values = {};
    setFirstColumn(values, columns, ['BANKA_ADI'], bankName.slice(0, 50));
    setFirstColumn(values, columns, ['SUBESI'], textOrNull(body.branch || body.subesi));
    setFirstColumn(values, columns, ['TELEFON_1'], textOrNull(body.phone || body.telefon));
    setFirstColumn(values, columns, ['ADRESI'], textOrNull(body.address || body.adresi));
    setFirstColumn(values, columns, ['HESAP_NO'], textOrNull(body.hesapNo));
    setFirstColumn(values, columns, ['SUBE_KODU'], textOrNull(body.subeKodu));
    setFirstColumn(values, columns, ['KAYDEDEN'], 'MICROVISE');
    setFirstColumn(values, columns, ['DEGISTIREN'], 'MICROVISE');
    setFirstColumn(values, columns, ['DEGISTIRME_TARIHI'], new Date());
    setFirstColumn(values, columns, ['SOURCE_APP'], 'MICROVISE');

    if (sourceId) {
      const id = Number(sourceId);
      const sets = [];
      const req = pool.request();
      req.input('id', sql.BigInt, id);
      let i = 0;
      for (const [key, value] of Object.entries(values)) {
        if (key === 'BLKODU') continue;
        const p = `p${i++}`;
        sets.push(`[${key}]=@${p}`);
        if (value instanceof Date) req.input(p, sql.DateTime, value);
        else if (typeof value === 'number') req.input(p, sql.Float, value);
        else req.input(p, sql.NVarChar, value == null ? null : String(value));
      }
      if (!sets.length) throw new Error('Güncellenecek alan yok.');
      await req.query(`update dbo.BANKA_ADI set ${sets.join(', ')} where BLKODU=@id`);
      return { sourceId: String(id), action: 'updated' };
    }

    const blkodu = await akinsoftNextBlkoduSafe(pool, 'BANKA_ADI');
    values.BLKODU = blkodu;
    setFirstColumn(values, columns, ['KAYIT_TARIHI'], new Date());
    setFirstColumn(values, columns, ['POS_KULLAN'], 0);
    setFirstColumn(values, columns, ['KK_KULLAN'], 0);
    setFirstColumn(values, columns, ['CEK_KULLAN'], 0);
    setFirstColumn(values, columns, ['SANALPOS_KULLAN'], 0);
    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'BANKA_ADI', columns, values);
    return { sourceId: String(blkodu), action: 'created' };
  }

  async function upsertBankAccount(pool, body) {
    const columns = await akinsoftTableColumnSet(pool, 'BANKA_HESAP');
    const bankSourceId = Number(body.bankSourceId || body.blbnkodu);
    if (!Number.isFinite(bankSourceId)) {
      throw Object.assign(new Error('Banka (BLBNKODU) zorunlu.'), { statusCode: 400 });
    }
    const tanimi = textOrNull(body.tanimi || body.name);
    const hesapTuru = textOrNull(body.hesapTuru || body.currency) || 'TL';
    const normalizedTuru =
      hesapTuru === 'TRY' || hesapTuru === 'TL'
        ? 'TL'
        : hesapTuru === 'USD'
          ? '$'
          : hesapTuru === 'EUR'
            ? '€'
            : hesapTuru === 'GBP'
              ? '£'
              : hesapTuru.slice(0, 2);
    const sourceId = textOrNull(body.sourceId || body.blkodu);
    const values = {};
    setFirstColumn(values, columns, ['BLBNKODU'], bankSourceId);
    setFirstColumn(values, columns, ['HESAP_NO'], textOrNull(body.hesapNo) || normalizedTuru);
    setFirstColumn(values, columns, ['HESAP_TURU'], normalizedTuru);
    setFirstColumn(values, columns, ['TANIMI'], (tanimi || normalizedTuru).slice(0, 15));
    setFirstColumn(values, columns, ['IBAN_NO'], textOrNull(body.iban));
    setFirstColumn(values, columns, ['MUH_KODU'], textOrNull(body.muhKodu) || '102');
    setFirstColumn(values, columns, ['SWIFT'], textOrNull(body.swift));
    setFirstColumn(values, columns, ['VADELI'], 0);
    setFirstColumn(values, columns, ['CEK_KREDI_HESABI'], 0);
    setFirstColumn(values, columns, ['SUBE_ORTAK_KULLAN'], 0);

    if (sourceId) {
      const id = Number(sourceId);
      const sets = [];
      const req = pool.request();
      req.input('id', sql.BigInt, id);
      let i = 0;
      for (const [key, value] of Object.entries(values)) {
        const p = `p${i++}`;
        sets.push(`[${key}]=@${p}`);
        if (typeof value === 'number') req.input(p, Number.isInteger(value) ? sql.BigInt : sql.Float, value);
        else req.input(p, sql.NVarChar, value == null ? null : String(value));
      }
      await req.query(`update dbo.BANKA_HESAP set ${sets.join(', ')} where BLKODU=@id`);
      return { sourceId: String(id), action: 'updated' };
    }

    const blkodu = await akinsoftNextBlkoduSafe(pool, 'BANKA_HESAP');
    values.BLKODU = blkodu;
    setFirstColumn(values, columns, ['ACILIS_TARIHI'], toSqlDate(body.openedAt, new Date()) || new Date());
    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'BANKA_HESAP', columns, values);
    return { sourceId: String(blkodu), action: 'created' };
  }

  async function upsertKasa(pool, body) {
    const columns = await akinsoftTableColumnSet(pool, 'KASA');
    const kasaAdi = textOrNull(body.kasaAdi || body.name);
    if (!kasaAdi) throw Object.assign(new Error('Kasa adı zorunlu.'), { statusCode: 400 });
    const sourceId = textOrNull(body.sourceId || body.blkodu);
    const values = {};
    setFirstColumn(values, columns, ['KASA_ADI'], kasaAdi.slice(0, 10));
    setFirstColumn(values, columns, ['YETKILISI'], textOrNull(body.yetkilisi));
    setFirstColumn(values, columns, ['ACIKLAMA1'], textOrNull(body.aciklama1 || body.notes));
    setFirstColumn(values, columns, ['MUH_KODU'], textOrNull(body.muhKodu) || '100');
    setFirstColumn(values, columns, ['OZEL_KODU'], textOrNull(body.ozelKodu));
    setFirstColumn(values, columns, ['SUBE_KODU'], textOrNull(body.subeKodu));
    setFirstColumn(values, columns, ['AKTIF'], body.isActive === false ? 0 : 1);
    setFirstColumn(values, columns, ['KAYDEDEN'], 'MICROVISE');
    setFirstColumn(values, columns, ['DEGISTIREN'], 'MICROVISE');
    setFirstColumn(values, columns, ['DEGISTIRME_TARIHI'], new Date());

    if (sourceId) {
      const id = Number(sourceId);
      const sets = [];
      const req = pool.request();
      req.input('id', sql.BigInt, id);
      let i = 0;
      for (const [key, value] of Object.entries(values)) {
        const p = `p${i++}`;
        sets.push(`[${key}]=@${p}`);
        if (value instanceof Date) req.input(p, sql.DateTime, value);
        else if (typeof value === 'number') req.input(p, sql.Float, value);
        else req.input(p, sql.NVarChar, value == null ? null : String(value));
      }
      await req.query(`update dbo.KASA set ${sets.join(', ')} where BLKODU=@id`);
      return { sourceId: String(id), action: 'updated', kasaAdi: kasaAdi.slice(0, 10) };
    }

    const blkodu = await akinsoftNextBlkoduSafe(pool, 'KASA');
    values.BLKODU = blkodu;
    setFirstColumn(values, columns, ['KAYIT_TARIHI'], new Date());
    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'KASA', columns, values);
    return { sourceId: String(blkodu), action: 'created', kasaAdi: kasaAdi.slice(0, 10) };
  }

  async function deleteBank(pool, body) {
    const sourceId = Number(body.sourceId || body.blkodu);
    if (!Number.isFinite(sourceId)) {
      throw Object.assign(new Error('sourceId zorunlu.'), { statusCode: 400 });
    }
    const linked = await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`select count(*) as c from dbo.BANKA_HESAP where BLBNKODU=@id`);
    if (Number(linked.recordset?.[0]?.c || 0) > 0) {
      throw Object.assign(
        new Error('Bankaya bağlı hesap var. Önce hesapları silin veya kapatın.'),
        { statusCode: 400 },
      );
    }
    await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`delete from dbo.BANKA_ADI where BLKODU=@id`);
    return { sourceId: String(sourceId), action: 'deleted' };
  }

  async function deleteBankAccount(pool, body) {
    const sourceId = Number(body.sourceId || body.blkodu);
    if (!Number.isFinite(sourceId)) {
      throw Object.assign(new Error('sourceId zorunlu.'), { statusCode: 400 });
    }
    const moves = await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`
        select count(*) as c from dbo.BANKAHR
        where BLHSKODU=@id and coalesce(SILINDI,0)=0
      `);
    if (Number(moves.recordset?.[0]?.c || 0) > 0) {
      // Soft-close: set kapanış tarihi instead of hard delete
      await pool
        .request()
        .input('id', sql.BigInt, sourceId)
        .query(`update dbo.BANKA_HESAP set KAPANIS_TARIHI=getdate() where BLKODU=@id`);
      return { sourceId: String(sourceId), action: 'closed' };
    }
    await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`delete from dbo.BANKA_HESAP where BLKODU=@id`);
    return { sourceId: String(sourceId), action: 'deleted' };
  }

  async function deleteKasa(pool, body) {
    const sourceId = Number(body.sourceId || body.blkodu);
    if (!Number.isFinite(sourceId)) {
      throw Object.assign(new Error('sourceId zorunlu.'), { statusCode: 400 });
    }
    const nameRes = await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`select convert(nvarchar(40), KASA_ADI) as adi from dbo.KASA where BLKODU=@id`);
    const adi = textOrNull(nameRes.recordset?.[0]?.adi);
    if (!adi) throw Object.assign(new Error('Kasa bulunamadı.'), { statusCode: 404 });
    const moves = await pool
      .request()
      .input('adi', sql.NVarChar(40), adi)
      .query(`select count(*) as c from dbo.KASAHR where KASA_ADI=@adi and coalesce(SILINDI,0)=0`);
    if (Number(moves.recordset?.[0]?.c || 0) > 0) {
      await pool
        .request()
        .input('id', sql.BigInt, sourceId)
        .query(`update dbo.KASA set AKTIF=0, DEGISTIRME_TARIHI=getdate(), DEGISTIREN=N'MICROVISE' where BLKODU=@id`);
      return { sourceId: String(sourceId), action: 'deactivated' };
    }
    await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`delete from dbo.KASA where BLKODU=@id`);
    return { sourceId: String(sourceId), action: 'deleted' };
  }

  async function resolveAccountMeta(pool, accountId) {
    const req = pool.request();
    req.input('id', sql.BigInt, Number(accountId));
    const result = await req.query(`
      select
        cast(h.BLKODU as nvarchar(32)) as sourceId,
        convert(nvarchar(80), a.BANKA_ADI) as bankName,
        convert(nvarchar(40), h.TANIMI) as tanimi,
        convert(nvarchar(40), h.HESAP_NO) as hesapNo,
        convert(nvarchar(8), h.HESAP_TURU) as hesapTuru
      from dbo.BANKA_HESAP h
      left join dbo.BANKA_ADI a on a.BLKODU = h.BLBNKODU
      where h.BLKODU = @id
    `);
    const row = result.recordset?.[0];
    if (!row) throw Object.assign(new Error(`Banka hesabı bulunamadı: ${accountId}`), { statusCode: 400 });
    return {
      sourceId: String(row.sourceId),
      label: accountLabel(row.bankName, row.tanimi, row.hesapNo, row.hesapTuru),
    };
  }

  async function createBankBankTransfer(pool, body) {
    const fromId = Number(body.fromAccountId);
    const toId = Number(body.toAccountId);
    const amount = numberOrZero(body.amount);
    if (!Number.isFinite(fromId) || !Number.isFinite(toId) || fromId === toId) {
      throw Object.assign(new Error('Kaynak ve hedef banka hesabı gerekli.'), { statusCode: 400 });
    }
    if (!(amount > 0)) {
      throw Object.assign(new Error('Tutar 0’dan büyük olmalı.'), { statusCode: 400 });
    }
    const columns = await akinsoftTableColumnSet(pool, 'BANKAHR');
    const fromMeta = await resolveAccountMeta(pool, fromId);
    const toMeta = await resolveAccountMeta(pool, toId);
    const tarih = toSqlDate(body.date, new Date()) || new Date();
    const tarihOnly = new Date(tarih);
    tarihOnly.setHours(0, 0, 0, 0);
    const evrakNo = textOrNull(body.evrakNo) || (await nextEvrakNo(pool, 'BANKAHR', 'BH'));
    const descFrom = textOrNull(body.description) || `Hedef Banka : ${toMeta.label}`;
    const descTo = textOrNull(body.description) || `Kaynak Banka : ${fromMeta.label}`;

    const outId = await akinsoftNextBlkoduSafe(pool, 'BANKAHR');
    const inId = await akinsoftNextBlkoduSafe(pool, 'BANKAHR');

    const base = {
      EVRAK_NO: evrakNo.slice(0, 10),
      OZEL_KODU: 'Banka Transferi'.slice(0, 10),
      TARIHI: tarih,
      VADESI: tarihOnly,
      ISLEM_TURU: 4,
      SILINDI: 0,
      KAYDEDEN: 'MICROVISE',
      KAYIT_TARIHI: new Date(),
      SOURCE_APP: 'MICROVISE',
      KPB_TUTARI: amount,
      BAG_NO: '',
      POS_TANIMI: '',
    };

    const outRow = { ...base, BLKODU: outId, BLHSKODU: fromId, BLTRSKODU: inId, ACIKLAMA: descFrom.slice(0, 50), TUTAR_ALACAK: amount };
    const inRow = { ...base, BLKODU: inId, BLHSKODU: toId, BLTRSKODU: outId, ACIKLAMA: descTo.slice(0, 50), TUTAR_BORC: amount };

    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'BANKAHR', columns, outRow);
    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'BANKAHR', columns, inRow);
    return {
      type: 'bank_bank',
      evrakNo,
      amount,
      fromSourceId: String(outId),
      toSourceId: String(inId),
      fromAccountId: String(fromId),
      toAccountId: String(toId),
    };
  }

  async function createKasaBankTransfer(pool, body) {
    const direction = String(body.direction || body.type || '').toLowerCase();
    const isKasaToBank = direction === 'kasa_bank' || direction === 'kasa-banka' || direction === 'kasa_to_bank';
    const isBankToKasa = direction === 'bank_kasa' || direction === 'banka-kasa' || direction === 'bank_to_kasa';
    if (!isKasaToBank && !isBankToKasa) {
      throw Object.assign(new Error('direction: kasa_bank veya bank_kasa olmalı.'), { statusCode: 400 });
    }
    const accountId = Number(body.accountId || body.bankAccountId);
    const amount = numberOrZero(body.amount);
    const kasaAdi = textOrNull(body.kasaAdi);
    if (!Number.isFinite(accountId) || !kasaAdi) {
      throw Object.assign(new Error('Kasa adı ve banka hesabı zorunlu.'), { statusCode: 400 });
    }
    if (!(amount > 0)) {
      throw Object.assign(new Error('Tutar 0’dan büyük olmalı.'), { statusCode: 400 });
    }

    const accountMeta = await resolveAccountMeta(pool, accountId);
    const bankHrColumns = await akinsoftTableColumnSet(pool, 'BANKAHR');
    const kasaHrColumns = await akinsoftTableColumnSet(pool, 'KASAHR');
    const tarih = toSqlDate(body.date, new Date()) || new Date();
    const tarihOnly = new Date(tarih);
    tarihOnly.setHours(0, 0, 0, 0);
    const evrakNo = textOrNull(body.evrakNo) || (await nextEvrakNo(pool, 'BANKAHR', 'BH'));
    const aciklama = (
      textOrNull(body.description) ||
      (isKasaToBank ? 'Kasa-Banka Transferi' : 'Banka-Kasa Transferi')
    ).slice(0, 50);

    const kasaHrId = await akinsoftNextBlkoduSafe(pool, 'KASAHR');
    const bankHrId = await akinsoftNextBlkoduSafe(pool, 'BANKAHR');

    const kasaRow = {
      BLKODU: kasaHrId,
      TARIHI: tarih,
      EVRAK_NO: evrakNo.slice(0, 10),
      OZEL_KODU: (isKasaToBank ? 'Kasa-Banka' : 'Banka-Kasa').slice(0, 10),
      KASA_ADI: kasaAdi.slice(0, 10),
      ACIKLAMA: aciklama,
      BANKA_ADI: accountMeta.label.slice(0, 35),
      BLBNHSKODU: accountId,
      KPB_GLTUT: isBankToKasa ? amount : null,
      KPB_GDTUT: isKasaToBank ? amount : null,
      DOVIZ_KULLAN: 0,
      DOVIZ_BIRIMI: '',
      DOVIZ_ALIS: 1,
      DOVIZ_SATIS: 1,
      KPBDVZ: 1,
      SILINDI: 0,
      KAYDEDEN: 'MICROVISE',
      KAYIT_TARIHI: new Date(),
      SOURCE_APP: 'MICROVISE',
      BAG_NO: '',
      GM_ENTEGRASYON: 0,
      GRUBU: '',
      ARA_GRUBU: '',
      ALT_GRUBU: '',
      MUH_KODU: '',
    };

    const bankRow = {
      BLKODU: bankHrId,
      EVRAK_NO: evrakNo.slice(0, 10),
      OZEL_KODU: (isKasaToBank ? 'Kasa-Banka' : 'Banka-Kasa').slice(0, 10),
      TARIHI: tarih,
      VADESI: tarihOnly,
      ISLEM_TURU: 2,
      ACIKLAMA: aciklama,
      BAG_NO: `KH${kasaHrId}`.slice(0, 15),
      SILINDI: 0,
      KAYDEDEN: 'MICROVISE',
      BLHSKODU: accountId,
      TUTAR_BORC: isKasaToBank ? amount : null,
      TUTAR_ALACAK: isBankToKasa ? amount : null,
      KPB_TUTARI: amount,
      KAYIT_TARIHI: new Date(),
      SOURCE_APP: 'MICROVISE',
      POS_TANIMI: '',
    };

    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'KASAHR', kasaHrColumns, kasaRow);
    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'BANKAHR', bankHrColumns, bankRow);

    return {
      type: isKasaToBank ? 'kasa_bank' : 'bank_kasa',
      evrakNo,
      amount,
      kasaHrId: String(kasaHrId),
      bankHrId: String(bankHrId),
      accountId: String(accountId),
      kasaAdi,
    };
  }

  async function createMasraf(pool, body) {
    const hasFatura = await akinsoftTableExists(pool, 'FATURA');
    const hasFaturaHr = await akinsoftTableExists(pool, 'FATURAHR');
    if (!hasFatura || !hasFaturaHr) {
      throw Object.assign(new Error('FATURA / FATURAHR bulunamadı.'), { statusCode: 400 });
    }
    const items = Array.isArray(body.items) ? body.items : [];
    if (!items.length) {
      throw Object.assign(new Error('En az bir masraf kalemi girin.'), { statusCode: 400 });
    }

    const faturaColumns = await akinsoftTableColumnSet(pool, 'FATURA');
    const lineColumns = await akinsoftTableColumnSet(pool, 'FATURAHR');
    const faturaNo = textOrNull(body.faturaNo) || (await nextMasrafNo(pool));
    const tarih = toSqlDate(body.date, new Date()) || new Date();
    const cariSourceId = textOrNull(body.cariSourceId || body.blcrkodu);
    const cariKodu = textOrNull(body.cariKodu || body.carikodu);
    const cariUnvan = textOrNull(body.cariUnvan || body.customerName);

    let alt = 0;
    let kdv = 0;
    const linePayloads = items.map((item) => {
      const qty = numberOrZero(item.qty ?? item.quantity) || 1;
      const unit = numberOrZero(item.unitPrice ?? item.amount);
      const rate = numberOrZero(item.taxRate ?? item.kdv);
      const lineNet = qty * unit;
      const lineKdv = lineNet * (rate / 100);
      alt += lineNet;
      kdv += lineKdv;
      return {
        name: (textOrNull(item.name) || 'Masraf').slice(0, 50),
        qty,
        unit,
        rate,
        lineNet,
        lineKdv,
        lineTotal: lineNet + lineKdv,
        hizmetId: textOrNull(item.hizmetId || item.blhzmkodu),
      };
    });
    const genel = alt + kdv;

    const faturaId = await akinsoftNextBlkoduSafe(pool, 'FATURA');
    const header = { BLKODU: faturaId };
    setFirstColumn(header, faturaColumns, ['FATURA_NO'], faturaNo.slice(0, 40));
    setFirstColumn(header, faturaColumns, ['TARIHI', 'TARIHI2'], tarih);
    setFirstColumn(header, faturaColumns, ['FATURA_TIPI'], 1);
    setFirstColumn(header, faturaColumns, ['FATURA_DURUMU'], 7);
    setFirstColumn(header, faturaColumns, ['KDV_DURUMU'], 0);
    setFirstColumn(header, faturaColumns, ['KDV_ORANI'], linePayloads[0]?.rate || 0);
    setFirstColumn(header, faturaColumns, ['CARIHRK_ISLE'], cariSourceId ? 1 : 0);
    setFirstColumn(header, faturaColumns, ['STOKHRK_ISLE'], 0);
    setFirstColumn(header, faturaColumns, ['SILINDI'], 0);
    setFirstColumn(header, faturaColumns, ['IPTAL'], 0);
    setFirstColumn(header, faturaColumns, ['KAYDEDEN'], 'MICROVISE');
    setFirstColumn(header, faturaColumns, ['KAYIT_TARIHI'], new Date());
    setFirstColumn(header, faturaColumns, ['SOURCE_APP'], 'MICROVISE');
    setFirstColumn(header, faturaColumns, ['ACIKLAMA'], textOrNull(body.description || body.aciklama));
    if (cariSourceId) setFirstColumn(header, faturaColumns, ['BLCRKODU'], Number(cariSourceId));
    if (cariKodu) setFirstColumn(header, faturaColumns, ['CARIKODU'], cariKodu);
    if (cariUnvan) setFirstColumn(header, faturaColumns, ['TICARI_UNVANI', 'ADI_SOYADI'], cariUnvan);
    setAllColumns(header, faturaColumns, ['TOPLAM_ALT_KPB', 'TOPLAM_ARA_KPB'], alt);
    setAllColumns(header, faturaColumns, ['TOPLAM_KDV_KPB'], kdv);
    setAllColumns(header, faturaColumns, ['TOPLAM_GENEL_KPB'], genel);
    setAllColumns(header, faturaColumns, ['MIKTAR1_TOPLAM', 'MIKTAR2_TOPLAM'], linePayloads.reduce((s, l) => s + l.qty, 0));
    setFirstColumn(header, faturaColumns, ['DOVIZ_KULLAN'], 0);
    setFirstColumn(header, faturaColumns, ['DOVIZ_BIRIMI'], 'TL');

    await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'FATURA', faturaColumns, header);

    const lineIds = [];
    for (const line of linePayloads) {
      const lineId = await akinsoftNextBlkoduSafe(pool, 'FATURAHR');
      const row = { BLKODU: lineId };
      setFirstColumn(row, lineColumns, ['BLFTKODU'], faturaId);
      setFirstColumn(row, lineColumns, ['BLSTKODU'], -1);
      setFirstColumn(row, lineColumns, ['STOK_ADI'], line.name);
      setFirstColumn(row, lineColumns, ['MIKTARI', 'MIKTARI_2'], line.qty);
      setAllColumns(row, lineColumns, ['KPB_FIYATI', 'KPB_KDV_HARICFY', 'KPB_IND_FIYAT', 'KPB_FIYATI_2'], line.unit);
      setAllColumns(row, lineColumns, ['KPB_ARA_TUTAR', 'KPB_IND_TUTAR', 'KPB_TOPLAM_TUTAR'], line.lineNet);
      setAllColumns(row, lineColumns, ['KPB_KDVLI_TUTAR'], line.lineTotal);
      setFirstColumn(row, lineColumns, ['KDV_ORANI'], line.rate);
      setFirstColumn(row, lineColumns, ['KDV_TUTARI'], line.lineKdv || null);
      setFirstColumn(row, lineColumns, ['KDV_DURUMU'], 1);
      if (line.hizmetId) setFirstColumn(row, lineColumns, ['BLHZMKODU'], Number(line.hizmetId));
      await insertAkinsoftRowWithRequest(() => pool.request(), sql, 'FATURAHR', lineColumns, row);
      lineIds.push(String(lineId));
    }

    return {
      sourceId: String(faturaId),
      faturaNo,
      toplam: genel,
      lineIds,
    };
  }

  async function softDeleteTransfer(pool, body) {
    const type = String(body.type || '').toLowerCase();
    if (type === 'bank_bank') {
      const id = Number(body.sourceId);
      const pairId = Number(body.pairSourceId);
      if (!Number.isFinite(id)) throw Object.assign(new Error('sourceId zorunlu.'), { statusCode: 400 });
      const ids = [id, pairId].filter((n) => Number.isFinite(n));
      for (const blkodu of ids) {
        await pool
          .request()
          .input('id', sql.BigInt, blkodu)
          .query(`
            update dbo.BANKAHR
            set SILINDI=1, DEGISTIREN=N'MICROVISE', DEGISTIRME_TARIHI=getdate()
            where BLKODU=@id
          `);
      }
      return { action: 'soft_deleted', ids: ids.map(String) };
    }
    if (type === 'kasa_bank' || type === 'bank_kasa') {
      const kasaHrId = Number(String(body.sourceId || '').replace(/^kasa:/, ''));
      const bankHrId = Number(body.pairSourceId);
      if (Number.isFinite(kasaHrId)) {
        await pool
          .request()
          .input('id', sql.BigInt, kasaHrId)
          .query(`
            update dbo.KASAHR
            set SILINDI=1, DEGISTIREN=N'MICROVISE', DEGISTIRME_TARIHI=getdate()
            where BLKODU=@id
          `);
      }
      if (Number.isFinite(bankHrId)) {
        await pool
          .request()
          .input('id', sql.BigInt, bankHrId)
          .query(`
            update dbo.BANKAHR
            set SILINDI=1, DEGISTIREN=N'MICROVISE', DEGISTIRME_TARIHI=getdate()
            where BLKODU=@id
          `);
      }
      return { action: 'soft_deleted', kasaHrId, bankHrId };
    }
    throw Object.assign(new Error('Desteklenmeyen transfer tipi.'), { statusCode: 400 });
  }

  async function softDeleteMasraf(pool, body) {
    const sourceId = Number(body.sourceId);
    if (!Number.isFinite(sourceId)) {
      throw Object.assign(new Error('sourceId zorunlu.'), { statusCode: 400 });
    }
    await pool
      .request()
      .input('id', sql.BigInt, sourceId)
      .query(`
        update dbo.FATURA
        set SILINDI=1, DEGISTIREN=N'MICROVISE', DEGISTIRME_TARIHI=getdate()
        where BLKODU=@id
      `);
    return { sourceId: String(sourceId), action: 'soft_deleted' };
  }

  function wrapMutator(mutator) {
    return async function handler(req, res) {
      if (req.method !== 'POST') return jsonErr(res, 405, 'POST gerekli.');
      const body = await readJson(req);
      try {
        const result = await withPool(body, (pool) => mutator(pool, body));
        return jsonOk(res, { result });
      } catch (error) {
        return jsonErr(res, error.statusCode || 500, error.message || error);
      }
    };
  }

  return {
    '/api/akinsoft/finance/pull': handleFinancePull,
    '/api/akinsoft/finance/bank': wrapMutator(async (pool, body) => {
      const action = String(body.action || 'upsert').toLowerCase();
      if (action === 'delete') return deleteBank(pool, body);
      return upsertBank(pool, body);
    }),
    '/api/akinsoft/finance/bank-account': wrapMutator(async (pool, body) => {
      const action = String(body.action || 'upsert').toLowerCase();
      if (action === 'delete') return deleteBankAccount(pool, body);
      return upsertBankAccount(pool, body);
    }),
    '/api/akinsoft/finance/kasa': wrapMutator(async (pool, body) => {
      const action = String(body.action || 'upsert').toLowerCase();
      if (action === 'delete') return deleteKasa(pool, body);
      return upsertKasa(pool, body);
    }),
    '/api/akinsoft/finance/transfer': wrapMutator(async (pool, body) => {
      const action = String(body.action || 'create').toLowerCase();
      if (action === 'delete') return softDeleteTransfer(pool, body);
      const type = String(body.type || body.transferType || '').toLowerCase();
      if (type === 'bank_bank' || type === 'banka-banka') {
        return createBankBankTransfer(pool, body);
      }
      if (
        type === 'kasa_bank' ||
        type === 'bank_kasa' ||
        type === 'kasa-banka' ||
        type === 'banka-kasa'
      ) {
        return createKasaBankTransfer(pool, {
          ...body,
          direction: type.replace('-', '_'),
        });
      }
      throw Object.assign(
        new Error('type: bank_bank | kasa_bank | bank_kasa olmalı.'),
        { statusCode: 400 },
      );
    }),
    '/api/akinsoft/finance/masraf': wrapMutator(async (pool, body) => {
      const action = String(body.action || 'create').toLowerCase();
      if (action === 'delete') return softDeleteMasraf(pool, body);
      return createMasraf(pool, body);
    }),
  };
}

module.exports = {
  createAkinsoftFinanceHandlers,
};
