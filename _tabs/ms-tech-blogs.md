---
layout: page
icon: fas fa-newspaper
order: 5
title: MS Tech Blogs
---

Curated roundups of posts published on [techcommunity.microsoft.com](https://techcommunity.microsoft.com) for the products I track.
{% if site.ms_tech_blogs.size > 0 %}
<a href="/feed/ms_tech_blogs.xml" class="btn btn-sm btn-outline-secondary mt-1 mb-3">
  <i class="fas fa-rss" aria-hidden="true"></i> Subscribe via RSS
</a>
{% endif %}

{% assign entries = site.ms_tech_blogs | sort: 'date' | reverse %}

{% if entries.size == 0 %}
*First roundup coming soon.*
{% else %}
<ul style="list-style: none; padding: 0;">
{% for entry in entries %}
  <li style="margin-bottom: 1.5rem;">
    <h3 style="margin-bottom: 0.25rem;">
      <a href="{{ entry.url | relative_url }}">{{ entry.title }}</a>
    </h3>
    <time datetime="{{ entry.date | date_to_xmlschema }}" style="font-size: 0.875rem; opacity: 0.75;">
      {{ entry.date | date: "%Y-%m-%d" }}
    </time>
    {% if entry.excerpt %}
      <p style="margin-top: 0.5rem; margin-bottom: 0;">{{ entry.excerpt | strip_html | truncate: 220 }}</p>
    {% endif %}
  </li>
{% endfor %}
</ul>
{% endif %}
