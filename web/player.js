let ws = null;
let reconnect = false;
let loggedIn = false;
let reconnectDelayMs = 800;
let currentPayload = null;
let timerId = null;

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
    currentPayload = envelope.payload;
    renderState(envelope.payload);
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
    html += `<div class="card">${p.displayName} <span class="muted">(${p.state})</span></div>`;
  });
  return html;
}

function renderLeaderboard(board) {
  let html = '';
  board.forEach(function (r) {
    html += `<div class="card"><strong>${r.displayName}</strong><span class="float">${r.score}</span></div>`;
  });
  return html;
}

function renderEntries(entries) {
  let html = '';
  entries.forEach(function (e) {
    html += `<div class="card"><strong>${e.text}</strong><br><span class="muted">by ${e.ownerDisplayName}</span></div>`;
  });
  return html;
}

function renderVoteButtons(entries, locked, selectedEntryId) {
  let html = '';
  entries.forEach(function (e) {
    let selected = selectedEntryId === e.entryId ? ' selected' : '';
    let disabled = locked ? ' disabled' : '';
    html += `<button class="vote-button${selected}" data-entry-id="${e.entryId}"${disabled}>${e.text}<span class="vote-owner">${e.ownerDisplayName}</span></button>`;
  });
  return html;
}

function renderReveal(entries, results) {
  let html = '';
  entries.forEach(function (e) {
    let votes = (results.voteCountByEntry && results.voteCountByEntry[e.entryId]) || 0;
    let points = (results.pointsByEntry && results.pointsByEntry[e.entryId]) || 0;
    html += `<div class="card"><strong>${e.text}</strong><br><span class="muted">${votes} votes • +${points} points to ${e.ownerDisplayName}</span></div>`;
  });
  return html;
}

function updateHeader(payload) {
  byId('header-room').textContent = `Room: ${payload.room}`;
  byId('header-name').textContent = payload.displayName || '-';
  byId('header-phase').textContent = `Phase: ${payload.phase}`;
}

function renderState(payload) {
  updateHeader(payload);

  byId('lobby-start').disabled = !(payload.host && payload.lobby && payload.lobby.canStart);
  byId('round-advance').style.display = payload.host ? 'block' : 'none';
  byId('reveal-advance').style.display = payload.host ? 'block' : 'none';
  byId('round-summary-advance').style.display = payload.host ? 'block' : 'none';
  byId('game-summary-advance').style.display = payload.host ? 'block' : 'none';
  byId('game-summary-end').style.display = payload.host ? 'block' : 'none';

  switch (payload.phase) {
    case 'Lobby':
      byId('lobby-status').textContent = payload.lobby && payload.lobby.canStart
        ? 'Ready to start.'
        : 'Waiting for more players.';
      byId('lobby-player-list').innerHTML = renderPlayers(payload.players || []);
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
      byId('entry-submit').disabled = !!payload.youSubmitted;
      byId('entry-note').textContent = payload.youSubmitted
        ? 'Entry submitted. Waiting for others.'
        : 'Submit one entry for this category.';
      attachTimer(payload.round.timeoutSeconds);
      showScreen('screen-entry');
      break;

    case 'VoteInput':
      byId('vote-title').textContent = `Vote ${Number(payload.vote.voteIndex || 0) + 1}`;
      byId('vote-prompt').textContent = payload.vote.promptText;
      byId('vote-note').textContent = payload.youVoted
        ? 'Vote locked in. Waiting for others.'
        : 'Choose the best entry for this superlative.';
      byId('vote-list').innerHTML = renderVoteButtons(
        payload.vote.entries || [],
        !!payload.youVoted,
        payload.yourVoteEntryId || null
      );
      attachTimer(payload.vote.timeoutSeconds);
      showScreen('screen-vote');
      break;

    case 'VoteReveal':
      byId('reveal-prompt').textContent = payload.reveal.promptText;
      byId('reveal-list').innerHTML = renderReveal(
        payload.reveal.entries || [],
        payload.reveal.results || {}
      );
      attachTimer(payload.reveal.timeoutSeconds);
      showScreen('screen-reveal');
      break;

    case 'RoundSummary':
      byId('round-summary-board').innerHTML = renderLeaderboard(payload.leaderboard || []);
      attachTimer(payload.roundSummary.timeoutSeconds);
      showScreen('screen-round-summary');
      break;

    case 'GameSummary':
      byId('game-summary-board').innerHTML = renderLeaderboard(payload.leaderboard || []);
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

  byId('round-advance').onclick = function () {
    send({ event: 'advance' });
  };

  byId('reveal-advance').onclick = function () {
    send({ event: 'advance' });
  };

  byId('round-summary-advance').onclick = function () {
    send({ event: 'advance' });
  };

  byId('game-summary-advance').onclick = function () {
    send({ event: 'advance' });
  };

  byId('game-summary-end').onclick = function () {
    send({ event: 'endGame' });
  };

  byId('entry-submit').onclick = function () {
    let text = byId('entry-text').value.trim();
    if (!text) {
      return;
    }

    send({ event: 'submitEntry', text: text });
    byId('entry-text').value = '';
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
