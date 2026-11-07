// SPDX-License-Identifier: AGPL-3.0-or-later

package settings

var Twins = map[string]string{
	"AFENDOR_APP_FAVICON_DARK_URL":                 "app_public.branding.favicon_dark_url",
	"AFENDOR_APP_FAVICON_URL":                      "app_public.branding.favicon_url",
	"AFENDOR_APP_ICON_URL":                         "app_public.branding.icon_url",
	"AFENDOR_APP_LOGO_URL":                         "app_public.branding.logo_url",
	"AFENDOR_APP_PRODUCT_NAME":                     "app_public.branding.product_name",
	"AFENDOR_APP_SIGN_IN_BACKDROP_URL":             "app_public.branding.sign_in_backdrop_url",
	"AFENDOR_APP_STATUS_PAGE_INCIDENT_HISTORY_URL": "app_public.branding.status_page_incident_history_url",
	"AFENDOR_APP_STATUS_PAGE_URL":                  "app_public.branding.status_page_url",
	"AFENDOR_APP_SYMBOL_URL":                       "app_public.branding.symbol_url",
	"AFENDOR_APP_THEME_COLOR":                      "app_public.branding.theme_color",
	"AFENDOR_APP_WORDMARK_URL":                     "app_public.branding.wordmark_url",
	"AFENDOR_AUTH_BLUESKY_CLIENT_NAME":             "integrations.bluesky.client_name",
	"AFENDOR_AUTH_BLUESKY_CLIENT_URI":              "integrations.bluesky.client_uri",
	"AFENDOR_AUTH_BLUESKY_ENABLED":                 "integrations.bluesky.enabled",
	"AFENDOR_AUTH_BLUESKY_KEYS":                    "integrations.bluesky.keys",
	"AFENDOR_AUTH_BLUESKY_LOGO_URI":                "integrations.bluesky.logo_uri",
	"AFENDOR_AUTH_BLUESKY_POLICY_URI":              "integrations.bluesky.policy_uri",
	"AFENDOR_AUTH_BLUESKY_TOS_URI":                 "integrations.bluesky.tos_uri",
	"AFENDOR_EMAIL_DELIVERY":                       "integrations.email.delivery",
	"AFENDOR_EMAIL_ENABLED":                        "integrations.email.delivery",
	"AFENDOR_EMAIL_FROM_EMAIL":                     "integrations.email.from_email",
	"AFENDOR_EMAIL_FROM_NAME":                      "integrations.email.from_name",
	"AFENDOR_EMAIL_PROVIDER":                       "integrations.email.delivery",
	"AFENDOR_EMAIL_SMTP_HOST":                      "integrations.email.smtp.host",
	"AFENDOR_EMAIL_SMTP_PASSWORD":                  "integrations.email.smtp.password",
	"AFENDOR_EMAIL_SMTP_PORT":                      "integrations.email.smtp.port",
	"AFENDOR_EMAIL_SMTP_SECURE":                    "integrations.email.smtp.tls_mode",
	"AFENDOR_EMAIL_SMTP_TLS_MODE":                  "integrations.email.smtp.tls_mode",
	"AFENDOR_EMAIL_SMTP_USERNAME":                  "integrations.email.smtp.username",
	"AFENDOR_KLIPY_API_KEY":                        "integrations.gif.klipy_api_key",
	"AFENDOR_STRIPE_ENABLED":                       "billing.enabled",
	"AFENDOR_STRIPE_LEGACY_PRICES":                 "billing.legacy_prices",
	"AFENDOR_STRIPE_PRICES":                        "billing.prices",
	"AFENDOR_STRIPE_SECRET_KEY":                    "billing.stripe_secret_key",
	"AFENDOR_STRIPE_WEBHOOK_SECRET":                "billing.stripe_webhook_secret",
	"AFENDOR_YOUTUBE_API_KEY":                      "integrations.youtube.api_key",
}

var twinVars = map[string]string{
	"integrations.email.delivery":      "AFENDOR_EMAIL_DELIVERY",
	"integrations.email.smtp.tls_mode": "AFENDOR_EMAIL_SMTP_TLS_MODE",
}

func TwinVar(adminKey string) (string, bool) {
	if v, ok := twinVars[adminKey]; ok {
		return v, true
	}
	for v, k := range Twins {
		if k == adminKey {
			return v, true
		}
	}
	return "", false
}
