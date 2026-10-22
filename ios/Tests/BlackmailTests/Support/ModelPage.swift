import Foundation
@testable import Blackmail

/// The stack's own script (`ConversationDocument.script`) run in node on a
/// model of the pane's page, for what reading the script cannot show: where
/// the letters are on the glass, frame by frame, as a finger drags the
/// stack and the pane's changes come.
///
/// A model, not WebKit. A line is 38 px, a letter's "Found in" 20, a
/// body the `data-h` of what is in it or 30 for "Loading…", and the last
/// letter at least the pane, 700 px, as its `min-height` has it. Time is a
/// clock of the model's: timers, `performance.now()`, and a frame every 16
/// ms, in which the scroll events go out and then the `ResizeObserver`'s
/// answers. The page's offset is the script's to set, but for one thing,
/// which is what the iPad showed on 2026-10-22 (B-104): while a finger
/// drags the stack, or the stack coasts after it, the offset is the
/// finger's or the coast's, from where the pan began, so one the script set
/// meanwhile is replaced at the next move or the next frame, as WKWebView's
/// scroll view, in another process, replaced it. A pan begins once the
/// finger has moved 10 px. The touches go to the window's listeners, as
/// WebKit sends them, on whatever is under the finger, or nowhere for a
/// finger that landed on the page before this one, which WebKit does not
/// send this page. The stack is never scrolled past its top or its bottom:
/// a pull past the top, or a coast into it, as the bounce back from it is
/// here, holds the page at the top and sends it no scroll.
///
/// The pane's side is modelled too, as `MessageDetailViewController` has
/// it (`ConversationDocument.Motion`): with each insert it says whether its
/// scroll view is moving the stack, a finger down or the stack coasting,
/// and while it is it says so again every tenth of a second until it says
/// it is still. A finger down counts from the moment it lands, still or
/// not, as UIKit's `isTracking` is taken to.
///
/// Run only where node is: elsewhere the tests that use it skip, and the
/// script's own pins, read from its source, still hold it.
enum ModelPage {

    /// One thing done to the page at `at` milliseconds.
    struct Step: Encodable {
        let at: Int
        let action: String
        var y: Int? = nil
        var silent: Bool? = nil
        var coast: Double? = nil
        var html: String? = nil
        var before: String? = nil
        var id: String? = nil
        var isHTML: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case at, action = "do", y, silent, coast, html, before, id, isHTML
        }

