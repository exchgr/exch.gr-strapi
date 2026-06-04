module.exports = ({ env }) => ({
	upload: {
		config: {
			provider: 'strapi-provider-upload-cloudflare',
			providerOptions: {
				accountId: env('CLOUDFLARE_ACCOUNT_ID'),
				apiKey: env('CLOUDFLARE_API_TOKEN'),
			},
		},
	},
	graphql: {
		config: {
			v4CompatibilityMode: false,
		},
		amountLimit: 100000,
	}
});
