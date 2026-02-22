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
let musicFadeIntervalId = null;
let musicAudio = null;
let musicTrackId = null;
let musicTransitionToken = 0;
let shouldIgnoreLiveState = function () {
  return false;
};

const MUSIC_FADE_DURATION_MS = 1000;
const MUSIC_FADE_STEP_MS = 50;
const MUSIC_TRACKS = {
  gameShow: {
    src: 'audio/music/game_show.mp3',
    loop: true,
  },
  waiting: {
    src: 'audio/music/waiting.mp3',
    loop: true,
  },
  fanfare: {
    src: 'audio/music/fanfare.mp3',
    loop: false,
  },
};

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
    if (shouldIgnoreLiveState()) {
      return;
    }
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

function getMusicTrackForPhase(phaseName) {
  if (phaseName === 'GameStarting' || phaseName === 'GameSummary') {
    return 'gameShow';
  }
  if (phaseName === 'EntryInput' || phaseName === 'VoteInput') {
    return 'waiting';
  }
  if (phaseName === 'VoteReveal') {
    return 'fanfare';
  }
  return null;
}

function ensureMusicAudio() {
  if (!musicAudio) {
    musicAudio = new Audio();
    musicAudio.preload = 'auto';
    musicAudio.volume = 1;
  }
  return musicAudio;
}

function clearMusicFadeInterval() {
  if (musicFadeIntervalId) {
    clearInterval(musicFadeIntervalId);
    musicFadeIntervalId = null;
  }
}

function fadeOutCurrentMusic(onDone) {
  if (!musicAudio || !musicTrackId) {
    musicTrackId = null;
    if (onDone) {
      onDone();
    }
    return;
  }

  clearMusicFadeInterval();
  let audio = musicAudio;
  if (audio.paused || audio.ended) {
    audio.pause();
    audio.currentTime = 0;
    audio.volume = 1;
    musicTrackId = null;
    if (onDone) {
      onDone();
    }
    return;
  }
  let startVolume = Math.max(0, Math.min(1, Number(audio.volume) || 1));
  let steps = Math.max(1, Math.round(MUSIC_FADE_DURATION_MS / MUSIC_FADE_STEP_MS));
  let step = 0;

  musicFadeIntervalId = setInterval(function () {
    step += 1;
    let nextVolume = Math.max(0, startVolume * (1 - (step / steps)));
    audio.volume = nextVolume;
    if (step < steps) {
      return;
    }

    clearMusicFadeInterval();
    audio.pause();
    audio.currentTime = 0;
    audio.volume = 1;
    musicTrackId = null;
    if (onDone) {
      onDone();
    }
  }, MUSIC_FADE_STEP_MS);
}

function playMusicTrack(trackId) {
  let track = MUSIC_TRACKS[trackId];
  if (!track) {
    return;
  }

  let audio = ensureMusicAudio();
  clearMusicFadeInterval();
  audio.volume = 1;
  audio.loop = !!track.loop;
  if (audio.src !== new URL(track.src, window.location.href).href) {
    audio.src = track.src;
    audio.currentTime = 0;
  }

  musicTrackId = trackId;
  let playPromise = audio.play();
  if (playPromise && typeof playPromise.catch === 'function') {
    playPromise.catch(function () {
      // Ignore autoplay-block failures; playback will resume after user gesture.
    });
  }
}

function transitionMusicForPhase(nextPhaseName) {
  let nextTrackId = getMusicTrackForPhase(nextPhaseName);
  if (musicTrackId === nextTrackId) {
    return;
  }

  musicTransitionToken += 1;
  let token = musicTransitionToken;
  let startNextTrack = function () {
    if (token !== musicTransitionToken) {
      return;
    }
    if (!nextTrackId) {
      return;
    }
    playMusicTrack(nextTrackId);
  };

  if (!musicTrackId) {
    startNextTrack();
    return;
  }

  fadeOutCurrentMusic(startNextTrack);
}

