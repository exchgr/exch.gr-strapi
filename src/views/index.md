---
layout: "main.njk"
page_title: Articles
---

# {{ page_title }}

{% for article in articles %}
<article>

  ## {{ article.title }}
  by {{ article.author }} on {{ article.publishedAt }}

  {{ article.body }}

  last updated at {{ article.updatedAt }}
  {% for tag in article.tags.data %}
    [{{ tag.attributes.name }}](/tags/{{ tag.attributes.slug }})
  {% endfor %}
</article>
{% endfor %}
