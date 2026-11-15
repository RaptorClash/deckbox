/**
 * CardRenderer Test Suite
 * Tests card HTML/CSS DOM generation for standard colors and action values,
 * colorblind geometric symbols (Triangle, Diamond, Circle, Star), playable highlight
 * classes, disabled states, masked opponent cards, and deck rendering.
 *
 * Command: node --test web_lite/test/card_renderer.test.js
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setupGlobalDOM } from './mock_dom.js';

setupGlobalDOM();

// Resolve module under test: web_lite/js/card_renderer.js or contract specification
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const implPath = path.resolve(__dirname, '../js/card_renderer.js');

let CardRenderer, COLOR_SYMBOLS;
if (fs.existsSync(implPath)) {
  const mod = await import(pathToFileURL(implPath).href);
  CardRenderer = mod.CardRenderer || mod.default;
  COLOR_SYMBOLS = mod.COLOR_SYMBOLS;
} else {
  const mod = await import('./web_contracts.js');
  CardRenderer = mod.CardRenderer;
  COLOR_SYMBOLS = mod.COLOR_SYMBOLS;
}

describe('CardRenderer (HTML/CSS DOM Generation & Accessibility)', () => {
  const renderer = new CardRenderer();

  // ==========================================================================
  // Tier 1: Feature Coverage Tests
  // ==========================================================================
  describe('Tier 1: Feature Coverage', () => {
    it('1. Renders all 4 standard UNO colors (red, blue, green, yellow)', () => {
      const colors = ['red', 'blue', 'green', 'yellow'];
      for (const color of colors) {
        const card = { id: `card-${color}`, color, value: '5' };
        const el = renderer.renderCard(card);

        assert.equal(el.classList.contains(`card--${color}`), true);
        assert.equal(el.getAttribute('data-color'), color);
        assert.equal(el.getAttribute('data-value'), '5');
      }
    });

    it('2. Renders wild and wild_draw_four cards with wild class styling', () => {
      const wild = { id: 'w1', color: 'wild', value: 'wild' };
      const wildEl = renderer.renderCard(wild);
      assert.equal(wildEl.classList.contains('card--wild'), true);
      assert.equal(wildEl.getAttribute('data-color'), 'wild');
      assert.equal(wildEl.getAttribute('data-value'), 'wild');

      const wildDrawFour = { id: 'w4', color: 'wild', value: 'wild_draw_four' };
      const w4El = renderer.renderCard(wildDrawFour);
      assert.equal(w4El.classList.contains('card--wild'), true);
      assert.equal(w4El.classList.contains('card--val-wild_draw_four'), true);
      assert.match(w4El.getAttribute('aria-label'), /Wild Draw Four/i);
    });

    it('3. Renders number values 0 through 9 with correct value labels', () => {
      for (let num = 0; num <= 9; num++) {
        const card = { id: `c-${num}`, color: 'red', value: String(num) };
        const el = renderer.renderCard(card);

        assert.equal(el.classList.contains(`card--val-${num}`), true);
        assert.equal(el.getAttribute('data-value'), String(num));
        assert.match(el.textContent, new RegExp(String(num)));
      }
    });

    it('4. Renders action cards (skip, reverse, draw_two)', () => {
      const actions = [
        { value: 'skip', classVal: 'skip' },
        { value: 'reverse', classVal: 'reverse' },
        { value: 'draw_two', classVal: 'draw_two' }
      ];

      for (const act of actions) {
        const card = { id: `act-${act.value}`, color: 'green', value: act.value };
        const el = renderer.renderCard(card);

        assert.equal(el.classList.contains(`card--val-${act.classVal}`), true);
        assert.equal(el.getAttribute('data-value'), act.value);
        assert.equal(el.classList.contains('card--green'), true);
      }
    });

    it('5. Assigns Red cards the Triangle geometric symbol with aria-label', () => {
      const redCard = { id: 'r3', color: 'red', value: '3' };
      const el = renderer.renderCard(redCard);

      const symbolEl = el.querySelector('.symbol-triangle');
      assert.notEqual(symbolEl, null, 'Red card must contain .symbol-triangle');
      assert.equal(symbolEl.textContent, '▲');
      assert.match(el.getAttribute('aria-label'), /Triangle/);
    });

    it('6. Assigns Blue cards the Diamond geometric symbol with aria-label', () => {
      const blueCard = { id: 'b7', color: 'blue', value: '7' };
      const el = renderer.renderCard(blueCard);

      const symbolEl = el.querySelector('.symbol-diamond');
      assert.notEqual(symbolEl, null, 'Blue card must contain .symbol-diamond');
      assert.equal(symbolEl.textContent, '◆');
      assert.match(el.getAttribute('aria-label'), /Diamond/);
    });

    it('7. Assigns Green cards the Circle and Yellow cards the Star geometric symbol', () => {
      const greenCard = { id: 'g0', color: 'green', value: '0' };
      const greenEl = renderer.renderCard(greenCard);
      const circleEl = greenEl.querySelector('.symbol-circle');
      assert.notEqual(circleEl, null);
      assert.equal(circleEl.textContent, '●');
      assert.match(greenEl.getAttribute('aria-label'), /Circle/);

      const yellowCard = { id: 'y9', color: 'yellow', value: '9' };
      const yellowEl = renderer.renderCard(yellowCard);
      const starEl = yellowEl.querySelector('.symbol-star');
      assert.notEqual(starEl, null);
      assert.equal(starEl.textContent, '★');
      assert.match(yellowEl.getAttribute('aria-label'), /Star/);
    });
  });

  // ==========================================================================
  // Tier 2: Boundary & Corner Cases
  // ==========================================================================
  describe('Tier 2: Boundary & Corner Cases', () => {
    it('8. Sets card--playable class, role=button, and tabindex=0 when playable is true', () => {
      const card = { id: 'c-play', color: 'red', value: '8', playable: true };
      const el = renderer.renderCard(card);

      assert.equal(el.classList.contains('card--playable'), true);
      assert.equal(el.getAttribute('role'), 'button');
      assert.equal(el.getAttribute('tabindex'), '0');
      assert.equal(el.getAttribute('aria-disabled'), 'false');
    });

    it('9. Sets card--disabled class and aria-disabled=true when playable is false', () => {
      const card = { id: 'c-dis', color: 'blue', value: '2', playable: false };
      const el = renderer.renderCard(card);

      assert.equal(el.classList.contains('card--disabled'), true);
      assert.equal(el.classList.contains('card--playable'), false);
      assert.equal(el.getAttribute('aria-disabled'), 'true');
      assert.equal(el.getAttribute('tabindex'), '-1');
    });

    it('10. Renders masked card with card--masked and card--back and NO face content', () => {
      const maskedCard = { masked: true };
      const el = renderer.renderCard(maskedCard);

      assert.equal(el.classList.contains('card--masked'), true);
      assert.equal(el.classList.contains('card--back'), true);
      assert.equal(el.hasAttribute('data-card-id'), false);
      assert.equal(el.hasAttribute('data-color'), false);
      assert.equal(el.hasAttribute('data-value'), false);
      assert.equal(el.getAttribute('aria-label'), 'Card (Face Down)');
    });

    it('11. Handles null or undefined card gracefully returning fallback element', () => {
      const nullEl = renderer.renderCard(null);
      assert.equal(nullEl.classList.contains('card--unknown'), true);

      const undefEl = renderer.renderCard(undefined);
      assert.equal(undefEl.classList.contains('card--unknown'), true);
    });

    it('12. Sanitizes card value to prevent HTML and script injection (XSS)', () => {
      const maliciousCard = {
        id: 'xss-1',
        color: 'red',
        value: '<script>alert("pwned")</script>'
      };
      const el = renderer.renderCard(maliciousCard);

      // Must not contain raw script tags in innerHTML or attributes
      assert.equal(el.innerHTML.includes('<script>'), false);
      assert.equal(el.getAttribute('data-value').includes('<'), false);
    });

    it('13. renderHand renders empty hand container when card array is empty', () => {
      const doc = globalThis.document;
      const container = doc.createElement('div');

      renderer.renderHand([], container);
      assert.equal(container.classList.contains('hand--empty'), true);
      assert.equal(container.children.length, 0);
    });

    it('14. renderHand renders multiple cards preserving order and attributes', () => {
      const doc = globalThis.document;
      const container = doc.createElement('div');
      const hand = [
        { id: 'c1', color: 'red', value: '1', playable: true },
        { id: 'c2', color: 'blue', value: 'skip', playable: false },
        { id: 'c3', color: 'wild', value: 'wild_draw_four', playable: true }
      ];

      renderer.renderHand(hand, container);
      assert.equal(container.children.length, 3);
      assert.equal(container.children[0].getAttribute('data-card-id'), 'c1');
      assert.equal(container.children[1].getAttribute('data-card-id'), 'c2');
      assert.equal(container.children[2].getAttribute('data-card-id'), 'c3');
    });
  });

  // ==========================================================================
  // Tier 3: Pairwise & Interactive Scenarios
  // ==========================================================================
  describe('Tier 3: Pairwise & Interactive Features', () => {
    it('15. renderDeck renders draw pile stack with card back and deck count badge', () => {
      const doc = globalThis.document;
      const container = doc.createElement('div');

      renderer.renderDeck(54, container);
      const deckEl = container.querySelector('.deck-stack');
      assert.notEqual(deckEl, null);

      const countBadge = container.querySelector('.deck-stack__count');
      assert.notEqual(countBadge, null);
      assert.equal(countBadge.textContent, '54');
      assert.match(deckEl.getAttribute('aria-label'), /54 cards/);
    });

    it('16. renderDeck with 0 cards renders depleted deck styling', () => {
      const doc = globalThis.document;
      const container = doc.createElement('div');

      renderer.renderDeck(0, container);
      const deckEl = container.querySelector('.deck-stack');
      assert.notEqual(deckEl, null);
      assert.equal(deckEl.classList.contains('deck-stack--depleted'), true);
      assert.match(deckEl.getAttribute('aria-label'), /Empty/);
    });

    it('17. Interactive click handler triggers onClick callback with card payload', () => {
      let clickedCard = null;
      const card = { id: 'clickable-1', color: 'green', value: '7', playable: true };

      const el = renderer.renderCard(card, {
        isPlayable: true,
        onClick: (c) => {
          clickedCard = c;
        }
      });

      el.click();
      assert.notEqual(clickedCard, null);
      assert.equal(clickedCard.id, 'clickable-1');
      assert.equal(clickedCard.value, '7');
    });
  });
});
