/**
 * StateStore — Reactive client match state store
 * Handles message envelopes, monotonic sequence ordering, deep-clone snapshots,
 * and pub/sub listener notification.
 */

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
      this._state.players = payload.players.filter(Boolean).map(p => ({
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
      this._state.myHand = payload.my_hand.filter(Boolean).map(card => {
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

export default StateStore;
