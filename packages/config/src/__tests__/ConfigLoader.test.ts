// SPDX-License-Identifier: AGPL-3.0-or-later

import {generateKeyPairSync} from 'node:crypto';
import {loadConfig, resetConfig} from '@fluxer/config/src/ConfigLoader';
import {afterEach, beforeEach, describe, expect, test, vi} from 'vitest';

const MINIMAL_ENV: Record<string, string> = {
	AFENDOR_ENV: 'test',
	AFENDOR_BASE_DOMAIN: 'localhost',
	AFENDOR_PUBLIC_SCHEME: 'http',
	AFENDOR_PUBLIC_PORT: '8088',
	AFENDOR_CASSANDRA_HOSTS: '127.0.0.1',
	AFENDOR_CASSANDRA_PORT: '9042',
	AFENDOR_CASSANDRA_KEYSPACE: 'fluxer_test',
	AFENDOR_CASSANDRA_LOCAL_DC: 'datacenter1',
	AFENDOR_CASSANDRA_USERNAME: 'test-user',
	AFENDOR_CASSANDRA_PASSWORD: 'test-password',
	AFENDOR_S3_ENDPOINT: 'http://127.0.0.1:3900',
	AFENDOR_S3_ACCESS_KEY_ID: 'test-key',
	AFENDOR_S3_SECRET_ACCESS_KEY: 'test-secret',
	AFENDOR_MEDIA_PROXY_SECRET_KEY: 'test-media-secret',
	AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
	AFENDOR_ADMIN_SECRET_KEY_BASE: 'test-admin-secret',
	AFENDOR_ADMIN_OAUTH_CLIENT_SECRET: 'test-admin-oauth-secret',
	AFENDOR_GATEWAY_RPC_AUTH_TOKEN: 'test-gateway-token',
	AFENDOR_SUDO_MODE_SECRET: 'test-sudo-secret',
	AFENDOR_CONNECTION_INITIATION_SECRET: 'test-connection-secret',
	AFENDOR_PROFILE_PSEUDONYM_SECRET: 'test-profile-pseudonym-secret',
	AFENDOR_VAPID_PUBLIC_KEY: 'BB76bTFIuoqmxJtTfZX0yGTn1f_qu9H03B_nkj8OyExJFkN7Y-HBZZzShnHZoEhXKc5ZRy3jFu7OkBbnaQG-4aw',
	AFENDOR_VAPID_PRIVATE_KEY: 'Xgi-3P8J-I3Q6U1HlCcXMuc_tKLGAM9nIfznX3Hz68o',
};

