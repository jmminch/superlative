let ws = null;
let reconnect = false;
let loggedIn = false;
let reconnectDelayMs = 800;
let currentPayload = null;
let timerFrameId = null;
let timerMode = 'none';
let timerKey = null;
let timerDeadlineMs = 0;
let timerDurationMs = 0;

function byId(id) {
  return document.getElementById(id);
}

function currentLogin() {
  return {
    name: byId('login-name').value.trim(),
    room: byId('login-room').value.trim(),
  };
}

function storeLogin(name, room) {
  localStorage.setItem('superlatives_name', name);
  localStorage.setItem('superlatives_room', room);
}

function restoreLogin() {
  let name = localStorage.getItem('superlatives_name');
  let room = localStorage.getItem('superlatives_room');

  if (name && !byId('login-name').value) {
    byId('login-name').value = name;
  }

  if (room && !byId('login-room').value) {
    byId('login-room').value = room;
  }
}

function connect() {
  let login = currentLogin();
  if (!login.name || !login.room) {
    showError('Name and room are required.');
    return;
  }

  reconnect = true;
  loggedIn = false;
  storeLogin(login.name, login.room);

  if (ws) {
    ws.close();
  }

  ws = new WebSocket(
    (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'
  );

  ws.onopen = function () {
    send({
      event: 'login',
      room: login.room,
      name: login.name,
      role: 'player'
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

function send(obj) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return;
  }

  ws.send(JSON.stringify(obj));
}

function handleMessage(event) {
  let envelope = JSON.parse(event.data);

  if (!envelope || typeof envelope.event !== 'string') {
    return;
  }

  if (envelope.event === 'success') {
    loggedIn = true;
    return;
  }

  if (envelope.event === 'error') {
    let payload = envelope.payload || {};
    if (payload.code === 'duplicate_entry' &&
        currentPayload &&
        currentPayload.phase === 'EntryInput') {
      byId('entry-note').textContent =
        payload.message || 'Someone already entered that. Try a different entry.';
      setVisible('entry-form', true);
      byId('entry-submit').disabled = false;
      return;
    }
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
    let previous = currentPayload;
    currentPayload = envelope.payload;
    renderState(envelope.payload, previous);
  }
}

function showError(msg) {
  byId('error-text').textContent = msg;
  showScreen('screen-error');
}

function showScreen(id) {
  let screens = document.querySelectorAll('.screen');
  for (let i = 0; i < screens.length; i++) {
    screens[i].classList.remove('active');
  }

  byId(id).classList.add('active');
  let inRoomScreen = id !== 'screen-login' && id !== 'screen-error';
  let logoutButton = byId('logout');
  if (logoutButton) {
    logoutButton.style.display = loggedIn && inRoomScreen ? 'inline-block' : 'none';
  }
}

function clearTimer() {
  if (timerFrameId !== null) {
    cancelAnimationFrame(timerFrameId);
    timerFrameId = null;
  }
  timerMode = 'none';
  timerKey = null;
  timerDeadlineMs = 0;
  timerDurationMs = 0;
}

function setTimerBarWidth(percent, immediate = false) {
  let clamped = Math.max(0, Math.min(100, percent));
  let bar = byId('header-timer-bar');
  if (bar) {
    if (immediate) {
      bar.style.transition = 'none';
    }
    bar.style.width = `${clamped}%`;
    if (immediate) {
      // Force reflow so the no-transition width write is committed.
      bar.offsetWidth;
      bar.style.transition = '';
    }
  }
}

function _timerPercentAt(nowMs) {
  if (timerMode === 'entry-extend-empty') {
    return 0;
  }
  if (timerDurationMs <= 0) {
    return 0;
  }
  let remainingMs = Math.max(0, timerDeadlineMs - nowMs);
  return (remainingMs / timerDurationMs) * 100;
}

function _renderTimerFrame() {
  let nowMs = Date.now();
  setTimerBarWidth(_timerPercentAt(nowMs));
  if (nowMs >= timerDeadlineMs) {
    timerFrameId = null;
    return;
  }
  timerFrameId = requestAnimationFrame(_renderTimerFrame);
}

function _startTimerLoop() {
  if (timerFrameId !== null) {
    cancelAnimationFrame(timerFrameId);
  }
  timerFrameId = requestAnimationFrame(_renderTimerFrame);
}

function attachTimer(initialSeconds, options = {}) {
  let mode = options.mode || 'normal';
  let nextKey = options.key || null;
  let suppliedDeadlineMs = Number(options.deadlineMs);

  if (initialSeconds === null || initialSeconds === undefined) {
    clearTimer();
    setTimerBarWidth(0);
    return;
  }

  let nextSeconds = Math.max(0, Number(initialSeconds) || 0);
  let nowMs = Date.now();
  let nextDeadlineMs = Number.isFinite(suppliedDeadlineMs) && suppliedDeadlineMs > 0
    ? suppliedDeadlineMs
    : nowMs + (nextSeconds * 1000);
  let restart = timerFrameId === null || timerMode !== mode || timerKey !== nextKey;

  if (mode === 'entry-extend-empty' && timerFrameId !== null) {
    timerKey = nextKey;
    timerDeadlineMs = nextDeadlineMs;
    setTimerBarWidth(0);
    return;
  }

  if (!restart && timerFrameId !== null) {
    timerDeadlineMs = Math.min(timerDeadlineMs, nextDeadlineMs);
    return;
  }

  if (timerFrameId !== null && restart) {
    cancelAnimationFrame(timerFrameId);
    timerFrameId = null;
  }

  timerMode = mode;
  timerKey = nextKey;
  timerDeadlineMs = nextDeadlineMs;
  timerDurationMs = Math.max(1, timerDeadlineMs - nowMs);

  if (timerMode === 'entry-extend-empty') {
    setTimerBarWidth(0, true);
  } else {
    setTimerBarWidth(100, true);
    _startTimerLoop();
  }
}

function entryTimerMode(payload, previousPayload) {
  if (!previousPayload || previousPayload.phase !== 'EntryInput') {
    return 'normal';
  }
  let prev = previousPayload.round || {};
  let curr = payload.round || {};
  if (
    typeof prev.timeoutSeconds === 'number' &&
    typeof curr.timeoutSeconds === 'number' &&
    curr.timeoutSeconds > prev.timeoutSeconds
  ) {
    return 'entry-extend-empty';
  }
  return 'normal';
}

function renderVoteButtons(entries, locked, selectedEntryId) {
  let html = '';
  entries.forEach(function (e) {
    let selected = selectedEntryId === e.entryId ? ' selected' : '';
    let disabled = locked ? ' disabled' : '';
    html += `<button class="vote-button${selected}" data-entry-id="${e.entryId}"${disabled}>${e.text}</button>`;
  });
  return html;
}

function setVisible(id, visible) {
  let node = byId(id);
  if (!node) {
    return;
  }
  node.classList.toggle('hidden', !visible);
}

function updateHeader(payload) {
  let roomNode = byId('header-room');
  if (roomNode) {
    roomNode.textContent = `Room: ${payload.room}`;
  }

  let nameNode = byId('header-name');
  if (nameNode) {
    nameNode.textContent = payload.displayName || '-';
  }
}

function singularCategoryLabel(round) {
  if (!round) {
    return '';
  }
  if (round.categoryLabelSingular) {
    return String(round.categoryLabelSingular).trim();
  }
  if (round.categoryLabel) {
    return String(round.categoryLabel).trim();
  }
  return '';
}

function indefiniteArticleFor(text) {
  let firstLetterMatch = String(text || '').trim().match(/[A-Za-z]/);
  if (!firstLetterMatch) {
    return 'a';
  }
  return /^[AEIOUaeiou]$/.test(firstLetterMatch[0]) ? 'an' : 'a';
}

function entryTitleForRound(round) {
  let singular = singularCategoryLabel(round);
  if (!singular) {
    return 'Submit Your Entry';
  }
  return `Enter ${indefiniteArticleFor(singular)} ${singular}`;
}

function renderState(payload, previousPayload) {
  currentPayload = previousPayload;
  updateHeader(payload);
  currentPayload = payload;

  byId('lobby-start').disabled = !(payload.lobby && payload.lobby.canStart);

  switch (payload.phase) {
    case 'Lobby':
      byId('lobby-status').textContent = 'Waiting for game to start';
      attachTimer(null);
      showScreen('screen-lobby');
      break;

    case 'EntryInput':
      byId('entry-title').textContent = entryTitleForRound(payload.round);
      byId('entry-submit').disabled = !!payload.youSubmitted;
      byId('entry-note').textContent = payload.youSubmitted
        ? 'Your entry has been submitted.'
        : '';
      setVisible('entry-form', !payload.youSubmitted);
      attachTimer(payload.round.timeoutSeconds, {
        mode: entryTimerMode(payload, previousPayload),
        key: `EntryInput:${payload.round.roundId}`,
        deadlineMs: payload.round.timeoutAtMs
      });
      showScreen('screen-entry');
      break;

    case 'VoteInput':
      byId('vote-prompt').textContent = payload.vote.promptText;
      byId('vote-note').textContent = payload.youVoted
        ? 'Your votes have been submitted.'
        : '';
      byId('vote-list').innerHTML = renderVoteButtons(
        payload.vote.entries || [],
        !!payload.youVoted,
        payload.yourVoteEntryId || null
      );
      setVisible('vote-form', !payload.youVoted);
      attachTimer(payload.vote.timeoutSeconds, {
        mode: 'normal',
        key: `VoteInput:${payload.vote.roundId}:${payload.round.currentSetIndex}`,
        deadlineMs: payload.vote.timeoutAtMs
      });
      showScreen('screen-vote');
      break;

    default:
      byId('wait-note').textContent = 'Just wait...';
      attachTimer(null);
      showScreen('screen-wait');
      break;
  }
}

function setupHandlers() {
  byId('login-button').onclick = function () {
    connect();
  };

  byId('login-name').onkeyup = function (event) {
    if (event.key === 'Enter') {
      byId('login-room').focus();
    }
  };

  byId('login-room').onkeyup = function (event) {
    if (event.key === 'Enter') {
      byId('login-button').click();
    }
  };

  byId('lobby-start').onclick = function () {
    send({ event: 'startGame' });
  };

  byId('entry-submit').onclick = function () {
    let text = byId('entry-text').value.trim();
    if (!text) {
      return;
    }

    send({ event: 'submitEntry', text: text });
    byId('entry-text').value = '';
  };

  byId('entry-text').onkeyup = function (event) {
    if (event.key === 'Enter' && !byId('entry-submit').disabled) {
      byId('entry-submit').click();
    }
  };

  byId('vote-list').onclick = function (event) {
    let target = event.target.closest('button[data-entry-id]');
    if (!target) {
      return;
    }

    if (target.disabled) {
      return;
    }

    send({ event: 'submitVote', entryId: target.dataset.entryId });
  };

  byId('logout').onclick = function () {
    reconnect = false;
    loggedIn = false;
    currentPayload = null;
    send({ event: 'logout' });
    if (ws) {
      ws.close();
    }
    clearTimer();
    showScreen('screen-login');
  };
}

restoreLogin();
setupHandlers();
showScreen('screen-login');
