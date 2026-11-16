/**
 * ActionDispatcher Test Suite
 * Tests action payload construction, envelope framing (v=1, seq, sender, timestamp),
 * and client-side pre-validation (blocking unplayable card plays, out-of-turn actions,
 * missing wild colors, and rapid duplicate dispatches).
 *
 * Command: node --test web_lite/test/action_dispatcher.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Resolve module under test: web_lite/js/action_dispatcher.js or contract specification
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const implPath = path.resolve(__dirname, '../js/action_dispatcher.js');

let ActionDispatcher;
if (fs.existsSync(implPath)) {
  const mod = await import(pathToFileURL(implPath).href);
  ActionDispatcher = mod.ActionDispatcher || mod.default;
} else {
  const mod = await import('./web_contracts.js');
  ActionDispatcher = mod.ActionDispatcher;
}

class MockTransport {
  constructor() {
    this.sent = [];
    this.connected = true;
  }

  send(msg) {
    if (!this.connected) {
      throw new Error('Transport is disconnected');
    }
    this.sent.push(msg);
  }

  lastMessage() {
    return this.sent[this.sent.length - 1];
  }

  clear() {
    this.sent = [];
  }
}

describe('ActionDispatcher (Framing & Pre-Validation)', () => {
  const createHarness = (stateOverrides = {}) => {
    const transport = new MockTransport();
    const playerId = 'player-uuid-42';
    const state = {
      isMyTurn: true,
      topDiscard: { id: 'disc-top', color: 'red', value: '5' },
      myHand: [
        { id: 'c-red-3', color: 'red', value: '3' },
        { id: 'c-blue-5', color: 'blue', value: '5' },
        { id: 'c-green-9', color: 'green', value: '9' },
        { id: 'c-wild', color: 'wild', value: 'wild' }
      ],
      ...stateOverrides
    };

    const dispatcher = new ActionDispatcher({
      transport,
      playerId,
      getState: () => state
    });

    return { dispatcher, transport, state };
  };

  // ==========================================================================
  // Tier 1: Feature Coverage Tests
  // ==========================================================================
  describe('Tier 1: Feature Coverage', () => {
    it('1. Frames ACTION_PLAY_CARD with v=1, monotonic seq, sender UUID, and timestamp', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchPlayCard('c-red-3');

      assert.equal(res.success, true);
      assert.equal(transport.sent.length, 1);

      const msg = transport.lastMessage();
      assert.equal(msg.v, 1);
      assert.equal(msg.type, 'ACTION_PLAY_CARD');
      assert.equal(msg.seq, 1);
      assert.equal(msg.sender, 'player-uuid-42');
      assert.equal(typeof msg.timestamp, 'number');
      assert.equal(msg.payload.card_id, 'c-red-3');
      assert.equal(msg.payload.chosen_color, null);
    });

    it('2. Frames ACTION_DRAW_CARD with empty payload envelope', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchDrawCard();

      assert.equal(res.success, true);
      assert.equal(transport.sent.length, 1);

      const msg = transport.lastMessage();
      assert.equal(msg.v, 1);
      assert.equal(msg.type, 'ACTION_DRAW_CARD');
      assert.deepEqual(msg.payload, {});
    });

    it('3. Frames ACTION_CALL_UNO with target_player_id payload', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchCallUno('opponent-seat-2');

      assert.equal(res.success, true);
      assert.equal(transport.sent.length, 1);

      const msg = transport.lastMessage();
      assert.equal(msg.v, 1);
      assert.equal(msg.type, 'ACTION_CALL_UNO');
      assert.equal(msg.payload.target_player_id, 'opponent-seat-2');
    });

    it('4. Frames ACTION_SEND_EMOTE with emote_id payload', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchSendEmote('thumbs_up');

      assert.equal(res.success, true);
      assert.equal(transport.sent.length, 1);

      const msg = transport.lastMessage();
      assert.equal(msg.v, 1);
      assert.equal(msg.type, 'ACTION_SEND_EMOTE');
      assert.equal(msg.payload.emote_id, 'thumbs_up');
    });

    it('5. Increments seq counter monotonically on consecutive dispatches', () => {
      const { dispatcher, transport } = createHarness();
      dispatcher.dispatchDrawCard();
      dispatcher.dispatchCallUno();
      dispatcher.dispatchSendEmote('heart');

      assert.equal(transport.sent.length, 3);
      assert.equal(transport.sent[0].seq, 1);
      assert.equal(transport.sent[1].seq, 2);
      assert.equal(transport.sent[2].seq, 3);
    });

    it('6. Transport.send receives complete structured envelope matching JSON contract', () => {
      const { dispatcher, transport } = createHarness();
      dispatcher.dispatchPlayCard('c-blue-5'); // matches value 5 on top discard

      const raw = JSON.stringify(transport.lastMessage());
      const parsed = JSON.parse(raw);

      assert.equal(parsed.v, 1);
      assert.equal(parsed.type, 'ACTION_PLAY_CARD');
      assert.equal(parsed.sender, 'player-uuid-42');
      assert.equal(parsed.payload.card_id, 'c-blue-5');
    });
  });

  // ==========================================================================
  // Tier 2: Boundary & Pre-Validation Cases
  // ==========================================================================
  describe('Tier 2: Boundary & Pre-Validation Cases', () => {
    it('7. Pre-validation blocks ACTION_PLAY_CARD when isMyTurn is false and does NOT send', () => {
      const { dispatcher, transport } = createHarness({ isMyTurn: false });
      const res = dispatcher.dispatchPlayCard('c-red-3');

      assert.equal(res.success, false);
      assert.equal(res.error, 'NOT_MY_TURN');
      assert.equal(transport.sent.length, 0, 'Must NOT transmit unvalidated action');
    });

    it('8. Pre-validation blocks ACTION_PLAY_CARD when card is not in player hand', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchPlayCard('non-existent-card-id');

      assert.equal(res.success, false);
      assert.equal(res.error, 'CARD_NOT_IN_HAND');
      assert.equal(transport.sent.length, 0);
    });

    it('9. Pre-validation blocks ACTION_PLAY_CARD when card is not playable (mismatch color & value)', () => {
      // Top discard is Red 5. c-green-9 is Green 9. Neither color nor value matches!
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchPlayCard('c-green-9');

      assert.equal(res.success, false);
      assert.equal(res.error, 'CARD_NOT_PLAYABLE');
      assert.equal(transport.sent.length, 0);
    });

    it('10. Pre-validation blocks Wild play when chosen_color is missing', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchPlayCard('c-wild', null);

      assert.equal(res.success, false);
      assert.equal(res.error, 'MISSING_CHOSEN_COLOR');
      assert.equal(transport.sent.length, 0);
    });

    it('10b. Pre-validation cleanly rejects non-string chosen_color on Wild card without throwing', () => {
      const { dispatcher, transport } = createHarness();
      for (const badColor of [123, true, false, {}, [], () => {}]) {
        const res = dispatcher.dispatchPlayCard('c-wild', badColor);
        assert.equal(res.success, false);
        assert.equal(res.error, 'MISSING_CHOSEN_COLOR');
        assert.equal(transport.sent.length, 0);
      }
    });

    it('11. Pre-validation blocks Wild play when chosen_color is invalid (e.g. purple)', () => {
      const { dispatcher, transport } = createHarness();
      const res = dispatcher.dispatchPlayCard('c-wild', 'purple');

      assert.equal(res.success, false);
      assert.equal(res.error, 'INVALID_CHOSEN_COLOR');
      assert.equal(transport.sent.length, 0);
    });

    it('12. Pre-validation allows Wild play when valid chosen_color is provided', () => {
      const validColors = ['red', 'blue', 'green', 'yellow'];
      for (const color of validColors) {
        const { dispatcher, transport } = createHarness();
        const res = dispatcher.dispatchPlayCard('c-wild', color);

        assert.equal(res.success, true);
        assert.equal(transport.sent.length, 1);
        assert.equal(transport.lastMessage().payload.chosen_color, color);
      }
    });

    it('13. Pre-validation blocks ACTION_DRAW_CARD when isMyTurn is false', () => {
      const { dispatcher, transport } = createHarness({ isMyTurn: false });
      const res = dispatcher.dispatchDrawCard();

      assert.equal(res.success, false);
      assert.equal(res.error, 'NOT_MY_TURN');
      assert.equal(transport.sent.length, 0);
    });

    it('14. ActionDispatcher rejects when transport throws or is disconnected', () => {
      const { dispatcher, transport } = createHarness();
      transport.connected = false;

      assert.throws(() => {
        dispatcher.dispatchDrawCard();
      }, /Transport is disconnected/);
    });
  });

  // ==========================================================================
  // Tier 3: Combinatorial & Robustness
  // ==========================================================================
  describe('Tier 3: Combinatorial & Robustness', () => {
    it('15. Rejects invalid emote ID (empty string or non-string)', () => {
      const { dispatcher, transport } = createHarness();
      const res1 = dispatcher.dispatchSendEmote('');
      assert.equal(res1.success, false);
      assert.equal(res1.error, 'INVALID_EMOTE_ID');

      const res2 = dispatcher.dispatchSendEmote(null);
      assert.equal(res2.success, false);
      assert.equal(transport.sent.length, 0);
    });

    it('16. Validates constructor parameters requiring transport, playerId, and getState', () => {
      assert.throws(() => {
        new ActionDispatcher({});
      }, /Transport/);

      assert.throws(() => {
        new ActionDispatcher({ transport: new MockTransport() });
      }, /playerId/);

      assert.throws(() => {
        new ActionDispatcher({ transport: new MockTransport(), playerId: 'p1' });
      }, /getState/);
    });
  });
});
