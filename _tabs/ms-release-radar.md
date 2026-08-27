---
layout: page
icon: fas fa-satellite-dish
order: 4
title: MS Release Radar
---

A curated list of Microsoft Defender and Azure service release notes I track — refreshed weekly, with monthly lookbacks. The last 6 months are listed here — the full history, plus filtering and drill-down, is served via the dedicated [ms-release-radar-app](https://pisinger.tngx-voice.com/ms-release-radar/).
{% if site.ms_release_radar.size > 0 %}
<a href="/feed/ms_release_radar.xml" class="btn btn-sm btn-outline-secondary mt-1 mb-3">
  <i class="fas fa-rss" aria-hidden="true"></i> Subscribe via RSS
</a>
{% endif %}

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
