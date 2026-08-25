<?php
/* Template Name: Fatura Odeme */
$session_token = isset($_GET['session']) ? sanitize_text_field(wp_unslash($_GET['session'])) : '';
$invoice_status = isset($_GET['invoice']) ? sanitize_key(wp_unslash($_GET['invoice'])) : '';
$token = isset($_GET['token']) ? sanitize_text_field(wp_unslash($_GET['token'])) : '';
$amount = isset($_GET['amount']) ? sanitize_text_field(wp_unslash($_GET['amount'])) : '0.00';
$currency = isset($_GET['currency']) ? sanitize_text_field(wp_unslash($_GET['currency'])) : 'TRY';
$customer_name = isset($_GET['customer']) ? sanitize_text_field(wp_unslash($_GET['customer'])) : 'Musteri';
$invoice_count = isset($_GET['invoices']) ? absint($_GET['invoices']) : 0;
$error_message = isset($_GET['errmsg']) ? sanitize_text_field(wp_unslash($_GET['errmsg'])) : '';
$invoice_numbers = isset($_GET['numbers']) ? sanitize_text_field(wp_unslash($_GET['numbers'])) : '';
$fatura_label = $invoice_numbers !== '' ? $invoice_numbers : ($invoice_count > 0 ? ((string) $invoice_count . ' adet') : '-');
$api_url = apply_filters(
  'microvise_invoice_payment_pay_url',
  'https://crm.microvise.net/api/invoice-pay?action=pay'
);
?><!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
<meta charset="<?php bloginfo('charset'); ?>">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fatura Odeme</title>
<?php wp_head(); ?>
<style>
body{margin:0;background:linear-gradient(180deg,#eff6ff 0%,#f8fafc 100%);font-family:Arial,sans-serif;color:#0f172a}
.wrap{max-width:800px;margin:10px auto;padding:0 10px}
.card{background:#fff;border:1px solid #dbe4f0;border-radius:22px;overflow:hidden;box-shadow:0 16px 40px rgba(15,23,42,.10)}
.hero{padding:16px 18px;background:linear-gradient(135deg,#0d6efd 0%,#1d4ed8 55%,#0f3d91 100%);color:#fff}
.hero h1{margin:0 0 4px;font-size:26px;line-height:1.1}
.hero p{margin:0;font-size:14px;color:rgba(255,255,255,.92)}
.body{padding:16px}
.result-card{border-radius:18px;padding:18px 18px 16px;margin-bottom:18px;border:1px solid}
.result-card.success{background:linear-gradient(180deg,#ecfdf5 0%,#f7fffb 100%);border-color:#86efac}
.result-card.error{background:linear-gradient(180deg,#fff1f2 0%,#fff8f8 100%);border-color:#fda4af}
.result-head{display:flex;align-items:flex-start;gap:12px;margin-bottom:10px}
.result-icon{width:46px;height:46px;border-radius:999px;display:flex;align-items:center;justify-content:center;font-size:21px;font-weight:700;flex:0 0 46px}
.result-card.success .result-icon{background:#16a34a;color:#fff}
.result-card.error .result-icon{background:#dc2626;color:#fff}
.result-title{margin:0;font-size:22px;font-weight:800}
.result-sub{margin:4px 0 0;color:#475569;line-height:1.45}
.detail-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-top:14px}
.detail-box{background:rgba(255,255,255,.7);border:1px solid rgba(148,163,184,.22);border-radius:12px;padding:12px}
.detail-label{display:block;font-size:11px;color:#64748b;margin-bottom:4px}
.detail-value{font-size:16px;font-weight:700;word-break:break-word}
.summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-bottom:10px}
.box{background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:10px}
.label{display:block;font-size:11px;color:#64748b;margin-bottom:4px}
.value{font-size:17px;font-weight:800;line-height:1.2}
.helper{margin:0 0 12px;color:#64748b;font-size:12px}
.notice{padding:12px 14px;border-radius:12px;margin-bottom:12px;border:1px solid #fecaca;background:#fff1f2;color:#b91c1c}
.actions{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:10px;padding-top:10px;border-top:1px solid #e2e8f0}
.button{border:0;border-radius:999px;padding:12px 18px;font-size:14px;font-weight:700;cursor:pointer}
.primary{background:#dc2626;color:#fff}
.secondary{display:inline-flex;align-items:center;justify-content:center;text-decoration:none;background:#e0ecff;color:#1d4ed8}
.muted{font-size:11px;color:#64748b;line-height:1.35}
.loader{display:none;margin-top:8px;color:#1d4ed8;font-weight:700;font-size:12px}
.pay-shell{background:#fff;border:1px solid #e2e8f0;border-radius:18px;box-shadow:0 10px 24px rgba(15,23,42,.05);padding:16px}
.secure{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:12px 14px;border:1px solid #dbe4f0;border-radius:14px;background:linear-gradient(180deg,#f8fafc 0%,#eef4ff 100%);margin-bottom:12px}
.secure strong{font-size:18px}
@media(max-width:640px){.summary,.detail-grid{grid-template-columns:1fr}.actions{flex-direction:column;align-items:stretch}.hero h1{font-size:24px}.wrap{padding:0 8px}.body{padding:12px}}
</style>
</head>
<body <?php body_class('microvise-invoice-payment'); ?>>
<div class="wrap">
  <div class="card">
    <div class="hero">
      <h1>Fatura Odeme</h1>
      <p>Odeme Microvise uzerinden alinir. Banka onayi sonrasi sonuc bu ekranda gosterilir.</p>
    </div>
    <div class="body">
<?php if ($invoice_status === 'success') : ?>
      <div class="result-card success">
        <div class="result-head">
          <div class="result-icon">✓</div>
          <div>
            <h2 class="result-title">Odeme Onaylandi</h2>
            <p class="result-sub">Tesekkurler. Odemeniz alindi, ilgili faturalar guncellendi.</p>
          </div>
        </div>
        <div class="detail-grid">
          <div class="detail-box"><span class="detail-label">Musteri</span><div class="detail-value"><?php echo esc_html($customer_name !== '' ? $customer_name : '-'); ?></div></div>
          <div class="detail-box"><span class="detail-label">Tutar</span><div class="detail-value"><?php echo esc_html($amount . ' ' . $currency); ?></div></div>
          <div class="detail-box"><span class="detail-label">Durum</span><div class="detail-value">Basarili</div></div>
        </div>
      </div>
<?php elseif ($invoice_status === 'fail') : ?>
      <div class="result-card error">
        <div class="result-head">
          <div class="result-icon">!</div>
          <div>
            <h2 class="result-title">Odeme Tamamlanamadi</h2>
            <p class="result-sub"><?php echo esc_html($error_message !== '' ? $error_message : 'Banka islemi basarisiz dondu.'); ?></p>
          </div>
        </div>
        <div class="detail-grid">
          <div class="detail-box"><span class="detail-label">Musteri</span><div class="detail-value"><?php echo esc_html($customer_name !== '' ? $customer_name : '-'); ?></div></div>
          <div class="detail-box"><span class="detail-label">Tutar</span><div class="detail-value"><?php echo esc_html($amount . ' ' . $currency); ?></div></div>
          <div class="detail-box"><span class="detail-label">Durum</span><div class="detail-value">Basarisiz</div></div>
        </div>
      </div>
      <?php if ($session_token !== '') : ?>
      <a class="button secondary" href="<?php echo esc_url(add_query_arg(array(
        'session' => $session_token,
        'token' => $token,
        'amount' => $amount,
        'currency' => $currency,
        'customer' => $customer_name,
        'invoices' => $invoice_count,
      ), home_url('/fatura-odeme/'))); ?>">Tekrar dene</a>
      <?php endif; ?>
<?php elseif ($session_token === '') : ?>
      <div class="notice"><strong>Odeme baglantisi gecersiz.</strong><br>Bu ekran CRM uzerinden olusturulan gecerli odeme oturumu ile acilmalidir.</div>
<?php else : ?>
      <div class="summary">
        <div class="box"><span class="label">Musteri</span><div class="value"><?php echo esc_html($customer_name); ?></div></div>
        <div class="box"><span class="label">Fatura No</span><div class="value"><?php echo esc_html($fatura_label); ?></div></div>
        <div class="box"><span class="label">Tutar</span><div class="value"><?php echo esc_html($amount . ' ' . $currency); ?></div></div>
      </div>
      <p class="helper">Guvenli odeme icin banka sayfasina yonlendirileceksiniz. Kart bilgileriniz banka ekraninda girilir.</p>
      <div id="invoice-error" class="notice" style="display:none"></div>
      <div class="pay-shell">
        <div class="secure">
          <div>
            <span class="label">Toplam Odeme</span>
            <strong><?php echo esc_html($amount . ' ' . $currency); ?></strong>
          </div>
          <div class="muted">3D Secure · Microvise Sanal POS</div>
        </div>
        <div class="actions">
          <div class="muted">Islem sonrasi sonuc bu sayfada gosterilir.</div>
          <button id="pay-button" class="button primary" type="button">Odemeye Git</button>
        </div>
        <div id="invoice-loader" class="loader">Banka ekrani hazirlaniyor...</div>
      </div>
      <script>
      (function(){
        var sessionToken=<?php echo wp_json_encode($session_token); ?>;
        var token=<?php echo wp_json_encode($token); ?>;
        var apiUrl=<?php echo wp_json_encode($api_url); ?>;
        var errorBox=document.getElementById('invoice-error');
        var loader=document.getElementById('invoice-loader');
        var payButton=document.getElementById('pay-button');
        function showError(message){errorBox.textContent=message;errorBox.style.display='block';}
        payButton.addEventListener('click',function(){
          errorBox.style.display='none';
          loader.style.display='block';
          payButton.disabled=true;
          fetch(apiUrl,{
            method:'POST',
            headers:{'Content-Type':'application/json'},
            body:JSON.stringify({sessionToken:sessionToken,token:token})
          }).then(function(response){return response.json().then(function(data){return {ok:response.ok,data:data};});})
          .then(function(result){
            if(result.data&&result.data.success&&result.data.html){
              document.open();
              document.write(result.data.html);
              document.close();
              return;
            }
            throw new Error((result.data&&result.data.message)||'Odeme baslatilamadi.');
          }).catch(function(error){
            loader.style.display='none';
            payButton.disabled=false;
            showError(error&&error.message?error.message:'Odeme baslatilamadi.');
          });
        });
      })();
      </script>
<?php endif; ?>
    </div>
  </div>
</div>
<?php wp_footer(); ?>
</body>
</html>
