---
layout: page
icon: fas fa-magic
order: 5
title: Wiz Release Radar
---

Weekly digest covering Wiz platform updates, cloud security capabilities, and notable releases I'm tracking.
{% if site.wiz_release_radar.size > 0 %}
<a href="/feed/wiz_release_radar.xml" class="btn btn-sm btn-outline-secondary mt-1 mb-3">
  <i class="fas fa-rss" aria-hidden="true"></i> Subscribe via RSS
</a>
{% endif %}

{% assign digests = site.wiz_release_radar | sort: 'date' | reverse %}

{% if digests.size == 0 %}
*First digest coming soon.*
{% else %}
<ul style="list-style: none; padding: 0;">
{% for digest in digests %}
  <li style="margin-bottom: 1.5rem;">
    <h3 style="margin-bottom: 0.25rem;">
      <a href="{{ digest.url | relative_url }}">{{ digest.title }}</a>
    </h3>
    <time datetime="{{ digest.date | date_to_xmlschema }}" style="font-size: 0.875rem; opacity: 0.75;">
      {{ digest.date | date: "%Y-%m-%d" }}
    </time>
    {% if digest.excerpt %}
      <p style="margin-top: 0.5rem; margin-bottom: 0;">{{ digest.excerpt | strip_html | truncate: 220 }}</p>
    {% endif %}
  </li>
{% endfor %}
</ul>
{% endif %}
