module.exports = ({ env }) => ({
	"media-prefix": {
		enabled: true
	},
	graphql: {
		config: {
			v4CompatibilityMode: true,
		},
		amountLimit: 100000,
	}
});
