/**
 * StateStore Test Suite
 * Tests reactive match state store initialization, PUBLIC_STATE_UPDATE, PLAYER_VIEW_UPDATE,
 * turn calculation, sequence ordering, boundary conditions, and immutability.
 *
 * Command: node --test web_lite/test/state_store.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Resolve module under test: use web_lite/js/state_store.js if present, otherwise contract specification
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const implPath = path.resolve(__dirname, '../js/state_store.js');

let StateStore;
if (fs.existsSync(implPath)) {
  const mod = await import(implPath);
  StateStore = mod.StateStore || mod.default;
} else {
  const mod = await import('./web_contracts.js');
  StateStore = mod.StateStore;
}

describe('StateStore (Reactive Match State)', () => {
  // ==========================================================================
  // Tier 1: Feature Coverage Tests
  // ==========================================================================
  describe('Tier 1: Feature Coverage', () => {
    it('1. Initial state defaults to idle status, zero seq, empty players, and null matchId', () => {
      const store = new StateStore();
      const state = store.getState();

      assert.equal(state.status, 'idle');
      assert.equal(state.seq, 0);
      assert.equal(state.matchId, null);
      assert.deepEqual(state.players, []);
      assert.deepEqual(state.myHand, []);
      assert.equal(state.topDiscard, null);
      assert.equal(state.drawPileCount, 0);
      assert.equal(state.direction, 1);
      assert.equal(state.isMyTurn, false);
      assert.equal(state.activePlayer, null);
    });

    it('2. Subscribing notifies listener with newState and prevState upon state update', () => {
      const store = new StateStore();
      const events = [];

      store.subscribe((newState, prevState) => {
        events.push({ newState, prevState });
      });

      const message = {
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          match_id: 'match-101',
          status: 'in_progress',
          top_discard: { id: 'c-1', color: 'red', value: '7' },
          draw_pile_count: 50,
          direction: 1,
          turn_seat: 0,
          players: [
            { seat: 0, name: 'Alice', card_count: 7, called_uno: false },
            { seat: 1, name: 'Bob', card_count: 7, called_uno: false }
          ]
        }
      };

      const result = store.applyMessage(message);
      assert.equal(result.success, true);
      assert.equal(events.length, 1);
      assert.equal(events[0].prevState.status, 'idle');
      assert.equal(events[0].newState.status, 'in_progress');
      assert.equal(events[0].newState.matchId, 'match-101');
      assert.equal(events[0].newState.seq, 1);
    });

    it('3. Unsubscribe function stops firing callbacks on future updates', () => {
      const store = new StateStore();
      let callCount = 0;

      const unsubscribe = store.subscribe(() => {
        callCount++;
      });

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: { match_id: 'm1', status: 'in_progress' }
      });
      assert.equal(callCount, 1);

      // Unsubscribe
      unsubscribe();

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 2,
        payload: { match_id: 'm1', status: 'round_over' }
      });
      assert.equal(callCount, 1); // Not incremented
    });

    it('4. Handles PUBLIC_STATE_UPDATE updating discard, draw pile, direction, and players', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          match_id: 'uno-game-99',
          status: 'in_progress',
          top_discard: { id: 'blue-5', color: 'blue', value: '5' },
          draw_pile_count: 42,
          direction: -1,
          turn_seat: 2,
          players: [
            { seat: 0, name: 'Player 0', card_count: 5, called_uno: false },
            { seat: 1, name: 'Player 1', card_count: 1, called_uno: true },
            { seat: 2, name: 'Player 2', card_count: 6, called_uno: false }
          ]
        }
      });

      const s = store.getState();
      assert.equal(s.matchId, 'uno-game-99');
      assert.deepEqual(s.topDiscard, { id: 'blue-5', color: 'blue', value: '5' });
      assert.equal(s.drawPileCount, 42);
      assert.equal(s.direction, -1);
      assert.equal(s.turnSeat, 2);
      assert.equal(s.players.length, 3);
      assert.equal(s.players[1].calledUno, true);
      assert.equal(s.players[1].cardCount, 1);
    });

    it('5. Computes activePlayer correctly matching turn_seat in players array', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 10,
        payload: {
          turn_seat: 1,
          players: [
            { seat: 0, name: 'SeatZero', card_count: 3 },
            { seat: 1, name: 'SeatOne', card_count: 4 }
          ]
        }
      });

      const s = store.getState();
      assert.notEqual(s.activePlayer, null);
      assert.equal(s.activePlayer.seat, 1);
      assert.equal(s.activePlayer.name, 'SeatOne');
    });

    it('6. Handles PLAYER_VIEW_UPDATE preserving private hand and setting mySeat and myPlayerId', () => {
      const store = new StateStore();
      const myCards = [
        { id: 'c-red-2', color: 'red', value: '2' },
        { id: 'c-blue-9', color: 'blue', value: '9' },
        { id: 'c-wild', color: 'wild', value: 'wild' }
      ];

      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 1,
        payload: {
          match_id: 'match-pv',
          status: 'in_progress',
          my_player_id: 'user-uuid-1234',
          my_seat: 1,
          turn_seat: 0,
          top_discard: { id: 'disc-1', color: 'red', value: '8' },
          draw_pile_count: 30,
          players: [
            { seat: 0, name: 'Opponent', card_count: 3 },
            { seat: 1, name: 'Me', card_count: 3 }
          ],
          my_hand: myCards
        }
      });

      const s = store.getState();
      assert.equal(s.myPlayerId, 'user-uuid-1234');
      assert.equal(s.mySeat, 1);
      assert.equal(s.myHand.length, 3);
      assert.equal(s.myHand[0].id, 'c-red-2');
      assert.equal(s.myHand[1].id, 'c-blue-9');
      assert.equal(s.myHand[2].id, 'c-wild');
    });

    it('7. Computes isMyTurn dynamically when turn_seat matches mySeat', () => {
      const store = new StateStore();

      // Setup player view for seat 2
      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 1,
        payload: {
          my_seat: 2,
          turn_seat: 1,
          players: [{ seat: 1, name: 'P1' }, { seat: 2, name: 'P2' }]
        }
      });
      assert.equal(store.getState().isMyTurn, false);

      // Now advance turn to seat 2
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 2,
        payload: {
          turn_seat: 2
        }
      });
      assert.equal(store.getState().isMyTurn, true);
    });
  });

  // ==========================================================================
  // Tier 2: Boundary & Corner Cases
  // ==========================================================================
  describe('Tier 2: Boundary & Corner Cases', () => {
    it('8. Handles empty or null message envelope gracefully without crashing', () => {
      const store = new StateStore();
      const resNull = store.applyMessage(null);
      assert.equal(resNull.success, false);
      assert.equal(resNull.error, 'INVALID_MESSAGE_ENVELOPE');

      const resUndef = store.applyMessage(undefined);
      assert.equal(resUndef.success, false);

      const resEmpty = store.applyMessage({});
      assert.equal(resEmpty.success, false);
    });

    it('9. Rejects malformed message with missing seq or missing payload', () => {
      const store = new StateStore();

      const missingSeq = store.applyMessage({
        type: 'PUBLIC_STATE_UPDATE',
        payload: {}
      });
      assert.equal(missingSeq.success, false);
      assert.equal(missingSeq.error, 'INVALID_SEQUENCE_NUMBER');

      const missingPayload = store.applyMessage({
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1
      });
      assert.equal(missingPayload.success, false);
      assert.equal(missingPayload.error, 'INVALID_MESSAGE_PAYLOAD');
    });

    it('10. Drops stale out-of-order sequence updates (seq <= current seq)', () => {
      const store = new StateStore();

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 10,
        payload: { turn_seat: 1, draw_pile_count: 50 }
      });
      assert.equal(store.getState().seq, 10);
      assert.equal(store.getState().drawPileCount, 50);

      // Incoming stale message with seq 5
      const staleRes = store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 5,
        payload: { turn_seat: 0, draw_pile_count: 80 }
      });

      assert.equal(staleRes.success, false);
      assert.equal(staleRes.error, 'STALE_SEQUENCE_DROPPED');
      // State remains at seq 10 with draw pile 50
      assert.equal(store.getState().seq, 10);
      assert.equal(store.getState().drawPileCount, 50);
      assert.equal(store.getState().turnSeat, 1);
    });

    it('11. Handles duplicate sequence updates idempotently without notifying subscribers', () => {
      const store = new StateStore();
      let notifyCount = 0;
      store.subscribe(() => { notifyCount++; });

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 4,
        payload: { draw_pile_count: 20 }
      });
      assert.equal(notifyCount, 1);

      // Re-send seq 4
      const dupRes = store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 4,
        payload: { draw_pile_count: 20 }
      });

      assert.equal(dupRes.success, false);
      assert.equal(notifyCount, 1); // No second notification
    });

    it('12. Accurately tracks draw pile count updates from depleted (0) to reshuffled', () => {
      const store = new StateStore();

      // Deplete deck
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: { draw_pile_count: 0 }
      });
      assert.equal(store.getState().drawPileCount, 0);

      // Reshuffle discard pile back into draw pile
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 2,
        payload: { draw_pile_count: 75 }
      });
      assert.equal(store.getState().drawPileCount, 75);
    });

    it('13. Protects state immutability preventing direct external mutations', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 1,
        payload: {
          my_hand: [{ id: 'c1', color: 'red', value: '1' }]
        }
      });

      const snapshot = store.getState();
      snapshot.myHand.push({ id: 'injected', color: 'green', value: '9' });
      snapshot.status = 'hacked';

      // Internal state must remain unmodified
      const freshSnapshot = store.getState();
      assert.equal(freshSnapshot.myHand.length, 1);
      assert.equal(freshSnapshot.status, 'idle');
    });

    it('14. Handles reverse direction (-1) and turn wrap-around', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          direction: -1,
          turn_seat: 3,
          players: [
            { seat: 0, name: 'P0' },
            { seat: 1, name: 'P1' },
            { seat: 2, name: 'P2' },
            { seat: 3, name: 'P3' }
          ]
        }
      });

      const s = store.getState();
      assert.equal(s.direction, -1);
      assert.equal(s.activePlayer.name, 'P3');
    });
  });

  // ==========================================================================
  // Tier 3: Combinatorial & Workload Stress
  // ==========================================================================
  describe('Tier 3: Combinatorial & Stress Workloads', () => {
    it('15. Transitions through waiting -> in_progress -> round_over -> match_over lifecycle', () => {
      const store = new StateStore();
      const statuses = [];

      store.subscribe((state) => {
        statuses.push(state.status);
      });

      const sequence = ['waiting', 'in_progress', 'round_over', 'match_over'];
      for (let i = 0; i < sequence.length; i++) {
        store.applyMessage({
          v: 1,
          type: 'STATUS_UPDATE',
          seq: i + 1,
          payload: { status: sequence[i] }
        });
      }

      assert.deepEqual(statuses, ['waiting', 'in_progress', 'round_over', 'match_over']);
      assert.equal(store.getState().status, 'match_over');
    });

    it('16. Multiple independent subscribers receive consistent state updates', () => {
      const store = new StateStore();
      const sub1Updates = [];
      const sub2Updates = [];

      store.subscribe((s) => sub1Updates.push(s.seq));
      store.subscribe((s) => sub2Updates.push(s.seq));

      for (let i = 1; i <= 5; i++) {
        store.applyMessage({
          v: 1,
          type: 'PUBLIC_STATE_UPDATE',
          seq: i,
          payload: { draw_pile_count: 100 - i }
        });
      }

      assert.deepEqual(sub1Updates, [1, 2, 3, 4, 5]);
      assert.deepEqual(sub2Updates, [1, 2, 3, 4, 5]);
    });

    it('17. Stress test: processes 100 sequential updates correctly with strict ordering', () => {
      const store = new StateStore();
      for (let i = 1; i <= 100; i++) {
        const res = store.applyMessage({
          v: 1,
          type: 'PUBLIC_STATE_UPDATE',
          seq: i,
          payload: {
            draw_pile_count: i,
            turn_seat: i % 4
          }
        });
        assert.equal(res.success, true);
      }

      const finalState = store.getState();
      assert.equal(finalState.seq, 100);
      assert.equal(finalState.drawPileCount, 100);
      assert.equal(finalState.turnSeat, 0); // 100 % 4 === 0
    });
  });
});
