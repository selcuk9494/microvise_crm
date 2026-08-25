<?php
/**
 * Plugin Name: Microvise Invoice Payment Bridge
 * Description: Fatura ödemesini WooCommerce Halkbank POS ile başlatır (aynı NestPay 3d + CC5). Banka dönüşünü CRM'e iletir.
 * Version: 1.3.2
 * Author: Microvise
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_action( 'init', 'microvise_invoice_bridge_override', 30 );
function microvise_invoice_bridge_override() {
	remove_action( 'admin_post_microvise_halkbank_bridge', 'microvise_halkbank_bridge' );
	remove_action( 'admin_post_nopriv_microvise_halkbank_bridge', 'microvise_halkbank_bridge' );
	add_action( 'admin_post_microvise_halkbank_bridge', 'microvise_invoice_halkbank_bridge' );
	add_action( 'admin_post_nopriv_microvise_halkbank_bridge', 'microvise_invoice_halkbank_bridge' );
}

add_action( 'admin_post_microvise_invoice_nestpay', 'microvise_invoice_nestpay_start' );
add_action( 'admin_post_nopriv_microvise_invoice_nestpay', 'microvise_invoice_nestpay_start' );
add_action( 'admin_post_microvise_invoice_nestpay_return', 'microvise_invoice_nestpay_return' );
add_action( 'admin_post_nopriv_microvise_invoice_nestpay_return', 'microvise_invoice_nestpay_return' );
add_action( 'admin_post_microvise_invoice_nestpay_refund', 'microvise_invoice_nestpay_refund' );
add_action( 'admin_post_nopriv_microvise_invoice_nestpay_refund', 'microvise_invoice_nestpay_refund' );

function microvise_invoice_crm_base() {
	return untrailingslashit(
		(string) apply_filters( 'microvise_invoice_payment_bridge_base_url', 'https://crm.microvise.net' )
	);
}

function microvise_invoice_req_value( $keys ) {
	foreach ( (array) $keys as $key ) {
		if ( isset( $_POST[ $key ] ) && (string) wp_unslash( $_POST[ $key ] ) !== '' ) {
			return sanitize_text_field( wp_unslash( $_POST[ $key ] ) );
		}
		if ( isset( $_GET[ $key ] ) && (string) wp_unslash( $_GET[ $key ] ) !== '' ) {
			return sanitize_text_field( wp_unslash( $_GET[ $key ] ) );
		}
	}
	return '';
}

function microvise_invoice_halkbank_gateway() {
	if ( ! function_exists( 'WC' ) ) {
		return null;
	}
	$gateways = WC()->payment_gateways()->payment_gateways();
	return isset( $gateways['microvise_halkbank'] ) ? $gateways['microvise_halkbank'] : null;
}

function microvise_invoice_nestpay_escape( $v ) {
	return str_replace( '|', '\\|', str_replace( '\\', '\\\\', (string) $v ) );
}

function microvise_invoice_nestpay_hash_ver3( array $params, $store_key ) {
	$keys = array_keys( $params );
	usort(
		$keys,
		function ( $a, $b ) {
			return strcasecmp( $a, $b );
		}
	);
	$hashval = '';
	foreach ( $keys as $k ) {
		$lk = strtolower( $k );
		if ( $lk === 'hash' || $lk === 'encoding' ) {
			continue;
		}
		$hashval .= microvise_invoice_nestpay_escape( (string) $params[ $k ] ) . '|';
	}
	$hashval .= microvise_invoice_nestpay_escape( (string) $store_key );
	return base64_encode( pack( 'H*', hash( 'sha512', $hashval ) ) );
}

function microvise_invoice_xml_escape( $v ) {
	return htmlspecialchars( (string) $v, ENT_XML1 | ENT_COMPAT, 'UTF-8' );
}

function microvise_invoice_to_try_amount( $amount, $currency ) {
	$cur = strtoupper( trim( (string) $currency ) );
	$amt = (float) $amount;
	if ( $cur === 'TRY' || $cur === 'TL' || $cur === '' ) {
		return array(
			'amount'   => number_format( $amt, 2, '.', '' ),
			'currency' => '949',
			'rate'     => 1.0,
			'original' => number_format( $amt, 2, '.', '' ) . ' TRY',
		);
	}
	$rate = null;
	if ( $cur === 'USD' && function_exists( 'microvise_halkbank_usd_satis_rate' ) ) {
		$rate = microvise_halkbank_usd_satis_rate();
	}
	if ( ! is_numeric( $rate ) || (float) $rate <= 0 ) {
		$settings = get_option( 'woocommerce_microvise_halkbank_settings', array() );
		$manual   = isset( $settings['usd_satis_rate_manual'] ) ? (string) $settings['usd_satis_rate_manual'] : '';
		$manual   = str_replace( array( ' ', ',' ), array( '', '.' ), $manual );
		if ( is_numeric( $manual ) && (float) $manual > 0 ) {
			$rate = (float) $manual;
		}
	}
	if ( ( ! is_numeric( $rate ) || (float) $rate <= 0 ) && $cur === 'USD' ) {
		$last = get_option( 'microvise_halkbank_usd_satis_rate_last' );
		if ( is_numeric( $last ) && (float) $last > 0 ) {
			$rate = (float) $last;
		}
	}
	if ( ! is_numeric( $rate ) || (float) $rate <= 0 ) {
		return new WP_Error(
			'no_rate',
			'Doviz odemesi icin TRY kuru bulunamadi. Magaza Halkbank POS kur ayarini kontrol edin.'
		);
	}
	$try_amt = round( $amt * (float) $rate, 2 );
	return array(
		'amount'   => number_format( $try_amt, 2, '.', '' ),
		'currency' => '949',
		'rate'     => (float) $rate,
		'original' => number_format( $amt, 2, '.', '' ) . ' ' . $cur,
	);
}

function microvise_invoice_nestpay_fail( $message, $token = '' ) {
	$crm = microvise_invoice_crm_base();
	$url = $crm . '/api/invoice-pay?invoice=fail&token=' . rawurlencode( (string) $token ) . '&errmsg=' . rawurlencode( (string) $message );
	wp_safe_redirect( $url, 302 );
	exit;
}

function microvise_invoice_nestpay_start() {
	$session  = isset( $_POST['session'] ) ? sanitize_text_field( wp_unslash( $_POST['session'] ) ) : '';
	$token    = isset( $_POST['token'] ) ? sanitize_text_field( wp_unslash( $_POST['token'] ) ) : '';
	$amount   = isset( $_POST['amount'] ) ? sanitize_text_field( wp_unslash( $_POST['amount'] ) ) : '';
	$currency = isset( $_POST['currency'] ) ? sanitize_text_field( wp_unslash( $_POST['currency'] ) ) : 'TRY';

	$pan = isset( $_POST['pan'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['pan'] ) ) : '';
	$cv2 = isset( $_POST['cv2'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['cv2'] ) ) : '';
	if ( $cv2 === '' && isset( $_POST['sc'] ) ) {
		$cv2 = preg_replace( '/\D+/', '', wp_unslash( $_POST['sc'] ) );
	}
	$mm = isset( $_POST['mm'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['mm'] ) ) : '';
	$yy = isset( $_POST['yy'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['yy'] ) ) : '';
	$mm = str_pad( substr( $mm, -2 ), 2, '0', STR_PAD_LEFT );
	$yy = str_pad( substr( $yy, -2 ), 2, '0', STR_PAD_LEFT );

	// CRM sayfasından klasik form POST (CORS yok). Hataları CRM fail ekranına yönlendir.
	if ( $session === '' || $token === '' || $pan === '' || $cv2 === '' || $mm === '00' || $yy === '00' ) {
		microvise_invoice_nestpay_fail( 'Eksik odeme veya kart bilgisi.', $token );
	}

	$crm  = microvise_invoice_crm_base();
	$info = wp_remote_get(
		$crm . '/api/invoice-pay?action=session&session=' . rawurlencode( $session ) . '&token=' . rawurlencode( $token ),
		array( 'timeout' => 20 )
	);
	if ( is_wp_error( $info ) ) {
		microvise_invoice_nestpay_fail( 'CRM oturum dogrulanamadi.', $token );
	}
	$body = json_decode( (string) wp_remote_retrieve_body( $info ), true );
	if ( empty( $body['ok'] ) ) {
		microvise_invoice_nestpay_fail( $body['message'] ?? 'Odeme oturumu gecersiz.', $token );
	}
	if ( ! empty( $body['paid'] ) || ( isset( $body['status'] ) && $body['status'] === 'paid' ) ) {
		microvise_invoice_nestpay_fail( 'Bu odeme zaten tamamlanmis.', $token );
	}

	$amount   = (string) ( $body['amount'] ?? $amount );
	$currency = (string) ( $body['currency'] ?? $currency );
	$try      = microvise_invoice_to_try_amount( $amount, $currency );
	if ( is_wp_error( $try ) ) {
		microvise_invoice_nestpay_fail( $try->get_error_message(), $token );
	}

	$gw = microvise_invoice_halkbank_gateway();
	if ( ! $gw ) {
		microvise_invoice_nestpay_fail( 'WooCommerce microvise_halkbank gecidi bulunamadi.', $token );
	}
	$gateway_url = (string) $gw->get_option( 'gateway_url' );
	$merchant_id = (string) $gw->get_option( 'merchant_id' );
	$store_key   = (string) $gw->get_option( 'store_key' );
	$storetype   = (string) ( $gw->get_option( 'store_type' ) ?: '3d' );
	if ( $gateway_url === '' || $merchant_id === '' || $store_key === '' ) {
		microvise_invoice_nestpay_fail( 'Halkbank POS ayarlari eksik.', $token );
	}

	$oid      = substr( preg_replace( '/[^a-zA-Z0-9]/', '', $token . wp_generate_password( 8, false, false ) ), 0, 20 );
	$callback = add_query_arg(
		array(
			'action' => 'microvise_invoice_nestpay_return',
			'token'  => $token,
		),
		admin_url( 'admin-post.php' )
	);
	$rnd = (string) microtime( true );

	// Birebir: woocommerce_receipt_microvise_halkbank formu
	$params = array(
		'clientid'                        => $merchant_id,
		'storetype'                       => $storetype ? $storetype : '3d',
		'hashAlgorithm'                   => 'ver3',
		'islemtipi'                       => 'Auth',
		'TranType'                        => 'Auth',
		'Instalment'                      => '',
		'amount'                          => $try['amount'],
		'currency'                        => $try['currency'],
		'oid'                             => $oid,
		'okUrl'                           => $callback,
		'failUrl'                         => $callback,
		'lang'                            => 'tr',
		'rnd'                             => $rnd,
		'pan'                             => $pan,
		'cv2'                             => $cv2,
		'Ecom_Payment_Card_ExpDate_Year'  => $yy,
		'Ecom_Payment_Card_ExpDate_Month' => $mm,
	);
	$hash           = microvise_invoice_nestpay_hash_ver3( $params, $store_key );
	$params['HASH'] = $hash;
	$params['hash'] = $hash;

	// JSON degil HTML don (CRM document.write bekliyor)
	header( 'Content-Type: text/html; charset=UTF-8' );
	echo '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Banka</title></head>';
	echo '<body onload="document.forms[0].submit()" style="font-family:Arial,sans-serif;background:#f5f5f7;margin:0;padding:24px;text-align:center">';
	echo '<p>Bankaya yonlendiriliyorsunuz…</p>';
	if ( $try['rate'] !== 1.0 ) {
		echo '<p style="color:#64748b;font-size:13px">Karttan cekilecek: <strong>' . esc_html( $try['amount'] ) . ' TRY</strong> (' . esc_html( $try['original'] ) . ', kur ' . esc_html( (string) $try['rate'] ) . ')</p>';
	}
	echo '<form method="post" action="' . esc_url( $gateway_url ) . '">';
	foreach ( $params as $k => $v ) {
		echo '<input type="hidden" name="' . esc_attr( $k ) . '" value="' . esc_attr( (string) $v ) . '">';
	}
	echo '</form></body></html>';
	exit;
}

function microvise_invoice_nestpay_return() {
	$token = isset( $_GET['token'] ) ? sanitize_text_field( wp_unslash( $_GET['token'] ) ) : '';
	$crm   = microvise_invoice_crm_base();
	$fail  = function ( $msg ) use ( $crm, $token ) {
		$url = $crm . '/api/invoice-pay?invoice=fail&token=' . rawurlencode( $token ) . '&errmsg=' . rawurlencode( $msg );
		wp_redirect( $url, 302 );
		exit;
	};
	if ( $token === '' ) {
		$fail( 'Eksik token' );
	}

	$code = microvise_invoice_req_value( array( 'ProcReturnCode', 'procReturnCode', 'PROCRETURNCODE' ) );
	$resp = microvise_invoice_req_value( array( 'Response', 'response' ) );
	$md   = microvise_invoice_req_value( array( 'mdStatus', 'MdStatus', 'mdstatus', 'MDSTATUS' ) );
	$err  = microvise_invoice_req_value( array( 'ErrMsg', 'errmsg', 'mdErrorMsg', 'mderrormessage' ) );

	$gw = microvise_invoice_halkbank_gateway();
	$ok = false;

	if ( $gw ) {
		$st = strtolower( (string) ( $gw->get_option( 'store_type' ) ?: '3d' ) );
		if ( in_array( $st, array( '3d_pay', '3d_pay_hosting' ), true ) ) {
			if ( $code === '00' || strtoupper( $resp ) === 'APPROVED' ) {
				$ok = true;
			}
		} elseif ( in_array( $md, array( '1', '2', '3', '4' ), true ) ) {
			$api_url      = (string) $gw->get_option( 'api_url' );
			$api_name     = (string) $gw->get_option( 'api_name' );
			$api_password = (string) $gw->get_option( 'api_password' );
			$clientid     = (string) $gw->get_option( 'merchant_id' );
			$mode         = ( $gw->get_option( 'test_mode' ) === 'yes' ) ? 'T' : 'P';
			if ( $api_url && $api_name && $api_password && $clientid ) {
				$xid   = microvise_invoice_req_value( array( 'xid', 'XID' ) );
				$eci   = microvise_invoice_req_value( array( 'eci', 'ECI' ) );
				$cavv  = microvise_invoice_req_value( array( 'cavv', 'CAVV' ) );
				$mdpan = microvise_invoice_req_value( array( 'md', 'MD' ) );
				$oid   = microvise_invoice_req_value( array( 'oid', 'OrderId', 'orderid' ) );
				$total = microvise_invoice_req_value( array( 'amount', 'Total' ) );
				$cur   = microvise_invoice_req_value( array( 'currency' ) ) ?: '949';

				$xml = '<?xml version="1.0" encoding="UTF-8"?>'
					. '<CC5Request>'
					. '<Name>' . microvise_invoice_xml_escape( $api_name ) . '</Name>'
					. '<Password>' . microvise_invoice_xml_escape( $api_password ) . '</Password>'
					. '<ClientId>' . microvise_invoice_xml_escape( $clientid ) . '</ClientId>'
					. '<Mode>' . microvise_invoice_xml_escape( $mode ) . '</Mode>'
					. '<Type>Auth</Type>'
					. '<OrderId>' . microvise_invoice_xml_escape( $oid ) . '</OrderId>'
					. '<Total>' . microvise_invoice_xml_escape( $total ) . '</Total>'
					. '<Currency>' . microvise_invoice_xml_escape( $cur ) . '</Currency>'
					. '<Number>' . microvise_invoice_xml_escape( $mdpan ) . '</Number>'
					. '<PayerTxnId>' . microvise_invoice_xml_escape( $xid ) . '</PayerTxnId>'
					. '<PayerSecurityLevel>' . microvise_invoice_xml_escape( $eci ) . '</PayerSecurityLevel>'
					. '<PayerAuthenticationCode>' . microvise_invoice_xml_escape( $cavv ) . '</PayerAuthenticationCode>'
					. '</CC5Request>';

				$urls = array( $api_url );
				if ( preg_match( '#/fim/cc5xml/?$#i', $api_url ) ) {
					$urls[] = preg_replace( '#/fim/cc5xml/?$#i', '/fim/api', $api_url );
				} elseif ( preg_match( '#/fim/api/?$#i', $api_url ) ) {
					$urls[] = preg_replace( '#/fim/api/?$#i', '/fim/cc5xml', $api_url );
				}
				$api_body = '';
				foreach ( $urls as $u ) {
					foreach (
						array(
							array( 'headers' => array( 'Content-Type' => 'text/xml; charset=UTF-8' ), 'body' => $xml ),
							array( 'body' => array( 'DATA' => $xml ) ),
						) as $args
					) {
						$r = wp_remote_post( $u, array_merge( array( 'timeout' => 25 ), $args ) );
						if ( is_wp_error( $r ) ) {
							continue;
						}
						$api_body = (string) wp_remote_retrieve_body( $r );
						if ( preg_match( '/<ProcReturnCode>\s*00\s*<\/ProcReturnCode>/i', $api_body )
							|| preg_match( '/<Response>\s*Approved\s*<\/Response>/i', $api_body ) ) {
							$ok = true;
							break 2;
						}
						if ( preg_match( '/<ErrMsg>([^<]+)<\/ErrMsg>/i', $api_body, $m ) ) {
							$err = trim( $m[1] );
						}
					}
				}
			} else {
				$err = $err !== '' ? $err : 'POS API kullanici bilgisi eksik.';
			}
		} else {
			$err = $err !== '' ? $err : ( 'MDStatus ' . ( $md !== '' ? $md : '0' ) );
		}
	}

	// CRM'e sonucu bildir (ProcReturnCode ile; CRM tekrar finalize etmez)
	$payload = array();
	foreach ( (array) $_POST as $key => $value ) {
		$payload[ $key ] = is_array( $value ) ? array_map( 'wp_unslash', $value ) : wp_unslash( $value );
	}
	if ( $ok ) {
		$payload['ProcReturnCode'] = '00';
		$payload['Response']       = 'Approved';
	} else {
		$payload['ProcReturnCode'] = $code !== '' ? $code : '99';
		$payload['ErrMsg']         = $err !== '' ? $err : 'Odeme basarisiz';
	}

	$response = wp_remote_post(
		$crm . '/api/invoice-pay?action=callback&token=' . rawurlencode( $token ),
		array(
			'timeout'     => 30,
			'redirection' => 0,
			'body'        => $payload,
		)
	);

	if ( ! is_wp_error( $response ) ) {
		$location = wp_remote_retrieve_header( $response, 'location' );
		if ( $location ) {
			wp_redirect( $location, 302 );
			exit;
		}
		$body = (string) wp_remote_retrieve_body( $response );
		if ( $body !== '' ) {
			status_header( (int) wp_remote_retrieve_response_code( $response ) );
			echo $body; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
			exit;
		}
	}

	if ( $ok ) {
		wp_redirect( $crm . '/api/invoice-pay?invoice=success&token=' . rawurlencode( $token ), 302 );
	} else {
		$fail( $err !== '' ? $err : 'Odeme basarisiz' );
	}
	exit;
}

function microvise_invoice_halkbank_bridge() {
	$callback = isset( $_GET['callback'] ) ? sanitize_key( wp_unslash( $_GET['callback'] ) ) : 'license';
	if ( ! in_array( $callback, array( 'license', 'license_hosted', 'halkbank', 'invoice_hosted' ), true ) ) {
		status_header( 400 );
		echo 'Gecersiz callback';
		exit;
	}

	if ( 'invoice_hosted' === $callback ) {
		$token      = isset( $_GET['token'] ) ? sanitize_text_field( wp_unslash( $_GET['token'] ) ) : '';
		$target_url = microvise_invoice_crm_base() . '/api/invoice-pay?action=callback&token=' . rawurlencode( $token );
	} else {
		$base            = function_exists( 'microvise_payment_bridge_base_url' )
			? microvise_payment_bridge_base_url()
			: 'https://frfood-backend.onrender.com';
		$target_callback = ( 'license_hosted' === $callback ) ? 'license-hosted' : $callback;
		$target_url      = untrailingslashit( (string) $base ) . '/api/payment/' . $target_callback . '/callback';
	}

	$payload = array();
	foreach ( (array) $_POST as $key => $value ) {
		$payload[ $key ] = is_array( $value ) ? array_map( 'wp_unslash', $value ) : wp_unslash( $value );
	}

	$response = wp_remote_post(
		$target_url,
		array(
			'timeout'     => 30,
			'redirection' => 0,
			'body'        => $payload,
		)
	);

	if ( is_wp_error( $response ) ) {
		status_header( 502 );
		echo 'Bridge error: ' . esc_html( $response->get_error_message() );
		exit;
	}

	$status_code = (int) wp_remote_retrieve_response_code( $response );
	$location    = wp_remote_retrieve_header( $response, 'location' );
	if ( $location ) {
		wp_redirect( $location, 302 );
		exit;
	}

	status_header( $status_code > 0 ? $status_code : 200 );
	$body = wp_remote_retrieve_body( $response );
	if ( $body !== '' ) {
		echo $body; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
	}
	exit;
}

/**
 * CRM'den Sanal POS iade. Auth: refund_ticket (CRM dogrular) veya store_key/api_password.
 */
