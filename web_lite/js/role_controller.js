/**
 * RoleController — Dynamic layout switching and view rendering for
 * Player (hand + actions), Table View (public scoreboard), and Spectator (read-only overlay).
 */

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

export default RoleController;