function stopMusicImmediately() {
  musicTransitionToken += 1;
  clearMusicFadeInterval();
  if (!musicAudio) {
    musicTrackId = null;
    return;
  }
  musicAudio.pause();
  musicAudio.currentTime = 0;
  musicAudio.volume = 1;
  musicTrackId = null;
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

  let top = ranked.slice(0, 3).map(function (row, index) {
    return mergeObjects(row, { rank: index + 1 });
  });
  if (!top.length) {
    return '<p class="muted">No votes recorded for this prompt.</p>';
  }

  return `
    <div class="reveal-top-grid">
      ${top.map(function (row, index) {
    return `
          <article class="card reveal-top-card reveal-top-card-pending" data-rank="${row.rank}">
            <span class="board-rank">#${row.rank}</span>
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
        <span class="reveal-standing-points">
          <span class="reveal-standing-total">${row.roundPoints}</span>
          <span class="reveal-standing-gain">+${row.setPoints}</span>
        </span>
      </article>
    `;
  }).join('');
}

function normalizeRevealPromptResults(reveal) {
  let promptResults = Array.isArray(reveal && reveal.promptResults)
    ? reveal.promptResults.slice()
    : [];

  promptResults.sort(function (a, b) {
    let aIndex = Number(a && a.promptIndex);
    let bIndex = Number(b && b.promptIndex);
    if (!Number.isFinite(aIndex) || !Number.isFinite(bIndex)) {
      return 0;
    }
    return aIndex - bIndex;
  });
  return promptResults;
}

function combinePromptResults(promptResults) {
  let combined = {
    voteCountByEntry: {},
    pointsByEntry: {},
    pointsByPlayer: {},
  };

  (promptResults || []).forEach(function (prompt) {
    let results = (prompt && prompt.results) || {};
    let voteCountByEntry = results.voteCountByEntry || {};
    let pointsByEntry = results.pointsByEntry || {};
    let pointsByPlayer = results.pointsByPlayer || {};

    Object.keys(voteCountByEntry).forEach(function (entryId) {
      combined.voteCountByEntry[entryId] =
        (combined.voteCountByEntry[entryId] || 0) + Number(voteCountByEntry[entryId] || 0);
    });
    Object.keys(pointsByEntry).forEach(function (entryId) {
      combined.pointsByEntry[entryId] =
        (combined.pointsByEntry[entryId] || 0) + Number(pointsByEntry[entryId] || 0);
    });
    Object.keys(pointsByPlayer).forEach(function (playerId) {
      combined.pointsByPlayer[playerId] =
        (combined.pointsByPlayer[playerId] || 0) + Number(pointsByPlayer[playerId] || 0);
    });
  });

  return combined;
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
  transitionMusicForPhase(payload.phase);
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
    }, index * 1500);
    gameStartingLineTimers.push(timer);
  });
}

function renderRoundIntro(payload) {
  byId('round-title').textContent = `Round ${Number(payload.round.roundIndex || 0) + 1}`;
  byId('round-category').textContent = `${displayCategoryLabel(payload.round)}`;
  byId('round-superlatives').innerHTML = renderPromptStrip(payload.round.superlatives || []);
}

function renderEntryInput(payload) {
  let submitted = payload.round && payload.round.submittedPlayerIds
    ? payload.round.submittedPlayerIds
    : [];
  byId('entry-category').textContent = `${displayCategoryLabel(payload.round)}`;
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
  byId('vote-category').textContent = `${displayCategoryLabel(payload.round) || '-'}`;
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
  let promptResults = normalizeRevealPromptResults(reveal);
  let aggregateResults = combinePromptResults(promptResults);
  let roundPointsByEntry = reveal.roundPointsByEntry || {};
  let revealList = byId('reveal-list');
  let renderToken = ++voteRevealRenderToken;
  let firstRevealDelayMs = 2000;
  let secondRevealDelayMs = firstRevealDelayMs + 1000;
  let thirdRevealDelayMs = secondRevealDelayMs + 1000;
  let betweenPromptsDelayMs = 3000;
  let afterAllVotesToStandingsMs = 5000;
  let promptWindowMs = thirdRevealDelayMs + betweenPromptsDelayMs;

  clearVoteRevealTimers();
  clearAutoScrollTasks();

  function renderPromptStage(promptRow) {
    let promptText = promptRow && promptRow.promptText ? promptRow.promptText : '';
    let promptResults = promptRow && promptRow.results ? promptRow.results : {};
    let section = document.createElement('section');
    section.className = 'reveal-prompt-section';
    section.innerHTML = `
      <p class="reveal-stage-label">${escapeHtml(promptText)}</p>
      ${renderRevealTopThree(entries, promptResults)}
    `;
    return section;
  }

  function queueRankReveal(sectionNode, rank, delayMs) {
    let timer = setTimeout(function () {
      if (renderToken !== voteRevealRenderToken) {
        return;
      }
      if (!sectionNode || !sectionNode.isConnected) {
        return;
      }
      let card = sectionNode.querySelector(`.reveal-top-card[data-rank="${rank}"]`);
      if (card) {
        card.classList.add('revealed');
      }
    }, delayMs);
    voteRevealTimers.push(timer);
  }

  revealList.innerHTML = '';

  let revealSections = promptResults.map(function (promptRow) {
    let section = renderPromptStage(promptRow);
    section.classList.add('is-hidden');
    revealList.appendChild(section);
    return section;
  });

  if (!promptResults.length) {
    revealList.innerHTML = '<p class="reveal-stage-label">No reveal prompt results available.</p>';
  }

  promptResults.forEach(function (promptRow, index) {
    let startMs = index * promptWindowMs;
    let timer = setTimeout(function () {
      if (renderToken !== voteRevealRenderToken) {
        return;
      }
      let section = revealSections[index];
      if (!section) {
        return;
      }
      section.classList.remove('is-hidden');
      section.classList.add('is-visible');
      queueRankReveal(section, 3, firstRevealDelayMs);
      queueRankReveal(section, 2, secondRevealDelayMs);
      queueRankReveal(section, 1, thirdRevealDelayMs);
    }, startMs);
    voteRevealTimers.push(timer);
  });

  let allVotesRevealedMs = promptResults.length > 0
    ? ((promptResults.length - 1) * promptWindowMs) + thirdRevealDelayMs
    : 0;
  let standingsDelayMs = allVotesRevealedMs + afterAllVotesToStandingsMs;
  let transitionTimer = setTimeout(function () {
    if (renderToken !== voteRevealRenderToken) {
      return;
    }
    revealList.innerHTML = `
      <p class="reveal-stage-label">ROUND STANDINGS</p>
      ${renderRoundStandings(entries, aggregateResults, roundPointsByEntry)}
    `;
    scheduleAutoScroll('reveal-list');
  }, standingsDelayMs);
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

function displayCategoryLabel(round) {
  if (!round) {
    return '';
  }
  if (round.categoryLabelPlural) {
    return round.categoryLabelPlural;
  }
  return round.categoryLabel || '';
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
    timerFn: function () { return null; },
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

function mergeObjects(base, overrides) {
  if (!overrides || typeof overrides !== 'object' || Array.isArray(overrides)) {
    return base;
  }
  let out = Array.isArray(base) ? base.slice() : Object.assign({}, base);
  Object.keys(overrides).forEach(function (key) {
    let nextValue = overrides[key];
    if (nextValue &&
      typeof nextValue === 'object' &&
      !Array.isArray(nextValue) &&
      out[key] &&
      typeof out[key] === 'object' &&
      !Array.isArray(out[key])) {
      out[key] = mergeObjects(out[key], nextValue);
      return;
    }
    out[key] = nextValue;
  });
  return out;
}

function createDebugPlayers() {
  return [
    { playerId: 'p1', role: 'player', displayName: 'Avery Lane', state: 'active' },
    { playerId: 'p2', role: 'player', displayName: 'Jordan Fox', state: 'active' },
    { playerId: 'p3', role: 'player', displayName: 'Mika Chen', state: 'active' },
    { playerId: 'p4', role: 'player', displayName: 'Sam Patel', state: 'active' },
    { playerId: 'p5', role: 'player', displayName: 'Noah Kim', state: 'eliminated' },
    { playerId: 'd1', role: 'display', displayName: 'Display', state: 'active' },
  ];
}

function createDebugPrompts() {
  return [
    { superlativeId: 's1', promptText: 'Most likely to survive on a desert island' },
    { superlativeId: 's2', promptText: 'Most likely to become a meme' },
    { superlativeId: 's3', promptText: 'Most likely to accidentally start a trend' },
  ];
}

function createDebugEntries() {
  return [
    { entryId: 'e1', text: 'Duct tape and optimism', ownerDisplayName: 'Avery Lane', status: 'active' },
    { entryId: 'e2', text: 'A spreadsheet for coconuts', ownerDisplayName: 'Jordan Fox', status: 'active' },
    { entryId: 'e3', text: 'Pocket-sized karaoke machine', ownerDisplayName: 'Mika Chen', status: 'active' },
    { entryId: 'e4', text: 'Emergency glitter', ownerDisplayName: 'Sam Patel', status: 'eliminated' },
  ];
}

function createDebugLeaderboard() {
  return [
    { displayName: 'Avery Lane', score: 42 },
    { displayName: 'Jordan Fox', score: 37 },
    { displayName: 'Mika Chen', score: 34 },
    { displayName: 'Sam Patel', score: 30 },
    { displayName: 'Noah Kim', score: 22 },
  ];
}

function createDebugStateByPhase() {
  let nowMs = Date.now();
  let players = createDebugPlayers();
  let prompts = createDebugPrompts();
  let entries = createDebugEntries();
  let leaderboard = createDebugLeaderboard();
  let shared = {
    room: 'DEMO',
    players: players,
    round: {
      roundId: 'r1',
      roundIndex: 0,
      categoryLabel: 'Things you bring on a deserted island',
      superlatives: prompts,
    },
    updatedAt: new Date(nowMs).toISOString(),
  };
  return {
    Lobby: mergeObjects(shared, {
      phase: 'Lobby',
      lobby: { canStart: true },
      players: players.map(function (player, index) {
        if (player.role !== 'player') {
          return player;
        }
        return mergeObjects(player, {
          state: index < 4 ? 'ready' : player.state
        });
      }),
    }),
    GameStarting: mergeObjects(shared, {
      phase: 'GameStarting',
      gameStarting: { showInstructions: true },
    }),
    RoundIntro: mergeObjects(shared, {
      phase: 'RoundIntro',
    }),
    EntryInput: mergeObjects(shared, {
      phase: 'EntryInput',
      round: mergeObjects(shared.round, {
        submittedPlayerIds: ['p1', 'p2', 'p4'],
        timeoutSeconds: 30,
        timeoutAtMs: nowMs + 30000,
      }),
    }),
    VoteInput: mergeObjects(shared, {
      phase: 'VoteInput',
      round: mergeObjects(shared.round, {
        currentSetIndex: 1,
        setSuperlatives: [prompts[1]],
        completedPlayerIds: ['p1', 'p2'],
      }),
      vote: {
        voteIndex: 1,
        roundId: 'r1',
        superlativeId: 's2',
        timeoutSeconds: 20,
        timeoutAtMs: nowMs + 20000,
      },
    }),
    VoteReveal: mergeObjects(shared, {
      phase: 'VoteReveal',
      reveal: {
        entries: entries,
        promptResults: [
          {
            promptIndex: 0,
            superlativeId: prompts[0].superlativeId,
            promptText: prompts[0].promptText,
            results: {
              voteCountByEntry: { e1: 4, e2: 2, e3: 1, e4: 0 },
              pointsByEntry: { e1: 12, e2: 6, e3: 3, e4: 0 },
            },
          },
          {
            promptIndex: 1,
            superlativeId: prompts[1].superlativeId,
            promptText: prompts[1].promptText,
            results: {
              voteCountByEntry: { e1: 2, e2: 3, e3: 1, e4: 0 },
              pointsByEntry: { e1: 6, e2: 9, e3: 3, e4: 0 },
            },
          },
          {
            promptIndex: 2,
            superlativeId: prompts[2].superlativeId,
            promptText: prompts[2].promptText,
            results: {
              voteCountByEntry: { e1: 1, e2: 3, e3: 2, e4: 0 },
              pointsByEntry: { e1: 3, e2: 9, e3: 6, e4: 0 },
            },
          },
        ],
        roundPointsByEntry: { e1: 21, e2: 17, e3: 12, e4: 8 },
      },
    }),
    RoundSummary: mergeObjects(shared, {
      phase: 'RoundSummary',
      roundSummary: {
        playerRoundResults: [
          { displayName: 'Avery Lane', entryText: 'Duct tape and optimism', pointsThisRound: 14, totalScore: 42 },
          { displayName: 'Jordan Fox', entryText: 'A spreadsheet for coconuts', pointsThisRound: 11, totalScore: 37 },
          { displayName: 'Mika Chen', entryText: 'Pocket-sized karaoke machine', pointsThisRound: 9, totalScore: 34 },
          { displayName: 'Sam Patel', entryText: 'Emergency glitter', pointsThisRound: 6, totalScore: 30 },
        ],
      },
    }),
    GameSummary: mergeObjects(shared, {
      phase: 'GameSummary',
      leaderboard: leaderboard,
    }),
  };
}

function installDisplayDebugApi() {
  let debugStateLock = false;

  window.displayDebug = {
    phases: Object.keys(phaseControllers),
    lockLiveState: function () {
      debugStateLock = true;
    },
    unlockLiveState: function () {
      debugStateLock = false;
    },
    show: function (phaseName, overrides = {}) {
      let fixtures = createDebugStateByPhase();
      let base = fixtures[phaseName];
      if (!base) {
        showError('Unknown debug phase: ' + phaseName);
        return;
      }
      debugStateLock = true;
      applyState(mergeObjects(base, overrides));
    },
    showAll: function (delayMs = 2500) {
      let phases = this.phases.slice();
      let index = 0;
      let self = this;
      function next() {
        if (index >= phases.length) {
          return;
        }
        self.show(phases[index]);
        index += 1;
        setTimeout(next, delayMs);
      }
      next();
    },
    payload: function (phaseName) {
      return createDebugStateByPhase()[phaseName] || null;
    },
    apply: function (payload, lockState = true) {
      if (lockState) {
        debugStateLock = true;
      }
      applyState(payload || {});
    },
    isLiveStateLocked: function () {
      return debugStateLock;
    },
  };

  return function shouldIgnoreState() {
    return debugStateLock;
  };
}

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
    stopMusicImmediately();
    showScreen('screen-login');
  };
}

const DISPLAY_ASSET_URLS = [];
shouldIgnoreLiveState = installDisplayDebugApi();
restoreRoom();
setupHandlers();
preloadDisplayAssets(DISPLAY_ASSET_URLS);
showScreen('screen-login');
