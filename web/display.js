let ws = null;
let reconnect = false;
let reconnectDelayMs = 800;
let timerId = null;
let timerFrameId = null;
let timerKey = null;
let timerDeadlineMs = 0;
let timerDurationMs = 1;
let activeController = null;
let lastStateUpdatedAtMs = 0;
let gameStartingLineTimers = [];
let voteRevealTimers = [];
let voteRevealRenderToken = 0;
let autoScrollTasks = [];
let lobbyTransitionTimers = [];
let gameSummaryRevealTimers = [];
let gameSummaryRevealToken = 0;

const transitionCoordinator = {
  token: 0,
  nextToken() {
    this.token += 1;
    return this.token;
  },
  isCurrent(token) {
    return token === this.token;
  },
};

function byId(id) {
  return document.getElementById(id);
}

function escapeHtml(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function storeRoom(room) {
  localStorage.setItem('superlatives_display_room', room);
}

function restoreRoom() {
  let room = localStorage.getItem('superlatives_display_room');
  if (room && !byId('login-room').value) {
    byId('login-room').value = room;
  }
}

function send(obj) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return;
  }
  ws.send(JSON.stringify(obj));
}

function connect() {
  let room = byId('login-room').value.trim();
  if (!room) {
    showError('Room is required.');
    return;
  }

  reconnect = true;
  storeRoom(room);

  if (ws) {
    ws.close();
  }

  ws = new WebSocket(
    (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'
  );

  ws.onopen = function () {
    send({
      event: 'login',
      room: room,
      role: 'display'
    });
  };

  ws.onmessage = handleMessage;
  ws.onclose = function () {
    ws = null;
    if (reconnect) {
      setTimeout(function () {
        if (reconnect) {
          connect();
        }
      }, reconnectDelayMs);
    } else {
      showScreen('screen-login');
    }
  };
}

function handleMessage(event) {
  let envelope = JSON.parse(event.data);
  if (!envelope || typeof envelope.event !== 'string') {
    return;
  }

  if (envelope.event === 'error') {
    let payload = envelope.payload || {};
    showError(payload.message || 'Unknown server error.');
    return;
  }

  if (envelope.event === 'ping') {
    send({ event: 'pong' });
    return;
  }

  if (envelope.event === 'disconnect') {
    reconnect = false;
    return;
  }

  if (envelope.event === 'state') {
    applyState(envelope.payload || {});
  }
}

function showScreen(id) {
  let screens = document.querySelectorAll('.screen');
  for (let i = 0; i < screens.length; i++) {
    screens[i].classList.remove('active', 'screen-enter');
  }

  let screen = byId(id);
  if (!screen) {
    return;
  }

  screen.classList.add('active', 'screen-enter');
  requestAnimationFrame(function () {
    screen.classList.remove('screen-enter');
  });
}

function showError(msg) {
  byId('error-text').textContent = msg;
  showScreen('screen-error');
}

function clearTimer() {
  if (timerId) {
    clearInterval(timerId);
    timerId = null;
  }
  if (timerFrameId) {
    cancelAnimationFrame(timerFrameId);
    timerFrameId = null;
  }
  timerKey = null;
  timerDeadlineMs = 0;
  timerDurationMs = 1;
  byId('display-timer-text').textContent = '';
  setTimerBarWidth(0);
  setTimerVisible(false);
}

function setTimerVisible(visible) {
  document.body.classList.toggle('display-timer-visible', !!visible);
}

function setTimerBarWidth(percent) {
  let bar = byId('display-timer-bar');
  if (!bar) {
    return;
  }
  let clamped = Math.max(0, Math.min(100, percent));
  bar.style.width = `${clamped}%`;
}

function renderTimerFrame() {
  let nowMs = Date.now();
  let remainingMs = Math.max(0, timerDeadlineMs - nowMs);
  let seconds = Math.ceil(remainingMs / 1000);
  let label = `:${String(seconds).padStart(2, '0')}`;
  let percent = timerDurationMs <= 0 ? 0 : (remainingMs / timerDurationMs) * 100;
  byId('display-timer-text').textContent = label;
  setTimerBarWidth(percent);

  if (remainingMs <= 0) {
    timerFrameId = null;
    return;
  }

  timerFrameId = requestAnimationFrame(renderTimerFrame);
}

function attachTimer(initialSeconds, options = {}) {
  if (initialSeconds === null || initialSeconds === undefined) {
    clearTimer();
    return;
  }

  let nextKey = options.key || null;
  let nowMs = Date.now();
  let nextSeconds = Math.max(0, Number(initialSeconds) || 0);
  let nextDeadlineMs = Number(options.deadlineMs);
  if (!Number.isFinite(nextDeadlineMs) || nextDeadlineMs <= 0) {
    nextDeadlineMs = nowMs + (nextSeconds * 1000);
  }
  let shouldRestart = !timerFrameId || timerKey !== nextKey;
  if (!shouldRestart) {
    timerDeadlineMs = nextDeadlineMs;
    timerDurationMs = Math.max(timerDurationMs, Math.max(1, nextDeadlineMs - nowMs));
    setTimerVisible(true);
    return;
  }

  if (timerFrameId) {
    cancelAnimationFrame(timerFrameId);
    timerFrameId = null;
  }
  timerDurationMs = Math.max(1, nextDeadlineMs - nowMs);

  timerKey = nextKey;
  timerDeadlineMs = nextDeadlineMs;
  setTimerVisible(true);
  renderTimerFrame();
}

function clearGameStartingTimers() {
  for (let i = 0; i < gameStartingLineTimers.length; i++) {
    clearTimeout(gameStartingLineTimers[i]);
  }
  gameStartingLineTimers = [];
}

function clearVoteRevealTimers() {
  for (let i = 0; i < voteRevealTimers.length; i++) {
    clearTimeout(voteRevealTimers[i]);
  }
  voteRevealTimers = [];
}

function clearAutoScrollTasks() {
  for (let i = 0; i < autoScrollTasks.length; i++) {
    autoScrollTasks[i]();
  }
  autoScrollTasks = [];
}

function clearTransientEffects() {
  clearGameStartingTimers();
  clearVoteRevealTimers();
  clearAutoScrollTasks();
  clearLobbyTransitionTimers();
  clearGameSummaryRevealTimers();
}

function clearLobbyTransitionTimers() {
  for (let i = 0; i < lobbyTransitionTimers.length; i++) {
    clearTimeout(lobbyTransitionTimers[i]);
  }
  lobbyTransitionTimers = [];
}

function clearGameSummaryRevealTimers() {
  for (let i = 0; i < gameSummaryRevealTimers.length; i++) {
    clearTimeout(gameSummaryRevealTimers[i]);
  }
  gameSummaryRevealTimers = [];
}

function preloadDisplayAssets(urls) {
  if (!urls || !urls.length) {
    return Promise.resolve();
  }

  return Promise.all(urls.map(function (url) {
    return new Promise(function (resolve) {
      let img = new Image();
      img.onload = resolve;
      img.onerror = resolve;
      img.src = url;
    });
  })).then(function () {
    return true;
  });
}

function initialsForName(name) {
  if (!name) {
    return '?';
  }
  let parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) {
    return '?';
  }
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function normalizeStateLabel(state) {
  if (!state) {
    return '';
  }
  return String(state).replace(/_/g, ' ').toUpperCase();
}

function canonicalizeRenderPayload(value) {
  if (value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(canonicalizeRenderPayload);
  }
  if (typeof value !== 'object') {
    return value;
  }

  let out = {};
  Object.keys(value).sort().forEach(function (key) {
    if (key === 'updatedAt' || key === 'timeoutSeconds' || key === 'timeoutAtMs') {
      return;
    }
    out[key] = canonicalizeRenderPayload(value[key]);
  });
  return out;
}

function defaultRenderKey(payload) {
  return JSON.stringify(canonicalizeRenderPayload(payload));
}

function setPhaseTheme(phaseName) {
  let body = document.body;
  body.classList.remove('phase-lobby', 'phase-in-game', 'phase-game-summary');
  if (phaseName === 'Lobby') {
    body.classList.add('phase-lobby');
    return;
  }
  if (phaseName === 'GameSummary') {
    body.classList.add('phase-game-summary');
    return;
  }
  body.classList.add('phase-in-game');
}

function renderPlayers(players) {
  let html = '';
  players.forEach(function (p, index) {
    if (p.role !== 'player') {
      return;
    }
    let initials = escapeHtml(initialsForName(p.displayName));
    let stateLabel = normalizeStateLabel(p.state);
    let displayName = escapeHtml(p.displayName || '');
    html += `
      <article class="card player-card" style="animation-delay:${index * 70}ms">
        <div class="player-avatar" aria-hidden="true">${initials}</div>
        <div class="player-meta">
          <strong class="player-name">${displayName}</strong>
          <span class="player-state">${escapeHtml(stateLabel)}</span>
        </div>
      </article>
    `;
  });
  return html;
}

function renderEntries(entries, options = {}) {
  let html = '';
  let showOwner = !!options.showOwner;
  entries.forEach(function (e, index) {
    let owner = showOwner ? (e.ownerDisplayName || '') : '';
    let ownerLine = owner
      ? `<span class="muted entry-owner">Submitted by ${escapeHtml(owner)}</span>`
      : '';
    let status = e.status
      ? `<span class="entry-status">${escapeHtml(normalizeStateLabel(e.status))}</span>`
      : '';
    html += `
      <article class="card entry-card" style="animation-delay:${index * 55}ms">
        <strong class="entry-text">${escapeHtml(e.text || '')}</strong>
        <div class="entry-meta">${status}${ownerLine}</div>
      </article>
    `;
  });
  return html;
}

function renderReveal(entries, results, roundPointsByEntry) {
  let html = '';
  entries.forEach(function (e, index) {
    let votes = (results.voteCountByEntry && results.voteCountByEntry[e.entryId]) || 0;
    let points = (results.pointsByEntry && results.pointsByEntry[e.entryId]) || 0;
    let roundPoints = (roundPointsByEntry && roundPointsByEntry[e.entryId]) || 0;
    html += `
      <article class="card reveal-card" style="animation-delay:${index * 55}ms">
        <strong class="entry-text">${escapeHtml(e.text || '')}</strong>
        <div class="reveal-metrics">
          <span>${votes} votes</span>
          <span>+${points} this set</span>
          <span>${roundPoints} round total</span>
        </div>
      </article>
    `;
  });
  return html;
}

function renderRevealTopThree(entries, results) {
  let ranked = (entries || []).map(function (entry) {
    let votes = (results.voteCountByEntry && results.voteCountByEntry[entry.entryId]) || 0;
    let points = (results.pointsByEntry && results.pointsByEntry[entry.entryId]) || 0;
    return {
      entryId: entry.entryId,
      text: entry.text || '',
      votes: votes,
      points: points,
    };
  }).filter(function (row) {
    return row.votes > 0;
  });

  ranked.sort(function (a, b) {
    if (b.votes !== a.votes) {
      return b.votes - a.votes;
    }
    return String(a.entryId).localeCompare(String(b.entryId));
  });

  let top = ranked.slice(0, 3);
  if (!top.length) {
    return '<p class="muted">No votes recorded for this prompt.</p>';
  }

  return `
    <div class="reveal-top-grid">
      ${top.map(function (row, index) {
    return `
          <article class="card reveal-top-card" style="animation-delay:${index * 140}ms">
            <span class="board-rank">#${index + 1}</span>
            <strong class="entry-text">${escapeHtml(row.text)}</strong>
            <span class="float">+${row.points}</span>
          </article>
        `;
  }).join('')}
    </div>
  `;
}

function renderRoundStandings(entries, results, roundPointsByEntry) {
  let ranked = (entries || []).map(function (entry) {
    let setPoints = (results.pointsByEntry && results.pointsByEntry[entry.entryId]) || 0;
    let roundPoints = (roundPointsByEntry && roundPointsByEntry[entry.entryId]) || 0;
    return {
      entryId: entry.entryId,
      text: entry.text || '',
      status: entry.status || '',
      setPoints: setPoints,
      roundPoints: roundPoints,
    };
  });

  ranked.sort(function (a, b) {
    if (b.roundPoints !== a.roundPoints) {
      return b.roundPoints - a.roundPoints;
    }
    if (b.setPoints !== a.setPoints) {
      return b.setPoints - a.setPoints;
    }
    return String(a.entryId).localeCompare(String(b.entryId));
  });

  return ranked.map(function (row, index) {
    let eliminated = row.status && row.status !== 'active';
    return `
      <article class="card reveal-standing-card${eliminated ? ' is-eliminated' : ''}" style="animation-delay:${index * 60}ms">
        <span class="board-rank">#${index + 1}</span>
        <strong class="entry-text">${escapeHtml(row.text)}</strong>
        <span class="reveal-metrics">
          <span>${row.roundPoints} total</span>
          <span>+${row.setPoints} this reveal</span>
          <span>${escapeHtml(normalizeStateLabel(row.status || 'active'))}</span>
        </span>
      </article>
    `;
  }).join('');
}

function renderBoard(rows) {
  let html = '';
  rows.forEach(function (r, index) {
    html += `
      <article class="card board-card" style="animation-delay:${index * 60}ms">
        <span class="board-rank">#${index + 1}</span>
        <strong class="board-name">${escapeHtml(r.displayName || '')}</strong>
        <span class="board-score">${r.score}</span>
      </article>
    `;
  });
  return html;
}

function promptStripKey(prompts) {
  return JSON.stringify((prompts || []).slice(0, 3).map(function (s) {
    return `${s.superlativeId || ''}:${s.promptText || ''}`;
  }));
}

function renderPromptStripIfChanged(containerId, prompts) {
  let node = byId(containerId);
  if (!node) {
    return;
  }
  let key = promptStripKey(prompts);
  if (node.dataset.promptKey === key) {
    return;
  }
  node.innerHTML = renderPromptStrip(prompts || []);
  node.dataset.promptKey = key;
}

function reconcileProgressCards(containerId, players, completedPlayerIds) {
  let container = byId(containerId);
  if (!container) {
    return;
  }

  let completed = new Set(completedPlayerIds || []);
  let activePlayers = (players || []).filter(function (p) {
    return p.role === 'player';
  });
  let nextIds = new Set(activePlayers.map(function (p) { return p.playerId; }));
  let existingCards = Array.from(container.querySelectorAll('.player-card[data-player-id]'));
  let existingById = new Map(existingCards.map(function (node) {
    return [node.dataset.playerId, node];
  }));
  let fragment = document.createDocumentFragment();

  activePlayers.forEach(function (p) {
    let done = completed.has(p.playerId);
    let doneClass = done ? 'is-complete' : 'is-pending';
    let doneText = done ? 'READY' : 'WAITING';
    let node = existingById.get(p.playerId);

    if (!node) {
      node = document.createElement('article');
      node.className = `card player-card progress-card ${doneClass}`;
      node.dataset.playerId = p.playerId;
      node.innerHTML = `
        <div class="player-avatar" aria-hidden="true">${escapeHtml(initialsForName(p.displayName))}</div>
        <div class="player-meta">
          <strong class="player-name">${escapeHtml(p.displayName || '')}</strong>
          <span class="player-state">${doneText}</span>
        </div>
      `;
    } else {
      node.classList.remove('is-complete', 'is-pending');
      node.classList.add(doneClass);
      let avatarNode = node.querySelector('.player-avatar');
      let nameNode = node.querySelector('.player-name');
      let stateNode = node.querySelector('.player-state');
      if (avatarNode) {
        avatarNode.textContent = initialsForName(p.displayName);
      }
      if (nameNode) {
        nameNode.textContent = p.displayName || '';
      }
      if (stateNode) {
        stateNode.textContent = doneText;
      }
    }

    fragment.appendChild(node);
  });

  container.appendChild(fragment);

  existingCards.forEach(function (node) {
    if (!nextIds.has(node.dataset.playerId)) {
      node.remove();
    }
  });
}

function renderPromptStrip(prompts) {
  let visible = (prompts || []).slice(0, 3);
  return visible.map(function (s, index) {
    return `
      <article class="card superlative-card" style="animation-delay:${index * 60}ms">
        <span class="superlative-index">${index + 1}</span>
        <span class="superlative-text">${escapeHtml(s.promptText || '')}</span>
      </article>
    `;
  }).join('');
}

function renderRoundSummaryRows(rows) {
  let html = '';
  rows.forEach(function (r, index) {
    let entryText = r.entryText || '-';
    html += `
      <article class="card round-summary-card" style="animation-delay:${index * 55}ms">
        <div class="player-avatar" aria-hidden="true">${escapeHtml(initialsForName(r.displayName))}</div>
        <div class="round-summary-main">
          <strong class="player-name">${escapeHtml(r.displayName || '')}</strong>
          <span class="round-entry">"${escapeHtml(entryText)}"</span>
          <span class="round-points">Round: +${Number(r.pointsThisRound || 0)}</span>
        </div>
        <div class="round-summary-score">${Number(r.totalScore || 0)}</div>
      </article>
    `;
  });
  return html;
}

function renderPodium(board) {
  let top3 = (board || []).slice(0, 3);
  let slots = ['third', 'first', 'second'];
  let ordered = [];
  if (top3[2]) {
    ordered.push({ row: top3[2], slot: slots[0], delay: 0 });
  }
  if (top3[0]) {
    ordered.push({ row: top3[0], slot: slots[1], delay: 2 });
  }
  if (top3[1]) {
    ordered.push({ row: top3[1], slot: slots[2], delay: 1 });
  }
  return ordered.map(function (item) {
    return `
      <article class="card podium-card podium-${item.slot}" style="animation-delay:${item.delay * 160}ms">
        <div class="player-avatar" aria-hidden="true">${escapeHtml(initialsForName(item.row.displayName))}</div>
        <strong class="podium-name">${escapeHtml(item.row.displayName || '')}</strong>
        <span class="podium-score">${Number(item.row.score || 0)} pts</span>
      </article>
    `;
  }).join('');
}

function scheduleAutoScroll(containerId, delayMs = 2000, pixelsPerSecond = 80) {
  let node = byId(containerId);
  if (!node) {
    return;
  }

  node.scrollTop = 0;
  if (node.scrollHeight <= node.clientHeight + 2) {
    return;
  }

  let rafId = 0;
  let timeoutId = setTimeout(function () {
    let distance = node.scrollHeight - node.clientHeight;
    let durationMs = Math.max(2000, (distance / pixelsPerSecond) * 1000);
    let startTime = 0;

    function frame(now) {
      if (!startTime) {
        startTime = now;
      }
      let progress = Math.min(1, (now - startTime) / durationMs);
      node.scrollTop = distance * progress;
      if (progress < 1) {
        rafId = requestAnimationFrame(frame);
      }
    }

    rafId = requestAnimationFrame(frame);
  }, delayMs);

  autoScrollTasks.push(function () {
    clearTimeout(timeoutId);
    if (rafId) {
      cancelAnimationFrame(rafId);
    }
  });
}

function updateHeader(payload) {
  byId('header-room').textContent = `Room: ${payload.room || '-'}`;
}

function getPayloadUpdatedAtMs(payload) {
  if (!payload || !payload.updatedAt) {
    return 0;
  }
  let ms = Date.parse(payload.updatedAt);
  if (Number.isNaN(ms)) {
    return 0;
  }
  return ms;
}

function shouldApplyPayload(payload) {
  let updatedAtMs = getPayloadUpdatedAtMs(payload);
  if (!updatedAtMs) {
    return true;
  }
  if (updatedAtMs < lastStateUpdatedAtMs) {
    return false;
  }
  lastStateUpdatedAtMs = updatedAtMs;
  return true;
}

function transitionToPhase(nextPhaseName, payload) {
  let nextController = phaseControllers[nextPhaseName];
  if (!nextController) {
    showError('Unknown phase: ' + nextPhaseName);
    return;
  }

  let token = transitionCoordinator.nextToken();

  if (activeController && activeController !== nextController && activeController.unmount) {
    activeController.unmount();
  }

  if (!transitionCoordinator.isCurrent(token)) {
    return;
  }

  if (activeController !== nextController && nextController.mount) {
    nextController.mount(payload);
  }

  activeController = nextController;

  if (activeController.update) {
    activeController.update(payload);
  }
}

function applyState(payload) {
  if (!shouldApplyPayload(payload)) {
    return;
  }

  updateHeader(payload);
  setPhaseTheme(payload.phase);
  transitionToPhase(payload.phase, payload);
}

function createPhaseController(config) {
  return {
    mount: function (payload) {
      this.lastRenderKey = null;
      showScreen(config.screenId);
      if (config.onMount) {
        config.onMount(payload);
      }
    },
    update: function (payload) {
      let renderKey = (config.renderKeyFn || defaultRenderKey)(payload);
      if (this.lastRenderKey !== renderKey) {
        config.renderFn(payload);
        this.lastRenderKey = renderKey;
      }
      let timerSeconds = config.timerFn ? config.timerFn(payload) : null;
      let timerOptions = config.timerOptionsFn ? config.timerOptionsFn(payload) : {};
      attachTimer(timerSeconds, timerOptions);
    },
    unmount: function () {
      this.lastRenderKey = null;
      clearTimer();
      if (config.onUnmount) {
        config.onUnmount();
      }
    }
  };
}

function renderLobby(payload) {
  let container = byId('lobby-player-list');
  let players = (payload.players || []).filter(function (p) {
    return p.role === 'player';
  });
  let nextIds = new Set(players.map(function (p) { return p.playerId; }));
  let existingCards = Array.from(container.querySelectorAll('.player-card[data-player-id]'));
  let existingById = new Map(existingCards.map(function (node) {
    return [node.dataset.playerId, node];
  }));
  let fragment = document.createDocumentFragment();

  players.forEach(function (p) {
    let node = existingById.get(p.playerId);
    let stateLabel = normalizeStateLabel(p.state);
    if (!node) {
      node = document.createElement('article');
      node.className = 'card player-card player-enter';
      node.dataset.playerId = p.playerId;
    } else {
      node.classList.remove('player-exit');
    }
    node.innerHTML = `
      <div class="player-avatar" aria-hidden="true">${escapeHtml(initialsForName(p.displayName))}</div>
      <div class="player-meta">
        <strong class="player-name">${escapeHtml(p.displayName || '')}</strong>
        <span class="player-state">${escapeHtml(stateLabel)}</span>
      </div>
    `;
    fragment.appendChild(node);

    if (node.classList.contains('player-enter')) {
      let enterTimer = setTimeout(function () {
        node.classList.remove('player-enter');
      }, 360);
      lobbyTransitionTimers.push(enterTimer);
    }
  });

  container.appendChild(fragment);

  existingCards.forEach(function (node) {
    if (nextIds.has(node.dataset.playerId)) {
      return;
    }
    node.classList.add('player-exit');
    let exitTimer = setTimeout(function () {
      if (node.parentNode) {
        node.parentNode.removeChild(node);
      }
    }, 300);
    lobbyTransitionTimers.push(exitTimer);
  });

  byId('lobby-note').textContent = payload.lobby && payload.lobby.canStart
    ? 'Ready to launch.'
    : 'Waiting for more players to join.';
}

function renderGameStarting(payload) {
  let title = byId('game-starting-title');
  let linesContainer = byId('game-starting-lines');
  if (!title || !linesContainer) {
    return;
  }

  clearGameStartingTimers();

  let showLongIntro = true;
  if (payload.gameStarting &&
      typeof payload.gameStarting.showInstructions === 'boolean') {
    showLongIntro = payload.gameStarting.showInstructions;
  }
  title.textContent = 'the game of SUPERLATIVES';
  linesContainer.innerHTML = '';

  if (!showLongIntro) {
    linesContainer.innerHTML = '<p class="game-starting-subtle">Next round starting...</p>';
    return;
  }

  let lines = [
    'Each player submits an entry in the given category.',
    'Everyone then votes on which entry matches a superlative best.',
    'Points build across the round before the final reveal.',
    'Good luck!'
  ];

  lines.forEach(function (line, index) {
    let item = document.createElement('p');
    item.className = 'game-starting-line';
    item.textContent = line;
    linesContainer.appendChild(item);

    let timer = setTimeout(function () {
      item.classList.add('visible');
    }, index * 420);
    gameStartingLineTimers.push(timer);
  });
}

function renderRoundIntro(payload) {
  byId('round-title').textContent = `Round ${Number(payload.round.roundIndex || 0) + 1}`;
  byId('round-category').textContent = `${payload.round.categoryLabel}`;
  byId('round-superlatives').innerHTML = renderPromptStrip(payload.round.superlatives || []);
}

function renderEntryInput(payload) {
  let submitted = payload.round && payload.round.submittedPlayerIds
    ? payload.round.submittedPlayerIds
    : [];
  byId('entry-category').textContent = `${payload.round.categoryLabel}`;
  renderPromptStripIfChanged('entry-superlatives', payload.round.superlatives || []);
  reconcileProgressCards(
    'entry-player-progress',
    payload.players || [],
    submitted
  );
}

function renderVoteInput(payload) {
  let setIndex = payload.round && typeof payload.round.currentSetIndex === 'number'
    ? payload.round.currentSetIndex + 1
    : Number(payload.vote.voteIndex || 0) + 1;
  let completed = payload.round && payload.round.completedPlayerIds
    ? payload.round.completedPlayerIds
    : [];
  byId('vote-category').textContent = `${payload.round && payload.round.categoryLabel ? payload.round.categoryLabel : '-'}`;
  renderPromptStripIfChanged(
    'vote-superlatives',
    payload.round && payload.round.setSuperlatives ? payload.round.setSuperlatives : []
  );
  reconcileProgressCards(
    'vote-player-progress',
    payload.players || [],
    completed
  );
}

function renderVoteReveal(payload) {
  let reveal = payload.reveal || {};
  let entries = reveal.entries || [];
  let results = reveal.results || {};
  let roundPointsByEntry = reveal.roundPointsByEntry || {};
  let revealList = byId('reveal-list');
  let prompt = reveal.promptText || '';
  let renderToken = ++voteRevealRenderToken;

  clearVoteRevealTimers();
  clearAutoScrollTasks();

  byId('reveal-prompt').textContent = prompt;
  revealList.innerHTML = `
    <p class="reveal-stage-label">Top entries for this superlative</p>
    ${renderRevealTopThree(entries, results)}
  `;

  let transitionTimer = setTimeout(function () {
    if (renderToken !== voteRevealRenderToken) {
      return;
    }
    revealList.innerHTML = `
      <p class="reveal-stage-label">Round standings after this reveal</p>
      ${renderRoundStandings(entries, results, roundPointsByEntry)}
    `;
    scheduleAutoScroll('reveal-list');
  }, 2200);
  voteRevealTimers.push(transitionTimer);
}

function renderRoundSummary(payload) {
  let roundSummary = payload.roundSummary || {};
  clearAutoScrollTasks();
  byId('round-summary-board').innerHTML = renderRoundSummaryRows(
    roundSummary.playerRoundResults || []
  );
  scheduleAutoScroll('round-summary-board');
}

function renderGameSummary(payload) {
  clearAutoScrollTasks();
  byId('game-summary-podium').innerHTML = renderPodium(payload.leaderboard || []);
  byId('game-summary-board').innerHTML = renderBoard(payload.leaderboard || []);
  startGameSummaryReveal();
  scheduleAutoScroll('game-summary-board');
}

function startGameSummaryReveal() {
  let podium = byId('game-summary-podium');
  if (!podium) {
    return;
  }

  clearGameSummaryRevealTimers();
  let token = ++gameSummaryRevealToken;
  let third = podium.querySelector('.podium-card.podium-third');
  let second = podium.querySelector('.podium-card.podium-second');
  let first = podium.querySelector('.podium-card.podium-first');
  let sequence = [
    { node: third, delayMs: 1000 },
    { node: second, delayMs: 2000 },
    { node: first, delayMs: 3000 },
  ];

  sequence.forEach(function (step) {
    if (!step.node) {
      return;
    }
    let timer = setTimeout(function () {
      if (token !== gameSummaryRevealToken) {
        return;
      }
      step.node.classList.add('revealed');
    }, step.delayMs);
    gameSummaryRevealTimers.push(timer);
  });
}

const phaseControllers = {
  Lobby: createPhaseController({
    screenId: 'screen-lobby',
    renderFn: renderLobby,
    timerFn: function () { return null; },
    onUnmount: clearLobbyTransitionTimers,
  }),
  GameStarting: createPhaseController({
    screenId: 'screen-game-starting',
    renderFn: renderGameStarting,
    timerFn: function (payload) {
      if (payload.gameStarting && payload.gameStarting.timeoutSeconds !== undefined) {
        return payload.gameStarting.timeoutSeconds;
      }
      return null;
    },
    onUnmount: clearTransientEffects,
  }),
  RoundIntro: createPhaseController({
    screenId: 'screen-round-intro',
    renderFn: renderRoundIntro,
    timerFn: function () { return null; },
  }),
  EntryInput: createPhaseController({
    screenId: 'screen-entry',
    renderFn: renderEntryInput,
    timerFn: function (payload) {
      return payload.round && payload.round.timeoutSeconds;
    },
    timerOptionsFn: function (payload) {
      return {
        key: `EntryInput:${payload.round && payload.round.roundId ? payload.round.roundId : ''}`,
        deadlineMs: payload.round && payload.round.timeoutAtMs,
      };
    },
  }),
  VoteInput: createPhaseController({
    screenId: 'screen-vote',
    renderFn: renderVoteInput,
    timerFn: function (payload) {
      return payload.vote && payload.vote.timeoutSeconds;
    },
    timerOptionsFn: function (payload) {
      return {
        key: `VoteInput:${payload.vote && payload.vote.roundId ? payload.vote.roundId : ''}:${payload.round && payload.round.currentSetIndex !== undefined ? payload.round.currentSetIndex : ''}:${payload.vote && payload.vote.superlativeId ? payload.vote.superlativeId : ''}`,
        deadlineMs: payload.vote && payload.vote.timeoutAtMs,
      };
    },
  }),
  VoteReveal: createPhaseController({
    screenId: 'screen-reveal',
    renderFn: renderVoteReveal,
    timerFn: function () { return null; },
    onUnmount: clearTransientEffects,
  }),
  RoundSummary: createPhaseController({
    screenId: 'screen-round-summary',
    renderFn: renderRoundSummary,
    timerFn: function () { return null; },
    onUnmount: clearAutoScrollTasks,
  }),
  GameSummary: createPhaseController({
    screenId: 'screen-game-summary',
    renderFn: renderGameSummary,
    timerFn: function () { return null; },
    onUnmount: function () {
      clearAutoScrollTasks();
      clearGameSummaryRevealTimers();
    },
  }),
};

function setupHandlers() {
  byId('login-button').onclick = function () {
    connect();
  };

  byId('login-room').onkeyup = function (event) {
    if (event.key === 'Enter') {
      byId('login-button').click();
    }
  };

  byId('disconnect').onclick = function () {
    reconnect = false;
    send({ event: 'logout' });
    if (ws) {
      ws.close();
    }
    clearTimer();
    clearTransientEffects();
    showScreen('screen-login');
  };
}

const DISPLAY_ASSET_URLS = [];
restoreRoom();
setupHandlers();
preloadDisplayAssets(DISPLAY_ASSET_URLS);
showScreen('screen-login');
