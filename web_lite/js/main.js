/**
 * main.js — DeckBox Lite Web Client Bootstrap Coordinator
 * Handles URL parsing, WebSocket networking, reactive state binding, and DOM event wiring.
 */

import { StateStore } from './state_store.js';
import { CardRenderer } from './card_renderer.js';
import { ActionDispatcher } from './action_dispatcher.js';
import { RoleController } from './role_controller.js';

class WebSocketTransport {
  constructor(url, onMessage, onOpen, onClose) {
    this.url = url;
    this.onMessage = onMessage;
    this.onOpen = onOpen;
    this.onClose = onClose;
    this.ws = null;
    this.connected = false;
    this._reconnectAttempts = 0;
    this._connect();
  }

  _connect() {
    try {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => {
        this.connected = true;
        this._reconnectAttempts = 0;
        if (this.onOpen) this.onOpen();
      };
      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          if (this.onMessage) this.onMessage(data);
        } catch (e) {
          console.error('Failed to parse WebSocket JSON frame:', e);
        }
      };
      this.ws.onclose = (event) => {
        this.connected = false;
        if (this.onClose) this.onClose(event);
        this._scheduleReconnect();
      };
      this.ws.onerror = (err) => {
        console.warn('WebSocket connection error:', err);
      };
    } catch (e) {
      console.warn('WebSocket initialization exception:', e);
      this._scheduleReconnect();
    }
  }

  _scheduleReconnect() {
    const delay = Math.min(1000 * Math.pow(1.5, this._reconnectAttempts), 10000);
    this._reconnectAttempts++;
    setTimeout(() => {
      this._connect();
    }, delay);
  }

  send(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
      return true;
    }
    console.warn('WebSocket send failed: socket not open');
    return false;
  }
}

