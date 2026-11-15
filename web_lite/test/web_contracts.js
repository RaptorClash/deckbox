/**
 * Web Client Contract Reference Implementation & Specification
 * Defines authoritative interfaces and logic for StateStore, CardRenderer,
 * ActionDispatcher, RoleController, and AntiLeakSanitizer.
 */

import { setupGlobalDOM } from './mock_dom.js';

setupGlobalDOM();

// ============================================================================
// 1. Reactive Match State Store
// ============================================================================

export class StateStore {
  constructor(initialState = {}) {
    this._listeners = new Set();
    this._state = {
      matchId: null,
      seq: 0,
      status: 'idle', // 'idle' | 'waiting' | 'in_progress' | 'round_over' | 'match_over'
      topDiscard: null,
      drawPileCount: 0,
      direction: 1, // 1 (clockwise) or -1 (counter-clockwise)
      turnSeat: 0,
      activePlayer: null,
      players: [],
      myPlayerId: null,
      mySeat: null,
      myHand: [],
      isMyTurn: false,
      ...initialState
    };
  }

  getState() {
    // Return deep cloned snapshot to preserve immutability
    return JSON.parse(JSON.stringify(this._state));
  }

  subscribe(listener) {
    if (typeof listener !== 'function') {
      throw new TypeError('Subscriber listener must be a function');
    }
    this._listeners.add(listener);
    return () => {
      this._listeners.delete(listener);
    };
  }

  applyMessage(message) {
    if (!message || typeof message !== 'object') {
      return { success: false, error: 'INVALID_MESSAGE_ENVELOPE' };
    }

    const { type, seq, payload } = message;

    if (!type || typeof type !== 'string') {
      return { success: false, error: 'MISSING_MESSAGE_TYPE' };
    }

    if (typeof seq !== 'number') {
      return { success: false, error: 'INVALID_SEQUENCE_NUMBER' };
    }

    // Sequence check: drop stale or duplicate messages if sequence is not newer
    if (seq <= this._state.seq && this._state.seq > 0) {
      return { success: false, error: 'STALE_SEQUENCE_DROPPED', droppedSeq: seq };
    }

    if (!payload || typeof payload !== 'object') {
      return { success: false, error: 'INVALID_MESSAGE_PAYLOAD' };
    }

    const prevState = this.getState();
    let updated = false;

    if (type === 'PUBLIC_STATE_UPDATE') {
      this._applyPublicUpdate(payload, seq);
      updated = true;
    } else if (type === 'PLAYER_VIEW_UPDATE') {
      this._applyPlayerViewUpdate(payload, seq);
      updated = true;
    } else if (type === 'STATUS_UPDATE') {
      this._state.seq = seq;
      if (payload.status) this._state.status = payload.status;
      updated = true;
    } else {
      return { success: false, error: 'UNKNOWN_MESSAGE_TYPE' };
    }

    if (updated) {
      const newState = this.getState();
      this._notifyListeners(newState, prevState);
      return { success: true, newState };
    }

    return { success: false, error: 'NO_UPDATE_APPLIED' };
  }

  _applyPublicUpdate(payload, seq) {
    this._state.seq = seq;
    if (payload.match_id !== undefined) this._state.matchId = payload.match_id;
    if (payload.status !== undefined) this._state.status = payload.status;
    if (payload.top_discard !== undefined) this._state.topDiscard = payload.top_discard;
    if (payload.draw_pile_count !== undefined) this._state.drawPileCount = payload.draw_pile_count;
    if (payload.direction !== undefined) this._state.direction = payload.direction;
    if (payload.turn_seat !== undefined) this._state.turnSeat = payload.turn_seat;
    if (Array.isArray(payload.players)) {
      this._state.players = payload.players.map(p => ({
        seat: p.seat,
        name: p.name,
        cardCount: p.card_count ?? p.cardCount ?? 0,
        calledUno: Boolean(p.called_uno ?? p.calledUno),
        id: p.id || null
      }));
    }

    this._computeActivePlayer();
    this._computeIsMyTurn();
  }

