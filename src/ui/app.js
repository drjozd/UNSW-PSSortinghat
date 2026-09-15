/* ==========================================================================
   Sortinghat - browser side
   Talks only to the PowerShell process that served this page.
   ========================================================================== */

'use strict';

const SESSION_KEY = new URLSearchParams(location.search).get('k') || '';

const S = {
  connected: false, account: '', mock: false,
  teams: [], teamId: '', teamName: '', youAreOwner: false,
  roster: new Map(),      // key -> person
  channels: [],           // { name, id, type, isNew, description }
  original: new Map(),    // channel name -> Set(key)   as Teams has it now
  assign: new Map(),      // channel name -> Set(key)   as the lecturer wants it
  locked: new Map(),      // channel name -> Set(key)   channel owners, cannot be removed
  selection: new Set(),
  filter: '',
  hasGroupColumn: false,
  ops: [], results: [], step: 'signin'
};

/* ── tiny helpers ───────────────────────────────────────────────────────── */

const $  = (sel, root) => (root || document).querySelector(sel);
const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
const asArray = v => (Array.isArray(v) ? v : (v === null || v === undefined ? [] : [v]));
const esc = s => String(s === null || s === undefined ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const keyOf = upn => String(upn || '').trim().toLowerCase();
const plural = (n, one, many) => `${n} ${n === 1 ? one : (many || one + 's')}`;

function toast(message, ms) {
  const el = $('#toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { el.hidden = true; }, ms || 3200);
}

/* ── theme ──────────────────────────────────────────────────────────────── */

const THEMES = ['auto', 'light', 'dark'];

function applyTheme(mode) {
  if (mode === 'auto') document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', mode);
  const btn = document.getElementById('themeBtn');
  if (btn) btn.textContent = 'Theme: ' + mode;
}

let themeMode = 'auto';
try { themeMode = localStorage.getItem('sortinghat-theme') || 'auto'; } catch (e) { /* private window */ }
if (THEMES.indexOf(themeMode) < 0) themeMode = 'auto';
applyTheme(themeMode);

document.getElementById('themeBtn').addEventListener('click', () => {
  themeMode = THEMES[(THEMES.indexOf(themeMode) + 1) % THEMES.length];
  applyTheme(themeMode);
  try { localStorage.setItem('sortinghat-theme', themeMode); } catch (e) { /* nothing to do */ }
});

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { 'X-Sortinghat-Key': SESSION_KEY, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  if (!res.ok && res.status !== 200) {
    let detail = '';
    try { detail = (await res.json()).error || ''; } catch (e) { /* ignore */ }
    throw new Error(detail || `The Sortinghat window stopped responding (${res.status}).`);
  }
  return res.json();
}

function askDialog({ title, message, label, value, okText }) {
  return new Promise(resolve => {
    const dlg = $('#promptDialog');
    $('#promptTitle').textContent = title;
    $('#promptMessage').textContent = message || '';
    $('#promptMessage').hidden = !message;
    $('#promptLabel').textContent = label || '';
    $('#promptLabelWrap').hidden = !label;
    $('#promptInput').value = value === undefined ? '' : value;
    $('#promptOk').textContent = okText || 'OK';
    dlg.onclose = () => resolve(dlg.returnValue === 'ok' ? $('#promptInput').value.trim() : null);
    dlg.showModal();
    setTimeout(() => { if (label) $('#promptInput').select(); }, 30);
  });
}

/* ── step navigation ────────────────────────────────────────────────────── */

const STEPS = ['signin', 'team', 'list', 'sort', 'review'];

function goto(step) {
  S.step = step;
  $$('[data-panel]').forEach(p => { p.hidden = p.dataset.panel !== step; });
  const reached = STEPS.indexOf(step);
  $$('#stepList li').forEach(li => {
    const i = STEPS.indexOf(li.dataset.step);
    li.classList.toggle('current', i === reached);
    li.classList.toggle('done', i < reached);
    li.classList.toggle('available', i < reached);
  });
  window.scrollTo({ top: 0, behavior: 'instant' });
  if (step === 'sort') renderBoard();
  if (step === 'review') renderReview();
}

$('#stepList').addEventListener('click', e => {
  const li = e.target.closest('li');
  if (li && li.classList.contains('available')) goto(li.dataset.step);
});

/* ── 1. sign in ─────────────────────────────────────────────────────────── */

async function refreshState() {
  const st = await api('GET', '/api/state');
  S.connected = !!st.connected;
  S.account = st.account || '';
  S.mock = !!st.mock;
  $('#mockBadge').hidden = !S.mock;
  $('#accountChip').hidden = !S.connected;
  $('#accountChip').textContent = S.account;
  $('#quitBtn').hidden = !S.connected;
  return st;
}

$('#signinBtn').addEventListener('click', async () => {
  $('#signinError').hidden = true;
  $('#signinBtn').disabled = true;
  $('#signinSpinner').hidden = false;
  try {
    const r = await api('POST', '/api/connect', {});
    if (!r.ok) throw new Error(r.error || 'Sign-in failed.');
    await refreshState();
    goto('team');
    loadTeams();
  } catch (err) {
    $('#signinError').textContent = err.message;
    $('#signinError').hidden = false;
  } finally {
    $('#signinBtn').disabled = false;
    $('#signinSpinner').hidden = true;
  }
});

$('#quitBtn').addEventListener('click', async () => {
  const ok = await askDialog({
    title: 'Finish and close Sortinghat?',
    message: 'This signs you out and stops the program. Anything you have already applied stays in Teams.',
    okText: 'Finish'
  });
  if (ok === null) return;
  try { await api('POST', '/api/quit', {}); } catch (e) { /* the server is gone, which is the point */ }
  document.body.innerHTML =
    '<div style="padding:3rem;text-align:center;font:15px system-ui">' +
    '<h1 style="font-size:1.3rem">Sortinghat has stopped.</h1>' +
    '<p style="color:#5c6675">You can close this tab.</p></div>';
});

/* ── 2. choose the team ─────────────────────────────────────────────────── */

async function loadTeams() {
  $('#teamLoading').hidden = false;
  $('#teamError').hidden = true;
  try {
    const r = await api('GET', '/api/teams');
    if (!r.ok) throw new Error(r.error);
    S.teams = asArray(r.teams);
    renderTeams();
  } catch (err) {
    $('#teamError').textContent = err.message;
    $('#teamError').hidden = false;
  } finally {
    $('#teamLoading').hidden = true;
  }
}

function renderTeams() {
  const q = $('#teamSearch').value.trim().toLowerCase();
  const list = S.teams.filter(t => !q || String(t.displayName || '').toLowerCase().includes(q));
  const box = $('#teamList');

  if (!list.length) {
    box.innerHTML = `<p class="muted">${S.teams.length ? 'No team matches that.' :
      'No teams found for your account. If you expect one here, check you are signed in with your staff account.'}</p>`;
    return;
  }
  box.innerHTML = list.map(t => {
    const desc = String(t.description || '').trim();
    const bits = [];
    if (desc && desc !== String(t.displayName).trim()) bits.push(desc);
    if (t.archived) bits.push('archived');
    return `<button class="team-item" data-id="${esc(t.groupId)}">
      <span class="name">${esc(t.displayName)}</span>
      ${bits.length ? `<span class="meta">${esc(bits.join(' \u00b7 '))}</span>` : ''}
    </button>`;
  }).join('');
}

$('#teamSearch').addEventListener('input', renderTeams);

$('#teamList').addEventListener('click', e => {
  const btn = e.target.closest('.team-item');
  if (!btn) return;
  const team = S.teams.find(t => t.groupId === btn.dataset.id);
  if (team) openTeam(team);
});

/* ── 3. load the team, then the class list ──────────────────────────────── */

async function openTeam(team) {
  S.teamId = team.groupId;
  S.teamName = team.displayName;
  $('#listTeamName').textContent = team.displayName;
  goto('list');
  await loadTeamContents();
}

async function loadTeamContents() {
  const progress = $('#loadProgress');
  const progressText = $('#loadProgressText');
  progress.hidden = false;
  progressText.textContent = 'Reading the team…';
  $('#toSortBtn').disabled = true;

  S.roster = new Map();
  S.original = new Map();
  S.assign = new Map();
  S.locked = new Map();
  S.channels = [];

  try {
    const r = await api('GET', '/api/team?groupId=' + encodeURIComponent(S.teamId));
    if (!r.ok) throw new Error(r.error);

    S.youAreOwner = !!r.youAreOwner;

    asArray(r.members).forEach(m => {
      const k = keyOf(m.upn);
      if (!k) return;
      S.roster.set(k, {
        key: k, upn: m.upn, name: m.name || m.upn.split('@')[0],
        zid: (m.upn.split('@')[0] || '').toLowerCase(),
        inTeam: true, isTeamOwner: String(m.role || '').toLowerCase() === 'owner',
        onList: false, group: ''
      });
    });

    const channels = asArray(r.channels);
    S.standardChannels = channels.filter(c => String(c.membershipType).toLowerCase() !== 'private');
    const priv = channels.filter(c => String(c.membershipType).toLowerCase() === 'private');

    for (let i = 0; i < priv.length; i++) {
      const c = priv[i];
      progressText.textContent = `Reading "${c.displayName}" (${i + 1} of ${priv.length})…`;
      const mr = await api('GET', '/api/channel-members?groupId=' +
        encodeURIComponent(S.teamId) + '&channel=' + encodeURIComponent(c.displayName));

      const members = mr.ok ? asArray(mr.members) : [];
      const set = new Set(), lockedSet = new Set();

      members.forEach(m => {
        const k = keyOf(m.upn);
        if (!k) return;
        if (!S.roster.has(k)) {
          S.roster.set(k, {
            key: k, upn: m.upn, name: m.name || m.upn.split('@')[0],
            zid: (m.upn.split('@')[0] || '').toLowerCase(),
            inTeam: true, isTeamOwner: false, onList: false, group: ''
          });
        }
        set.add(k);
        if (String(m.role || '').toLowerCase() === 'owner') lockedSet.add(k);
      });

      S.channels.push({ name: c.displayName, id: c.id, description: c.description || '', isNew: false });
      S.original.set(c.displayName, set);
      S.assign.set(c.displayName, new Set(set));
      S.locked.set(c.displayName, lockedSet);
      if (!mr.ok) toast(`Could not read the members of "${c.displayName}".`, 5000);
    }

    renderTeamSummary();
    $('#toSortBtn').disabled = false;
  } catch (err) {
    toast(err.message, 6000);
  } finally {
    progress.hidden = true;
  }
}

function renderTeamSummary() {
  const people = Array.from(S.roster.values());
  const owners = people.filter(p => p.isTeamOwner).length;
  const priv = S.channels.length;
  const added = people.filter(p => p.onList && !p.inTeam).length;

  $('#teamSummary').innerHTML = `
    <div class="stat"><div class="n">${people.length - added}</div><div class="k">people in the team</div></div>
    <div class="stat"><div class="n">${owners}</div><div class="k">owners</div></div>
    <div class="stat"><div class="n">${priv}</div><div class="k">private channel${priv === 1 ? '' : 's'}</div></div>`;

  const rows = S.channels.map(c => {
    const n = (S.original.get(c.name) || new Set()).size;
    return `<div class="cs-row"><span>${esc(c.name)}</span><span class="cs-n">${plural(n, 'member')}</span></div>`;
  });
  const std = asArray(S.standardChannels).map(c => c.displayName);
  $('#channelSummary').innerHTML =
    (rows.length ? rows.join('') : '<p class="muted">This team has no private channels yet. You can create some in the next step.</p>') +
    (std.length ? `<p class="hint" style="margin-top:.5rem">Standard channels (everyone in the team can see these, so they are not sorted): ${esc(std.join(', '))}</p>` : '');

  if (!S.youAreOwner) {
    $('#channelSummary').insertAdjacentHTML('afterbegin',
      '<div class="notice notice-warn">You are not listed as an owner of this team. ' +
      'Teams will refuse most of these changes unless you are. Ask the team owner to add you, ' +
      'or pick a different team.</div>');
  }
}

/* ── class list parsing ─────────────────────────────────────────────────── */

function splitRows(text) {
  const first = text.split(/\r?\n/).find(l => l.trim().length) || '';
  const counts = { ',': (first.match(/,/g) || []).length,
                   '\t': (first.match(/\t/g) || []).length,
                   ';': (first.match(/;/g) || []).length };
  const delim = Object.keys(counts).reduce((a, b) => (counts[b] > counts[a] ? b : a), ',');
  if (!counts[delim]) return { rows: text.split(/\r?\n/).filter(l => l.trim()).map(l => [l.trim()]), delim: null };

  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false; }
      else field += ch;
    } else if (ch === '"') { quoted = true; }
    else if (ch === delim) { row.push(field); field = ''; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (ch !== '\r') { field += ch; }
  }
  row.push(field); rows.push(row);
  return { rows: rows.filter(r => r.some(c => String(c).trim())), delim };
}

