---
title: Apps
icon: fas fa-rocket
order: 7
---

> Apps I build and host. Feel free to explore.
{: .prompt-tip }

<style>
  .app-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 1rem;
    margin: 1.5rem 0 2rem;
  }
  .app-tile {
    display: flex;
    gap: .9rem;
    padding: 1rem 1.1rem;
    border: 1px solid var(--card-border-color, rgba(128, 128, 128, .25));
    border-radius: 12px;
    background: var(--card-bg, transparent);
    text-decoration: none !important;
    color: inherit;
    transition: transform .15s ease, box-shadow .15s ease, border-color .15s ease;
  }
  .app-tile:hover,
  .app-tile:focus-visible {
    color: inherit;
    transform: translateY(-2px);
    border-color: #0056b2;
    box-shadow: 0 6px 18px rgba(0, 0, 0, .10);
  }
  .app-tile .app-icon {
    flex: 0 0 auto;
    width: 42px;
    height: 42px;
    display: grid;
    place-items: center;
    border-radius: 10px;
    background: rgba(0, 86, 178, .10);
    color: #0056b2;
    font-size: 1.1rem;
  }
  .app-tile .app-text {
    min-width: 0;
  }
  .app-tile .app-title {
    display: flex;
    align-items: center;
    gap: .4rem;
    font-weight: 600;
    line-height: 1.3;
    margin-bottom: .2rem;
  }
  .app-tile .app-title .arrow {
    font-size: .8em;
    color: #0056b2;
    opacity: 0;
    transform: translateX(-4px);
    transition: opacity .15s ease, transform .15s ease;
  }
  .app-tile:hover .app-title .arrow,
  .app-tile:focus-visible .app-title .arrow {
    opacity: 1;
    transform: translateX(0);
  }
  .app-tile .app-desc {
    font-size: .85rem;
    line-height: 1.4;
    color: var(--text-muted-color, #6c757d);
  }
  .app-tile--featured {
    grid-column: 1 / -1;
    background: rgba(0, 86, 178, .07);
    border-color: rgba(0, 86, 178, .35);
  }
</style>

<div class="app-grid">
  <a class="app-tile app-tile--featured" href="https://pisinger.tngx-voice.com/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-grip" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">My Apps <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Landing page for all my hosted apps.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/ms-release-radar/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-satellite-dish" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">Microsoft Security Release Radar <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Curated product updates across the Microsoft security and cloud stack.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/wiz-release-radar/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-wand-magic-sparkles" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">Wiz Release Radar <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Curated product announcements and release updates from public Wiz sources.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/kev-radar/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-triangle-exclamation" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">CISA KEV Radar <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Known Exploited Vulnerabilities catalog with traffic-light indicators and Microsoft/Windows/Azure filters.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/k8s-cve-radar/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-dharmachakra" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">K8s CVE Radar <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Kubernetes official CVE feed — vulnerabilities published by the K8s Security Response Committee.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/defender-cloud-alerts/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-bell" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">Defender Cloud Alerts <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Searchable reference of Microsoft Defender for Cloud security alerts with severity indicators and MITRE tactics.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/defender-cloud-mitre/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-table-cells" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">Defender Cloud MITRE Coverage <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">MITRE ATT&amp;CK coverage matrix showing which Defender plans cover which tactics.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/defender-containers-overview/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-cubes" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">Defender for Containers Overview <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Feature support, access patterns, registries, images, network requirements, and permissions across AKS, EKS, GKE, and Arc.</span>
    </span>
  </a>
  <a class="app-tile" href="https://pisinger.tngx-voice.com/ms-tech-news/" target="_blank" rel="noopener">
    <span class="app-icon"><i class="fas fa-newspaper" aria-hidden="true"></i></span>
    <span class="app-text">
      <span class="app-title">MS Tech News <i class="fas fa-arrow-right arrow" aria-hidden="true"></i></span>
      <span class="app-desc">Weekly curated digest of Microsoft Tech Community blog posts, security blogs, and engineering updates.</span>
    </span>
  </a>
</div>
