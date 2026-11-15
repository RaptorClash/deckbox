/**
 * Lightweight pure-JavaScript Mock DOM implementation for Node.js test environment.
 * Zero external dependencies.
 */

export class MockClassList {
  constructor(element) {
    this._element = element;
    this._classes = new Set();
  }

  add(...classes) {
    for (const c of classes) {
      if (c && typeof c === 'string') {
        const trimmed = c.trim();
        if (trimmed) this._classes.add(trimmed);
      }
    }
    this._sync();
  }

  remove(...classes) {
    for (const c of classes) {
      if (c) this._classes.delete(c.trim());
    }
    this._sync();
  }

  contains(cls) {
    return this._classes.has(cls);
  }

  toggle(cls, force) {
    if (force !== undefined) {
      if (force) this.add(cls);
      else this.remove(cls);
      return force;
    }
    if (this.contains(cls)) {
      this.remove(cls);
      return false;
    } else {
      this.add(cls);
      return true;
    }
  }

  _sync() {
    this._element._attributes.set('class', Array.from(this._classes).join(' '));
  }

  _loadFromClassString(str) {
    this._classes.clear();
    if (str) {
      str.split(/\s+/).filter(Boolean).forEach(c => this._classes.add(c));
    }
  }

  toString() {
    return Array.from(this._classes).join(' ');
  }
}

export class MockElement {
  constructor(tagName = 'div') {
    this.tagName = tagName.toUpperCase();
    this._attributes = new Map();
    this.classList = new MockClassList(this);
    this.children = [];
    this.parentElement = null;
    this.style = {};
    this._listeners = new Map();
    this._textContent = '';

    // Dataset proxy
    this.dataset = new Proxy({}, {
      get: (target, prop) => {
        const attrName = 'data-' + prop.replace(/([A-Z])/g, '-$1').toLowerCase();
        return this.getAttribute(attrName) ?? undefined;
      },
      set: (target, prop, value) => {
        const attrName = 'data-' + prop.replace(/([A-Z])/g, '-$1').toLowerCase();
        this.setAttribute(attrName, String(value));
        return true;
      },
      deleteProperty: (target, prop) => {
        const attrName = 'data-' + prop.replace(/([A-Z])/g, '-$1').toLowerCase();
        this.removeAttribute(attrName);
        return true;
      }
    });
  }

  get id() {
    return this.getAttribute('id') || '';
  }

  set id(val) {
    if (val) this.setAttribute('id', val);
    else this.removeAttribute('id');
  }

  get className() {
    return this.getAttribute('class') || '';
  }

  set className(val) {
    if (val) {
      this.setAttribute('class', val);
      this.classList._loadFromClassString(val);
    } else {
      this.removeAttribute('class');
      this.classList._classes.clear();
    }
  }

  get disabled() {
    return this.hasAttribute('disabled');
  }

  set disabled(val) {
    if (val) this.setAttribute('disabled', '');
    else this.removeAttribute('disabled');
  }

  get tabIndex() {
    const val = this.getAttribute('tabindex');
    return val !== null ? parseInt(val, 10) : -1;
  }

  set tabIndex(val) {
    this.setAttribute('tabindex', String(val));
  }

  get ariaLabel() {
    return this.getAttribute('aria-label') || '';
  }

  set ariaLabel(val) {
    this.setAttribute('aria-label', val);
  }

  get ariaDisabled() {
    return this.getAttribute('aria-disabled') || '';
  }

  set ariaDisabled(val) {
    this.setAttribute('aria-disabled', val);
  }

  setAttribute(name, value) {
    const strVal = String(value);
    this._attributes.set(name.toLowerCase(), strVal);
    if (name.toLowerCase() === 'class') {
      this.classList._loadFromClassString(strVal);
    }
  }

  getAttribute(name) {
    return this._attributes.get(name.toLowerCase()) ?? null;
  }

  hasAttribute(name) {
    return this._attributes.has(name.toLowerCase());
  }

  removeAttribute(name) {
    this._attributes.delete(name.toLowerCase());
    if (name.toLowerCase() === 'class') {
      this.classList._classes.clear();
    }
  }

  appendChild(child) {
    if (!child) return child;
    if (child.parentElement) {
      child.parentElement.removeChild(child);
    }
    child.parentElement = this;
    this.children.push(child);
    return child;
  }

  removeChild(child) {
    const idx = this.children.indexOf(child);
    if (idx !== -1) {
      this.children.splice(idx, 1);
      child.parentElement = null;
    }
    return child;
  }

  replaceChildren(...newChildren) {
    for (const child of this.children) {
      child.parentElement = null;
    }
    this.children = [];
    for (const child of newChildren) {
      this.appendChild(child);
    }
  }

  get textContent() {
    if (this.children.length === 0) {
      return this._textContent;
    }
    return this.children.map(c => c.textContent).join('');
  }

