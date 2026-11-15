/**
 * CardRenderer — DOM card generator with colorblind geometric symbols
 * and anti-leak masked card protection.
 */

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

export default CardRenderer;