        /// A finger lands at `y` on the pane; `silent`, with no touchstart
        /// sent, as for a finger that landed on the page before.
        static func down(_ at: Int, y: Int, silent: Bool = false) -> Step {
            Step(at: at, action: "down", y: y, silent: silent ? true : nil)
        }
        /// The finger moves to `y`; `silent`, with no touchmove sent.
        static func move(_ at: Int, y: Int, silent: Bool = false) -> Step {
            Step(at: at, action: "move", y: y, silent: silent ? true : nil)
        }
        /// The finger lifts, the stack coasting on at `coast` px a ms if
        /// given; `silent`, with no touchend sent, as if WebKit lost it.
        static func up(_ at: Int, coast: Double? = nil, silent: Bool = false) -> Step {
            Step(at: at, action: "up", silent: silent ? true : nil, coast: coast)
        }
        /// What `ConversationDocument.Insert` has the pane run.
        static func insert(_ at: Int, _ insert: ConversationDocument.Insert) -> Step {
            Step(at: at, action: "insert", html: insert.html, before: insert.before)
        }
        /// What `ConversationDocument.Append` has the pane run.
        static func append(_ at: Int, _ append: ConversationDocument.Append) -> Step {
            Step(at: at, action: "append", html: append.html)
        }
        /// What `ConversationDocument.Fill` has the pane run.
        static func fill(_ at: Int, _ fill: ConversationDocument.Fill) -> Step {
            Step(at: at, action: "fill", html: fill.body.html, id: fill.sectionID, isHTML: fill.body.isHTML)
        }
        /// The page's next `insertBefore` on its body throws, once.
        static func breakNextInsert(_ at: Int) -> Step { Step(at: at, action: "breakOnce") }
    }

    /// What the run saw: every frame, what the script told the pane, what
    /// threw, and when each step changed the stack's letters at once.
    struct Run: Decodable {
        let frames: [Frame]
        let posts: [Post]
        let errors: [String]
        let calls: [Call]
        /// What the script still held at the end, nil for a script that
        /// holds nothing.
        let held: Int?

        struct Frame: Decodable {
            let t: Double
            /// How far the finger and the coast have moved the stack, up,
            /// since the start.
            let moved: Double
            let fingerDown: Bool
            let coasting: Bool
            let sections: [Section]

            /// The top of a letter's line on the glass, nil when the letter
            /// is not on the page.
            func top(_ sectionID: String) -> Double? {
                sections.first { $0.id == sectionID }?.top
            }
        }

        struct Section: Decodable {
            let id: String
            let top: Double
            let open: Bool
            /// The `data-h` of what is in its body, "" for none.
            let body: String
        }

        struct Post: Decodable, Equatable {
            let id: String
            let open: Bool
        }

        struct Call: Decodable {
            let t: Double
            let action: String
            let changedAtOnce: Bool
        }

        /// The stack's sections, top to bottom, at the end.
        var order: [String] { frames.last?.sections.map(\.id) ?? [] }

        /// The time of the first frame with `sectionID` on the page.
        func firstFrame(with sectionID: String) -> Double? {
            frames.first { $0.top(sectionID) != nil }?.t
        }

        /// Every frame where the letter `sectionID` moved on the glass by
        /// other than the finger or the coast moved the stack: the frame's
        /// time and the jump, in px, down.
        func jumps(of sectionID: String) -> [(t: Double, by: Double)] {
            zip(frames, frames.dropFirst()).compactMap { was, now in
                guard let a = was.top(sectionID), let b = now.top(sectionID) else { return nil }
                let jump = (b - a) + (now.moved - was.moved)
                return abs(jump) < 0.001 ? nil : (now.t, jump)
            }
        }
    }

    /// What the pane tells the page of its scroll view.
    enum Pane {
        /// As the pane does (`ConversationDocument.Motion`).
        case tells
        /// With an insert, and never again, as if its ticks were lost.
        case tellsOnce
        /// Nothing: the insert as it was before the pane told the page
        /// anything, `bmInsert(html, before)`, the script on its own.
        case silent
    }

    /// No node on this host.
    struct NoNode: Error {}

    /// The model itself did not run: what node said.
    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    /// Runs `script` on the model of `page`, a document the pane draws
    /// (`ConversationDocument.html`), its head's `bm-opens` and its body's
    /// letters, through `steps`, to `end` ms, the pane telling the page of
    /// its scroll view as `pane` has it. The page has loaded at 0.
    static func run(_ script: String, page: String, steps: [Step], end: Int,
                    pane: Pane = .tells) throws -> Run {
        struct Input: Encodable {
            let script: String
            let html: String
            let steps: [Step]
            let end: Int
            let insert: String
            let motion: String?
            let ticks: Bool
            let every: Int
        }
        let input = try JSONEncoder().encode(Input(
            script: script, html: page, steps: steps, end: end,
            insert: pane == .silent ? "bmInsert(html, before)" : ConversationDocument.Insert.script,
            motion: pane == .silent ? nil : ConversationDocument.Motion.script,
            ticks: pane == .tells,
            every: Int((ConversationDocument.Motion.every * 1_000).rounded())))

        let node = Process()
        node.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        node.arguments = ["node", "-e", program]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        node.standardInput = stdin
        node.standardOutput = stdout
        node.standardError = stderr
        do { try node.run() } catch { throw NoNode() }
        let watchdog = DispatchWorkItem { if node.isRunning { node.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        defer { watchdog.cancel() }
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        node.waitUntilExit()
        // env's own status when it finds no node.
        if node.terminationStatus == 127 { throw NoNode() }
        guard node.terminationStatus == 0 else {
            throw Failed(description: String(data: err, encoding: .utf8) ?? "status \(node.terminationStatus)")
        }
        return try JSONDecoder().decode(Run.self, from: out)
    }

    /// The model, in node. Reads its input, the script, the page, the steps
    /// and the end, from standard input, and writes the run as JSON.
    static let program = #"""
    'use strict';
    const vm = require('vm');
    const INPUT = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const LINE = 38, FOUND = 20, WAITING = 30, VIEW = 700, FRAME = 16;

    let clock = 0;
    let timers = [];
    let timerSeq = 0;
    function modelSetTimeout(fn, ms) {
      timerSeq += 1;
      timers.push({ id: timerSeq, at: clock + Math.max(0, Number(ms) || 0), fn: fn });
      return timerSeq;
    }
    function modelClearTimeout(id) { timers = timers.filter(function (t) { return t.id !== id; }); }
    for (const [name, value] of [['setTimeout', modelSetTimeout], ['clearTimeout', modelClearTimeout],
                                 ['performance', { now: function () { return clock; } }]]) {
      Object.defineProperty(globalThis, name, { value: value, writable: true, configurable: true });
    }

    const VOID = new Set(['meta', 'br', 'img', 'hr', 'input', 'link']);
    class Element {
      constructor(tag, attrs) {
        this.tagName = tag.toUpperCase();
        this.attrs = attrs || {};
        this.children = [];
        this.parentNode = null;
        this.listeners = {};
      }
      get id() { return this.attrs.id || ''; }
      get className() { return this.attrs['class'] || ''; }
      set className(v) { this.attrs['class'] = v; }
      get classList() {
        const el = this;
        const list = function () { return el.className.split(/\s+/).filter(Boolean); };
        return {
          contains: function (c) { return list().indexOf(c) !== -1; },
          add: function (c) { if (list().indexOf(c) === -1) el.className = list().concat([c]).join(' '); },
          remove: function (c) { el.className = list().filter(function (x) { return x !== c; }).join(' '); },
          toggle: function (c) {
            if (list().indexOf(c) !== -1) { this.remove(c); return false; }
            this.add(c);
            return true;
          },
        };
      }
      getAttribute(n) { return Object.prototype.hasOwnProperty.call(this.attrs, n) ? this.attrs[n] : null; }
      get firstElementChild() { return this.children[0] || null; }
      get previousElementSibling() {
        if (!this.parentNode) return null;
        const i = this.parentNode.children.indexOf(this);
        return i > 0 ? this.parentNode.children[i - 1] : null;
      }
      insertBefore(child, ref) {
        if (child.parentNode) child.parentNode.removeChild(child);
        let i = this.children.length;
        if (ref) {
          i = this.children.indexOf(ref);
          if (i < 0) throw new Error('NotFoundError: not a child');
        }
        this.children.splice(i, 0, child);
        child.parentNode = this;
        return child;
      }
      appendChild(child) { return this.insertBefore(child, null); }
      removeChild(child) {
        const i = this.children.indexOf(child);
        if (i < 0) throw new Error('NotFoundError: not a child');
        this.children.splice(i, 1);
        child.parentNode = null;
        return child;
      }
      set innerHTML(html) {
        for (const c of this.children) c.parentNode = null;
        this.children = [];
        for (const c of parse(String(html))) this.appendChild(c);
      }
      addEventListener(name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); }
      descendants() {
        const out = [];
        (function walk(el) { for (const c of el.children) { out.push(c); walk(c); } })(this);
        return out;
      }
      querySelectorAll(selector) {
        const chain = selector.split('>').map(function (s) { return s.trim(); });
        return this.descendants().filter(function (el) { return matchesChain(el, chain); });
      }
      querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
      getBoundingClientRect() { return box(this); }
    }
    function matchesOne(el, simple) {
      const m = /^([a-z]+)?((?:\.[-\w]+)*)(?:\[([-\w]+)="([^"]*)"\])?$/.exec(simple);
      if (!m) throw new Error('selector not modelled: ' + simple);
      if (m[1] && el.tagName !== m[1].toUpperCase()) return false;
      for (const c of (m[2] || '').split('.').filter(Boolean)) if (!el.classList.contains(c)) return false;
      if (m[3] && el.getAttribute(m[3]) !== m[4]) return false;
      return true;
    }
    function matchesChain(el, chain) {
      if (!matchesOne(el, chain[chain.length - 1])) return false;
      if (chain.length === 1) return true;
      return el.parentNode instanceof Element && matchesChain(el.parentNode, chain.slice(0, -1));
    }
    function parse(html) {
      const top = [];
      const open = [];
      const re = /<\/([a-zA-Z0-9]+)\s*>|<([a-zA-Z0-9]+)((?:\s+[-\w:]+(?:="[^"]*")?)*)\s*\/?>|<!--[\s\S]*?-->|<![^>]*>|([^<]+)/g;
      let m;
      while ((m = re.exec(html))) {
        if (m[1]) {
          const tag = m[1].toUpperCase();
          while (open.length) { if (open.pop().tagName === tag) break; }
        } else if (m[2]) {
          const attrs = {};
          const are = /([-\w:]+)(?:="([^"]*)")?/g;
          let a;
          while ((a = are.exec(m[3] || ''))) attrs[a[1]] = a[2] === undefined ? '' : a[2];
          const el = new Element(m[2], attrs);
          if (open.length) open[open.length - 1].appendChild(el); else top.push(el);
          if (!VOID.has(m[2].toLowerCase())) open.push(el);
        }
      }
      return top;
    }

    const documentElement = new Element('html');
    const head = documentElement.appendChild(new Element('head'));
    const body = documentElement.appendChild(new Element('body'));
    const doc = {
      documentElement: documentElement, head: head, body: body,
      createElement: function (tag) { return new Element(tag); },
      getElementById: function (id) {
        return documentElement.descendants().find(function (el) { return el.id === id; }) || null;
      },
      querySelectorAll: function (s) { return documentElement.querySelectorAll(s); },
      querySelector: function (s) { return documentElement.querySelector(s); },
      addEventListener: function () { throw new Error('the document is not listened to'); },
    };

    function bodyHeight(el) {
      const sized = [el].concat(el.descendants()).find(function (d) { return d.getAttribute('data-h') !== null; });
      return sized ? Number(sized.getAttribute('data-h')) : WAITING;
    }
    function heightOf(section) {
      let h = LINE;
      if (section.classList.contains('bm-open')) {
        for (const c of section.children) {
          if (c.classList.contains('bm-found')) h += FOUND;
          if (c.classList.contains('bm-body')) h += bodyHeight(c);
        }
      }
      if (section === body.children[body.children.length - 1]) h = Math.max(h, VIEW);
      return h;
    }
    function layout() {
      let y = 0;
      const at = new Map();
      for (const s of body.children) { const h = heightOf(s); at.set(s, { y: y, h: h }); y += h; }
      return { at: at, height: y };
    }
    function sectionOf(el) {
      for (let n = el; n; n = n.parentNode) if (n.parentNode === body) return n;
      return null;
    }
    function box(el) {
      const l = layout();
      const s = sectionOf(el);
      if (!s) return { top: -scrollY, bottom: l.height - scrollY, height: l.height };
      const p = l.at.get(s);
      if (el === s) return { top: p.y - scrollY, bottom: p.y + p.h - scrollY, height: p.h };
      if (el.classList.contains('bm-head') || el.parentNode.classList.contains('bm-head')) {
        return { top: p.y - scrollY, bottom: p.y + LINE - scrollY, height: LINE };
      }
      return { top: p.y + LINE - scrollY, bottom: p.y + p.h - scrollY, height: p.h - LINE };
    }

    let scrollY = 0;
    let scrollPending = false;
    function clampScroll(y) { return Math.max(0, Math.min(Math.max(0, layout().height - VIEW), y)); }
    function setScroll(y) {
      const c = clampScroll(y);
      if (c !== scrollY) { scrollY = c; scrollPending = true; }
    }
    const windowListeners = {};
    const posts = [];
    Object.defineProperty(globalThis, 'pageYOffset', { get: function () { return scrollY; }, configurable: true });
    Object.defineProperty(globalThis, 'innerHeight', { get: function () { return VIEW; }, configurable: true });
    globalThis.window = globalThis;
    globalThis.document = doc;
    globalThis.scrollBy = function (x, dy) { setScroll(scrollY + dy); };
    globalThis.scrollTo = function (x, y) { setScroll(y); };
    globalThis.addEventListener = function (name, fn) {
      (windowListeners[name] = windowListeners[name] || []).push(fn);
    };
    globalThis.getSelection = function () { return { isCollapsed: true, removeAllRanges: function () {} }; };
    globalThis.webkit = { messageHandlers: { bmLetter: { postMessage: function (m) {
      posts.push({ id: m.id, open: m.open });
    } } } };
    const observers = [];
    globalThis.ResizeObserver = class {
      constructor(callback) { this.callback = callback; this.sizes = new Map(); observers.push(this); }
      observe(el) { if (!this.sizes.has(el)) this.sizes.set(el, -1); }
    };
    const errors = [];
    function dispatch(name, event) {
      for (const fn of (windowListeners[name] || []).slice()) {
        try { fn(event); } catch (e) { errors.push(name + ': ' + e.message); }
      }
    }

    let finger = null;
    let coast = null;
    let moved = 0;
    function lineAt(y) {
      const l = layout();
      for (const s of body.children) {
        const p = l.at.get(s);
        const top = p.y - scrollY;
        if (y >= top && y < top + p.h) return y < top + LINE ? (s.querySelector('.bm-head') || s) : s;
      }
      return body;
    }
    function touchEvent(y, down) {
      const touch = { clientX: 300, clientY: y };
      return { touches: down ? [touch] : [], changedTouches: [touch], target: lineAt(y),
               preventDefault: function () {} };
    }
    function fingerTo(y) {
      if (!finger.panning && Math.abs(y - finger.startY) > 10) {
        finger.panning = true;
        finger.startY = y;
        finger.startScroll = scrollY;
        finger.last = y;
      }
      if (finger.panning) {
        moved += clampScroll(finger.startScroll + (finger.startY - y))
               - clampScroll(finger.startScroll + (finger.startY - finger.last));
        finger.last = y;
        setScroll(finger.startScroll + (finger.startY - y));
      }
      finger.y = y;
    }

    // The pane: whether its scroll view moves the stack, and its word to
    // the page, run as callAsyncJavaScript runs a body, its arguments by
    // name.
    function paneMoving() { return !!finger || !!coast; }
    function callBody(body, args) {
      const names = Object.keys(args);
      return new Function(names.join(','), body).apply(null, names.map(function (n) { return args[n]; }));
    }
    let ticking = false;
    function paneTick() {
      const moving = paneMoving();
      try { callBody(INPUT.motion, { moving: moving }); } catch (e) { errors.push('motion: ' + e.message); }
      if (moving) modelSetTimeout(paneTick, INPUT.every); else ticking = false;
    }
    function paneInsert(step) {
      const moving = typeof INPUT.motion === 'string' && paneMoving();
      try {
        callBody(INPUT.insert, { html: step.html, before: step.before, moving: moving });
      } finally {
        if (moving && INPUT.ticks && !ticking) { ticking = true; modelSetTimeout(paneTick, INPUT.every); }
      }
    }

    const out = { frames: [], posts: posts, errors: errors, calls: [] };
    function frame() {
      if (coast) {
        const step = coast.v * FRAME;
        moved += clampScroll(coast.pos + step) - clampScroll(coast.pos);
        coast.pos += step;
        coast.v *= 0.9;
        setScroll(coast.pos);
        if (Math.abs(coast.v) < 0.02) coast = null;
      }
      if (scrollPending) { scrollPending = false; dispatch('scroll', {}); }
      for (let round = 0; round < 4; round++) {
        let any = false;
        for (const o of observers) {
          const entries = [];
          for (const [el, was] of o.sizes) {
            const h = heightOf(sectionOf(el) || el);
            if (h !== was) { o.sizes.set(el, h); entries.push({ target: el }); }
          }
          if (entries.length) {
            any = true;
            try { o.callback(entries); } catch (e) { errors.push('ResizeObserver: ' + e.message); }
          }
        }
        if (!any) break;
      }
      if (scrollPending) { scrollPending = false; dispatch('scroll', {}); }
      const l = layout();
      out.frames.push({ t: clock, moved: moved, fingerDown: !!finger, coasting: !!coast,
        sections: body.children.map(function (s) {
          const b = s.querySelector('.bm-body');
          return { id: s.id, top: l.at.get(s).y - scrollY, open: s.classList.contains('bm-open'),
                   body: b ? b.descendants().map(function (d) { return d.getAttribute('data-h'); })
                                .filter(function (h) { return h !== null; }).join(',') : '' };
        }) });
    }
    function act(step) {
      switch (step.do) {
        case 'down':
          finger = { startY: step.y, y: step.y, panning: false };
          coast = null;
          if (!step.silent) dispatch('touchstart', touchEvent(step.y, true));
          return;
        case 'move':
          fingerTo(step.y);
          if (!step.silent) dispatch('touchmove', touchEvent(step.y, true));
          return;
        case 'up': {
          const y = finger.y;
          if (step.coast) coast = { v: step.coast, pos: scrollY };
          finger = null;
          if (!step.silent) dispatch('touchend', touchEvent(y, false));
          return;
        }
        case 'breakOnce': {
          const real = body.insertBefore;
          body.insertBefore = function () { body.insertBefore = real; throw new Error('broken once'); };
          return;
        }
      }
      const was = body.children.map(function (s) { return s.id; }).join(' ');
      try {
        if (step.do === 'insert') paneInsert(step);
        else if (step.do === 'append') globalThis.bmAppend(step.html);
        else if (step.do === 'fill') globalThis.bmFill(step.id, step.html, step.isHTML);
        else throw new Error('no such step: ' + step.do);
      } catch (e) { errors.push(step.do + ': ' + e.message); }
      out.calls.push({ t: clock, action: step.do,
                       changedAtOnce: was !== body.children.map(function (s) { return s.id; }).join(' ') });
    }

    const page = INPUT.html;
    const meta = /<meta name="bm-opens" content="([^"]*)">/.exec(page);
    if (meta) head.appendChild(new Element('meta', { name: 'bm-opens', content: meta[1] }));
    body.innerHTML = page.slice(page.indexOf('<body>') + 6, page.lastIndexOf('</body>'));
    vm.runInThisContext(INPUT.script);
    dispatch('load', {});
    frame();

    const steps = INPUT.steps.slice().sort(function (a, b) { return a.at - b.at; });
    let nextFrame = FRAME;
    for (let turns = 0; ; turns++) {
      if (turns > 100000) throw new Error('the page never settles');
      const nextStep = steps.length ? steps[0].at : Infinity;
      const nextTimer = timers.length ? Math.min.apply(null, timers.map(function (t) { return t.at; })) : Infinity;
      const next = Math.min(nextStep, nextTimer, nextFrame);
      if (next > INPUT.end) break;
      clock = next;
      if (nextStep === next) { act(steps.shift()); continue; }
      if (nextTimer === next) {
        const due = timers.filter(function (t) { return t.at === next; })
                          .sort(function (a, b) { return a.id - b.id; })[0];
        timers = timers.filter(function (t) { return t !== due; });
        try { due.fn(); } catch (e) { errors.push('timer: ' + e.message); }
        continue;
      }
      frame();
      nextFrame += FRAME;
    }
    out.held = vm.runInThisContext('typeof bmHeld === "undefined" ? null : bmHeld.length');
    process.stdout.write(JSON.stringify(out));
    """#
}