function generateVapidPair(): {publicKey: string; privateKey: string} {
	const {privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
	const jwk = privateKey.export({format: 'jwk'});
	const x = Buffer.from(jwk.x ?? '', 'base64url');
	const y = Buffer.from(jwk.y ?? '', 'base64url');
	const d = Buffer.from(jwk.d ?? '', 'base64url');
	return {
		publicKey: Buffer.concat([Buffer.from([0x04]), x, y]).toString('base64url'),
		privateKey: d.toString('base64url'),
	};
}

function stubMinimalEnv(overrides: Record<string, string> = {}): void {
	for (const [key, value] of Object.entries({...MINIMAL_ENV, ...overrides})) {
		vi.stubEnv(key, value);
	}
}

function clearFluxerEnv(): void {
	for (const key of Object.keys(process.env)) {
		if (key.startsWith('AFENDOR_')) {
			vi.stubEnv(key, undefined);
		}
	}
}

describe('ConfigLoader', () => {
	beforeEach(() => {
		resetConfig();
		clearFluxerEnv();
	});

	afterEach(() => {
		resetConfig();
		vi.unstubAllEnvs();
	});

	test('a self-hosted instance without AFENDOR_ENV runs in production', async () => {
		stubMinimalEnv({
			AFENDOR_SELF_HOSTED: 'true',
			AFENDOR_PROFILE_PSEUDONYM_SECRET: 'self-hosted-secret',
			AFENDOR_POSTGRES_HOST: 'postgres',
			AFENDOR_POSTGRES_DATABASE: 'fluxer',
			AFENDOR_POSTGRES_PASSWORD: 'self-hosted-password',
		});
		vi.stubEnv('AFENDOR_ENV', undefined);
		expect((await loadConfig()).env).toBe('production');
	});

	test('reads the profile pseudonym secret and requires it in production', async () => {
		stubMinimalEnv();
		expect((await loadConfig()).auth.profile_pseudonym_secret).toBe('test-profile-pseudonym-secret');
		resetConfig();
		stubMinimalEnv({AFENDOR_PROFILE_PSEUDONYM_SECRET: ''});
		expect((await loadConfig()).auth.profile_pseudonym_secret).toBe('fluxer-dev-profile-pseudonym-secret');
		resetConfig();
		stubMinimalEnv({
			AFENDOR_ENV: 'production',
			AFENDOR_POSTGRES_HOST: 'postgres.internal',
			AFENDOR_POSTGRES_DATABASE: 'fluxer_prod',
			AFENDOR_POSTGRES_USERNAME: 'afendor_app',
			AFENDOR_POSTGRES_PASSWORD: 'prod-postgres-secret',
			AFENDOR_POSTGRES_SSL: 'true',
			AFENDOR_PROFILE_PSEUDONYM_SECRET: '',
		});
		await expect(loadConfig()).rejects.toThrow('AFENDOR_PROFILE_PSEUDONYM_SECRET is required');
	});

	test('rejects unsafe production Postgres defaults', async () => {
		stubMinimalEnv({AFENDOR_ENV: 'production'});
		await expect(loadConfig()).rejects.toThrow('AFENDOR_POSTGRES_HOST');
	});

	test('allows self-hosted production Postgres without TLS', async () => {
		stubMinimalEnv({
			AFENDOR_ENV: 'production',
			AFENDOR_SELF_HOSTED: 'true',
			AFENDOR_POSTGRES_HOST: 'postgres',
			AFENDOR_POSTGRES_DATABASE: 'fluxer',
			AFENDOR_POSTGRES_USERNAME: 'fluxer',
			AFENDOR_POSTGRES_PASSWORD: 'self-hosted-postgres-secret',
			AFENDOR_POSTGRES_SSL: 'false',
		});

		const config = await loadConfig();

		expect(config.instance.self_hosted).toBe(true);
		expect(config.database.postgres.ssl).toBe(false);
	});

	test('still requires TLS for non-self-hosted production Postgres', async () => {
		stubMinimalEnv({
			AFENDOR_ENV: 'production',
			AFENDOR_POSTGRES_HOST: 'postgres.internal',
			AFENDOR_POSTGRES_DATABASE: 'fluxer_prod',
			AFENDOR_POSTGRES_USERNAME: 'afendor_app',
			AFENDOR_POSTGRES_PASSWORD: 'prod-postgres-secret',
			AFENDOR_POSTGRES_SSL: 'false',
		});

		await expect(loadConfig()).rejects.toThrow('AFENDOR_POSTGRES_SSL must be true');
	});

	test('rejects an App Store product mapped to an unknown slot', async () => {
		stubMinimalEnv({AFENDOR_APP_STORE_PRODUCTS: '{"com.fluxer.visionary":"visionary"}'});
		await expect(loadConfig()).rejects.toThrow(
			'Invalid AFENDOR_APP_STORE_PRODUCTS slot for com.fluxer.visionary: visionary',
		);
	});

	test('rejects a Google Play product mapped to an unknown slot', async () => {
		stubMinimalEnv({AFENDOR_GOOGLE_PLAY_PRODUCTS: '{"plutonium:weekly":"weekly"}'});
		await expect(loadConfig()).rejects.toThrow('Invalid AFENDOR_GOOGLE_PLAY_PRODUCTS slot for plutonium:weekly: weekly');
	});

	test('rejects a Google Play product key that does not fit its slot kind', async () => {
		stubMinimalEnv({AFENDOR_GOOGLE_PLAY_PRODUCTS: '{"plutonium":"monthly"}'});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_GOOGLE_PLAY_PRODUCTS key plutonium does not match its monthly slot',
		);
		resetConfig();
		stubMinimalEnv({AFENDOR_GOOGLE_PLAY_PRODUCTS: '{"gift:one":"gift_1_month"}'});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_GOOGLE_PLAY_PRODUCTS key gift:one does not match its gift_1_month slot',
		);
	});

	test('rejects a cache purge endpoint that contains credentials', async () => {
		stubMinimalEnv({
			AFENDOR_CACHE_PURGE_ADAPTER: 'http',
			AFENDOR_CACHE_PURGE_HTTP_ENDPOINT: 'https://purger:secret@purge.internal/purge',
		});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_CACHE_PURGE_HTTP_ENDPOINT must be an absolute http or https URL without credentials',
		);
	});

	test('rejects a cache purge token with spaces or control characters without echoing it', async () => {
		for (const token of ['secret\nvalue', 'secret\rvalue', 'secret value', 'secret-value\n']) {
			stubMinimalEnv({
				AFENDOR_CACHE_PURGE_ADAPTER: 'http',
				AFENDOR_CACHE_PURGE_HTTP_ENDPOINT: 'https://purge.internal/purge',
				AFENDOR_CACHE_PURGE_HTTP_TOKEN: token,
			});
			await expect(loadConfig()).rejects.toThrow(
				/^AFENDOR_CACHE_PURGE_HTTP_TOKEN must contain only visible ASCII characters$/,
			);
		}
	});

	test('rejects a controller cache purge endpoint that is not https', async () => {
		stubMinimalEnv({
			AFENDOR_CACHE_PURGE_ADAPTER: 'controller',
			AFENDOR_CACHE_PURGE_CONTROLLER_ENDPOINT: 'http://controller.test/v1/orgs/a/sites/b/purge',
			AFENDOR_CACHE_PURGE_CONTROLLER_TOKEN: 'pak_test',
		});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_CACHE_PURGE_CONTROLLER_ENDPOINT must be an absolute https URL without credentials',
		);
	});

	test('rejects a missing upload relay secret', async () => {
		stubMinimalEnv();
		vi.stubEnv('AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64', '');

		await expect(loadConfig()).rejects.toThrow('AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64 is required');
	});

	test('rejects a non-base64 upload relay secret', async () => {
		stubMinimalEnv({AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64: 'not base64!'});
		await expect(loadConfig()).rejects.toThrow('AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64 must be base64');
	});

	test('rejects an upload relay secret shorter than 32 bytes', async () => {
		stubMinimalEnv({AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64: Buffer.alloc(16, 7).toString('base64')});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64 must decode to at least 32 bytes',
		);
	});

	test('rejects a VAPID public key that is not a 65-byte uncompressed point', async () => {
		const {privateKey} = generateVapidPair();
		stubMinimalEnv({
			AFENDOR_VAPID_PUBLIC_KEY: Buffer.alloc(64, 4).toString('base64url'),
			AFENDOR_VAPID_PRIVATE_KEY: privateKey,
		});
		await expect(loadConfig()).rejects.toThrow(
			/^AFENDOR_VAPID_PUBLIC_KEY must be the base64url 65-byte uncompressed P-256 point\. Run rexctl doctor --fix/u,
		);
	});

	test('rejects a VAPID private key that is not a 32-byte scalar', async () => {
		const {publicKey} = generateVapidPair();
		stubMinimalEnv({
			AFENDOR_VAPID_PUBLIC_KEY: publicKey,
			AFENDOR_VAPID_PRIVATE_KEY: Buffer.alloc(31, 9).toString('base64url'),
		});
		await expect(loadConfig()).rejects.toThrow(
			/^AFENDOR_VAPID_PRIVATE_KEY must be the base64url 32-byte P-256 scalar\. Run rexctl doctor --fix/u,
		);
	});

	test('rejects a well formed VAPID scalar that does not derive the public point', async () => {
		const {publicKey} = generateVapidPair();
		const other = generateVapidPair();
		stubMinimalEnv({
			AFENDOR_VAPID_PUBLIC_KEY: publicKey,
			AFENDOR_VAPID_PRIVATE_KEY: other.privateKey,
		});
		await expect(loadConfig()).rejects.toThrow('AFENDOR_VAPID_PRIVATE_KEY does not match AFENDOR_VAPID_PUBLIC_KEY');
	});

	test('accepts a generated VAPID pair', async () => {
		const pair = generateVapidPair();
		stubMinimalEnv({
			AFENDOR_VAPID_PUBLIC_KEY: pair.publicKey,
			AFENDOR_VAPID_PRIVATE_KEY: pair.privateKey,
		});

		const config = await loadConfig();

		expect(config.auth.vapid.public_key).toBe(pair.publicKey);
		expect(config.auth.vapid.private_key).toBe(pair.privateKey);
	});

	test('inserts the public port into every other public url the config contains', async () => {
		stubMinimalEnv({
			AFENDOR_S3_PUBLIC_ENDPOINT: 'http://localhost/s3',
			AFENDOR_EMAIL_APP_BASE_URL: 'http://localhost',
			AFENDOR_AUTH_BLUESKY_CLIENT_URI: 'http://localhost',
			AFENDOR_AUTH_BLUESKY_TOS_URI: 'http://localhost/terms',
			AFENDOR_APP_ICON_URL: 'http://localhost/icon.png',
			AFENDOR_LIVEKIT_INTERNAL_URL: 'http://livekit:7880',
		});

		const config = await loadConfig();

		expect(config.s3?.presigned_url_base).toBe('http://localhost:8088/s3');
		expect(config.integrations.email.app_base_url).toBe('http://localhost:8088');
		expect(config.auth.bluesky.client_uri).toBe('http://localhost:8088');
		expect(config.auth.bluesky.tos_uri).toBe('http://localhost:8088/terms');
		expect(config.instance.branding.icon_url).toBe('http://localhost:8088/icon.png');
		expect(config.integrations.voice.internal_url).toBe('http://livekit:7880');
	});
});