function microvise_invoice_nestpay_refund() {
	header( 'Content-Type: application/json; charset=utf-8' );

	$bridge_key    = isset( $_POST['bridge_key'] ) ? (string) wp_unslash( $_POST['bridge_key'] ) : '';
	$refund_ticket = isset( $_POST['refund_ticket'] ) ? sanitize_text_field( wp_unslash( $_POST['refund_ticket'] ) ) : '';
	$order_id      = isset( $_POST['order_id'] ) ? sanitize_text_field( wp_unslash( $_POST['order_id'] ) ) : '';
	$amount        = isset( $_POST['amount'] ) ? sanitize_text_field( wp_unslash( $_POST['amount'] ) ) : '';
	$currency      = isset( $_POST['currency'] ) ? sanitize_text_field( wp_unslash( $_POST['currency'] ) ) : '949';

	$gw = microvise_invoice_halkbank_gateway();
	if ( ! $gw ) {
		status_header( 500 );
		echo wp_json_encode( array( 'success' => false, 'message' => 'WooCommerce Halkbank gecidi yok.' ) );
		exit;
	}

	$auth_ok = false;
	if ( $refund_ticket !== '' ) {
		$crm  = microvise_invoice_crm_base();
		$info = wp_remote_get(
			$crm . '/api/invoice-pay?action=verify-refund&ticket=' . rawurlencode( $refund_ticket ),
			array( 'timeout' => 20 )
		);
		if ( ! is_wp_error( $info ) ) {
			$verified = json_decode( (string) wp_remote_retrieve_body( $info ), true );
			if ( ! empty( $verified['ok'] ) ) {
				$auth_ok  = true;
				$order_id = (string) ( $verified['orderId'] ?? $order_id );
				$amount   = (string) ( $verified['amount'] ?? $amount );
				$currency = (string) ( $verified['currency'] ?? $currency );
			} else {
				status_header( 403 );
				echo wp_json_encode(
					array(
						'success' => false,
						'message' => $verified['message'] ?? 'CRM iade bileti gecersiz.',
					)
				);
				exit;
			}
		}
	}

	if ( ! $auth_ok ) {
		$store_key     = (string) $gw->get_option( 'store_key' );
		$api_password  = (string) $gw->get_option( 'api_password' );
		$option_secret = (string) get_option( 'microvise_invoice_bridge_secret', '' );
		foreach ( array( $store_key, $api_password, $option_secret ) as $candidate ) {
			if ( $candidate !== '' && $bridge_key !== '' && hash_equals( $candidate, $bridge_key ) ) {
				$auth_ok = true;
				break;
			}
		}
	}

	if ( ! $auth_ok ) {
		status_header( 403 );
		echo wp_json_encode( array( 'success' => false, 'message' => 'Yetkisiz iade istegi.' ) );
		exit;
	}
	if ( $order_id === '' || ! is_numeric( $amount ) || (float) $amount <= 0 ) {
		status_header( 400 );
		echo wp_json_encode( array( 'success' => false, 'message' => 'order_id / amount zorunlu.' ) );
		exit;
	}

	$api_url      = (string) $gw->get_option( 'api_url' );
	$api_name     = (string) $gw->get_option( 'api_name' );
	$api_password = (string) $gw->get_option( 'api_password' );
	$clientid     = (string) $gw->get_option( 'merchant_id' );
	$mode         = ( $gw->get_option( 'test_mode' ) === 'yes' ) ? 'T' : 'P';
	if ( ! $api_url || ! $api_name || ! $api_password || ! $clientid ) {
		status_header( 500 );
		echo wp_json_encode( array( 'success' => false, 'message' => 'POS API ayarlari eksik.' ) );
		exit;
	}

	$urls = array( $api_url );
	if ( preg_match( '#/fim/cc5xml/?$#i', $api_url ) ) {
		$urls[] = preg_replace( '#/fim/cc5xml/?$#i', '/fim/api', $api_url );
	} elseif ( preg_match( '#/fim/api/?$#i', $api_url ) ) {
		$urls[] = preg_replace( '#/fim/api/?$#i', '/fim/cc5xml', $api_url );
	}

	$try_types = array( 'Credit', 'Void' );
	$last_err  = 'Iade basarisiz';
	foreach ( $try_types as $type ) {
		$xml = '<?xml version="1.0" encoding="UTF-8"?>'
			. '<CC5Request>'
			. '<Name>' . microvise_invoice_xml_escape( $api_name ) . '</Name>'
			. '<Password>' . microvise_invoice_xml_escape( $api_password ) . '</Password>'
			. '<ClientId>' . microvise_invoice_xml_escape( $clientid ) . '</ClientId>'
			. '<Mode>' . microvise_invoice_xml_escape( $mode ) . '</Mode>'
			. '<Type>' . microvise_invoice_xml_escape( $type ) . '</Type>'
			. '<OrderId>' . microvise_invoice_xml_escape( $order_id ) . '</OrderId>'
			. '<Total>' . microvise_invoice_xml_escape( number_format( (float) $amount, 2, '.', '' ) ) . '</Total>'
			. '<Currency>' . microvise_invoice_xml_escape( $currency ? $currency : '949' ) . '</Currency>'
			. '</CC5Request>';

		foreach ( $urls as $u ) {
			foreach (
				array(
					array( 'headers' => array( 'Content-Type' => 'text/xml; charset=UTF-8' ), 'body' => $xml ),
					array( 'body' => array( 'DATA' => $xml ) ),
				) as $args
			) {
				$r = wp_remote_post( $u, array_merge( array( 'timeout' => 25 ), $args ) );
				if ( is_wp_error( $r ) ) {
					$last_err = $r->get_error_message();
					continue;
				}
				$api_body = (string) wp_remote_retrieve_body( $r );
				if ( preg_match( '/<ProcReturnCode>\s*00\s*<\/ProcReturnCode>/i', $api_body )
					|| preg_match( '/<Response>\s*Approved\s*<\/Response>/i', $api_body ) ) {
					echo wp_json_encode(
						array(
							'success' => true,
							'type'    => $type,
							'message' => 'Iade onaylandi',
							'parsed'  => array(
								'procReturnCode' => '00',
								'orderId'        => $order_id,
							),
						)
					);
					exit;
				}
				if ( preg_match( '/<ErrMsg>([^<]+)<\/ErrMsg>/i', $api_body, $m ) ) {
					$last_err = trim( $m[1] );
				}
			}
		}
	}

	status_header( 400 );
	echo wp_json_encode( array( 'success' => false, 'message' => $last_err ) );
	exit;
}