  _applyPlayerViewUpdate(payload, seq) {
    this._applyPublicUpdate(payload, seq);

    if (payload.my_player_id !== undefined) this._state.myPlayerId = payload.my_player_id;
    if (payload.my_seat !== undefined) this._state.mySeat = payload.my_seat;
    if (Array.isArray(payload.my_hand)) {
      this._state.myHand = payload.my_hand.map(card => {
        const isPlayable = this._isCardPlayable(card);
        return {
          ...card,
          playable: card.playable !== undefined ? card.playable : isPlayable
        };
      });
    }

    this._computeIsMyTurn();
  }

  _computeActivePlayer() {
    const active = this._state.players.find(p => p.seat === this._state.turnSeat);
    this._state.activePlayer = active ? { ...active } : null;
  }

  _computeIsMyTurn() {
    if (this._state.mySeat !== null && this._state.mySeat !== undefined) {
      this._state.isMyTurn = (this._state.turnSeat === this._state.mySeat);
    } else {
      this._state.isMyTurn = false;
    }
  }

  _isCardPlayable(card) {
    if (!this._state.topDiscard) return true;
    if (card.color === 'wild') return true;
    if (card.color === this._state.topDiscard.color) return true;
    if (card.value !== undefined && card.value === this._state.topDiscard.value) return true;
    return false;
  }

  _notifyListeners(newState, prevState) {
    for (const listener of this._listeners) {
      try {
        listener(newState, prevState);
      } catch (err) {
        // Prevent listener exceptions from breaking store dispatch
        console.error('StateStore listener error:', err);
      }
    }
  }
}

// ============================================================================
// 2. Card HTML/CSS DOM Renderer & Accessibility Geometric Symbols
// ============================================================================

export const COLOR_SYMBOLS = {
  red: { name: 'Triangle', char: '▲', shape: 'triangle' },
  blue: { name: 'Diamond', char: '◆', shape: 'diamond' },
  green: { name: 'Circle', char: '●', shape: 'circle' },
  yellow: { name: 'Star', char: '★', shape: 'star' },
  wild: { name: 'Wild', char: '✱', shape: 'wild' }
};

export const VALUE_LABELS = {
  '0': '0', '1': '1', '2': '2', '3': '3', '4': '4',
  '5': '5', '6': '6', '7': '7', '8': '8', '9': '9',
  'skip': '⊘',
  'reverse': '⇄',
  'draw_two': '+2',
  'wild': 'W',
  'wild_draw_four': '+4'
};

export class CardRenderer {
  constructor(options = {}) {
    this.options = {
      enableColorblindSymbols: true,
      cardBackAsset: 'assets/card_back.svg',
      ...options
    };
  }

