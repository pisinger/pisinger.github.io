---
icon: fas fa-envelope
order: 9
---

<style>
  .contact-tip {
    margin-bottom: 1.5rem;
    padding: .7rem 1rem;
    border-left: 4px solid #0969da;
    border-radius: .45rem;
    color: #29476d;
    background: #e8f1ff;
  }
  .contact-hero {
    padding: clamp(1.75rem, 5vw, 4rem);
    border: 1px solid #cfe0f6;
    border-radius: 1.25rem;
    background: var(--card-bg);
    box-shadow: 0 1rem 2.8rem rgba(32, 58, 95, .1);
  }
  .contact-hero h2 {
    max-width: 45rem;
    margin-top: .75rem;
    font-size: clamp(2rem, 5vw, 3.8rem);
    letter-spacing: -.025em;
  }
  .contact-hero > p { max-width: 41rem; font-size: 1.1rem; }
  .contact-availability { color: var(--text-muted-color); font-size: .92rem; }
  .contact-availability::before {
    content: ""; display: inline-block; width: .55rem; height: .55rem;
    margin-right: .55rem; border-radius: 50%; background: #22a06b;
    box-shadow: 0 0 0 4px #dff5e9;
  }
  .contact-actions { display: flex; flex-wrap: wrap; gap: .75rem; margin-top: 1.5rem; }
  .contact-actions .btn { transition: transform .15s ease, box-shadow .15s ease; }
  .contact-actions .btn:hover, .contact-actions .btn:focus-visible {
    transform: translateY(-1px); box-shadow: 0 .4rem 1rem rgba(9, 105, 218, .2);
  }
  .contact-section { padding-top: 3.5rem; }
  .contact-card { height: 100%; transition: border-color .15s ease, transform .15s ease; }
  .contact-card:hover { border-color: #a9c8ef; transform: translateY(-2px); }
  .contact-icon {
    display: grid; place-items: center; width: 2.5rem; height: 2.5rem;
    margin-bottom: 1.1rem; border-radius: .7rem; color: #0756b4;
    background: #e8f1ff; font-size: 1.2rem;
  }
  .contact-tag { color: #0756b4; font-size: .82rem; font-weight: 700; }
  .contact-process { counter-reset: contact-step; }
  .contact-step { position: relative; padding-left: 3.2rem; counter-increment: contact-step; }
  .contact-step::before {
    content: counter(contact-step); position: absolute; left: 0; top: 0;
    display: grid; place-items: center; width: 2.1rem; height: 2.1rem;
    border-radius: 50%; color: #fff; background: #0969da; font-weight: 800;
  }
  .contact-step p { color: var(--text-muted-color); font-size: .94rem; }
  .contact-cta {
    display: flex; align-items: center; justify-content: space-between; gap: 1.5rem;
    margin-top: 3.5rem; padding: 1.75rem 2rem; border-radius: 1rem;
    color: #fff; background: #182b49;
  }
  .contact-cta h3 { margin-bottom: .35rem; }
  .contact-cta p { margin-bottom: 0; color: #cbd7e8; }
  @media (max-width: 576px) {
    .contact-cta { align-items: flex-start; flex-direction: column; padding: 1.5rem; }
  }
</style>

<section class="contact-hero" aria-labelledby="contact-title">
  <div class="contact-tip">Practical cloud architecture, security, and automation for Microsoft-focused small businesses.</div>
  <p class="text-uppercase small fw-bold text-primary mb-2">Cloud · Security · Automation</p>
  <h2 id="contact-title">Make confident cloud and security decisions.</h2>
  <p class="text-muted">I help Microsoft-focused businesses turn complex Azure and security challenges into practical, secure next steps — from an architecture review to a working proof of concept.</p>
  <p class="contact-availability">Limited availability for selected projects and collaborations</p>
  <div class="contact-actions">
    <a href="mailto:kontakt.psingert@outlook.de" class="btn btn-primary"><i class="fas fa-envelope" aria-hidden="true"></i> Start a conversation</a>
    <a href="https://de.linkedin.com/in/pit-singert" class="btn btn-outline-primary"><i class="fab fa-linkedin" aria-hidden="true"></i> Connect on LinkedIn</a>
  </div>
  <p class="text-muted small mt-3 mb-0"><strong>DE</strong> native · <strong>EN</strong> fluent — write in whichever language is most comfortable.</p>
</section>

<section class="contact-section" aria-labelledby="capabilities-title">
  <p class="text-uppercase small fw-bold text-primary mb-2">Where I can help</p>
  <h2 id="capabilities-title">Focused expertise for real-world delivery</h2>
  <p class="text-muted">A few clear outcomes are easier to scan than a long service catalogue.</p>
  <div class="row g-3 mt-2">
    <div class="col-md-4">
      <article class="card contact-card"><div class="card-body p-4"><div class="contact-icon"><i class="fas fa-cloud" aria-hidden="true"></i></div><h3 class="h5">Cloud architecture</h3><p class="text-muted">Azure, containers, Kubernetes, serverless, and microservices designed for security, resilience, and sensible operations.</p><span class="contact-tag">Review · Design · Roadmap</span></div></article>
    </div>
    <div class="col-md-4">
      <article class="card contact-card"><div class="card-body p-4"><div class="contact-icon"><i class="fas fa-shield-halved" aria-hidden="true"></i></div><h3 class="h5">Microsoft security</h3><p class="text-muted">Defender and Sentinel architecture, posture improvement, detection engineering, and security operations that produce useful signal.</p><span class="contact-tag">Assess · Improve · Enable</span></div></article>
    </div>
    <div class="col-md-4">
      <article class="card contact-card"><div class="card-body p-4"><div class="contact-icon"><i class="fas fa-code-branch" aria-hidden="true"></i></div><h3 class="h5">Automation &amp; prototypes</h3><p class="text-muted">Secure CI/CD, AI-enabled systems, MVPs, demos, and proof-of-concepts that help teams validate ideas before they scale.</p><span class="contact-tag">Prototype · Demonstrate · Transfer</span></div></article>
    </div>
  </div>
</section>

<section class="contact-section" aria-labelledby="process-title">
  <p class="text-uppercase small fw-bold text-primary mb-2">A simple starting point</p>
  <h2 id="process-title">What happens after you reach out?</h2>
  <div class="row g-4 mt-2 contact-process">
    <div class="col-md-4 contact-step"><h3 class="h5">Share the context</h3><p>Tell me briefly about your organization, the challenge, and what a useful outcome would look like.</p></div>
    <div class="col-md-4 contact-step"><h3 class="h5">Have a focused conversation</h3><p>We identify the real constraint, the right scope, and whether my experience is a good fit.</p></div>
    <div class="col-md-4 contact-step"><h3 class="h5">Leave with a next step</h3><p>For suitable projects, we agree on a practical review, roadmap, workshop, or prototype.</p></div>
  </div>
</section>

<section class="contact-cta" aria-labelledby="cta-title">
  <div><h3 id="cta-title">Have a challenge worth discussing?</h3><p>Send a short summary. I’ll get back to you if it looks like a good fit.</p></div>
  <a href="mailto:kontakt.psingert@outlook.de" class="btn btn-light text-nowrap">kontakt.psingert@outlook.de</a>
</section>

<hr class="my-5">

<section lang="de" aria-labelledby="contact-title-de">
  <div class="contact-tip">Praktische Cloud-Architektur, Security und Automatisierung für Microsoft-orientierte kleine Unternehmen.</div>
  <p class="text-uppercase small fw-bold text-primary mb-2">Cloud · Security · Automatisierung</p>
  <h2 id="contact-title-de">Sichere Entscheidungen für Cloud und Security treffen.</h2>
  <p>Ich unterstütze Microsoft-orientierte Unternehmen dabei, komplexe Azure- und Security-Herausforderungen in praktikable nächste Schritte zu übersetzen — von der Architekturprüfung bis zum Proof of Concept.</p>
  <p class="text-muted"><strong>DE</strong> Muttersprache · <strong>EN</strong> fließend — schreiben Sie gerne in der Sprache, die für Sie am angenehmsten ist.</p>
  <div class="contact-actions mb-4">
    <a href="mailto:kontakt.psingert@outlook.de" class="btn btn-primary"><i class="fas fa-envelope" aria-hidden="true"></i> Gespräch starten</a>
    <a href="https://de.linkedin.com/in/pit-singert" class="btn btn-outline-primary"><i class="fab fa-linkedin" aria-hidden="true"></i> Auf LinkedIn vernetzen</a>
  </div>
  <p class="text-muted">Meine zeitliche Verfügbarkeit ist begrenzt. Wenn Sie ein passendes Projekt oder eine Kooperationsmöglichkeit besprechen möchten, schreiben Sie mir gerne eine E-Mail mit einer kurzen Beschreibung Ihres Unternehmens, der aktuellen Herausforderung und der gewünschten Unterstützung.</p>
  <div class="text-center my-4"><a href="mailto:kontakt.psingert@outlook.de" class="btn btn-primary">kontakt.psingert@outlook.de</a></div>
</section>
