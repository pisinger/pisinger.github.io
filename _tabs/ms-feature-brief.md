---
layout: page
icon: fas fa-list-check
order: 7
title: MS FEATURE BRIEF
---

Monthly Microsoft feature briefs.

{% assign briefs = site.ms_feature_brief | reverse %}

{% for brief in briefs %}
- [{{ brief.title }}]({{ brief.url | relative_url }})
{% endfor %}
