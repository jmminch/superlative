let ws = null;
let reconnect = false;
let reconnectDelayMs = 800;
let timerId = null;

function byId(id) {
  return document.getElementById(id);
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
    renderState(envelope.payload || {});
  }
}

function showScreen(id) {
  let screens = document.querySelectorAll('.screen');
  for (let i = 0; i < screens.length; i++) {
    screens[i].classList.remove('active');
  }
  byId(id).classList.add('active');
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
}

function attachTimer(initialSeconds) {
  clearTimer();

  if (initialSeconds === null || initialSeconds === undefined) {
    byId('header-timer').textContent = '';
    return;
  }

  let seconds = Math.max(0, Number(initialSeconds) || 0);
  byId('header-timer').textContent = `:${String(seconds).padStart(2, '0')}`;

  timerId = setInterval(function () {
    seconds = Math.max(0, seconds - 1);
    byId('header-timer').textContent = `:${String(seconds).padStart(2, '0')}`;
    if (seconds <= 0) {
      clearTimer();
    }
  }, 1000);
}

function renderPlayers(players) {
  let html = '';
  players.forEach(function (p) {
    if (p.role !== 'player') {
      return;
    }
    html += `<div class="card"><strong>${p.displayName}</strong><span class="float">${p.state}</span></div>`;
  });
  return html;
}

function renderEntries(entries) {
  let html = '';
  entries.forEach(function (e) {
    html += `<div class="card"><strong>${e.text}</strong><br><span class="muted">${e.ownerDisplayName}</span></div>`;
  });
  return html;
}

function renderReveal(entries, results) {
  let html = '';
  entries.forEach(function (e) {
    let votes = (results.voteCountByEntry && results.voteCountByEntry[e.entryId]) || 0;
    let points = (results.pointsByEntry && results.pointsByEntry[e.entryId]) || 0;
    html += `<div class="card"><strong>${e.text}</strong><br><span class="muted">${votes} votes • +${points}</span></div>`;
  });
  return html;
}

function renderBoard(rows) {
  let html = '';
  rows.forEach(function (r) {
    html += `<div class="card"><strong>${r.displayName}</strong><span class="float">${r.score}</span></div>`;
  });
  return html;
}

function updateHeader(payload) {
  byId('header-room').textContent = `Room: ${payload.room || '-'}`;
  byId('header-phase').textContent = `Phase: ${payload.phase || '-'}`;
}

function renderState(payload) {
  updateHeader(payload);

  switch (payload.phase) {
    case 'Lobby':
      byId('lobby-player-list').innerHTML = renderPlayers(payload.players || []);
      byId('lobby-note').textContent = payload.lobby && payload.lobby.canStart
        ? 'Ready to start.'
        : 'Waiting for players.';
      attachTimer(null);
      showScreen('screen-lobby');
      break;

    case 'RoundIntro':
      byId('round-title').textContent = `Round ${Number(payload.round.roundIndex || 0) + 1}`;
      byId('round-category').textContent = `Category: ${payload.round.categoryLabel}`;
      byId('round-superlatives').innerHTML = (payload.round.superlatives || []).map(
        (s) => `<div class="card">${s.promptText}</div>`
      ).join('');
      attachTimer(payload.round.timeoutSeconds);
      showScreen('screen-round-intro');
      break;

    case 'EntryInput':
      byId('entry-category').textContent = `Category: ${payload.round.categoryLabel}`;
      byId('entry-list').innerHTML = renderEntries(payload.round.entries || []);
      attachTimer(payload.round.timeoutSeconds);
      showScreen('screen-entry');
      break;

    case 'VoteInput':
      byId('vote-title').textContent = `Vote ${Number(payload.vote.voteIndex || 0) + 1}`;
      byId('vote-prompt').textContent = payload.vote.promptText || '';
      byId('vote-list').innerHTML = renderEntries(payload.vote.entries || []);
      attachTimer(payload.vote.timeoutSeconds);
      showScreen('screen-vote');
      break;

    case 'VoteReveal':
      byId('reveal-prompt').textContent = payload.reveal.promptText || '';
      byId('reveal-list').innerHTML = renderReveal(
        payload.reveal.entries || [],
        payload.reveal.results || {}
      );
      attachTimer(payload.reveal.timeoutSeconds);
      showScreen('screen-reveal');
      break;

    case 'RoundSummary':
      byId('round-summary-board').innerHTML = renderBoard(payload.leaderboard || []);
      attachTimer(payload.roundSummary.timeoutSeconds);
      showScreen('screen-round-summary');
      break;

    case 'GameSummary':
      byId('game-summary-board').innerHTML = renderBoard(payload.leaderboard || []);
      attachTimer(payload.gameSummary.timeoutSeconds);
      showScreen('screen-game-summary');
      break;

    default:
      showError('Unknown phase: ' + payload.phase);
      break;
  }
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
    showScreen('screen-login');
  };
}

restoreRoom();
setupHandlers();
showScreen('screen-login');
