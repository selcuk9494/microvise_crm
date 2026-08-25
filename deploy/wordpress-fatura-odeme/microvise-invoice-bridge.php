<?php
/**
 * Plugin Name: Microvise Invoice Payment Bridge
 * Description: Fatura ödemesini microvise.net WooCommerce Halkbank POS (çalışan NestPay 3d) ile başlatır; banka callback'ini CRM'e iletir.
 * Version: 1.1.0
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

function microvise_invoice_crm_base() {
	return untrailingslashit(
		(string) apply_filters( 'microvise_invoice_payment_bridge_base_url', 'https://crm.microvise.net' )
	);
}

function microvise_invoice_halkbank_gateway_settings() {
	$gateway_url = '';
	$merchant_id = '';
	$store_key   = '';

	if ( function_exists( 'WC' ) ) {
		$gateways = WC()->payment_gateways()->payment_gateways();
		$gw       = isset( $gateways['microvise_halkbank'] ) ? $gateways['microvise_halkbank'] : null;
		if ( $gw ) {
			$gateway_url = (string) $gw->get_option( 'gateway_url' );
			$merchant_id = (string) $gw->get_option( 'merchant_id' );
			$store_key   = (string) $gw->get_option( 'store_key' );
		}
	}

	if ( $gateway_url === '' || $merchant_id === '' || $store_key === '' ) {
		$settings    = get_option( 'woocommerce_microvise_halkbank_settings', array() );
		$gateway_url = $gateway_url !== '' ? $gateway_url : (string) ( $settings['gateway_url'] ?? 'https://sanalpos.halkbank.com.tr/fim/est3Dgate' );
		$merchant_id = $merchant_id !== '' ? $merchant_id : (string) ( $settings['merchant_id'] ?? '' );
		$store_key   = $store_key !== '' ? $store_key : (string) ( $settings['store_key'] ?? '' );
	}

	return array(
		'gateway_url' => $gateway_url,
		'merchant_id' => $merchant_id,
		'store_key'   => $store_key,
	);
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
	$hex = hash( 'sha512', $hashval );
	return base64_encode( pack( 'H*', $hex ) );
}

function microvise_invoice_nestpay_currency( $cur ) {
	$map = array(
		'TRY' => '949',
		'TL'  => '949',
		'USD' => '840',
		'EUR' => '978',
		'GBP' => '826',
	);
	$key = strtoupper( trim( (string) $cur ) );
	return $map[ $key ] ?? '949';
}

function microvise_invoice_nestpay_start() {
	$session = isset( $_POST['session'] ) ? sanitize_text_field( wp_unslash( $_POST['session'] ) ) : '';
	$token   = isset( $_POST['token'] ) ? sanitize_text_field( wp_unslash( $_POST['token'] ) ) : '';
	$amount  = isset( $_POST['amount'] ) ? sanitize_text_field( wp_unslash( $_POST['amount'] ) ) : '';
	$currency = isset( $_POST['currency'] ) ? sanitize_text_field( wp_unslash( $_POST['currency'] ) ) : 'TRY';

	$pan = isset( $_POST['pan'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['pan'] ) ) : '';
	$cv2 = isset( $_POST['cv2'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['cv2'] ) ) : '';
	if ( $cv2 === '' && isset( $_POST['sc'] ) ) {
		$cv2 = preg_replace( '/\D+/', '', wp_unslash( $_POST['sc'] ) );
	}
	$mm = isset( $_POST['mm'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['mm'] ) ) : '';
	$yy = isset( $_POST['yy'] ) ? preg_replace( '/\D+/', '', wp_unslash( $_POST['yy'] ) ) : '';
	if ( strlen( $mm ) > 2 ) {
		$mm = substr( $mm, -2 );
	}
	$mm = str_pad( $mm, 2, '0', STR_PAD_LEFT );
	if ( strlen( $yy ) > 2 ) {
		$yy = substr( $yy, -2 );
	}
	$yy = str_pad( $yy, 2, '0', STR_PAD_LEFT );

	if ( $session === '' || $token === '' || $pan === '' || $cv2 === '' || $mm === '' || $yy === '' ) {
		status_header( 400 );
		header( 'Content-Type: application/json; charset=utf-8' );
		echo wp_json_encode(
			array(
				'success' => false,
				'message' => 'Eksik odeme veya kart bilgisi.',
			)
		);
		exit;
	}

	$crm  = microvise_invoice_crm_base();
	$info = wp_remote_get(
		$crm . '/api/invoice-pay?action=session&session=' . rawurlencode( $session ) . '&token=' . rawurlencode( $token ),
		array( 'timeout' => 20 )
	);
	if ( is_wp_error( $info ) ) {
		status_header( 502 );
		header( 'Content-Type: application/json; charset=utf-8' );
		echo wp_json_encode(
			array(
				'success' => false,
				'message' => 'CRM oturum dogrulanamadi: ' . $info->get_error_message(),
			)
		);
		exit;
	}
	$body = json_decode( (string) wp_remote_retrieve_body( $info ), true );
	if ( empty( $body['ok'] ) ) {
		status_header( 400 );
		header( 'Content-Type: application/json; charset=utf-8' );
		echo wp_json_encode(
			array(
				'success' => false,
				'message' => $body['message'] ?? 'Odeme oturumu gecersiz.',
			)
		);
		exit;
	}
	if ( ! empty( $body['paid'] ) || ( isset( $body['status'] ) && $body['status'] === 'paid' ) ) {
		status_header( 400 );
		header( 'Content-Type: application/json; charset=utf-8' );
		echo wp_json_encode(
			array(
				'success' => false,
				'message' => 'Bu odeme zaten tamamlanmis.',
			)
		);
		exit;
	}

	$amount_num = number_format( (float) ( $body['amount'] ?? $amount ), 2, '.', '' );
	$currency   = (string) ( $body['currency'] ?? $currency );

	$settings = microvise_invoice_halkbank_gateway_settings();
	if ( $settings['merchant_id'] === '' || $settings['store_key'] === '' || $settings['gateway_url'] === '' ) {
		status_header( 500 );
		header( 'Content-Type: application/json; charset=utf-8' );
		echo wp_json_encode(
			array(
				'success' => false,
				'message' => 'WooCommerce Halkbank POS ayarlari eksik (merchant_id / store_key).',
			)
		);
		exit;
	}

	$oid = substr( preg_replace( '/[^a-zA-Z0-9]/', '', $token . (string) microtime( true ) ), 0, 20 );
	$callback = $crm . '/api/invoice-pay?action=callback&token=' . rawurlencode( $token );
	$rnd      = (string) microtime( true );

	// Birebir: WooCommerce microvise_halkbank checkout NestPay alanlari
	$params = array(
		'clientid'                          => $settings['merchant_id'],
		'storetype'                         => '3d',
		'hashAlgorithm'                     => 'ver3',
		'islemtipi'                         => 'Auth',
		'amount'                            => $amount_num,
		'currency'                          => microvise_invoice_nestpay_currency( $currency ),
		'oid'                               => $oid,
		'okUrl'                             => $callback,
		'failUrl'                           => $callback,
		'okurl'                             => $callback,
		'failurl'                           => $callback,
		'encoding'                          => 'UTF-8',
		'lang'                              => 'tr',
		'rnd'                               => $rnd,
		'pan'                               => $pan,
		'cv2'                               => $cv2,
		'Ecom_Payment_Card_ExpDate_Year'    => $yy,
		'Ecom_Payment_Card_ExpDate_Month'   => $mm,
	);
	$hash = microvise_invoice_nestpay_hash_ver3( $params, $settings['store_key'] );
	$params['HASH'] = $hash;
	$params['hash'] = $hash;

	header( 'Content-Type: text/html; charset=UTF-8' );
	echo '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Banka</title></head>';
	echo '<body onload="document.forms[0].submit()" style="font-family:Arial,sans-serif;background:#f5f5f7;margin:0;padding:24px;text-align:center">';
	echo '<p>Bankaya yonlendiriliyorsunuz…</p>';
	echo '<form method="post" action="' . esc_url( $settings['gateway_url'] ) . '">';
	foreach ( $params as $k => $v ) {
		echo '<input type="hidden" name="' . esc_attr( $k ) . '" value="' . esc_attr( (string) $v ) . '">';
	}
	echo '</form></body></html>';
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
		if ( is_array( $value ) ) {
			$payload[ $key ] = array_map( 'wp_unslash', $value );
		} else {
			$payload[ $key ] = wp_unslash( $value );
		}
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