const EMAIL_RE = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/;
const ZID_RE = /^z\d{6,8}$/i;

function parseRoster(text, domain) {
  const clean = String(text || '').trim();
  if (!clean) return { people: [], skipped: [], hasGroups: false };

  const { rows, delim } = splitRows(clean);
  const people = [], skipped = [];
  let hasGroups = false;

  let cols = { email: -1, zid: -1, name: -1, first: -1, last: -1, group: -1 };
  let start = 0;

  if (delim && rows.length) {
    const header = rows[0].map(c => String(c).trim().toLowerCase());
    const find = re => header.findIndex(h => re.test(h));
    const looksLikeHeader = header.some(h =>
      /^(e-?mail|upn|user ?principal|zid|student ?(id|number)|id|name|full ?name|display ?name|given|first|sur|last|family|group|channel|tutorial|class|stream|team)/.test(h));
    if (looksLikeHeader) {
      start = 1;
      cols.email = find(/e-?mail|upn|user ?principal/);
      cols.zid   = find(/zid|student ?(id|number)|^id$/);
      cols.name  = find(/^(full ?name|display ?name|name|student ?name)$/);
      cols.first = find(/given|first/);
      cols.last  = find(/^(sur ?name|surname|last ?name|family ?name)$/);
      cols.group = find(/group|channel|tutorial|class|stream|^team$/);
    }
  }

  for (let i = start; i < rows.length; i++) {
    const cells = rows[i].map(c => String(c).trim());
    if (!cells.some(c => c)) continue;

    let upn = '';
    if (cols.email >= 0 && cells[cols.email]) {
      const m = cells[cols.email].match(EMAIL_RE);
      if (m) upn = m[0];
    }
    if (!upn && cols.zid >= 0 && ZID_RE.test(cells[cols.zid] || '')) {
      upn = `${cells[cols.zid].toLowerCase()}@${domain}`;
    }
    if (!upn) {
      const joined = cells.join(' ');
      const m = joined.match(EMAIL_RE);
      if (m) upn = m[0];
      else {
        const z = cells.map(c => c.replace(/[^A-Za-z0-9]/g, '')).find(c => ZID_RE.test(c));
        if (z) upn = `${z.toLowerCase()}@${domain}`;
      }
    }
    if (!upn) { skipped.push(cells.join(delim || ' ')); continue; }

    let name = '';
    if (cols.name >= 0) name = cells[cols.name] || '';
    if (!name && (cols.first >= 0 || cols.last >= 0)) {
      name = [cells[cols.first] || '', cells[cols.last] || ''].join(' ').trim();
    }
    if (!name) {
      const local = upn.split('@')[0];
      const candidate = cells.find(c => c && !EMAIL_RE.test(c) && !ZID_RE.test(c) &&
        /[A-Za-z]{2,}\s+[A-Za-z]/.test(c) && c.length < 60);
      name = candidate || local;
    }

    let group = '';
    if (cols.group >= 0) group = (cells[cols.group] || '').trim();
    if (group) hasGroups = true;

    people.push({ upn, name: name.trim(), group });
  }

  const seen = new Set();
  const unique = people.filter(p => {
    const k = keyOf(p.upn);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  return { people: unique, skipped, hasGroups };
}

function applyRoster() {
  const domain = ($('#domainInput').value || 'ad.unsw.edu.au').trim().replace(/^@/, '');
  const { people, skipped, hasGroups } = parseRoster($('#pasteBox').value, domain);
  const box = $('#parseSummary');

  Array.from(S.roster.values()).forEach(p => { p.onList = false; p.group = ''; });

  let added = 0, matched = 0;
  people.forEach(p => {
    const k = keyOf(p.upn);
    const existing = S.roster.get(k);
    if (existing) {
      existing.onList = true;
      existing.group = p.group;
      if (p.name && /@/.test(existing.name)) existing.name = p.name;
      matched++;
    } else {
      S.roster.set(k, {
        key: k, upn: p.upn, name: p.name || p.upn.split('@')[0],
        zid: (p.upn.split('@')[0] || '').toLowerCase(),
        inTeam: false, isTeamOwner: false, onList: true, group: p.group
      });
      added++;
    }
  });

  S.hasGroupColumn = hasGroups;

  if (!people.length) {
    box.hidden = $('#pasteBox').value.trim() === '';
    box.className = 'notice notice-warn';
    box.innerHTML = 'No students could be read from that. Sortinghat looks for an email address ' +
      'or a zID on each row &mdash; check the list has one of those.';
    renderTeamSummary();
    return;
  }

  box.hidden = false;
  box.className = 'notice notice-ok';
  box.innerHTML =
    `Read <strong>${plural(people.length, 'person', 'people')}</strong>. ` +
    `${matched} already in the team, <strong>${added}</strong> not in the team yet ` +
    `${added ? '(Sortinghat will add them when you apply)' : ''}.` +
    (hasGroups ? ' A group column was found &mdash; you can use it to fill the channels automatically.' : '') +
    (skipped.length ? `<br><span class="muted">${plural(skipped.length, 'line')} skipped: ${esc(skipped.slice(0, 3).join(' | '))}${skipped.length > 3 ? '&hellip;' : ''}</span>` : '');

  renderTeamSummary();
}

let parseTimer = null;
$('#pasteBox').addEventListener('input', () => {
  clearTimeout(parseTimer);
  parseTimer = setTimeout(applyRoster, 350);
});
$('#domainInput').addEventListener('change', applyRoster);

$('#browseBtn').addEventListener('click', () => $('#fileInput').click());
$('#fileInput').addEventListener('change', e => {
  const file = e.target.files && e.target.files[0];
  if (file) file.text().then(t => { $('#pasteBox').value = t; applyRoster(); });
});

const dz = $('#dropZone');
['dragenter', 'dragover'].forEach(ev => dz.addEventListener(ev, e => {
  e.preventDefault(); dz.classList.add('over');
}));
['dragleave', 'drop'].forEach(ev => dz.addEventListener(ev, e => {
  if (ev === 'dragleave' && dz.contains(e.relatedTarget)) return;
  dz.classList.remove('over');
}));
dz.addEventListener('drop', e => {
  e.preventDefault();
  const file = e.dataTransfer.files && e.dataTransfer.files[0];
  if (file) file.text().then(t => { $('#pasteBox').value = t; applyRoster(); });
});

$('#toSortBtn').addEventListener('click', () => goto('sort'));
$('#backToTeamBtn').addEventListener('click', () => goto('team'));
$('#backToListBtn').addEventListener('click', () => goto('list'));
$('#backToSortBtn').addEventListener('click', () => goto('sort'));

/* ── 4. the sorting board ───────────────────────────────────────────────── */

const meKey = () => keyOf(S.account);

function allAssigned() {
  const set = new Set();
  S.assign.forEach(s => s.forEach(k => set.add(k)));
  return set;
}

function channelsOf(key) {
  const names = [];
  S.assign.forEach((set, name) => { if (set.has(key)) names.push(name); });
  return names;
}

function poolKeys() {
  const assigned = allAssigned();
  const me = meKey();
  return Array.from(S.roster.values())
    .filter(p => p.key !== me && !assigned.has(p.key))
    .sort(byName)
    .map(p => p.key);
}

function byName(a, b) {
  return String(a.name || a.upn).localeCompare(String(b.name || b.upn), undefined, { sensitivity: 'base' });
}

function personCard(key, colName) {
  const p = S.roster.get(key);
  if (!p) return '';
  const locked = colName !== '__pool__' && (S.locked.get(colName) || new Set()).has(key);
  const memberships = channelsOf(key).length;

  const tags = [];
  if (locked) tags.push('<span class="tag tag-owner">owner</span>');
  else if (!p.inTeam) tags.push('<span class="tag tag-newteam">joins team</span>');
  else if (!p.onList && S.hasImportedList && !p.isTeamOwner) tags.push('<span class="tag tag-extra">not on list</span>');
  else if (p.isTeamOwner) tags.push('<span class="tag tag-extra">staff</span>');
  // Channel owners are in every channel they own, so the count is noise on them.
  if (memberships > 1 && !locked) {
    tags.push(`<span class="tag tag-multi" title="In ${memberships} channels">in ${memberships}</span>`);
  }

  const hidden = S.filter && !(`${p.name} ${p.upn}`.toLowerCase().includes(S.filter)) ? ' filtered-out' : '';
  const sel = S.selection.has(key) ? ' selected' : '';

  return `<div class="card-person${sel}${hidden}${locked ? ' locked' : ''}"
       draggable="${locked ? 'false' : 'true'}" data-key="${esc(key)}" data-col="${esc(colName)}"
       title="${esc(p.name)} - ${esc(p.upn)}">
    <span class="pname">${esc(p.name)}</span>
    <span class="card-tags">${tags.join('')}</span>
    <button class="card-menu-btn" data-menu="${esc(key)}" aria-label="Channels for ${esc(p.name)}">&hellip;</button>
    <span class="pid">${esc(p.upn)}</span>
  </div>`;
}

function renderBoard() {
  S.hasImportedList = Array.from(S.roster.values()).some(p => p.onList);

  const pool = poolKeys();
  $('#poolCount').textContent = pool.length;
  $('#poolCards').innerHTML = pool.length
    ? pool.map(k => personCard(k, '__pool__')).join('')
    : '<div class="empty-col">Everyone has a channel.</div>';

  $('#boardScroll').innerHTML = S.channels.map(c => {
    const set = S.assign.get(c.name) || new Set();
    const members = Array.from(set).map(k => S.roster.get(k)).filter(Boolean).sort(byName);
    return `<section class="board-col${c.isNew ? ' is-new' : ''}" data-channel="${esc(c.name)}">
      <header>
        <h3 title="${esc(c.name)}">${esc(c.name)}</h3>
        <span class="count">${members.length}</span>
        <span class="col-menu">
          ${c.isNew ? `<button class="icon-btn" data-act="rename" title="Rename">&#9998;</button>
                       <button class="icon-btn" data-act="delete" title="Remove this new channel">&times;</button>`
                    : `<button class="icon-btn" data-act="empty" title="Move everyone out">&#8630;</button>`}
        </span>
      </header>
      <div class="cards" data-dropzone="${esc(c.name)}">
        ${members.length ? members.map(p => personCard(p.key, c.name)).join('')
                         : '<div class="empty-col">Drag people here.</div>'}
      </div>
    </section>`;
  }).join('') || '<div class="empty-col" style="padding:2rem">No private channels yet. Use <strong>+ New private channel</strong>.</div>';

  const unassigned = pool.length;
  $('#sortLede').textContent =
    `${S.teamName} — ${plural(S.channels.length, 'private channel')}, ` +
    `${unassigned ? `${plural(unassigned, 'person', 'people')} still unsorted` : 'everyone sorted'}.`;

  $('#autoGroupBtn').hidden = !S.hasGroupColumn;
  renderSelectionBar();
  if (S.menuState) renderMemberMenu();
}

function channelOptions(placeholder) {
  return `<option value="">${placeholder}</option>` +
    S.channels.map(c => `<option value="${esc(c.name)}">${esc(c.name)}</option>`).join('');
}

function renderSelectionBar() {
  const bar = $('#selectionBar');
  bar.hidden = S.selection.size === 0;
  if (S.selection.size === 0) return;
  $('#selectionCount').textContent = `${plural(S.selection.size, 'person', 'people')} selected`;
  $('#moveToSelect').innerHTML = channelOptions('Choose a channel…') +
    '<option value="__pool__">Not in a channel</option>';
  $('#addToSelect').innerHTML = channelOptions('Choose a channel…');
}

/* membership ------------------------------------------------------------ */

function isLockedIn(key, channel) {
  return (S.locked.get(channel) || new Set()).has(key);
}

/* Put these people in `channel` and take them out of every other one. */
function moveKeys(keys, target) {
  keys.forEach(key => {
    S.assign.forEach((set, name) => {
      if (isLockedIn(key, name)) return;
      set.delete(key);
    });
    if (target !== '__pool__' && S.assign.has(target)) S.assign.get(target).add(key);
  });
}

/* Put these people in `channel` as well, leaving other channels alone. */
function addKeys(keys, target) {
  if (!S.assign.has(target)) return;
  keys.forEach(key => S.assign.get(target).add(key));
}

function setMembership(keys, channel, on) {
  const set = S.assign.get(channel);
  if (!set) return;
  keys.forEach(key => {
    if (on) set.add(key);
    else if (!isLockedIn(key, channel)) set.delete(key);
  });
}

function removeFromEverything(keys) {
  keys.forEach(key => S.assign.forEach((set, name) => {
    if (!isLockedIn(key, name)) set.delete(key);
  }));
}

/* selection ------------------------------------------------------------- */

let lastClickedKey = null;

$('#main').addEventListener('click', e => {
  const card = e.target.closest('.card-person');
  if (!card || !$('[data-panel="sort"]').contains(card)) return;
  if (e.target.closest('.card-menu-btn')) return;   // handled separately
  const key = card.dataset.key;

  if (e.shiftKey && lastClickedKey) {
    const container = card.closest('.cards');
    const keys = $$('.card-person', container).map(c => c.dataset.key);
    const a = keys.indexOf(lastClickedKey), b = keys.indexOf(key);
    if (a >= 0 && b >= 0) {
      keys.slice(Math.min(a, b), Math.max(a, b) + 1).forEach(k => S.selection.add(k));
    } else S.selection.add(key);
  } else if (e.ctrlKey || e.metaKey) {
    if (S.selection.has(key)) S.selection.delete(key); else S.selection.add(key);
  } else {
    const only = S.selection.size === 1 && S.selection.has(key);
    S.selection.clear();
    if (!only) S.selection.add(key);
  }
  lastClickedKey = key;
  renderBoard();
});

$('#clearSelectionBtn').addEventListener('click', () => { S.selection.clear(); renderBoard(); });

$('#moveToSelect').addEventListener('change', e => {
  if (!e.target.value) return;
  moveKeys(Array.from(S.selection), e.target.value);
  S.selection.clear();
  renderBoard();
});

$('#addToSelect').addEventListener('change', e => {
  if (!e.target.value) return;
  const n = S.selection.size;
  addKeys(Array.from(S.selection), e.target.value);
  toast(`${plural(n, 'person', 'people')} are now in "${e.target.value}" as well.`);
  S.selection.clear();
  renderBoard();
});

/* the per-person channel menu ------------------------------------------- */

function renderMemberMenu() {
  const { keys } = S.menuState;
  const menu = $('#memberMenu');
  const many = keys.length > 1;
  const p = S.roster.get(keys[0]);

  const head = many
    ? `<div class="mh-name">${plural(keys.length, 'person', 'people')} selected</div>
       <div class="mh-sub">Ticking a channel applies to all of them</div>`
    : `<div class="mh-name">${esc(p ? p.name : keys[0])}</div>
       <div class="mh-sub">${esc(p ? p.upn : '')}</div>`;

  const rows = S.channels.map(c => {
    const set = S.assign.get(c.name) || new Set();
    const inCount = keys.filter(k => set.has(k)).length;
    const all = inCount === keys.length;
    const some = inCount > 0 && !all;
    const locked = keys.some(k => isLockedIn(k, c.name));
    return `<button class="menu-row${all ? ' on' : ''}" data-channel="${esc(c.name)}"
        ${locked && all ? 'disabled title="Channel owners cannot be removed by Sortinghat"' : ''}>
      <span class="mr-box">${all ? '&check;' : (some ? '&ndash;' : '')}</span>
      <span class="mr-name">${esc(c.name)}</span>
      <span class="mr-only" data-only="${esc(c.name)}" title="Put them in this channel only">only</span>
    </button>`;
  }).join('');

  menu.innerHTML =
    `<div class="menu-head">${head}</div>` +
    (S.channels.length
      ? `<div class="menu-label">In these channels</div>${rows}
         <div class="menu-sep"></div>
         <button class="menu-row danger" data-act="none"><span class="mr-box"></span>
           <span class="mr-name">Take out of every channel</span></button>`
      : '<div class="menu-label">No private channels yet</div>');
  menu.hidden = false;
}

function openMemberMenu(x, y, keys) {
  const list = keys.filter(k => S.roster.has(k));
  if (!list.length) return;
  S.menuState = { keys: list };
  renderMemberMenu();

  const menu = $('#memberMenu');
  const w = menu.offsetWidth, h = menu.offsetHeight;
  const left = Math.min(x, window.scrollX + document.documentElement.clientWidth - w - 8);
  const top = Math.min(y, window.scrollY + document.documentElement.clientHeight - h - 8);
  menu.style.left = Math.max(8, left) + 'px';
  menu.style.top = Math.max(8, top) + 'px';
}

function closeMemberMenu() {
  S.menuState = null;
  $('#memberMenu').hidden = true;
}

function menuTargets(key) {
  return S.selection.has(key) && S.selection.size > 1 ? Array.from(S.selection) : [key];
}

$('#main').addEventListener('click', e => {
  const btn = e.target.closest('.card-menu-btn');
  if (!btn) return;
  e.stopPropagation();
  const r = btn.getBoundingClientRect();
  openMemberMenu(r.left + window.scrollX, r.bottom + window.scrollY + 4, menuTargets(btn.dataset.menu));
});

$('#main').addEventListener('contextmenu', e => {
  const card = e.target.closest('.card-person');
  if (!card || !$('[data-panel="sort"]').contains(card)) return;
  e.preventDefault();
  openMemberMenu(e.pageX, e.pageY, menuTargets(card.dataset.key));
});

$('#memberMenu').addEventListener('click', e => {
  if (!S.menuState) return;
  const keys = S.menuState.keys;

  const only = e.target.closest('[data-only]');
  if (only) {
    moveKeys(keys, only.dataset.only);
    closeMemberMenu();
    S.selection.clear();
    return renderBoard();
  }

  const row = e.target.closest('.menu-row');
  if (!row || row.disabled) return;

  if (row.dataset.act === 'none') {
    removeFromEverything(keys);
    closeMemberMenu();
    S.selection.clear();
    return renderBoard();
  }

  const channel = row.dataset.channel;
  const set = S.assign.get(channel) || new Set();
  const all = keys.every(k => set.has(k));
  setMembership(keys, channel, !all);
  renderBoard();
});

document.addEventListener('click', e => {
  if (!S.menuState) return;
  if (e.target.closest('#memberMenu') || e.target.closest('.card-menu-btn')) return;
  closeMemberMenu();
});
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeMemberMenu(); });

/* drag and drop --------------------------------------------------------- */

let dragKeys = [];

$('#main').addEventListener('dragstart', e => {
  const card = e.target.closest('.card-person');
  if (!card || card.classList.contains('locked')) return;
  closeMemberMenu();
  const key = card.dataset.key;
  dragKeys = S.selection.has(key) && S.selection.size > 1 ? Array.from(S.selection) : [key];
  card.classList.add('dragging');
  try {
    e.dataTransfer.effectAllowed = 'copyMove';
    e.dataTransfer.setData('text/plain', dragKeys.join(','));
  } catch (err) { /* older browsers */ }
});

$('#main').addEventListener('dragend', e => {
  const card = e.target.closest('.card-person');
  if (card) card.classList.remove('dragging');
  $$('.board-col.drag-over').forEach(c => c.classList.remove('drag-over'));
});

const wantsCopy = e => e.ctrlKey || e.altKey || e.metaKey;

$('#main').addEventListener('dragover', e => {
  const zone = e.target.closest('[data-dropzone]');
  if (!zone || !dragKeys.length) return;
  e.preventDefault();
  e.dataTransfer.dropEffect =
    (wantsCopy(e) && zone.dataset.dropzone !== '__pool__') ? 'copy' : 'move';
  const col = zone.closest('.board-col');
  $$('.board-col.drag-over').forEach(c => { if (c !== col) c.classList.remove('drag-over'); });
  if (col) col.classList.add('drag-over');
});

$('#main').addEventListener('drop', e => {
  const zone = e.target.closest('[data-dropzone]');
  if (!zone) return;
  e.preventDefault();
  let keys = dragKeys;
  if (!keys.length) {
    const text = (e.dataTransfer.getData('text/plain') || '').trim();
    keys = text ? text.split(',') : [];
  }
  const target = zone.dataset.dropzone;

  if (wantsCopy(e) && target !== '__pool__') {
    addKeys(keys, target);
    toast(`${plural(keys.length, 'person', 'people')} added to "${target}" as well.`);
  } else {
    moveKeys(keys, target);
  }

  dragKeys = [];
  S.selection.clear();
  renderBoard();
});

/* board tools ----------------------------------------------------------- */

$('#personSearch').addEventListener('input', e => {
  S.filter = e.target.value.trim().toLowerCase();
  renderBoard();
});

$('#boardScroll').addEventListener('click', async e => {
  const btn = e.target.closest('.icon-btn');
  if (!btn) return;
  const name = btn.closest('.board-col').dataset.channel;
  const channel = S.channels.find(c => c.name === name);
  if (!channel) return;
  closeMemberMenu();

  if (btn.dataset.act === 'delete') {
    S.channels = S.channels.filter(c => c.name !== name);
    S.assign.delete(name); S.original.delete(name); S.locked.delete(name);
    renderBoard();
  } else if (btn.dataset.act === 'empty') {
    const locked = S.locked.get(name) || new Set();
    S.assign.set(name, new Set(Array.from(S.assign.get(name) || []).filter(k => locked.has(k))));
    renderBoard();
  } else if (btn.dataset.act === 'rename') {
    const value = await askDialog({
      title: 'Rename this channel', label: 'Channel name', value: name, okText: 'Rename'
    });
    if (!value || value === name) return;
    if (S.channels.some(c => c.name.toLowerCase() === value.toLowerCase())) {
      return toast('There is already a channel with that name.');
    }
    ['assign', 'original', 'locked'].forEach(m => {
      S[m].set(value, S[m].get(name)); S[m].delete(name);
    });
    channel.name = value;
    renderBoard();
  }
});

const BAD_CHANNEL_CHARS = /[#%&*{}/\\:<>?+|'"]/;

function addChannel(name, silent) {
  name = String(name || '').trim();
  if (!name) return null;
  if (name.length > 50) { if (!silent) toast('Channel names must be 50 characters or fewer.'); return null; }
  if (BAD_CHANNEL_CHARS.test(name)) {
    if (!silent) toast('Teams does not allow  # % & * { } / \\ : < > ? + | \' "  in a channel name.');
    return null;
  }
  if (S.channels.some(c => c.name.toLowerCase() === name.toLowerCase())) {
    if (!silent) toast('There is already a channel with that name.');
    return null;
  }
  const me = meKey();
  if (me && !S.roster.has(me)) {
    S.roster.set(me, { key: me, upn: S.account, name: S.account.split('@')[0],
      zid: '', inTeam: true, isTeamOwner: true, onList: false, group: '' });
  }
  S.channels.push({ name, id: '', description: '', isNew: true });
  S.original.set(name, new Set(me ? [me] : []));
  S.assign.set(name, new Set(me ? [me] : []));
  S.locked.set(name, new Set(me ? [me] : []));
  return name;
}

$('#addChannelBtn').addEventListener('click', async () => {
  const name = await askDialog({
    title: 'New private channel',
    message: 'It will be created in ' + S.teamName + ' when you apply. You become its owner.',
    label: 'Channel name', value: '', okText: 'Add'
  });
  if (name && addChannel(name)) renderBoard();
});

$('#distributeBtn').addEventListener('click', async () => {
  const pool = poolKeys();
  if (!pool.length) return toast('Everyone is already in a channel.');

  const countText = await askDialog({
    title: 'Spread people evenly',
    message: `${plural(pool.length, 'person', 'people')} are not in a channel yet. How many channels should they share?`,
    label: 'Number of channels', value: String(Math.max(2, S.channels.length || 4)), okText: 'Next'
  });
  if (!countText) return;
  const count = parseInt(countText, 10);
  if (!(count > 0)) return toast('Give a number greater than zero.');

  const prefix = await askDialog({
    title: 'What are they called?',
    message: 'Existing channels with these names are reused. Missing ones are created.',
    label: 'Name pattern', value: 'Group', okText: 'Spread them'
  });
  if (prefix === null) return;

  const targets = [];
  for (let i = 1; i <= count; i++) {
    const name = `${(prefix || 'Group').trim()} ${i}`;
    if (!S.channels.some(c => c.name.toLowerCase() === name.toLowerCase())) {
      if (!addChannel(name)) return renderBoard();
    }
    targets.push(S.channels.find(c => c.name.toLowerCase() === name.toLowerCase()).name);
  }

  pool.forEach((key, i) => moveKeys([key], targets[i % targets.length]));
  renderBoard();
  toast(`Spread ${plural(pool.length, 'person', 'people')} across ${plural(targets.length, 'channel')}.`);
});

$('#autoGroupBtn').addEventListener('click', () => {
  let placed = 0, madeChannels = 0;
  Array.from(S.roster.values()).forEach(p => {
    if (!p.group) return;
    let name = p.group.trim();
    const existing = S.channels.find(c => c.name.toLowerCase() === name.toLowerCase());
    if (existing) name = existing.name;
    else if (addChannel(name, true)) madeChannels++;
    else return;
    moveKeys([p.key], name);
    placed++;
  });
  renderBoard();
  toast(placed
    ? `Placed ${plural(placed, 'person', 'people')} from the group column${madeChannels ? `, creating ${plural(madeChannels, 'channel')}` : ''}.`
    : 'No group values could be used.');
});

$('#resetBoardBtn').addEventListener('click', async () => {
  const ok = await askDialog({
    title: 'Undo all your changes?',
    message: 'The board goes back to how the team looks in Teams right now. Nothing that has already been applied is undone.',
    okText: 'Undo'
  });
  if (ok === null) return;
  S.channels = S.channels.filter(c => !c.isNew);
  S.assign = new Map();
  S.channels.forEach(c => S.assign.set(c.name, new Set(S.original.get(c.name) || [])));
  Array.from(S.original.keys()).forEach(n => { if (!S.assign.has(n)) { S.original.delete(n); S.locked.delete(n); } });
  S.selection.clear();
  closeMemberMenu();
  renderBoard();
});

$('#toReviewBtn').addEventListener('click', () => { closeMemberMenu(); goto('review'); });


/* ── 5. review and apply ────────────────────────────────────────────────── */

function personName(key) {
  const p = S.roster.get(key);
  return p ? `${p.name} (${p.upn})` : key;
}

function buildOps() {
  const ops = [];
  const me = meKey();

  S.channels.filter(c => c.isNew).forEach(c => {
    ops.push({ type: 'createChannel', groupId: S.teamId, channel: c.name,
      description: c.description || '', person: '',
      label: `Create the private channel "${c.name}"` });
  });

  const needTeam = new Set();
  S.assign.forEach(set => set.forEach(k => {
    const p = S.roster.get(k);
    if (p && !p.inTeam) needTeam.add(k);
  }));
  Array.from(needTeam).sort().forEach(k => {
    ops.push({ type: 'addTeamUser', groupId: S.teamId, channel: '', user: S.roster.get(k).upn,
      person: personName(k), label: `Add ${personName(k)} to the team` });
  });

  S.channels.forEach(c => {
    const orig = S.original.get(c.name) || new Set();
    const cur = S.assign.get(c.name) || new Set();
    Array.from(cur).filter(k => !orig.has(k) && k !== me).sort().forEach(k => {
      ops.push({ type: 'addChannelUser', groupId: S.teamId, channel: c.name, user: S.roster.get(k).upn,
        person: personName(k), label: `Add ${personName(k)} to "${c.name}"` });
    });
  });

  S.channels.forEach(c => {
    const orig = S.original.get(c.name) || new Set();
    const cur = S.assign.get(c.name) || new Set();
    const locked = S.locked.get(c.name) || new Set();
    Array.from(orig).filter(k => !cur.has(k) && !locked.has(k)).sort().forEach(k => {
      ops.push({ type: 'removeChannelUser', groupId: S.teamId, channel: c.name, user: S.roster.get(k).upn,
        person: personName(k), label: `Remove ${personName(k)} from "${c.name}"` });
    });
  });

  return ops;
}

function buildWarnings(ops) {
  const warnings = [];

  if (!S.youAreOwner) {
    warnings.push({ level: 'error', text:
      'You are not an owner of this team, so Teams will refuse most of these changes. ' +
      'Ask a team owner to make you an owner first.' });
  }

  const removals = ops.filter(o => o.type === 'removeChannelUser');
  if (removals.length) {
    warnings.push({ level: 'warn', text:
      `${plural(removals.length, 'person', 'people')} will lose access to a private channel, ` +
      'including everything already posted there. Check the removals below before you apply.' });
  }

  const strangers = new Set();
  if (S.hasImportedList) {
    S.assign.forEach((set, name) => set.forEach(k => {
      const p = S.roster.get(k);
      if (p && !p.onList && !p.isTeamOwner && k !== meKey()) strangers.add(k);
    }));
    if (strangers.size) {
      const n = strangers.size;
      warnings.push({ level: 'info', text:
        `${plural(n, 'person', 'people')} in these channels ${n === 1 ? 'is' : 'are'} not on the class list ` +
        'you pasted (tutors, or students who have dropped). They are left exactly as they are.' });
    }
  }

  const empties = S.channels.filter(c => {
    const cur = S.assign.get(c.name) || new Set();
    const locked = S.locked.get(c.name) || new Set();
    return Array.from(cur).every(k => locked.has(k));
  });
  if (empties.length) {
    warnings.push({ level: 'info', text:
      `${plural(empties.length, 'channel')} will have no students in ${empties.length === 1 ? 'it' : 'them'}: ` +
      empties.map(c => `"${c.name}"`).join(', ') + '.' });
  }

  const unsorted = poolKeys().length;
  if (unsorted) {
    warnings.push({ level: 'info', text:
      `${plural(unsorted, 'person', 'people')} ${unsorted === 1 ? 'is' : 'are'} still not in any channel. ` +
      'Nothing happens to them.' });
  }

  const slow = ops.length * 2;
  if (ops.length > 40) {
    warnings.push({ level: 'info', text:
      `This is ${plural(ops.length, 'step')}. Teams is slow to accept changes, so allow roughly ` +
      `${Math.ceil(slow / 60)} minute${Math.ceil(slow / 60) === 1 ? '' : 's'}. Leave this window open.` });
  }

  return warnings;
}

function renderReview() {
  S.ops = buildOps();
  const warnings = buildWarnings(S.ops);

  $('#reviewWarnings').innerHTML = warnings.map(w =>
    `<div class="notice notice-${w.level === 'error' ? 'error' : (w.level === 'warn' ? 'warn' : '')}">${esc(w.text)}</div>`
  ).join('');

  $('#applyPanel').hidden = true;
  $('#applyActions').hidden = false;
  $('#applyBtn').disabled = S.ops.length === 0;

  if (!S.ops.length) {
    $('#reviewBody').innerHTML =
      '<p class="review-empty">Nothing to change &mdash; the board already matches Teams.</p>';
    return;
  }

  const groups = [];
  const creates = S.ops.filter(o => o.type === 'createChannel');
  if (creates.length) {
    groups.push({ title: `Create ${plural(creates.length, 'private channel')}`,
      what: 'You become the owner.',
      items: creates.map(o => o.channel) });
  }
  const joins = S.ops.filter(o => o.type === 'addTeamUser');
  if (joins.length) {
    groups.push({ title: `Add ${plural(joins.length, 'person', 'people')} to the team`,
      what: 'Teams requires this before anyone can be put in a private channel.',
      items: joins.map(o => o.person) });
  }
  S.channels.forEach(c => {
    const adds = S.ops.filter(o => o.type === 'addChannelUser' && o.channel === c.name);
    const rems = S.ops.filter(o => o.type === 'removeChannelUser' && o.channel === c.name);
    if (!adds.length && !rems.length) return;
    const bits = [];
    if (adds.length) bits.push(`add ${plural(adds.length, 'person', 'people')}`);
    if (rems.length) bits.push(`remove ${plural(rems.length, 'person', 'people')}`);
    groups.push({
      title: c.name + (c.isNew ? ' (new)' : ''),
      what: bits.join(', ').replace(/^./, m => m.toUpperCase()) + '.',
      items: adds.map(o => '+ ' + o.person).concat(rems.map(o => '− ' + o.person))
    });
  });

  $('#reviewBody').innerHTML = groups.map(g => `
    <div class="review-group">
      <h3>${esc(g.title)}</h3>
      <div class="what">${esc(g.what)}</div>
      <ul>${g.items.map(i => `<li>${esc(i)}</li>`).join('')}</ul>
    </div>`).join('') +
    `<p class="muted">${plural(S.ops.length, 'step')} in total.</p>`;
}

/* applying -------------------------------------------------------------- */

function logLine(cls, text) {
  const el = document.createElement('div');
  el.className = cls;
  el.textContent = text;
  $('#applyLog').appendChild(el);
  $('#applyLog').scrollTop = $('#applyLog').scrollHeight;
}

async function runOps(ops, isRetry) {
  $('#applyActions').hidden = true;
  $('#applyPanel').hidden = false;
  $('#applyFooter').hidden = true;
  $('#retryBtn').hidden = true;
  $('#applyTitle').textContent = isRetry ? 'Retrying the failed steps' : 'Applying changes to Teams';
  if (!isRetry) { $('#applyLog').innerHTML = ''; S.results = []; }
  logLine('l-head', `${isRetry ? 'Retry' : 'Start'} — ${new Date().toLocaleTimeString()} — ${ops.length} steps`);

  const failed = [];
  for (let i = 0; i < ops.length; i++) {
    const op = ops[i];
    const pct = Math.round((i / ops.length) * 100);
    $('#progressBar').style.width = pct + '%';
    $('#progressText').textContent = `Step ${i + 1} of ${ops.length}: ${op.label}`;

    let res;
    try {
      res = await api('POST', '/api/op', { op: op });
    } catch (err) {
      res = { ok: false, message: err.message };
    }

    const outcome = res.ok ? (res.skipped ? 'skipped' : 'done') : 'failed';
    if (outcome === 'failed') failed.push(op);

    logLine(res.ok ? (res.skipped ? 'l-skip' : 'l-ok') : 'l-fail',
      `${outcome === 'done' ? '✓' : outcome === 'skipped' ? '–' : '✗'} ${op.label}` +
      (res.message ? ` — ${res.message}` : ''));

    S.results.push({
      time: new Date().toLocaleString(), action: op.label, channel: op.channel || '',
      person: op.person || '', result: outcome, detail: res.message || ''
    });

    if (res.ok) applyOptimistically(op);
  }

  $('#progressBar').style.width = '100%';
  const done = S.results.filter(r => r.result === 'done').length;
  const skipped = S.results.filter(r => r.result === 'skipped').length;

  $('#applyTitle').textContent = failed.length ? 'Finished with some problems' : 'All done';
  $('#progressText').textContent =
    `${done} applied` + (skipped ? `, ${skipped} already in place` : '') +
    (failed.length ? `, ${failed.length} failed` : '') +
    '. Teams can take a minute or two to show the changes.';
  logLine('l-head', `Finished — ${new Date().toLocaleTimeString()}`);

  $('#applyFooter').hidden = false;
  $('#retryBtn').hidden = failed.length === 0;
  S.failedOps = failed;

  try {
    const r = await api('POST', '/api/report', { rows: S.results, label: S.teamName });
    if (r.ok) logLine('l-skip', `Report saved to ${r.path}`);
  } catch (e) { /* the download button still works */ }

  if (!failed.length) toast('Done. Refresh Teams to see the channels.', 5000);
}

function applyOptimistically(op) {
  const k = keyOf(op.user);
  if (op.type === 'createChannel') {
    const c = S.channels.find(x => x.name === op.channel);
    if (c) c.isNew = false;
  } else if (op.type === 'addTeamUser') {
    const p = S.roster.get(k); if (p) p.inTeam = true;
  } else if (op.type === 'addChannelUser') {
    (S.original.get(op.channel) || new Set()).add(k);
  } else if (op.type === 'removeChannelUser') {
    const set = S.original.get(op.channel); if (set) set.delete(k);
  }
}

$('#applyBtn').addEventListener('click', async () => {
  const removals = S.ops.filter(o => o.type === 'removeChannelUser').length;
  const ok = await askDialog({
    title: 'Apply these changes to Teams?',
    message: `${plural(S.ops.length, 'step')} will run against "${S.teamName}"` +
      (removals ? `, including ${plural(removals, 'removal')} that cannot be undone from here.` : '.'),
    okText: 'Apply'
  });
  if (ok === null) return;
  await runOps(S.ops, false);
});

$('#retryBtn').addEventListener('click', () => runOps(S.failedOps || [], true));

$('#downloadReportBtn').addEventListener('click', () => {
  const header = ['Time', 'Action', 'Channel', 'Person', 'Result', 'Detail'];
  const cell = v => `"${String(v === null || v === undefined ? '' : v).replace(/"/g, '""')}"`;
  const csv = [header.join(',')]
    .concat(S.results.map(r => [r.time, r.action, r.channel, r.person, r.result, r.detail].map(cell).join(',')))
    .join('\r\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `sortinghat-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.csv`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
});

$('#openReportsBtn').addEventListener('click', async () => {
  try { await api('POST', '/api/open-reports', {}); } catch (e) { toast('Could not open the folder.'); }
});

$('#reloadTeamBtn').addEventListener('click', async () => {
  goto('list');
  await loadTeamContents();
  applyRoster();
  toast('Reloaded from Teams.');
});

/* ── start ──────────────────────────────────────────────────────────────── */

(async function start() {
  if (!SESSION_KEY) {
    document.body.innerHTML =
      '<div style="padding:3rem;max-width:34rem;margin:auto;font:15px system-ui">' +
      '<h1 style="font-size:1.25rem">This page was opened without its one-time key.</h1>' +
      '<p style="color:#5c6675">Go back to the Sortinghat console window and use the link printed there.</p></div>';
    return;
  }
  try {
    const st = await refreshState();
    if (st.connected) { goto('team'); loadTeams(); }
    else goto('signin');
  } catch (err) {
    goto('signin');
    $('#signinError').textContent = err.message;
    $('#signinError').hidden = false;
  }
})();