// Bootstrap on DOMContentLoaded
window.addEventListener('DOMContentLoaded', async () => {
  const urlParams = new URLSearchParams(window.location.search);
  let roomCode = urlParams.get('room') || '';
  let initialRole = urlParams.get('role') || '';
  let wsPortParam = urlParams.get('ws') || '';

  if (!roomCode && typeof fetch === 'function') {
    try {
      const resp = await fetch('/api/room', { cache: 'no-store' });
      if (resp && resp.ok) {
        const meta = await resp.json();
        if (meta && meta.room_code) {
          roomCode = String(meta.room_code);
          if (!initialRole) initialRole = String(meta.role || 'player');
          if (!wsPortParam && meta.ws_port) wsPortParam = String(meta.ws_port);
        }
      }
    } catch (_err) {
      // Ignore auto-discovery errors and fall back to Join Modal
    }
  }

  if (!initialRole) initialRole = 'spectator';
  const playerName = urlParams.get('name') || 'Spieler_' + Math.floor(Math.random() * 900 + 100);
  const reconnectToken = urlParams.get('token') || '';

  const displayRoomEl = document.getElementById('display-room-code');
  if (displayRoomEl) displayRoomEl.textContent = roomCode || '----';

  const statusIndicatorEl = document.getElementById('connection-status');
  const roleSelectEl = document.getElementById('role-selector');
  const appRoot = document.getElementById('deckbox-app');

  const stateStore = new StateStore();
  const cardRenderer = new CardRenderer();

  let transport = null;
  let actionDispatcher = null;
  let roleController = null;
  let chosenWildCardId = null;
  const clientSenderId = sessionStorage.getItem('deckbox_sender_id') || ('web_' + Math.floor(Math.random() * 900000 + 100000));
  sessionStorage.setItem('deckbox_sender_id', clientSenderId);
  let joinSeq = 1;

  // Determine WebSocket URL
  const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsHost = window.location.hostname || 'localhost';
  const wsPort = wsPortParam || 8081;
  const wsUrl = `${wsProtocol}//${wsHost}:${wsPort}/ws`;

  function setStatus(text, className) {
    if (!statusIndicatorEl) return;
    statusIndicatorEl.className = `status-indicator ${className}`;
    const txt = statusIndicatorEl.querySelector('.status-text');
    if (txt) txt.textContent = text;
  }

  function sendJoinRequest(requestedRole) {
    if (!transport || !transport.connected) return;
    const token = reconnectToken || sessionStorage.getItem('deckbox_token') || '';
    transport.send({
      v: 1,
      type: 'JOIN_REQUEST',
      seq: joinSeq++,
      sender: clientSenderId,
      timestamp: Math.floor(Date.now() / 1000),
      payload: {
        app_version: '0.1.0',
        protocol_version: 1,
        rules_hash: '',
        player_name: playerName,
        role: requestedRole,
        reconnect_token: token
      }
    });
  }

  setStatus('Connecting...', 'status--connecting');

  transport = new WebSocketTransport(
    wsUrl,
    // onMessage
    (message) => {
      if (message.type === 'JOIN_RESPONSE') {
        const payload = message.payload || {};
        if (payload.status === 'ACCEPTED') {
          setStatus('Connected', 'status--connected');
          if (payload.reconnect_token) {
            sessionStorage.setItem('deckbox_token', payload.reconnect_token);
          }
          if (payload.role) {
            const resolvedPid = message.recipient || clientSenderId;
            if (actionDispatcher) actionDispatcher.playerId = resolvedPid;
            roleController.setRole(payload.role, { playerId: resolvedPid });
            if (roleSelectEl) roleSelectEl.value = payload.role;
          }
        } else if (payload.status === 'REJECTED_VERSION_MISMATCH' || payload.status === 'REJECTED_PROTOCOL_MISMATCH') {
          setStatus('Version Mismatch', 'status--error');
          alert(`Version mismatch: Host is on ${payload.host_version || 'different version'}`);
        } else {
          setStatus('Rejected', 'status--error');
        }
      } else {
        stateStore.applyMessage(message);
      }
    },
    // onOpen
    () => {
      setStatus('Joining Room...', 'status--connecting');
      sendJoinRequest(initialRole);
    },
    // onClose
    () => {
      setStatus('Disconnected (Reconnecting...)', 'status--error');
    }
  );

  actionDispatcher = new ActionDispatcher({
    transport,
    playerId: clientSenderId,
    getState: () => stateStore.getState()
  });

  roleController = new RoleController({
    rootElement: appRoot,
    stateStore,
    actionDispatcher,
    initialRole: 'spectator'
  });
  roleController.setRole(initialRole, { playerId: clientSenderId });

  if (roleSelectEl) {
    roleSelectEl.value = initialRole;
    roleSelectEl.addEventListener('change', (e) => {
      const nextRole = e.target.value;
      roleController.setRole(nextRole, { playerId: actionDispatcher.playerId });
      sendJoinRequest(nextRole);
    });
  }

  // Subscribe state store updates to UI elements
  stateStore.subscribe((state) => {
    // 1. Turn Banner
    const turnBannerEl = document.getElementById('turn-banner');
    if (turnBannerEl) {
      if (state.status === 'waiting') {
        turnBannerEl.textContent = 'Waiting for players...';
      } else if (state.isMyTurn) {
        turnBannerEl.textContent = '★ It is YOUR turn! ★';
      } else if (state.activePlayer) {
        turnBannerEl.textContent = `${state.activePlayer.name} ist am Zug`;
      } else {
        turnBannerEl.textContent = 'DeckBox — Alle Ablegen!';
      }
    }

    // 2. Discard Pile
    const discardContainer = document.getElementById('discard-pile-container');
    if (discardContainer) {
      if (state.topDiscard) {
        discardContainer.replaceChildren();
        const topCardEl = cardRenderer.renderCard(state.topDiscard, { isPlayable: false });
        discardContainer.appendChild(topCardEl);
      }
    }

    // 3. Draw Pile Deck
    const drawDeckContainer = document.getElementById('draw-deck-container');
    if (drawDeckContainer) {
      cardRenderer.renderDeck(state.drawPileCount, drawDeckContainer);
    }

    // 4. Direction Indicator
    const dirIndicator = document.getElementById('direction-indicator');
    if (dirIndicator) {
      dirIndicator.style.transform = `rotate(${state.direction === 1 ? '0deg' : '180deg'})`;
    }

    // 5. Player Hand
    const handContainer = document.getElementById('hand-container');
    if (handContainer && roleController.getRole() === 'player') {
      cardRenderer.renderHand(state.myHand, handContainer, {
        onClick: (card) => {
          if (card.color === 'wild') {
            chosenWildCardId = card.id;
            const modal = document.getElementById('color-picker-modal');
            if (modal) {
              if (typeof modal.showModal === 'function') modal.showModal();
              else modal.style.display = 'block';
            }
          } else {
            actionDispatcher.dispatchPlayCard(card.id);
          }
        }
      });
    }
  });

  // Wire buttons
  const btnDraw = document.getElementById('btn-draw');
  if (btnDraw) {
    btnDraw.addEventListener('click', () => {
      actionDispatcher.dispatchDrawCard();
    });
  }

  const btnUno = document.getElementById('btn-uno');
  if (btnUno) {
    btnUno.addEventListener('click', () => {
      actionDispatcher.dispatchCallUno();
    });
  }

  // Emotes
  const emoteButtons = document.querySelectorAll('.btn-emote');
  emoteButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const emoteId = btn.getAttribute('data-emote');
      if (emoteId) actionDispatcher.dispatchSendEmote(emoteId);
    });
  });

  // Wild Color Picker Modal buttons
  const colorButtons = document.querySelectorAll('.btn-color-pick');
  colorButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const color = btn.getAttribute('data-color');
      const modal = document.getElementById('color-picker-modal');
      if (modal) {
        if (typeof modal.close === 'function') modal.close();
        else modal.style.display = 'none';
      }
      if (chosenWildCardId && color) {
        actionDispatcher.dispatchPlayCard(chosenWildCardId, color);
        chosenWildCardId = null;
      }
    });
  });

  // Join Modal (if no room PIN was specified)
  const joinModal = document.getElementById('join-modal');
  if (!roomCode && joinModal) {
    if (typeof joinModal.showModal === 'function') joinModal.showModal();
    else joinModal.style.display = 'block';

    const joinForm = document.getElementById('join-form');
    if (joinForm) {
      joinForm.addEventListener('submit', (e) => {
        e.preventDefault();
        const pinInput = document.getElementById('input-room-code');
        const nameInput = document.getElementById('input-player-name');
        const roleInput = document.getElementById('input-role');
        const pin = pinInput ? pinInput.value.trim() : '';
        const name = nameInput ? nameInput.value.trim() : '';
        const role = roleInput ? roleInput.value : 'player';
        if (pin) {
          window.location.search = `?room=${encodeURIComponent(pin)}&role=${encodeURIComponent(role)}&name=${encodeURIComponent(name)}`;
        }
      });
    }
  }
});
