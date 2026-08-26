# WordPress fatura ödeme — v1.3.3

## Kurulum (iade için zorunlu)

1. `microvise-invoice-bridge-1.2.zip` yükle → sürüm **1.3.3**
2. CRM deploy bitsin
3. Sanal POS listesinden **İade** deneyin

## İade nasıl çalışır?

CRM kısa ömürlü bir **iade bileti** üretir → WordPress bileti CRM’den doğrular →
mağaza WooCommerce Halkbank API ile **Credit / Refund / Void** dener → CRM tahsilatı kapatır.

`store_key` eşleşmesi artık zorunlu değil (1.3.2+).

## Insufficient permissions

Banka `Insufficient permissions` döndürüyorsa WordPress/CRM tarafı çalışıyor demektir;
NestPay API kullanıcısında **Credit/Void iade yetkisi** kapalıdır. Halkbank üye işyeri
panelinden yetki açılmalı. Geçici olarak banka panelinden iade edip CRM’de
**CRM kaydını eşitle** kullanılabilir.
