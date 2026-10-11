// Brüce landing page: carousel, gallery, tabs, copy buttons, scroll reveal, theme toggle. No dependencies.
(() => {
  'use strict';
  const root = document.documentElement;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const systemLight = window.matchMedia('(prefers-color-scheme: light)');

  const SHOTS = [
    { id: 'home', label: 'Home', alt: 'Home screen with a spotlight class, category tiles and nearby gyms.' },
    { id: 'explore', label: 'Explore', alt: 'Explore tab listing studios with ratings, categories and distances, plus filter chips.' },
    { id: 'studio', label: 'Studio', alt: 'Studio page with a Show ticket button, opening status, facilities and description.' },
    { id: 'detail', label: 'Class', alt: 'Class page with book, check-in and cancel times and a lime Book button.' },
    { id: 'rules', label: 'Booking rules', alt: 'Booking rules sheet listing late check-in and cancellation times, a Book button and the strike notice.' },
    { id: 'quickcheckin', label: 'Quick check-in', alt: 'Quick check-in sheet suggesting the last visited studio with a Check in button.' },
    { id: 'drawarea', label: 'Custom area', alt: 'Map of Stockholm with a hand-drawn lime area outline and Clear, Draw and Save buttons.' },
    { id: 'mybookings', label: 'My classes', alt: 'My classes tab with two booked classes, a waitlist and bookmarks.' },
  ];
  const src = (id, mode) => `screenshots/iphone-${id}-${mode}.webp`;

  // Theme ------------------------------------------------------------------
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } },
  };
  const effectiveTheme = () => root.dataset.theme || (systemLight.matches ? 'light' : 'dark');
  const toggle = document.getElementById('theme-toggle');
  const labelToggle = () => toggle && toggle.setAttribute('aria-label', effectiveTheme() === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
  if (toggle) {
    labelToggle();
    toggle.addEventListener('click', () => {
      const next = effectiveTheme() === 'dark' ? 'light' : 'dark';
      root.dataset.theme = next;
      store.set('theme', next);
      labelToggle();
      setCarouselMode(next);
      setGalleryMode(next);
    });
  }
  systemLight.addEventListener('change', () => { if (!root.dataset.theme) { labelToggle(); setCarouselMode(effectiveTheme()); setGalleryMode(effectiveTheme()); } });

  // Carousel ---------------------------------------------------------------
  const screen = document.getElementById('slides');
  const dots = document.getElementById('dots');
  const caption = document.getElementById('caption');
  const playBtn = document.getElementById('play');
  let index = 0, timer = null, paused = reduceMotion.matches, carouselMode = effectiveTheme();

  function buildSlides() {
    if (!screen) return;
    screen.innerHTML = '';
    SHOTS.forEach((s, i) => {
      const fig = document.createElement('figure');
      fig.className = 'slide' + (i === index ? ' is-active' : '');
      fig.setAttribute('role', 'group');
      fig.setAttribute('aria-roledescription', 'slide');
      fig.setAttribute('aria-label', `${i + 1} of ${SHOTS.length}: ${s.label}`);
      if (i !== index) fig.setAttribute('aria-hidden', 'true');
      const img = document.createElement('img');
      img.src = src(s.id, carouselMode);
      img.alt = s.alt + ' Demo data.';
      img.width = 1179; img.height = 2563;
      img.decoding = 'async';
      if (i > 0) img.loading = 'lazy';
      fig.appendChild(img);
      screen.appendChild(fig);
    });
    dots.innerHTML = '';
    SHOTS.forEach((s, i) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('role', 'tab');
      b.setAttribute('aria-label', s.label);
      b.setAttribute('aria-selected', String(i === index));
      b.tabIndex = i === index ? 0 : -1;
      b.addEventListener('click', () => { go(i); restart(); });
      b.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
          e.preventDefault();
          go(index + (e.key === 'ArrowRight' ? 1 : -1));
          dots.children[index].focus();
          restart();
        }
      });
      dots.appendChild(b);
    });
  }
  function go(i) {
    index = (i + SHOTS.length) % SHOTS.length;
    [...screen.children].forEach((f, j) => {
      f.classList.toggle('is-active', j === index);
      if (j === index) f.removeAttribute('aria-hidden'); else f.setAttribute('aria-hidden', 'true');
    });
    [...dots.children].forEach((b, j) => { b.setAttribute('aria-selected', String(j === index)); b.tabIndex = j === index ? 0 : -1; });
    caption.textContent = SHOTS[index].label;
  }
  function setCarouselMode(mode) {
    carouselMode = mode;
    if (!screen) return;
    [...screen.querySelectorAll('img')].forEach((img, j) => { img.src = src(SHOTS[j].id, mode); });
  }
  function restart() {
    clearInterval(timer);
    if (!paused) timer = setInterval(() => go(index + 1), 4200);
  }
  function setPaused(p) {
    paused = p;
    playBtn.setAttribute('aria-pressed', String(p));
    playBtn.setAttribute('aria-label', p ? 'Play slideshow' : 'Pause slideshow');
    restart();
  }
  if (screen) {
    buildSlides();
    go(0);
    document.getElementById('prev').addEventListener('click', () => { go(index - 1); restart(); });
    document.getElementById('next').addEventListener('click', () => { go(index + 1); restart(); });
    playBtn.addEventListener('click', () => setPaused(!paused));
    const carousel = screen.closest('.carousel');
    // Pause while the pointer or keyboard focus is inside, as WAI-ARIA carousels should.
    carousel.addEventListener('mouseenter', () => clearInterval(timer));
    carousel.addEventListener('mouseleave', restart);
    carousel.addEventListener('focusin', () => clearInterval(timer));
    carousel.addEventListener('focusout', restart);
    setPaused(paused);
    reduceMotion.addEventListener('change', () => setPaused(reduceMotion.matches));
  }

  // Gallery ----------------------------------------------------------------
  const track = document.getElementById('gallery-track');
  const segButtons = document.querySelectorAll('.seg button');
  function setGalleryMode(mode) {
    if (!track) return;
    track.querySelectorAll('img').forEach((img) => { img.src = src(img.dataset.id, mode); });
    segButtons.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.shots === mode)));
  }
  if (track) {
    track.innerHTML = '';
    SHOTS.forEach((s) => {
      const fig = document.createElement('figure');
      const img = document.createElement('img');
      img.dataset.id = s.id;
      img.alt = s.alt + ' Demo data.';
      img.width = 1179; img.height = 2563;
      img.loading = 'lazy'; img.decoding = 'async';
      const cap = document.createElement('figcaption');
      cap.textContent = s.label;
      fig.append(img, cap);
      track.appendChild(fig);
    });
    setGalleryMode(effectiveTheme());
    segButtons.forEach((b) => b.addEventListener('click', () => setGalleryMode(b.dataset.shots)));
  }

  // Tabs -------------------------------------------------------------------
  const tabs = [...document.querySelectorAll('.tablist [role="tab"]')];
  function selectTab(t) {
    tabs.forEach((x) => {
      const on = x === t;
      x.setAttribute('aria-selected', String(on));
      x.tabIndex = on ? 0 : -1;
      document.getElementById(x.getAttribute('aria-controls')).hidden = !on;
    });
  }
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => selectTab(t));
    t.addEventListener('keydown', (e) => {
      const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      const n = tabs[(i + d + tabs.length) % tabs.length];
      selectTab(n); n.focus();
    });
  });

  // Copy buttons -----------------------------------------------------------
  document.querySelectorAll('[data-copy]').forEach((b) => {
    b.addEventListener('click', async () => {
      const text = document.getElementById(b.dataset.copy).innerText;
      try {
        await navigator.clipboard.writeText(text);
        b.textContent = 'Copied'; b.classList.add('done');
      } catch (e) {
        b.textContent = 'Select and copy';
      }
      setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1800);
    });
  });

  // Scroll reveal ----------------------------------------------------------
  const items = document.querySelectorAll('.reveal');
  if (reduceMotion.matches || !('IntersectionObserver' in window)) {
    items.forEach((el) => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    items.forEach((el) => io.observe(el));
  }
})();
