update public.e_invoice_settings
set api_base_url = case
      when environment = 'production'
        then 'https://efatura.maliye.gov.ct.tr/api'
      else 'https://test-efatura.maliye.gov.ct.tr/api'
    end,
    token_url = case
      when environment = 'production'
        then 'https://keycloak.maliye.gov.ct.tr/realms/production/protocol/openid-connect/token'
      else 'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token'
    end,
    updated_at = now();
