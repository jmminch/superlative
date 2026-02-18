let ws = null;
let reconnect = false;
let loggedIn = false;
let reconnectDelayMs = 800;
let currentPayload = null;
let timerId = null;
let timerMode = 'none';
let timerStartSeconds = 0;
let timerSeconds = 0;
let timerKey = null;

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
  if (timerId) {
    clearInterval(timerId);
    timerId = null;
  }
  timerMode = 'none';
  timerStartSeconds = 0;
  timerSeconds = 0;
  timerKey = null;
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

function attachTimer(initialSeconds, options = {}) {
  let mode = options.mode || 'normal';
  let nextKey = options.key || null;

  if (initialSeconds === null || initialSeconds === undefined) {
    clearTimer();
    setTimerBarWidth(0);
    return;
  }

  let nextSeconds = Math.max(0, Number(initialSeconds) || 0);
  let restart = !timerId || timerMode !== mode || timerKey !== nextKey;

  if (mode === 'entry-extend-empty' && timerId) {
    timerKey = nextKey;
    timerSeconds = nextSeconds;
    setTimerBarWidth(0);
    return;
  }

  if (!restart && timerId) {
    timerSeconds = Math.min(timerSeconds, nextSeconds);
    return;
  }

  if (timerId && restart) {
    clearInterval(timerId);
    timerId = null;
  }

  timerMode = mode;
  timerKey = nextKey;
  timerStartSeconds = Math.max(1, nextSeconds);
  timerSeconds = nextSeconds;

  let update = function () {
    if (timerMode === 'entry-extend-empty') {
      setTimerBarWidth(0);
      return;
    }
    let percent = (timerSeconds / timerStartSeconds) * 100;
    setTimerBarWidth(percent);
  };

  update();
  setTimerBarWidth((timerSeconds / timerStartSeconds) * 100, true);

  if (!timerId) {
    timerId = setInterval(function () {
      timerSeconds = Math.max(0, timerSeconds - 1);
      update();
      if (timerSeconds <= 0) {
        clearInterval(timerId);
        timerId = null;
      }
    }, 1000);
  }
}

function entryTimerMode(payload) {
  if (!currentPayload || currentPayload.phase !== 'EntryInput') {
    return 'normal';
  }
  let prev = currentPayload.round || {};
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

function renderRoundSummary(rows, superlativeResults) {
  let html = '';
  rows.forEach(function (r) {
    let entryText = r.entryText || '-';
    html += `<div class="card"><strong>${r.displayName}</strong><span class="float">${r.totalScore} total</span><br><span class="muted">Entry: ${entryText}</span><br><span class="muted">Round points: ${r.pointsThisRound}</span></div>`;
  });

  html += '<h3>Superlative Winners</h3>';
  (superlativeResults || []).forEach(function (result) {
    let top = result.topEntries || [];
    let lines = top.map(function (row) {
      return `<div class="muted">#${row.rank} ${row.entryText} - ${row.ownerDisplayName} - ${row.voteCount} votes</div>`;
    }).join('');
    if (!lines) {
      lines = '<div class="muted">No votes recorded.</div>';
    }
    html += `<div class="card"><strong>${result.promptText}</strong><br>${lines}</div>`;
  });

  return html;
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

function renderReveal(entries, results, roundPointsByEntry) {
  let html = '';
  entries.forEach(function (e) {
    let votes = (results.voteCountByEntry && results.voteCountByEntry[e.entryId]) || 0;
    let roundPoints = (roundPointsByEntry && roundPointsByEntry[e.entryId]) || 0;
    html += `<div class="card"><strong>${e.text}</strong><br><span class="muted">${votes} votes this prompt • ${roundPoints} round points total</span></div>`;
  });
  return html;
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

function renderState(payload, previousPayload) {
  currentPayload = previousPayload;
  updateHeader(payload);
  currentPayload = payload;

  byId('lobby-start').disabled = !(payload.lobby && payload.lobby.canStart);
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
      attachTimer(payload.round.timeoutSeconds, {
        mode: 'normal',
        key: `RoundIntro:${payload.round.roundId}`
      });
      showScreen('screen-round-intro');
      break;

    case 'EntryInput':
      byId('entry-category').textContent = `Enter a ${payload.round.categoryLabel}`;
      byId('entry-submit').disabled = !!payload.youSubmitted;
      byId('entry-note').textContent = payload.youSubmitted
        ? 'Submitted. Waiting for others.'
        : '';
      attachTimer(payload.round.timeoutSeconds, {
        mode: entryTimerMode(payload),
        key: `EntryInput:${payload.round.roundId}`
      });
      showScreen('screen-entry');
      break;

    case 'VoteInput':
      byId('vote-prompt').textContent = payload.vote.promptText;
      byId('vote-note').textContent = payload.youVoted
        ? 'Vote locked in. Waiting for others.'
        : 'Choose the best entry for this superlative.';
      byId('vote-list').innerHTML = renderVoteButtons(
        payload.vote.entries || [],
        !!payload.youVoted,
        payload.yourVoteEntryId || null
      );
      attachTimer(payload.vote.timeoutSeconds, {
        mode: 'normal',
        key: `VoteInput:${payload.vote.roundId}:${payload.round.currentSetIndex}`
      });
      showScreen('screen-vote');
      break;

    case 'VoteReveal':
      byId('reveal-prompt').textContent = payload.reveal.promptText;
      byId('reveal-list').innerHTML = renderReveal(
        payload.reveal.entries || [],
        payload.reveal.results || {},
        payload.reveal.roundPointsByEntry || {}
      );
      attachTimer(payload.reveal.timeoutSeconds, {
        mode: 'normal',
        key: `VoteReveal:${payload.reveal.roundId}:${payload.reveal.setIndex}`
      });
      showScreen('screen-reveal');
      break;

    case 'RoundSummary':
      byId('round-summary-board').innerHTML = renderRoundSummary(
        payload.roundSummary.playerRoundResults || [],
        payload.roundSummary.superlativeResults || []
      );
      attachTimer(payload.roundSummary.timeoutSeconds, {
        mode: 'normal',
        key: `RoundSummary:${payload.roundSummary.roundId}`
      });
      showScreen('screen-round-summary');
      break;

    case 'GameSummary':
      byId('game-summary-board').innerHTML = renderLeaderboard(payload.leaderboard || []);
      attachTimer(payload.gameSummary.timeoutSeconds, {
        mode: 'normal',
        key: `GameSummary:${payload.gameSummary.gameId || ''}`
      });
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
