/**
 * ActionDispatcher — Client-side action validation and WebSocket envelope framing.
 * Enforces in-flight locking and turn validation rules.
 */

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
      const effectiveColor = state.activeColor || state.topDiscard.color;
      const colorMatch = (card.color === effectiveColor);
      const valueMatch = (card.value !== undefined && card.value === state.topDiscard.value);
      if (!colorMatch && !valueMatch) {
        return { valid: false, error: 'CARD_NOT_PLAYABLE' };
      }
    }

    // If wild, must select valid color
    if (isWild) {
      const validColors = (state.activeSide === 'dark')
        ? ['pink', 'teal', 'purple', 'orange']
        : ['red', 'blue', 'green', 'yellow'];
      if (!chosenColor || typeof chosenColor !== 'string') {
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

export default ActionDispatcher;
