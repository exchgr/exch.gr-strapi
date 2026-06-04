module.exports = ({ env }) => ({
	"media-prefix": {
		enabled: true
	},
	graphql: {
		config: {
			v4CompatibilityMode: false,
		},
		amountLimit: 100000,
	}
});
