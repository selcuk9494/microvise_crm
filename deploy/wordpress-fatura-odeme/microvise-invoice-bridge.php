<?php
/**
 * Plugin Name: Microvise Invoice Payment Bridge
 * Description: Halkbank NestPay callback=invoice_hosted → CRM fatura ödeme tamamlar. Tema bridge "Gecersiz callback" vermesin diye onu override eder.
 * Version: 1.0.0
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

function microvise_invoice_halkbank_bridge() {
	$callback = isset( $_GET['callback'] ) ? sanitize_key( wp_unslash( $_GET['callback'] ) ) : 'license';
	if ( ! in_array( $callback, array( 'license', 'license_hosted', 'halkbank', 'invoice_hosted' ), true ) ) {
		status_header( 400 );
		echo 'Gecersiz callback';
		exit;
	}

	if ( 'invoice_hosted' === $callback ) {
		$token    = isset( $_GET['token'] ) ? sanitize_text_field( wp_unslash( $_GET['token'] ) ) : '';
		$crm_base = apply_filters( 'microvise_invoice_payment_bridge_base_url', 'https://crm.microvise.net' );
		$target_url = untrailingslashit( (string) $crm_base ) . '/api/invoice-pay?action=callback&token=' . rawurlencode( $token );
	} else {
		$base = function_exists( 'microvise_payment_bridge_base_url' )
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
