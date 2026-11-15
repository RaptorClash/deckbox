/**
 * RoleController Test Suite
 * Tests role-based client view switching:
 * - 'player': Private hand tray, interactive action buttons (draw, call uno), playmat.
 * - 'table': Shared big screen display, public playmat, 360 player scoreboard, no private hand.
 * - 'spectator': Read-only view, spectator watermark/overlay, scoreboard, action controls disabled.
 *
 * Command: node --test web_lite/test/role_controller.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setupGlobalDOM } from './mock_dom.js';

setupGlobalDOM();

// Resolve module under test: web_lite/js/role_controller.js or contract specification
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const implPath = path.resolve(__dirname, '../js/role_controller.js');

let RoleController, StateStore;
if (fs.existsSync(implPath)) {
  const modRC = await import(pathToFileURL(implPath).href);
  RoleController = modRC.RoleController || modRC.default;
  const modSS = await import('./web_contracts.js');
  StateStore = modSS.StateStore;
} else {
  const contracts = await import('./web_contracts.js');
  RoleController = contracts.RoleController;
  StateStore = contracts.StateStore;
}

describe('RoleController (Role-Based View Management)', () => {
  const setupHarness = (initialRole = 'spectator') => {
    const doc = globalThis.document;
    const root = doc.createElement('div');
    root.id = 'app-root';

    const store = new StateStore({
      matchId: 'match-role-test',
      turnSeat: 0,
      players: [
        { seat: 0, name: 'Player 0', cardCount: 7 },
        { seat: 1, name: 'Player 1', cardCount: 7 }
      ]
    });

    const controller = new RoleController({
      rootElement: root,
      stateStore: store,
      initialRole
    });

    return { root, store, controller };
  };

  // ==========================================================================
  // Tier 1: Feature Coverage Tests
  // ==========================================================================
  describe('Tier 1: Feature Coverage', () => {
    it('1. Initializes with default spectator role and applies role--spectator class', () => {
      const { root, controller } = setupHarness('spectator');

      assert.equal(controller.getRole(), 'spectator');
      assert.equal(root.classList.contains('role--spectator'), true);
      assert.equal(root.classList.contains('role--player'), false);
      assert.equal(root.classList.contains('role--table'), false);
    });

    it('2. Switches to "player" role: displays player hand container and action controls', () => {
      const { root, controller } = setupHarness('spectator');
      const res = controller.setRole('player', { playerId: 'p-user-1' });

      assert.equal(res.success, true);
      assert.equal(controller.getRole(), 'player');
      assert.equal(root.classList.contains('role--player'), true);

      const handEl = root.querySelector('#hand-container');
      const actionsEl = root.querySelector('#player-actions');
      assert.notEqual(handEl, null);
      assert.notEqual(actionsEl, null);
      assert.equal(handEl.style.display, 'block');
      assert.equal(actionsEl.style.display, 'block');
    });

    it('3. Switches to "table" role: hides player hand and shows big-screen playmat and scoreboard', () => {
      const { root, controller } = setupHarness('player');
      const res = controller.setRole('table');

      assert.equal(res.success, true);
      assert.equal(controller.getRole(), 'table');
      assert.equal(root.classList.contains('role--table'), true);

      const handEl = root.querySelector('#hand-container');
      const actionsEl = root.querySelector('#player-actions');
      const scoreEl = root.querySelector('#scoreboard');
      const playmatEl = root.querySelector('#table-playmat');

      assert.equal(handEl.style.display, 'none');
      assert.equal(actionsEl.style.display, 'none');
      assert.equal(scoreEl.style.display, 'block');
      assert.equal(playmatEl.style.display, 'block');
    });

    it('4. Switches to "spectator" role: hides hand, disables action controls, shows spectator overlay', () => {
      const { root, controller } = setupHarness('table');
      const res = controller.setRole('spectator');

      assert.equal(res.success, true);
      assert.equal(controller.getRole(), 'spectator');
      assert.equal(root.classList.contains('role--spectator'), true);

      const handEl = root.querySelector('#hand-container');
      const specEl = root.querySelector('#spectator-overlay');
      const scoreEl = root.querySelector('#scoreboard');

      assert.equal(handEl.style.display, 'none');
      assert.equal(specEl.style.display, 'block');
      assert.equal(scoreEl.style.display, 'block');
    });

    it('5. Toggles root CSS classes cleanly on role switch without lingering classes', () => {
      const { root, controller } = setupHarness('spectator');

      controller.setRole('player', { playerId: 'p1' });
      assert.equal(root.classList.contains('role--player'), true);
      assert.equal(root.classList.contains('role--spectator'), false);

      controller.setRole('table');
      assert.equal(root.classList.contains('role--table'), true);
      assert.equal(root.classList.contains('role--player'), false);

      controller.setRole('spectator');
      assert.equal(root.classList.contains('role--spectator'), true);
      assert.equal(root.classList.contains('role--table'), false);
    });

    it('6. getRole() accurately reflects the currently active role string', () => {
      const { controller } = setupHarness('spectator');
      assert.equal(controller.getRole(), 'spectator');

      controller.setRole('table');
      assert.equal(controller.getRole(), 'table');

      controller.setRole('player', { playerId: 'test-p' });
      assert.equal(controller.getRole(), 'player');
    });
  });

  // ==========================================================================
  // Tier 2: Boundary & Corner Cases
  // ==========================================================================
  describe('Tier 2: Boundary & Corner Cases', () => {
    it('7. Rejects invalid role names preserving the existing role', () => {
      const { controller } = setupHarness('spectator');

      const res = controller.setRole('god_mode');
      assert.equal(res.success, false);
      assert.equal(res.error, 'INVALID_ROLE');
      assert.equal(controller.getRole(), 'spectator');

      const res2 = controller.setRole(null);
      assert.equal(res2.success, false);
      assert.equal(controller.getRole(), 'spectator');
    });

    it('8. Switching to "player" requires or validates valid player ID', () => {
      const { controller } = setupHarness('spectator');

      // Without playerId option and without myPlayerId in store
      const res = controller.setRole('player', { playerId: '' });
      assert.equal(res.success, false);
      assert.equal(res.error, 'PLAYER_ID_REQUIRED');
      assert.equal(controller.getRole(), 'spectator');
    });

    it('9. Table view scoreboard renders all players without revealing private cards', () => {
      const { root, store, controller } = setupHarness('spectator');
      controller.setRole('table');

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          turn_seat: 1,
          players: [
            { seat: 0, name: 'Alice', card_count: 5 },
            { seat: 1, name: 'Bob', card_count: 3 }
          ]
        }
      });

      const scoreItems = root.querySelectorAll('.scoreboard__item');
      assert.equal(scoreItems.length, 2);

      // Verify Alice item
      assert.match(scoreItems[0].textContent, /Alice/);
      assert.match(scoreItems[0].textContent, /5 cards/);

      // Verify Bob item (active turn seat)
      assert.match(scoreItems[1].textContent, /Bob/);
      assert.match(scoreItems[1].textContent, /3 cards/);
      assert.equal(scoreItems[1].classList.contains('scoreboard__item--active'), true);
    });

    it('10. Spectator overlay communicates read-only status and hides action buttons', () => {
      const { root, controller } = setupHarness('spectator');

      const specOverlay = root.querySelector('#spectator-overlay');
      assert.notEqual(specOverlay, null);
      assert.equal(specOverlay.style.display, 'block');
      assert.match(specOverlay.textContent, /Spectator Mode/);

      const actionControls = root.querySelector('#player-actions');
      assert.equal(actionControls.style.display, 'none');
    });

    it('11. Cleans up store subscription on destroy()', () => {
      const { store, controller } = setupHarness('spectator');
      assert.notEqual(controller._unsubscribe, null);

      controller.destroy();
      assert.equal(controller._unsubscribe, null);
    });

    it('12. Reactive view update: modifies button state when isMyTurn changes in store', () => {
      const { root, store, controller } = setupHarness('spectator');
      controller.setRole('player', { playerId: 'alice-id' });

      // Player view: not my turn
      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 1,
        payload: {
          my_player_id: 'alice-id',
          my_seat: 0,
          turn_seat: 1,
          players: [{ seat: 0, name: 'Alice' }, { seat: 1, name: 'Bob' }]
        }
      });

      const btnDraw = root.querySelector('#btn-draw');
      assert.equal(btnDraw.disabled, true);

      // Advance turn to my seat (0)
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 2,
        payload: {
          turn_seat: 0
        }
      });

      assert.equal(btnDraw.disabled, false);
    });
  });

  // ==========================================================================
  // Tier 3: Combinatorial & Cycling Scenarios
  // ==========================================================================
  describe('Tier 3: Combinatorial & Cycling', () => {
    it('13. Seamless role cycle: spectator -> player -> table -> spectator', () => {
      const { root, controller } = setupHarness('spectator');
      const sequence = [
        { role: 'player', opt: { playerId: 'p1' } },
        { role: 'table', opt: {} },
        { role: 'spectator', opt: {} }
      ];

      for (const step of sequence) {
        const res = controller.setRole(step.role, step.opt);
        assert.equal(res.success, true);
        assert.equal(controller.getRole(), step.role);
        assert.equal(root.classList.contains(`role--${step.role}`), true);
      }
    });

    it('14. Emote container is present and visible across all roles', () => {
      const { root, controller } = setupHarness('spectator');
      const emoteContainer = root.querySelector('#emote-container');
      assert.notEqual(emoteContainer, null);

      controller.setRole('player', { playerId: 'p1' });
      assert.notEqual(root.querySelector('#emote-container'), null);

      controller.setRole('table');
      assert.notEqual(root.querySelector('#emote-container'), null);
    });

    it('15. Handles null rootElement gracefully without crashing', () => {
      const controller = new RoleController({
        rootElement: null,
        initialRole: 'spectator'
      });

      assert.equal(controller.getRole(), 'spectator');
      const res = controller.setRole('table');
      assert.equal(res.success, true);
      assert.equal(controller.getRole(), 'table');
    });

    it('16. Table view highlights active turn player correctly when direction reverses', () => {
      const { root, store, controller } = setupHarness('spectator');
      controller.setRole('table');

      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          turn_seat: 2,
          direction: -1,
          players: [
            { seat: 0, name: 'P0', card_count: 5 },
            { seat: 1, name: 'P1', card_count: 4 },
            { seat: 2, name: 'P2', card_count: 3 }
          ]
        }
      });

      const activeItem = root.querySelector('.scoreboard__item--active');
      assert.notEqual(activeItem, null);
      assert.equal(activeItem.getAttribute('data-seat'), '2');
      assert.match(activeItem.textContent, /P2/);
    });
  });
});
