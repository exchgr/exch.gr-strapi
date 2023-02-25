module.exports = (_) => {
	return {
		dir: {
			input: "src/views",
			includes: "_includes",
			layouts: "_includes/layouts",
			data: "_data",
		},
		markdownTemplateEngine: "njk"
	}
}
