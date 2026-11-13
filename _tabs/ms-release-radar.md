---
layout: page
icon: fas fa-satellite-dish
order: 4
title: MS Release Radar
---

The interactive Microsoft Security Release Radar is embedded below. It covers the full history with filtering and drill-down; the latest monthly observation notes are listed underneath.
<p>
  <a class="btn btn-primary" href="https://pisinger.tngx-voice.com/ms-release-radar" target="_blank" rel="noopener noreferrer">
    Open MS Release Radar in a new tab <i class="fas fa-arrow-up-right-from-square" aria-hidden="true"></i>
  </a>
</p>
{% if site.ms_release_radar.size > 0 %}
<a href="/feed/ms_release_radar.xml" class="btn btn-sm btn-outline-secondary mt-1 mb-3">
  <i class="fas fa-rss" aria-hidden="true"></i> Subscribe via RSS
</a>
{% endif %}

<iframe
  src="https://pisinger.tngx-voice.com/ms-release-radar"
  title="Microsoft Security Release Radar"
  loading="eager"
  style="display:block; width:100%; height:82vh; min-height:680px; border:1px solid rgba(128,128,128,.3); border-radius:8px;"
>
  Your browser does not support embedded pages. Use the link above to open MS Release Radar.
</iframe>

{% assign MAX_DIGESTS = 6 %}
{% assign digests = site.ms_release_radar | sort: 'date' | reverse %}

{% if digests.size == 0 %}
*First digest coming soon.*
{% else %}
<ul style="list-style: none; padding: 0;">
{% for digest in digests limit: MAX_DIGESTS %}
  <li style="margin-bottom: 1.5rem;">
    <h3 style="margin-bottom: 0.25rem;">
      <a href="{{ digest.url | relative_url }}">{{ digest.title }}</a>
    </h3>
    <time datetime="{{ digest.date | date_to_xmlschema }}" style="font-size: 0.875rem; opacity: 0.75;">
      {{ digest.date | date: "%Y-%m-%d" }}
    </time>
  </li>
{% endfor %}
</ul>
{% endif %}