  renderCard(card, renderOptions = {}) {
    const doc = globalThis.document;
    const cardEl = doc.createElement('div');
    cardEl.classList.add('card');

    // Handle null or invalid card object
    if (!card || typeof card !== 'object') {
      cardEl.classList.add('card--unknown');
      cardEl.textContent = '?';
      return cardEl;
    }

    // Masked opponent card handling (strict anti-leak)
    if (card.masked === true) {
      cardEl.classList.add('card--masked', 'card--back');
      cardEl.setAttribute('role', 'img');
      cardEl.setAttribute('aria-label', 'Card (Face Down)');

      const backLogo = doc.createElement('div');
      backLogo.classList.add('card__back-logo');
      backLogo.textContent = 'DeckBox';
      cardEl.appendChild(backLogo);

      // NEVER attach card id, value, or color attributes to masked cards
      return cardEl;
    }

    const color = (card.color || 'wild').toLowerCase();
    const rawValue = String(card.value ?? 'unknown');
    // Sanitize value to prevent HTML injection
    const sanitizedValue = rawValue.replace(/[<>"'&]/g, '');
    const displayLabel = VALUE_LABELS[sanitizedValue] || sanitizedValue;
    const symbolInfo = COLOR_SYMBOLS[color] || COLOR_SYMBOLS.wild;

    // Visual classes
    cardEl.classList.add(`card--${color}`);
    cardEl.classList.add(`card--val-${sanitizedValue}`);

    // Data attributes
    if (card.id) {
      cardEl.setAttribute('data-card-id', String(card.id));
    }
    cardEl.setAttribute('data-color', color);
    cardEl.setAttribute('data-value', sanitizedValue);

    // Playable / Disabled states
    const isPlayable = Boolean(card.playable || renderOptions.isPlayable);
    if (isPlayable) {
      cardEl.classList.add('card--playable');
      cardEl.setAttribute('role', 'button');
      cardEl.setAttribute('tabindex', '0');
      cardEl.setAttribute('aria-disabled', 'false');

      if (typeof renderOptions.onClick === 'function') {
        cardEl.addEventListener('click', (e) => {
          renderOptions.onClick(card, e);
        });
      }
    } else {
      cardEl.classList.add('card--disabled');
      cardEl.setAttribute('role', 'img');
      cardEl.setAttribute('tabindex', '-1');
      cardEl.setAttribute('aria-disabled', 'true');
    }

    // Accessibility label with colorblind geometric symbol name
    const colorCap = color.charAt(0).toUpperCase() + color.slice(1);
    const ariaText = color === 'wild'
      ? `${sanitizedValue === 'wild_draw_four' ? 'Wild Draw Four' : 'Wild'}`
      : `${colorCap} ${sanitizedValue} (${symbolInfo.name})`;
    cardEl.setAttribute('aria-label', ariaText);

    // Corner badges with geometric symbol
    const cornerTop = this._createCornerBadge(displayLabel, symbolInfo, 'top-left');
    const centerDisplay = this._createCenterDisplay(displayLabel, symbolInfo, color);
    const cornerBottom = this._createCornerBadge(displayLabel, symbolInfo, 'bottom-right');

    cardEl.appendChild(cornerTop);
    cardEl.appendChild(centerDisplay);
    cardEl.appendChild(cornerBottom);

    return cardEl;
  }

  _createCornerBadge(label, symbolInfo, position) {
    const doc = globalThis.document;
    const badge = doc.createElement('div');
    badge.classList.add('card__badge', `card__badge--${position}`);

    const valSpan = doc.createElement('span');
    valSpan.classList.add('card__val');
    valSpan.textContent = label;
    badge.appendChild(valSpan);

    if (this.options.enableColorblindSymbols) {
      const symSpan = doc.createElement('span');
      symSpan.classList.add('card__symbol', `symbol-${symbolInfo.shape}`);
      symSpan.setAttribute('aria-hidden', 'true');
      symSpan.textContent = symbolInfo.char;
      badge.appendChild(symSpan);
    }

    return badge;
  }

  _createCenterDisplay(label, symbolInfo, color) {
    const doc = globalThis.document;
    const center = doc.createElement('div');
    center.classList.add('card__center');

    const mainVal = doc.createElement('span');
    mainVal.classList.add('card__main-val');
    mainVal.textContent = label;
    center.appendChild(mainVal);

    if (this.options.enableColorblindSymbols) {
      const symBig = doc.createElement('span');
      symBig.classList.add('card__center-symbol', `symbol-${symbolInfo.shape}`);
      symBig.setAttribute('aria-hidden', 'true');
      symBig.textContent = symbolInfo.char;
      center.appendChild(symBig);
    }

    return center;
  }

  renderHand(cards, container, options = {}) {
    if (!container) return;
    container.replaceChildren();

    if (!Array.isArray(cards) || cards.length === 0) {
      container.classList.add('hand--empty');
      return;
    }

    container.classList.remove('hand--empty');
    for (const card of cards) {
      const cardEl = this.renderCard(card, options);
      container.appendChild(cardEl);
    }
  }

  renderDeck(count, container) {
    if (!container) return;
    container.replaceChildren();

    const doc = globalThis.document;
    const deckEl = doc.createElement('div');
    deckEl.classList.add('deck-stack');

    if (count <= 0) {
      deckEl.classList.add('deck-stack--depleted');
      deckEl.setAttribute('aria-label', 'Draw Pile (Empty)');
      const label = doc.createElement('span');
      label.textContent = 'Empty';
      deckEl.appendChild(label);
    } else {
      deckEl.setAttribute('aria-label', `Draw Pile (${count} cards)`);
      const back = doc.createElement('div');
      back.classList.add('card', 'card--back');
      back.textContent = 'DeckBox';
      deckEl.appendChild(back);

      const countBadge = doc.createElement('span');
      countBadge.classList.add('deck-stack__count');
      countBadge.textContent = String(count);
      deckEl.appendChild(countBadge);
    }

    container.appendChild(deckEl);
  }
}

// ============================================================================
// 3. Action Dispatcher & Client-Side Pre-Validation
// ============================================================================

export class ActionDispatcher {
  constructor({ transport, playerId, getState }) {
    if (!transport || typeof transport.send !== 'function') {
      throw new Error('Transport with a send() method is required');
    }
    if (!playerId || typeof playerId !== 'string') {
      throw new Error('Valid playerId string is required');
    }
    if (typeof getState !== 'function') {
      throw new Error('getState function is required');
    }

    this.transport = transport;
    this.playerId = playerId;
    this.getState = getState;
    this.seq = 1;
    this._inFlight = false;
  }

  frameEnvelope(type, payload = {}) {
    return {
      v: 1,
      type,
      seq: this.seq++,
      sender: this.playerId,
      timestamp: Math.floor(Date.now() / 1000),
      payload
    };
  }

  validatePlayCard(cardId, chosenColor = null) {
    const state = this.getState();

    if (!state.isMyTurn) {
      return { valid: false, error: 'NOT_MY_TURN' };
    }

    const card = (state.myHand || []).find(c => c.id === cardId);
    if (!card) {
      return { valid: false, error: 'CARD_NOT_IN_HAND' };
    }

    // Check playability
    const isWild = (card.color === 'wild');
    if (!isWild && state.topDiscard) {
      const colorMatch = (card.color === state.topDiscard.color);
      const valueMatch = (card.value !== undefined && card.value === state.topDiscard.value);
      if (!colorMatch && !valueMatch) {
        return { valid: false, error: 'CARD_NOT_PLAYABLE' };
      }
    }

    // If wild, must select valid color
    if (isWild) {
      const validColors = ['red', 'blue', 'green', 'yellow'];
      if (!chosenColor) {
        return { valid: false, error: 'MISSING_CHOSEN_COLOR' };
      }
      if (!validColors.includes(chosenColor.toLowerCase())) {
        return { valid: false, error: 'INVALID_CHOSEN_COLOR' };
      }
    }

    return { valid: true, card };
  }

  dispatchPlayCard(cardId, chosenColor = null) {
    if (this._inFlight) {
      return { success: false, error: 'ACTION_IN_FLIGHT' };
    }

    const validation = this.validatePlayCard(cardId, chosenColor);
    if (!validation.valid) {
      return { success: false, error: validation.error };
    }

    this._inFlight = true;
    try {
      const envelope = this.frameEnvelope('ACTION_PLAY_CARD', {
        card_id: cardId,
        chosen_color: chosenColor ? chosenColor.toLowerCase() : null
      });

      this.transport.send(envelope);
      return { success: true, message: envelope };
    } finally {
      this._inFlight = false;
    }
  }

  validateDrawCard() {
    const state = this.getState();
    if (!state.isMyTurn) {
      return { valid: false, error: 'NOT_MY_TURN' };
    }
    return { valid: true };
  }

  dispatchDrawCard() {
    if (this._inFlight) {
      return { success: false, error: 'ACTION_IN_FLIGHT' };
    }

    const validation = this.validateDrawCard();
    if (!validation.valid) {
      return { success: false, error: validation.error };
    }

    this._inFlight = true;
    try {
      const envelope = this.frameEnvelope('ACTION_DRAW_CARD', {});
      this.transport.send(envelope);
      return { success: true, message: envelope };
    } finally {
      this._inFlight = false;
    }
  }

  dispatchCallUno(targetPlayerId = null) {
    const envelope = this.frameEnvelope('ACTION_CALL_UNO', {
      target_player_id: targetPlayerId || null
    });
    this.transport.send(envelope);
    return { success: true, message: envelope };
  }

  dispatchSendEmote(emoteId) {
    if (!emoteId || typeof emoteId !== 'string') {
      return { success: false, error: 'INVALID_EMOTE_ID' };
    }
    const envelope = this.frameEnvelope('ACTION_SEND_EMOTE', {
      emote_id: emoteId
    });
    this.transport.send(envelope);
    return { success: true, message: envelope };
  }
}

// ============================================================================
// 4. Role Controller (Player, Table, Spectator Views)
// ============================================================================

export class RoleController {
  constructor({ rootElement, stateStore, actionDispatcher, initialRole = 'spectator' }) {
    this.rootElement = rootElement;
    this.stateStore = stateStore;
    this.actionDispatcher = actionDispatcher;
    this.currentRole = null;
    this.playerId = null;
    this._unsubscribe = null;

    if (this.rootElement) {
      this._initDOMStructure();
    }

    this.setRole(initialRole);

    if (this.stateStore) {
      this._unsubscribe = this.stateStore.subscribe(() => {
        this.render();
      });
    }
  }

  destroy() {
    if (this._unsubscribe) {
      this._unsubscribe();
      this._unsubscribe = null;
    }
  }

  getRole() {
    return this.currentRole;
  }

  setRole(role, options = {}) {
    const validRoles = ['player', 'table', 'spectator'];
    if (!validRoles.includes(role)) {
      return { success: false, error: 'INVALID_ROLE' };
    }

    if (role === 'player') {
      const pId = options.playerId || (this.stateStore ? this.stateStore.getState().myPlayerId : null);
      if (!pId) {
        return { success: false, error: 'PLAYER_ID_REQUIRED' };
      }
      this.playerId = pId;
    }

    this.currentRole = role;

    if (this.rootElement) {
      this.rootElement.classList.remove('role--player', 'role--table', 'role--spectator');
      this.rootElement.classList.add(`role--${role}`);
      this._applyRoleVisibility(role);
      this.render();
    }

    return { success: true, role };
  }

  _initDOMStructure() {
    const doc = globalThis.document;

    // Hand container (player only)
    if (!this.rootElement.querySelector('#hand-container')) {
      const hand = doc.createElement('div');
      hand.id = 'hand-container';
      this.rootElement.appendChild(hand);
    }

    // Action controls (player only)
    if (!this.rootElement.querySelector('#player-actions')) {
      const actions = doc.createElement('div');
      actions.id = 'player-actions';

      const btnDraw = doc.createElement('button');
      btnDraw.id = 'btn-draw';
      btnDraw.textContent = 'Draw Card';

      const btnUno = doc.createElement('button');
      btnUno.id = 'btn-uno';
      btnUno.textContent = 'Call UNO!';

      actions.appendChild(btnDraw);
      actions.appendChild(btnUno);
      this.rootElement.appendChild(actions);
    }

    // Table playmat (table + spectator + player)
    if (!this.rootElement.querySelector('#table-playmat')) {
      const playmat = doc.createElement('div');
      playmat.id = 'table-playmat';
      this.rootElement.appendChild(playmat);
    }

    // Scoreboard / Player ring (table + spectator)
    if (!this.rootElement.querySelector('#scoreboard')) {
      const score = doc.createElement('div');
      score.id = 'scoreboard';
      this.rootElement.appendChild(score);
    }

    // Spectator overlay (spectator only)
    if (!this.rootElement.querySelector('#spectator-overlay')) {
      const spec = doc.createElement('div');
      spec.id = 'spectator-overlay';
      spec.textContent = 'Spectator Mode (Read-Only)';
      this.rootElement.appendChild(spec);
    }

    // Emotes container (all roles)
    if (!this.rootElement.querySelector('#emote-container')) {
      const emotes = doc.createElement('div');
      emotes.id = 'emote-container';
      this.rootElement.appendChild(emotes);
    }
  }

  _applyRoleVisibility(role) {
    const handEl = this.rootElement.querySelector('#hand-container');
    const actionsEl = this.rootElement.querySelector('#player-actions');
    const playmatEl = this.rootElement.querySelector('#table-playmat');
    const scoreEl = this.rootElement.querySelector('#scoreboard');
    const specEl = this.rootElement.querySelector('#spectator-overlay');

    if (role === 'player') {
      if (handEl) handEl.style.display = 'block';
      if (actionsEl) actionsEl.style.display = 'block';
      if (playmatEl) playmatEl.style.display = 'block';
      if (scoreEl) scoreEl.style.display = 'none';
      if (specEl) specEl.style.display = 'none';
    } else if (role === 'table') {
      if (handEl) handEl.style.display = 'none';
      if (actionsEl) actionsEl.style.display = 'none';
      if (playmatEl) playmatEl.style.display = 'block';
      if (scoreEl) scoreEl.style.display = 'block';
      if (specEl) specEl.style.display = 'none';
    } else if (role === 'spectator') {
      if (handEl) handEl.style.display = 'none';
      if (actionsEl) actionsEl.style.display = 'none';
      if (playmatEl) playmatEl.style.display = 'block';
      if (scoreEl) scoreEl.style.display = 'block';
      if (specEl) specEl.style.display = 'block';
    }
  }

  render() {
    if (!this.rootElement || !this.stateStore) return;
    const state = this.stateStore.getState();

    // If player view, update button enabled/disabled states based on isMyTurn
    if (this.currentRole === 'player') {
      const btnDraw = this.rootElement.querySelector('#btn-draw');
      const btnUno = this.rootElement.querySelector('#btn-uno');
      if (btnDraw) {
        btnDraw.disabled = !state.isMyTurn;
      }
      if (btnUno) {
        btnUno.disabled = false; // UNO can be called any time or reactively
      }
    }

    // If table or spectator view, render scoreboard without any private hand leaks
    if (this.currentRole === 'table' || this.currentRole === 'spectator') {
      const scoreEl = this.rootElement.querySelector('#scoreboard');
      if (scoreEl && Array.isArray(state.players)) {
        scoreEl.replaceChildren();
        const doc = globalThis.document;
        for (const player of state.players) {
          const item = doc.createElement('div');
          item.classList.add('scoreboard__item');
          item.setAttribute('data-seat', String(player.seat));
          if (player.seat === state.turnSeat) {
            item.classList.add('scoreboard__item--active');
          }
          const nameSpan = doc.createElement('span');
          nameSpan.classList.add('scoreboard__name');
          nameSpan.textContent = player.name;
          const countSpan = doc.createElement('span');
          countSpan.classList.add('scoreboard__count');
          countSpan.textContent = `${player.cardCount} cards`;
          item.appendChild(nameSpan);
          item.appendChild(countSpan);
          scoreEl.appendChild(item);
        }
      }
    }
  }
}

// ============================================================================
// 5. Anti-Leak Sanitizer (Adversarial Client Protection)
// ============================================================================

export class AntiLeakSanitizer {
  static sanitizeOpponentPayload(opponent) {
    if (!opponent || typeof opponent !== 'object') return {};
    // Strict whitelist: seat, name, cardCount, calledUno
    return {
      seat: opponent.seat,
      name: opponent.name,
      cardCount: opponent.cardCount ?? opponent.card_count ?? 0,
      calledUno: Boolean(opponent.calledUno ?? opponent.called_uno)
    };
  }

  static verifyNoLeakInDOM(containerElement, privateCardIds = []) {
    const leaks = [];
    if (!containerElement) return leaks;

    // Check all elements in container
    const all = [containerElement].concat(containerElement.querySelectorAll('*'));
    for (const elem of all) {
      // Check attributes
      const idAttr = elem.getAttribute('data-card-id');
      if (idAttr && privateCardIds.includes(idAttr)) {
        leaks.push({ type: 'PRIVATE_CARD_ID_EXPOSED', attr: 'data-card-id', value: idAttr });
      }
      // Check for undefined / null leakage
      if (idAttr === 'undefined' || idAttr === 'null') {
        leaks.push({ type: 'UNDEFINED_CARD_ID', attr: 'data-card-id' });
      }
      const valAttr = elem.getAttribute('data-value');
      if (valAttr === 'undefined' || valAttr === 'null') {
        leaks.push({ type: 'UNDEFINED_VALUE', attr: 'data-value' });
      }
      const colorAttr = elem.getAttribute('data-color');
      if (colorAttr === 'undefined' || colorAttr === 'null') {
        leaks.push({ type: 'UNDEFINED_COLOR', attr: 'data-color' });
      }

      // Check image src
      const src = elem.getAttribute('src');
      if (src && (src.includes('undefined') || src.includes('null'))) {
        leaks.push({ type: 'UNDEFINED_ASSET_URL', src });
      }
    }
    return leaks;
  }
}