  set textContent(text) {
    this.children = [];
    this._textContent = String(text ?? '');
  }

  get innerHTML() {
    if (this.children.length === 0) {
      return this._textContent;
    }
    return this.children.map(c => {
      const attrs = Array.from(c._attributes.entries())
        .map(([k, v]) => ` ${k}="${v}"`)
        .join('');
      const tag = c.tagName.toLowerCase();
      return `<${tag}${attrs}>${c.innerHTML}</${tag}>`;
    }).join('');
  }

  set innerHTML(htmlString) {
    this.children = [];
    this._textContent = '';
    if (!htmlString) return;

    // Very lightweight tag parser for tests
    const tagRegex = /<([a-z0-9-]+)([^>]*)>(.*?)<\/\1>|<([a-z0-9-]+)([^>]*)\/>/gis;
    let match;
    let hasTags = false;
    while ((match = tagRegex.exec(htmlString)) !== null) {
      hasTags = true;
      const tag = match[1] || match[4];
      const rawAttrs = match[2] || match[5] || '';
      const inner = match[3] || '';
      const elem = new MockElement(tag);

      // parse attrs
      const attrRegex = /([a-z0-9_-]+)(?:="([^"]*)")?/gi;
      let aMatch;
      while ((aMatch = attrRegex.exec(rawAttrs)) !== null) {
        elem.setAttribute(aMatch[1], aMatch[2] !== undefined ? aMatch[2] : '');
      }
      elem.innerHTML = inner;
      this.appendChild(elem);
    }
    if (!hasTags) {
      this._textContent = htmlString;
    }
  }

  addEventListener(event, callback) {
    if (!this._listeners.has(event)) {
      this._listeners.set(event, []);
    }
    this._listeners.get(event).push(callback);
  }

  removeEventListener(event, callback) {
    if (!this._listeners.has(event)) return;
    const list = this._listeners.get(event).filter(fn => fn !== callback);
    this._listeners.set(event, list);
  }

  dispatchEvent(event) {
    const eventType = typeof event === 'string' ? event : event.type;
    const evtObj = typeof event === 'string' ? { type: event, target: this, defaultPrevented: false } : event;
    evtObj.target = this;
    const list = this._listeners.get(eventType) || [];
    for (const fn of list) {
      fn.call(this, evtObj);
    }
    return !evtObj.defaultPrevented;
  }

  click() {
    this.dispatchEvent('click');
  }

  querySelector(selector) {
    const all = this.querySelectorAll(selector);
    return all.length > 0 ? all[0] : null;
  }

  querySelectorAll(selector) {
    const results = [];
    const match = (elem) => {
      if (_matchesSelector(elem, selector)) {
        results.push(elem);
      }
      for (const child of elem.children) {
        match(child);
      }
    };
    for (const child of this.children) {
      match(child);
    }
    return results;
  }
}

function _matchesSelector(elem, selector) {
  if (!selector) return false;
  const sel = selector.trim();

  // Wildcard selector *
  if (sel === '*') return true;

  // ID selector #foo
  if (sel.startsWith('#')) {
    return elem.id === sel.slice(1);
  }
  // Class selector .bar
  if (sel.startsWith('.')) {
    return elem.classList.contains(sel.slice(1));
  }
  // Attribute selector [attr] or [attr="val"]
  if (sel.startsWith('[') && sel.endsWith(']')) {
    const inner = sel.slice(1, -1);
    if (inner.includes('=')) {
      const [attr, rawVal] = inner.split('=');
      const cleanVal = rawVal.replace(/^["']|["']$/g, '');
      return elem.getAttribute(attr) === cleanVal;
    }
    return elem.hasAttribute(inner);
  }
  // Tag selector
  return elem.tagName.toLowerCase() === sel.toLowerCase();
}

export class MockDocument {
  constructor() {
    this.body = new MockElement('body');
  }

  createElement(tagName) {
    return new MockElement(tagName);
  }

  getElementById(id) {
    return this.body.querySelector('#' + id);
  }

  querySelector(selector) {
    if (_matchesSelector(this.body, selector)) return this.body;
    return this.body.querySelector(selector);
  }

  querySelectorAll(selector) {
    const res = [];
    if (_matchesSelector(this.body, selector)) res.push(this.body);
    return res.concat(this.body.querySelectorAll(selector));
  }
}

let originalDocument = null;
let originalWindow = null;

export function setupGlobalDOM() {
  if (typeof globalThis.document === 'undefined') {
    const doc = new MockDocument();
    globalThis.document = doc;
    globalThis.window = {
      document: doc,
      addEventListener: () => {},
      removeEventListener: () => {}
    };
    return { document: doc, window: globalThis.window };
  }
  return { document: globalThis.document, window: globalThis.window };
}

export function teardownGlobalDOM() {
  // restore if needed
}
