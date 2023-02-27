module.exports = async () => {
	try {
		const {default: fetch} = await import('node-fetch')
		const data = await fetch("http://127.0.0.1:1337/graphql", {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
				"Accept": "application/json",
			},
			body: JSON.stringify({
				query: `{
					articles(sort: "publishedAt:DESC") {
						data {
							id
							attributes {
								title
								body
								author
								slug
								publishedAt
								updatedAt
								tags(sort: "name:ASC") {
									data {
										attributes {
											name
											slug
										}
									}
								}
							}
						}
					}
				}`
			})
		})

		const response = await data.json()

		response.errors?.map((error) => {
			console.error(error.message)
			throw new Error(error.message)
		})

		return response.data.articles.data.map(article => article.attributes)
	} catch (error) {
		console.error(error.message)
	}
}
