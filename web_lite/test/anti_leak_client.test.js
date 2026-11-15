/**
 * AntiLeakClient Test Suite (Adversarial Security & Information-Leak Prevention)
 * Verifies that the web client:
 * 1. Renders masked opponent cards ({ masked: true }) with zero leakage of card UIDs, values, or colors in DOM.
 * 2. Never constructs or requests undefined image URLs (e.g. undefined.png or undefined.svg).
 * 3. Keeps draw pile order completely unexposed (store contains only draw_pile_count integer).
 * 4. Sanitizes unexpected private attributes if attached to opponent objects.
 * 5. Guarantees uniform card back presentation across all opponents.
 *
 * Command: node --test web_lite/test/anti_leak_client.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setupGlobalDOM } from './mock_dom.js';

setupGlobalDOM();

// Resolve module under test: web_lite/js or contract specification
const __dirname = path.dirname(fileURLToPath(import.meta.url));

let CardRenderer, StateStore, AntiLeakSanitizer;
const cardRendererPath = path.resolve(__dirname, '../js/card_renderer.js');
const stateStorePath = path.resolve(__dirname, '../js/state_store.js');

if (fs.existsSync(cardRendererPath) && fs.existsSync(stateStorePath)) {
  const modCR = await import(cardRendererPath);
  const modSS = await import(stateStorePath);
  CardRenderer = modCR.CardRenderer || modCR.default;
  StateStore = modSS.StateStore || modSS.default;
  // Use contracts for sanitizer helper
  const contracts = await import('./web_contracts.js');
  AntiLeakSanitizer = contracts.AntiLeakSanitizer;
} else {
  const contracts = await import('./web_contracts.js');
  CardRenderer = contracts.CardRenderer;
  StateStore = contracts.StateStore;
  AntiLeakSanitizer = contracts.AntiLeakSanitizer;
}

describe('AntiLeakClient (Zero-Information-Leak Adversarial Verification)', () => {
  const renderer = new CardRenderer();

  // ==========================================================================
  // Tier 1: Feature Coverage (Anti-Leak Contracts)
  // ==========================================================================
  describe('Tier 1: Feature Coverage', () => {
    it('1. Masked opponent card renders with NO data-card-id attribute in DOM', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      assert.equal(el.hasAttribute('data-card-id'), false);
      assert.equal(el.getAttribute('data-card-id'), null);
      assert.equal(el.dataset.cardId, undefined);
    });

    it('2. Masked opponent card renders with NO data-color or data-value attributes', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      assert.equal(el.hasAttribute('data-color'), false);
      assert.equal(el.hasAttribute('data-value'), false);
      assert.equal(el.dataset.color, undefined);
      assert.equal(el.dataset.value, undefined);
    });

    it('3. Masked opponent card textContent contains only uniform back logo and NO numbers or face values', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      const text = el.textContent.trim();
      assert.equal(text, 'DeckBox');
      assert.equal(/[0-9]/.test(text), false, 'Masked card must not contain numeric values');
      assert.equal(/skip|reverse|draw|wild/i.test(text), false, 'Masked card must not contain action names');
    });

    it('4. Masked opponent card does NOT create or request undefined/null image URLs', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      const leaks = AntiLeakSanitizer.verifyNoLeakInDOM(el);
      assert.deepEqual(leaks, [], 'DOM should contain no undefined attributes or asset requests');

      // Check innerHTML for any mention of undefined
      assert.equal(el.innerHTML.includes('undefined'), false);
      assert.equal(el.innerHTML.includes('null'), false);
    });

    it('5. StateStore public state exposes draw_pile_count as integer with ZERO upcoming card objects', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: {
          draw_pile_count: 38,
          turn_seat: 0
        }
      });

      const state = store.getState();
      assert.equal(typeof state.drawPileCount, 'number');
      assert.equal(state.drawPileCount, 38);
      // Ensure there are no private deck fields leaked in public state
      assert.equal(state.drawPile, undefined);
      assert.equal(state.deck, undefined);
      assert.equal(state.cards, undefined);
    });

    it('6. StateStore player view isolates requesting player hand while opponents remain masked summaries', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 1,
        payload: {
          my_player_id: 'alice-id',
          my_seat: 0,
          my_hand: [
            { id: 'c-red-1', color: 'red', value: '1' },
            { id: 'c-blue-2', color: 'blue', value: '2' }
          ],
          players: [
            { seat: 0, name: 'Alice', card_count: 2 },
            { seat: 1, name: 'Bob', card_count: 7 },
            { seat: 2, name: 'Charlie', card_count: 4 }
          ]
        }
      });

      const s = store.getState();
      // Alice has her 2 private cards
      assert.equal(s.myHand.length, 2);
      assert.equal(s.myHand[0].id, 'c-red-1');

      // Opponents have only counts, no card lists
      for (const opponent of s.players.filter(p => p.seat !== s.mySeat)) {
        assert.equal(opponent.hand, undefined);
        assert.equal(opponent.cards, undefined);
        assert.equal(typeof opponent.cardCount, 'number');
      }
    });
  });

  // ==========================================================================
  // Tier 2: Boundary & Adversarial Inspection
  // ==========================================================================
  describe('Tier 2: Boundary & Adversarial Checks', () => {
    it('7. Client sanitizer strips unexpected private attributes from opponent summaries', () => {
      const dirtyOpponent = {
        seat: 2,
        name: 'Eve',
        card_count: 5,
        called_uno: false,
        _secret_hand: ['wild_draw_four', 'red_skip'], // Injected leak attempt
        internal_deck_index: 12
      };

      const sanitized = AntiLeakSanitizer.sanitizeOpponentPayload(dirtyOpponent);
      assert.equal(sanitized.seat, 2);
      assert.equal(sanitized.name, 'Eve');
      assert.equal(sanitized.cardCount, 5);
      assert.equal(sanitized._secret_hand, undefined);
      assert.equal(sanitized.internal_deck_index, undefined);
    });

    it('8. Deep querySelectorAll on rendered opponent hand container finds ZERO elements with private attributes', () => {
      const doc = globalThis.document;
      const opponentHandContainer = doc.createElement('div');
      opponentHandContainer.classList.add('opponent-hand');

      // Opponent has 5 cards
      const maskedCards = Array(5).fill({ masked: true });
      renderer.renderHand(maskedCards, opponentHandContainer);

      assert.equal(opponentHandContainer.children.length, 5);
      const leakedIdElems = opponentHandContainer.querySelectorAll('[data-card-id]');
      const leakedValElems = opponentHandContainer.querySelectorAll('[data-value]');
      const leakedColorElems = opponentHandContainer.querySelectorAll('[data-color]');

      assert.equal(leakedIdElems.length, 0, 'No element in opponent hand may have data-card-id');
      assert.equal(leakedValElems.length, 0, 'No element in opponent hand may have data-value');
      assert.equal(leakedColorElems.length, 0, 'No element in opponent hand may have data-color');
    });

    it('9. Rendered masked cards have uniform card back CSS classes without unique identifiers', () => {
      const masked1 = renderer.renderCard({ masked: true });
      const masked2 = renderer.renderCard({ masked: true });

      assert.equal(masked1.className, masked2.className);
      assert.equal(masked1.classList.contains('card--masked'), true);
      assert.equal(masked1.classList.contains('card--back'), true);
    });

    it('10. Draw deck element has NO child nodes revealing upcoming card identities', () => {
      const doc = globalThis.document;
      const deckContainer = doc.createElement('div');

      renderer.renderDeck(25, deckContainer);
      const allChildren = deckContainer.querySelectorAll('*');

      assert.equal(allChildren.length > 0, true, 'Deck container must have rendered child elements');
      assert.equal(allChildren.length, 3, 'Deck stack consists of deck-stack wrapper, card back, and count badge');

      for (const child of allChildren) {
        assert.equal(child.hasAttribute('data-card-id'), false);
        assert.equal(child.hasAttribute('data-value'), false);
        assert.equal(child.hasAttribute('data-color'), false);
      }
    });

    it('11. Adversarial server payload with malicious card structure is safely handled without leaks', () => {
      const adversarialCard = {
        masked: true,
        id: 'SECRET_ID_SHOULD_NOT_LEAK',
        value: 'WILD_DRAW_FOUR',
        color: 'wild'
      };

      const el = renderer.renderCard(adversarialCard);
      // Because masked === true, renderer MUST enforce masked rules and suppress id/value/color
      assert.equal(el.hasAttribute('data-card-id'), false);
      assert.equal(el.hasAttribute('data-value'), false);
      assert.equal(el.hasAttribute('data-color'), false);
      assert.equal(el.classList.contains('card--masked'), true);
      assert.equal(el.textContent.includes('WILD_DRAW_FOUR'), false);
    });

    it('12. Adversarial attempt to read draw pile order from store produces undefined', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PUBLIC_STATE_UPDATE',
        seq: 1,
        payload: { draw_pile_count: 40 }
      });

      const s = store.getState();
      assert.equal(s.drawPileOrder, undefined);
      assert.equal(s.nextCard, undefined);
      assert.equal(s.peek, undefined);
    });

    it('13. AntiLeakSanitizer.verifyNoLeakInDOM accurately detects injected private card IDs and attribute leaks in child elements', () => {
      const doc = globalThis.document;
      const container = doc.createElement('div');
      container.classList.add('table-felt');

      const knownPrivateIds = ['secret-card-uno-001', 'secret-card-uno-002'];

      // Sub-case A: Clean container with legitimate masked opponent cards produces 0 leaks
      const maskedCards = [{ masked: true }, { masked: true }];
      renderer.renderHand(maskedCards, container);
      const cleanLeaks = AntiLeakSanitizer.verifyNoLeakInDOM(container, knownPrivateIds);
      assert.deepEqual(cleanLeaks, [], 'Clean masked hand must report zero DOM leaks');

      // Sub-case B: Adversarial child element leaking a known private card ID is caught
      const maliciousChild = doc.createElement('div');
      maliciousChild.classList.add('leaked-card-node');
      maliciousChild.setAttribute('data-card-id', 'secret-card-uno-001');
      container.appendChild(maliciousChild);

      const detectedLeaks = AntiLeakSanitizer.verifyNoLeakInDOM(container, knownPrivateIds);
      assert.equal(detectedLeaks.length > 0, true, 'Detector must catch exposed private card ID in child tree');
      const idLeak = detectedLeaks.find(l => l.type === 'PRIVATE_CARD_ID_EXPOSED');
      assert.ok(idLeak, 'Must detect PRIVATE_CARD_ID_EXPOSED leak type');
      assert.equal(idLeak.value, 'secret-card-uno-001');
      assert.equal(idLeak.attr, 'data-card-id');

      // Sub-case C: Deeply nested child with undefined attribute is also caught
      const nestedChild = doc.createElement('span');
      nestedChild.setAttribute('data-value', 'undefined');
      maliciousChild.appendChild(nestedChild);

      const multiLeaks = AntiLeakSanitizer.verifyNoLeakInDOM(container, knownPrivateIds);
      assert.ok(multiLeaks.some(l => l.type === 'UNDEFINED_VALUE'), 'Must catch nested undefined value attribute');
    });
  });

  // ==========================================================================
  // Tier 3: Combinatorial & Multi-Player Isolation
  // ==========================================================================
  describe('Tier 3: Multi-Player Game Isolation', () => {
    it('14. 4-Player match update completely isolates requesting player hand from 3 opponents', () => {
      const store = new StateStore();
      store.applyMessage({
        v: 1,
        type: 'PLAYER_VIEW_UPDATE',
        seq: 5,
        payload: {
          my_player_id: 'player-seat-3',
          my_seat: 3,
          my_hand: [
            { id: 'p3-c1', color: 'yellow', value: '4' },
            { id: 'p3-c2', color: 'green', value: 'reverse' }
          ],
          players: [
            { seat: 0, name: 'P0', card_count: 5 },
            { seat: 1, name: 'P1', card_count: 6 },
            { seat: 2, name: 'P2', card_count: 7 },
            { seat: 3, name: 'P3 (Me)', card_count: 2 }
          ]
        }
      });

      const state = store.getState();
      assert.equal(state.mySeat, 3);
      assert.equal(state.myHand.length, 2);

      // Verify opponents
      const opponents = state.players.filter(p => p.seat !== 3);
      assert.equal(opponents.length, 3);
      for (const op of opponents) {
        assert.equal(op.hand, undefined);
        assert.equal(op.cards, undefined);
      }
    });

    it('15. Rendered opponent card elements do not carry interactive play handlers', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      assert.equal(el.classList.contains('card--playable'), false);
      assert.equal(el.getAttribute('role'), 'img');
      assert.equal(el.getAttribute('tabindex'), null);
    });

    it('16. JSON serialization of rendered opponent cards contains no secret fields', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      const dump = JSON.stringify({
        className: el.className,
        ariaLabel: el.getAttribute('aria-label'),
        text: el.textContent
      });

      assert.equal(dump.includes('undefined'), false);
      assert.equal(dump.includes('null'), false);
      assert.equal(dump.includes('card-id'), false);
    });
  });
});
