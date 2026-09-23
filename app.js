(() => {
  const D = window.NEON_DATA;
  const C = window.NEON_CONFIG;
  const app = document.getElementById('app');
  const modal = document.getElementById('modal');
  const modalBody = document.getElementById('modalBody');

  let sb = null;
  let user = null;
  let profile = null;
  let catalog = D.courses.map(c => ({ ...c }));
  let ownedSlugs = [];
  let activeCourse = null;
  let activeLessons = [];
  let activeQuiz = [];
  let activeLessonId = null;

  const configured = () => C.supabaseUrl && !C.supabaseUrl.startsWith('YOUR_') && C.supabaseAnonKey && !C.supabaseAnonKey.startsWith('YOUR_');
  if (configured() && window.supabase) sb = window.supabase.createClient(C.supabaseUrl, C.supabaseAnonKey);

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = s => String(s ?? '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m]));
  const money = n => new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'GBP' }).format(Number(n || 0));

  function localProgress() { return JSON.parse(localStorage.getItem('neon_progress') || '{}'); }
  function saveLocalProgress(v) { localStorage.setItem('neon_progress', JSON.stringify(v)); }
  function ownedLocal() { return JSON.parse(localStorage.getItem('neon_owned') || '[]'); }
  function demoUnlock(slug) {
    const owned = ownedLocal();
    if (!owned.includes(slug)) owned.push(slug);
    localStorage.setItem('neon_owned', JSON.stringify(owned));
    refreshOwned();
  }

  async function refreshCatalog() {
    if (!sb) return;
    const { data, error } = await sb.from('courses').select('*').order('sort_order');
    if (error || !data?.length) return;
    catalog = data.map(row => {
      const base = D.courses.find(c => c.slug === row.slug) || {};
      return {
        ...base,
        slug: row.slug,
        name: row.name,
        focus: row.focus,
        detail: row.description || base.detail || '',
        price: Number(row.price),
        days: Number(row.duration_days),
        payment_url: row.payment_url || '',
        active: row.active,
        accent: base.accent || 'green',
        tagline: base.tagline || row.focus,
        features: base.features || []
      };
    }).filter(c => c.active || profile?.is_admin);
  }

  async function refreshUser() {
    if (!sb) return;
    const { data } = await sb.auth.getUser();
    user = data.user || null;
    profile = null;
    if (user) {
      const p = await sb.from('profiles').select('id,email,is_admin').eq('id', user.id).maybeSingle();
      profile = p.data || null;
    }
    syncAccount();
  }

  async function refreshOwned() {
    const owned = new Set(C.demoMode ? ownedLocal() : []);
    if (sb && user) {
      if (profile?.is_admin) {
        catalog.forEach(c => owned.add(c.slug));
      } else {
        const { data } = await sb.from('enrollments')
          .select('course_slug,expires_at')
          .eq('user_id', user.id)
          .gt('expires_at', new Date().toISOString());
        (data || []).forEach(r => owned.add(r.course_slug));
      }
    }
    ownedSlugs = [...owned];
  }

  async function init() {
    await refreshCatalog();
    await refreshUser();
    await refreshCatalog();
    await refreshOwned();
    if (sb) {
      sb.auth.onAuthStateChange(async (_event, session) => {
        user = session?.user || null;
        await refreshUser();
        await refreshCatalog();
        await refreshOwned();
        route();
      });
    }
    sourceLinks();
    route();
  }

  function syncAccount() {
    $('#loginBtn')?.classList.toggle('hidden', !!user);
    $('#logoutBtn')?.classList.toggle('hidden', !user);
  }

  function sourceLinks() {
    const e = $('#sourceLinks');
    if (e) e.innerHTML = D.sources.map(x => `<a href="${x.url}" target="_blank" rel="noopener">${esc(x.label)}</a>`).join(' · ');
  }

  function nav(view) { location.hash = view === 'home' ? '#home' : `#${view}`; }

  $$('[data-nav]').forEach(b => b.addEventListener('click', () => nav(b.dataset.nav)));
  $('#loginBtn').onclick = openAuth;
  $('#logoutBtn').onclick = async () => {
    if (sb) await sb.auth.signOut();
    user = null; profile = null; ownedSlugs = C.demoMode ? ownedLocal() : [];
    syncAccount(); route();
  };
  $('#closeModal').onclick = () => modal.classList.add('hidden');
  modal.addEventListener('click', e => { if (e.target === modal) modal.classList.add('hidden'); });

  function openAuth() {
    modal.classList.remove('hidden');
    modalBody.innerHTML = `<h2>Student account</h2>
      <p class="muted">Create an account or log in to sync course access and progress.</p>
      <div class="auth-tabs"><button class="btn small primary" data-auth="login">Log in</button><button class="btn small" data-auth="signup">Sign up</button></div>
      <form class="auth-form" id="authForm">
        <input id="email" type="email" placeholder="Email" required>
        <input id="password" type="password" placeholder="Password (6+ characters)" minlength="6" required>
        <button class="btn primary">Continue</button><div id="authMsg" class="muted"></div>
      </form>`;
    let mode = 'login';
    $$('[data-auth]', modalBody).forEach(b => b.onclick = () => {
      mode = b.dataset.auth;
      $$('[data-auth]', modalBody).forEach(x => x.classList.toggle('primary', x === b));
    });
    $('#authForm', modalBody).onsubmit = async e => {
      e.preventDefault();
      const msg = $('#authMsg', modalBody);
      if (!sb) { msg.textContent = 'Supabase is not connected yet. Follow README.md to enable real accounts.'; return; }
      msg.textContent = 'Working…';
      const email = $('#email', modalBody).value;
      const password = $('#password', modalBody).value;
      const r = mode === 'login' ? await sb.auth.signInWithPassword({ email, password }) : await sb.auth.signUp({ email, password });
      if (r.error) msg.textContent = r.error.message;
      else {
        msg.textContent = mode === 'signup' ? 'Account created. Check your email if confirmation is enabled.' : 'Logged in.';
        setTimeout(() => { modal.classList.add('hidden'); }, 500);
      }
    };
  }

  function courseCard(c) {
    return `<article class="course-card" style="--accent:var(--${c.accent || 'green'})">
      <span class="pill">${c.days} days access</span><h3>${esc(c.name)}</h3>
      <div class="focus">${esc(c.focus)}</div><div class="price">${money(c.price)}</div>
      <div class="duration">${esc(c.tagline || '')}</div>
      <ul>${(c.features || []).map(f => `<li>${esc(f)}</li>`).join('')}</ul>
      <button class="btn primary" data-open-course="${esc(c.slug)}">View course</button>
    </article>`;
  }

  async function latestAnnouncement() {
    if (!sb) return null;
    const { data } = await sb.from('announcements').select('title,body').eq('active', true).order('created_at', { ascending: false }).limit(1).maybeSingle();
    return data || null;
  }

  async function renderHome() {
    const announcement = await latestAnnouncement();
    app.innerHTML = `<section class="hero"><div>
      <div class="eyebrow">GCSE ENGLISH • AQA-FOCUSED • INTERACTIVE</div>
      <h1>REVISION<br><span>THAT MOVES.</span></h1>
      <p class="lead">A black, white, neon-green revision platform with interactive lessons, quick quizzes, progress tracking and game-style practice. Higher tiers last longer and unlock more detail.</p>
      <div class="actions"><button class="btn primary" data-go="courses">Choose a course</button><button class="btn purple" data-go="games">Try the games</button></div>
    </div><div class="hero-card"><div class="screen"><div class="eyebrow">YOUR COURSE STRATEGY</div><h2>Language: practise backwards.</h2>
      ${['Q5|Extended writing','Q4|Evaluation / comparison','Q3|Structure / language','Q2|Language / summary','Q1|Retrieval'].map(x => { const [q,t]=x.split('|'); return `<div class="mini-stat"><i class="dot"></i><b>${q}</b><span>${t}</span></div>`; }).join('')}
    </div></div></section>
    ${announcement ? `<div class="notice"><b>${esc(announcement.title)}</b><br>${esc(announcement.body)}</div>` : ''}
    <section><div class="section-head"><div><div class="eyebrow">COURSES</div><h2>Choose your level.</h2></div><p>Prices and durations are editable in the Control Room after Supabase is connected.</p></div>
      <div class="course-grid">${catalog.map(courseCard).join('')}</div>
    </section>
    <section class="panel" style="margin-top:26px"><h3>AQA structure, your teaching style.</h3><p class="muted">The platform follows the current AQA English Language and Literature assessment structure, while the backwards Language order is clearly labelled as your revision strategy rather than an exam-board rule.</p></section>`;
    wireCommon();
  }

  function renderCourses() {
    app.innerHTML = `<div class="section-head"><div><div class="eyebrow">ALL COURSES</div><h2>Pick the right depth.</h2></div><p>Shorter-price plans have shorter access. The complete Plus-Premium plan has the longest access and every game.</p></div>
      <div class="course-grid">${catalog.map(courseCard).join('')}</div>
      <div class="notice" style="margin-top:22px">Payment checkout is intentionally not hard-coded. Add a secure payment URL per course in the Control Room when we set up payments.</div>`;
    wireCommon();
  }

  async function hasAccess(slug) {
    if (C.demoMode && ownedLocal().includes(slug)) return true;
    if (profile?.is_admin) return true;
    if (!sb || !user) return false;
    const { data, error } = await sb.rpc('has_course_access', { p_course_slug: slug });
    return !error && !!data;
  }

  function fallbackLessons(slug) {
    return (D.courseLessons[slug] || []).map(id => ({ ...D.lessonBank[id], server: false }));
  }

  async function getLessons(slug, access) {
    if (sb && access) {
      const { data, error } = await sb.from('lessons').select('*').eq('course_slug', slug).order('sort_order');
      if (!error && data?.length) return data.map(x => ({ id: x.id, title: x.title, type: x.lesson_type, body: x.body, free_preview: x.free_preview, server: true }));
    }
    return fallbackLessons(slug);
  }

  async function getQuiz(slug, access) {
    if (sb && access) {
      const { data, error } = await sb.from('quiz_questions').select('*').eq('course_slug', slug).order('sort_order');
      if (!error && data?.length) return data.map(x => ({ q: x.question, options: x.options || [], answer: x.correct_index, why: x.explanation || '' }));
    }
    const kind = slug === 'standard' ? 'literature' : slug === 'pro' ? 'language' : 'mixed';
    return D.quizBanks[kind] || [];
  }

  async function completionMap(lessons) {
    const map = localProgress();
    if (sb && user) {
      const serverIds = lessons.filter(l => l.server).map(l => l.id);
      if (serverIds.length) {
        const { data } = await sb.from('progress').select('lesson_id,completed').eq('user_id', user.id).in('lesson_id', serverIds);
        (data || []).forEach(p => { if (p.completed) map[activeCourse.slug + ':' + p.lesson_id] = true; });
      }
    }
    return map;
  }

  async function renderCourse(slug) {
    const c = catalog.find(x => x.slug === slug);
    if (!c) return renderCourses();
    activeCourse = c;
    const access = await hasAccess(slug);
    activeLessons = await getLessons(slug, access);
    activeQuiz = await getQuiz(slug, access);
    const progress = await completionMap(activeLessons);

    app.innerHTML = `<div class="section-head"><div><div class="eyebrow">${esc(c.name)} • ${c.days} DAYS</div><h2>${esc(c.focus)}</h2></div><div><div class="price">${money(c.price)}</div></div></div>
      ${access ? `<div class="course-layout"><aside class="lesson-list panel">
        ${activeLessons.map((l,i) => `<button class="lesson-button ${progress[slug+':'+l.id] ? 'done' : ''}" data-lesson="${l.id}">${String(i+1).padStart(2,'0')} · ${esc(l.title)}</button>`).join('')}
        <button class="lesson-button" data-lesson="quiz">★ Course quiz</button></aside><section class="lesson-content panel" id="lessonContent"></section></div>`
      : `<div class="panel"><span class="pill">LOCKED</span><h2>${esc(c.name)} course access</h2><p class="lead">${esc(c.detail)}</p>
        <ul>${(c.features || []).map(x => `<li>${esc(x)}</li>`).join('')}</ul>
        <div class="actions"><button class="btn primary" id="buyBtn">${c.payment_url ? 'Buy securely' : 'Payment coming soon'}</button>${C.demoMode ? '<button class="btn" id="demoUnlock">Unlock demo on this device</button>' : ''}</div>
        <p class="muted">Admins can grant access from the Control Room. Paid access is designed to expire automatically after this course's configured number of days.</p></div>`}`;

    if (access) {
      $$('[data-lesson]').forEach(b => b.onclick = () => openLesson(b.dataset.lesson));
      openLesson(activeLessons[0]?.id || 'quiz');
    } else {
      if ($('#demoUnlock')) $('#demoUnlock').onclick = async () => { demoUnlock(slug); await refreshOwned(); renderCourse(slug); };
      $('#buyBtn').onclick = () => {
        if (c.payment_url) window.open(c.payment_url, '_blank', 'noopener');
        else alert('Payment is not connected yet. Add the secure payment URL in the Control Room when we set up checkout.');
      };
    }
  }

  function isP2Q5Lesson(l) { return l?.id === 'p2q5' || /paper\s*2\s*q5/i.test(l?.title || ''); }

  function openLesson(id) {
    activeLessonId = id;
    $$('.lesson-button').forEach(b => b.classList.toggle('active', b.dataset.lesson === id));
    const area = $('#lessonContent');
    if (id === 'quiz') return renderQuiz(area);
    const l = activeLessons.find(x => String(x.id) === String(id));
    if (!l) return;

    const p4 = isP2Q5Lesson(l) ? `<div class="interactive-box"><h3>P4 planning builder</h3><div class="builder-grid">
      <label>Presently<textarea id="bPresent" placeholder="Current issue + your viewpoint"></textarea></label>
      <label>Personally<textarea id="bPersonal" placeholder="Human/personal angle"></textarea></label>
      <label>Publicly<textarea id="bPublic" placeholder="Wider society / evidence"></textarea></label>
      <label>Predictably<textarea id="bPredict" placeholder="Opposing view + rebuttal + finish"></textarea></label>
      </div><button class="btn primary" id="buildP4" style="margin-top:12px">Build my outline</button><div id="p4Out" class="output hidden"></div></div>
      <img src="q5-layout.png" class="q5-image" alt="Paper 2 Question 5 layout supplied for this course">` : '';

    area.innerHTML = `<span class="pill">${esc((l.type || 'lesson').toUpperCase())}</span><h2>${esc(l.title)}</h2><div class="lesson-copy">${esc(l.body)}</div>${p4}
      <div class="actions"><button class="btn primary" id="completeLesson">Mark complete</button><button class="btn" data-go="games">Open games</button></div>`;

    $('#completeLesson').onclick = async () => {
      const p = localProgress();
      p[activeCourse.slug + ':' + id] = true;
      saveLocalProgress(p);
      $(`[data-lesson="${id}"]`)?.classList.add('done');
      $('#completeLesson').textContent = 'Completed ✓';
      if (sb && user && l.server) {
        await sb.from('progress').upsert({ user_id: user.id, lesson_id: l.id, completed: true, updated_at: new Date().toISOString() });
      }
    };
    $('[data-go="games"]', area).onclick = () => nav('games');
    if ($('#buildP4')) $('#buildP4').onclick = () => {
      const vals = [['PRESENTLY',$('#bPresent').value],['PERSONALLY',$('#bPersonal').value],['PUBLICLY',$('#bPublic').value],['PREDICTABLY',$('#bPredict').value]];
      const out = $('#p4Out');
      out.textContent = vals.map(([h,v]) => `${h}\n${v || '— add your idea —'}`).join('\n\n');
      out.classList.remove('hidden');
    };
  }

  function renderQuiz(area) {
    const bank = activeQuiz?.length ? activeQuiz : D.quizBanks.mixed;
    let idx = 0, score = 0;
    const draw = () => {
      if (idx >= bank.length) {
        area.innerHTML = `<div class="eyebrow">QUIZ COMPLETE</div><h2>${score}/${bank.length}</h2><p class="lead">Use mistakes as your next revision target.</p><button class="btn primary" id="quizAgain">Try again</button>`;
        $('#quizAgain').onclick = () => { idx = 0; score = 0; draw(); };
        return;
      }
      const q = bank[idx];
      area.innerHTML = `<div class="eyebrow">QUESTION ${idx+1} OF ${bank.length}</div><h2 style="font-size:2rem">${esc(q.q)}</h2><div>
        ${(q.options || []).map((o,i) => `<button class="quiz-option" data-ans="${i}">${esc(o)}</button>`).join('')}</div><div id="quizWhy" class="muted" style="margin-top:12px"></div>`;
      $$('[data-ans]', area).forEach(b => b.onclick = () => {
        const n = Number(b.dataset.ans);
        $$('[data-ans]', area).forEach(x => x.disabled = true);
        b.classList.add(n === Number(q.answer) ? 'correct' : 'wrong');
        if (n === Number(q.answer)) score++;
        $(`[data-ans="${q.answer}"]`, area)?.classList.add('correct');
        $('#quizWhy', area).innerHTML = `${esc(q.why)}<br><button class="btn small primary" id="nextQ" style="margin-top:12px">Next</button>`;
        $('#nextQ').onclick = () => { idx++; draw(); };
      });
    };
    draw();
  }

  function tierAccess(game) {
    if (profile?.is_admin || ownedSlugs.includes('plus-premium')) return true;
    if (!ownedSlugs.length) return false;
    if (game.id === 'quote-flip') return true;
    if (game.id === 'order-sprint') return ownedSlugs.some(s => ['pro','plus','premium'].includes(s));
    if (game.id === 'p4-builder') return ownedSlugs.some(s => ['plus','premium'].includes(s));
    if (game.id === 'technique-match') return false;
    return false;
  }

  function renderGames() {
    app.innerHTML = `<div class="section-head"><div><div class="eyebrow">REVISION ARCADE</div><h2>Learn by doing.</h2></div><p>Every plan gets interactive practice. Higher tiers unlock more game modes.</p></div>
      <div class="game-grid">${D.games.map(g => `<article class="game-card ${tierAccess(g) ? '' : 'locked'}"><span class="pill">${tierAccess(g) ? 'UNLOCKED' : 'LOCKED'}</span><h3>${esc(g.name)}</h3><p class="muted">${esc(g.description)}</p><button class="btn ${tierAccess(g) ? 'primary' : ''}" data-game="${g.id}" ${tierAccess(g) ? '' : 'disabled'}>Play</button></article>`).join('')}</div>
      <section id="gameStage" class="panel" style="margin-top:18px"><h3>Choose a game above.</h3></section>`;
    $$('[data-game]').forEach(b => b.onclick = () => playGame(b.dataset.game));
  }

  function playGame(id) {
    const s = $('#gameStage');
    if (id === 'order-sprint') {
      const target = ['Q5','Q4','Q3','Q2','Q1']; let pool = ['Q2','Q5','Q1','Q4','Q3'], selected = [];
      const draw = () => {
        s.innerHTML = `<div class="eyebrow">QUESTION ORDER SPRINT</div><h2>Build the course practice order</h2><p class="muted">Click the cards in order.</p>
          <div class="order-row">${pool.map(x => `<button class="order-chip" data-chip="${x}">${x}</button>`).join('')}</div><div class="output">${selected.join(' → ') || 'Your order will appear here.'}</div><button class="btn" id="resetOrder">Reset</button>`;
        $$('[data-chip]', s).forEach(b => b.onclick = () => { selected.push(b.dataset.chip); pool = pool.filter(x => x !== b.dataset.chip); if (selected.length === 5) setTimeout(() => alert(JSON.stringify(selected) === JSON.stringify(target) ? 'Perfect — Q5 → Q4 → Q3 → Q2 → Q1' : 'Not quite. Reset and try again.'), 30); draw(); });
        $('#resetOrder').onclick = () => { pool = ['Q2','Q5','Q1','Q4','Q3']; selected = []; draw(); };
      }; draw();
    } else if (id === 'quote-flip') {
      const cards = [['Ambition','Name one moment where ambition changes a character.'],['Change','Explain one stage of a character’s transformation.'],['Poetry','Give one similarity and one difference between two poems.'],['Method','Explain why a writer might use contrast.']];
      let i = 0, back = false;
      const draw = () => { s.innerHTML = `<div class="eyebrow">QUOTE FLIP</div><h2>Recall before you reveal.</h2><div class="flashcard" id="flash">${esc(back ? cards[i][1] : cards[i][0])}</div><div class="actions"><button class="btn" id="flip">Flip</button><button class="btn primary" id="nextCard">Next card</button></div>`; $('#flip').onclick = () => { back = !back; draw(); }; $('#nextCard').onclick = () => { i = (i+1)%cards.length; back = false; draw(); }; }; draw();
    } else if (id === 'p4-builder') {
      s.innerHTML = `<div class="eyebrow">P4 VIEWPOINT BUILDER</div><h2>Presently. Personally. Publicly. Predictably.</h2><div class="builder-grid"><label>Presently<textarea id="gp1"></textarea></label><label>Personally<textarea id="gp2"></textarea></label><label>Publicly<textarea id="gp3"></textarea></label><label>Predictably<textarea id="gp4"></textarea></label></div><button class="btn primary" id="makePlan" style="margin-top:12px">Generate outline</button><div id="gout" class="output hidden"></div>`;
      $('#makePlan').onclick = () => { const v = ['gp1','gp2','gp3','gp4'].map(x => $('#'+x).value || '—'); $('#gout').textContent = `PRESENTLY\n${v[0]}\n\nPERSONALLY\n${v[1]}\n\nPUBLICLY\n${v[2]}\n\nPREDICTABLY\n${v[3]}`; $('#gout').classList.remove('hidden'); };
    } else if (id === 'technique-match') {
      const items = [['Contrast','Highlights a difference to sharpen an idea'],['Short sentence','Can interrupt the rhythm or add emphasis'],['Semantic field','Builds a pattern of related meaning'],['Shift in focus','Changes what the reader notices across the text']]; const order=[2,0,3,1];
      s.innerHTML = `<div class="eyebrow">TECHNIQUE MATCH</div><h2>Match method to explanation.</h2>${items.map((x,i) => `<label style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:10px 0"><span class="panel">${esc(x[0])}</span><select class="field" data-match="${i}"><option value="">Choose…</option>${order.map(j => `<option value="${j}">${esc(items[j][1])}</option>`).join('')}</select></label>`).join('')}<button class="btn primary" id="checkMatch">Check</button><div id="matchOut" class="muted" style="margin-top:10px"></div>`;
      $('#checkMatch').onclick = () => { let n=0; $$('[data-match]',s).forEach(x => { if (Number(x.value) === Number(x.dataset.match)) n++; }); $('#matchOut').textContent = `${n}/${items.length} correct.`; };
    }
  }

  async function renderDashboard() {
    await refreshOwned();
    const p = localProgress();
    const completed = Object.values(p).filter(Boolean).length;
    const total = ownedSlugs.reduce((n, s) => n + (D.courseLessons[s]?.length || 0), 0);
    const pct = total ? Math.min(100, Math.round(completed / total * 100)) : 0;
    app.innerHTML = `<div class="section-head"><div><div class="eyebrow">MY PROGRESS</div><h2>Your dashboard.</h2></div><p>${user ? esc(user.email) : 'Local demo progress is saved on this device. Log in after Supabase setup to sync access.'}</p></div>
      <div class="dash-grid"><div class="stat">Courses owned<b>${ownedSlugs.length}</b></div><div class="stat">Lessons complete<b>${completed}</b></div><div class="stat">Overall progress<b>${pct}%</b></div><div class="stat">Practice order<b>Q5→Q1</b></div></div>
      <div class="panel" style="margin-top:18px"><h3>Overall progress</h3><div class="progressbar"><i style="width:${pct}%"></i></div><div class="actions">${ownedSlugs.map(s => { const c = catalog.find(x => x.slug === s); return c ? `<button class="btn" data-open-course="${s}">${esc(c.name)}</button>` : ''; }).join('') || '<span class="muted">No courses unlocked yet.</span>'}</div></div>`;
    wireCommon();
  }

  function wireCommon() {
    $$('[data-go]').forEach(b => b.onclick = () => nav(b.dataset.go));
    $$('[data-open-course]').forEach(b => b.onclick = () => nav('course/' + b.dataset.openCourse));
  }

  function route() {
    const h = (location.hash || '#home').slice(1);
    if (h.startsWith('course/')) return renderCourse(h.split('/')[1]);
    if (h === 'courses') return renderCourses();
    if (h === 'games') return renderGames();
    if (h === 'dashboard') return renderDashboard();
    return renderHome();
  }

  window.addEventListener('hashchange', route);
  init();
})();