describe('AFENDOR_PUBLIC_ORIGIN', () => {
	beforeEach(() => {
		resetConfig();
		clearFluxerEnv();
	});

	afterEach(() => {
		resetConfig();
		vi.unstubAllEnvs();
	});

	test('a ported origin ports every derived endpoint and every compose override', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'https',
			AFENDOR_PUBLIC_PORT: '',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com:29080',
			AFENDOR_MARKETING_ENDPOINT: 'https://chat.example.com:29080',
			AFENDOR_MEDIA_ENDPOINT: 'https://chat.example.com:29080/media',
			AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_ENDPOINT: 'https://chat.example.com:29080/media',
			AFENDOR_LIVEKIT_URL: 'https://chat.example.com:29080/livekit',
			AFENDOR_PASSKEY_ADDITIONAL_ALLOWED_ORIGINS: 'https://chat.example.com:29080',
		});

		const config = await loadConfig();

		expect(config.domain.public_port).toBe(29080);
		expect(config.domain.public_origin).toBe('https://chat.example.com:29080');
		expect(config.endpoints.api_client).toBe('https://chat.example.com:29080/api');
		expect(config.endpoints.app).toBe('https://chat.example.com:29080');
		expect(config.endpoints.gateway).toBe('wss://chat.example.com:29080/gateway');
		expect(config.endpoints.admin).toBe('https://chat.example.com:29080/admin');
		expect(config.endpoints.marketing).toBe('https://chat.example.com:29080');
		expect(config.endpoints.media).toBe('https://chat.example.com:29080/media');
		expect(config.services.media_proxy.upload_relay.endpoint).toBe('https://chat.example.com:29080/media');
		expect(config.integrations.voice.url).toBe('https://chat.example.com:29080/livekit');
		expect(config.auth.passkeys.additional_allowed_origins).toEqual([
			'https://chat.example.com:29080',
			'android:apk-key-hash:keSY4bimyLqZQV7bKXgpa2xYuqXi0qZJzsYtp6gpx7w',
			'android:apk-key-hash:Ld4qnT0TfBeHMT3Yu2H0WTwqlxgFs-32uDmwqtLndsk',
		]);
	});

	test('the origin port wins over a AFENDOR_PUBLIC_PORT that disagrees', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'https',
			AFENDOR_PUBLIC_PORT: '443',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com:29080',
		});

		const config = await loadConfig();

		expect(config.domain.public_port).toBe(29080);
		expect(config.endpoints.app).toBe('https://chat.example.com:29080');
		expect(config.endpoints.api_client).toBe('https://chat.example.com:29080/api');
		expect(config.endpoints.gateway).toBe('wss://chat.example.com:29080/gateway');
		expect(config.endpoints.admin).toBe('https://chat.example.com:29080/admin');
	});

	test('accepts an origin whose port matches AFENDOR_PUBLIC_PORT', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'https',
			AFENDOR_PUBLIC_PORT: '29080',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com:29080',
		});

		expect((await loadConfig()).endpoints.gateway).toBe('wss://chat.example.com:29080/gateway');
	});

	test('normalizes an origin written with an explicit default port', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'https',
			AFENDOR_PUBLIC_PORT: '443',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com:443',
			AFENDOR_ADMIN_ENDPOINT: 'https://chat.example.com/admin',
		});

		const config = await loadConfig();

		expect(config.domain.public_port).toBe(443);
		expect(config.domain.public_origin).toBe('https://chat.example.com');
		expect(config.endpoints.admin).toBe('https://chat.example.com/admin');
		expect(config.endpoints.app).toBe('https://chat.example.com');
		expect(config.endpoints.gateway).toBe('wss://chat.example.com/gateway');
	});

	test('takes the scheme and the domain from the origin when neither is set', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: '',
			AFENDOR_PUBLIC_SCHEME: '',
			AFENDOR_PUBLIC_PORT: '',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com:29080',
		});

		const config = await loadConfig();

		expect(config.domain.base_domain).toBe('chat.example.com');
		expect(config.domain.public_scheme).toBe('https');
		expect(config.domain.public_port).toBe(29080);
	});

	test('the origin scheme wins over a AFENDOR_PUBLIC_SCHEME that disagrees', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'http',
			AFENDOR_PUBLIC_PORT: '',
			AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com',
		});

		const config = await loadConfig();

		expect(config.domain.public_scheme).toBe('https');
		expect(config.endpoints.app).toBe('https://chat.example.com');
		expect(config.endpoints.gateway).toBe('wss://chat.example.com/gateway');
	});

	test('the origin host wins over a AFENDOR_BASE_DOMAIN that disagrees', async () => {
		stubMinimalEnv({
			AFENDOR_BASE_DOMAIN: 'chat.example.com',
			AFENDOR_PUBLIC_SCHEME: 'https',
			AFENDOR_PUBLIC_PORT: '',
			AFENDOR_PUBLIC_ORIGIN: 'https://other.example.com',
		});

		const config = await loadConfig();

		expect(config.domain.base_domain).toBe('other.example.com');
		expect(config.endpoints.app).toBe('https://other.example.com');
	});

	test('refuses to boot on an origin that is not a bare origin', async () => {
		stubMinimalEnv({AFENDOR_PUBLIC_ORIGIN: 'https://chat.example.com/app'});
		await expect(loadConfig()).rejects.toThrow(
			'AFENDOR_PUBLIC_ORIGIN must be a scheme, host and optional port such as https://chat.example.com:8443',
		);
	});

	test('leaves the derived origin canonical when nothing is set', async () => {
		stubMinimalEnv();
		expect((await loadConfig()).domain.public_origin).toBe('http://localhost:8088');
	});
});
