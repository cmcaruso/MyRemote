/**
 * Keyboard Mode: turns what the iOS keyboard does to a hidden field, and taps on the key bar, into
 * commands for the Host.
 *
 * Typing is live, kept in sync by a diff. The model remembers the text typed on the Mac since the last
 * reset; on every change to the field it sends just enough Backspaces plus new text to make the Mac
 * match, so autocorrect, predictions, dictation and paste all come out right. The field starts with
 * SENTINEL, so Backspace still does something when nothing has been typed: deleting the sentinel sends
 * a real Backspace. After each change the caller sets the field back to `field`.
 *
 * Wire format: `{ t: 'tx', bs, s }` types, `{ t: 'kp', k | c, m? }` presses a named key or the key for
 * a character with modifiers, `{ t: 'as' }` taps the App switcher.
 */

/** Zero-width space: invisible, and one Backspace deletes it. */
export const SENTINEL = '​';
/** Modifiers in the order the bar shows them, by their wire names. */
export const MODIFIERS = ['ctrl', 'opt', 'cmd', 'shift'];
/** A second tap on a modifier within this many ms locks it. */
const DOUBLE_TAP_MS = 350;

const segmenter = new Intl.Segmenter();
const graphemes = (text) => Array.from(segmenter.segment(text), (g) => g.segment);

/**
 * What to send to turn `before` into `after`: `bs` Backspaces, then the text `s`. Works on whole
 * characters (grapheme clusters), as the Mac's Backspace does.
 */
export function diff(before, after) {
  const a = graphemes(before), b = graphemes(after);
  let same = 0;
  while (same < a.length && same < b.length && a[same] === b[same]) same++;
  return { bs: a.length - same, s: b.slice(same).join('') };
}

/**
 * Sticky one-shot modifiers: a tap applies the modifier to the next key only, a quick second tap locks
 * it until it's tapped again, like Shift on iOS.
 */
export function createModifiers() {
  const state = Object.fromEntries(MODIFIERS.map((m) => [m, 'off']));
  const tappedAt = {};
  return {
    /** `off`, `once` or `locked`. */
    state: (name) => state[name],
    /** The modifiers that apply to the next key, by wire name. */
    get active() {
      return MODIFIERS.filter((m) => state[m] !== 'off');
    },
    tap(name, t) {
      const quick = t - (tappedAt[name] ?? -Infinity) <= DOUBLE_TAP_MS;
      state[name] = state[name] === 'off' ? 'once' : state[name] === 'once' && quick ? 'locked' : 'off';
      tappedAt[name] = t;
    },
    /** A key went out: one-shot modifiers are spent, locked ones stay. */
    consume() {
      for (const m of MODIFIERS) if (state[m] === 'once') state[m] = 'off';
    },
  };
}

/** Keys after which the Mac's text cursor may have moved, so the field starts over. */
const MOVES_CURSOR = new Set(['esc', 'tab', 'return', 'left', 'right', 'up', 'down', 'del', 'space']);

export function createKeyboard() {
  const mods = createModifiers();
  let typed = ''; // on the Mac since the last reset

  /** A key press carrying the active modifiers, which it spends. */
  function press(key) {
    const command = { t: 'kp', ...key };
    const m = mods.active;
    mods.consume();
    if (m.length) command.m = m;
    if (!('k' in key) || MOVES_CURSOR.has(key.k)) typed = '';
    return command;
  }

  /** Types `s` after `bs` Backspaces; each newline goes out as Return, which starts the field over. */
  function type(bs, s) {
    const commands = [];
    s.split('\n').forEach((line, i) => {
      if (i > 0) commands.push(press({ k: 'return' }));
      if (line || (i === 0 && bs)) commands.push({ t: 'tx', bs: i === 0 ? bs : 0, s: line });
      typed = (i === 0 ? typed : '') + line;
    });
    return commands;
  }

  /** A character typed with modifiers held is a shortcut: Return and Space by name, others by character. */
  function shortcut(character) {
    if (character === '\n') return press({ k: 'return' });
    if (character === ' ') return press({ k: 'space' });
    return press({ c: character });
  }

  return {
    mods,
    /** What has been typed on the Mac since the last reset, for the typed-text strip. */
    get typed() {
      return typed;
    },
    /** What the hidden field should hold. */
    get field() {
      return SENTINEL + typed;
    },
    /** The Mac's text cursor may have moved (a click, a Mode switch): start the field over. */
    reset() {
      typed = '';
    },

    /** The hidden field now holds `value`; returns the commands that make the Mac match. */
    input(value) {
      const text = value.replaceAll(SENTINEL, '');
      if (!value.includes(SENTINEL) && typed === '' && text === '') return [press({ k: 'del' })];
      const { bs, s } = diff(typed, text);
      if (bs === 0 && s === '') return [];
      if (mods.active.length === 0) {
        // Keep what the Mac has already, then type the rest.
        typed = graphemes(typed).slice(0, graphemes(typed).length - bs).join('');
        return type(bs, s);
      }
      // With modifiers held, Backspace is ⌥⌫ or ⌘⌫, and a character is a shortcut.
      if (s === '') return [press({ k: 'del' })];
      const [first, ...rest] = graphemes(s);
      return [shortcut(first), ...type(0, rest.join(''))];
    },

    /** A key on the bar: `esc`, `tab`, the arrows, `fwddel`. */
    key(name) {
      return [press({ k: name })];
    },

    // The palette; it ignores the sticky modifiers.
    appSwitcher() {
      typed = '';
      return [{ t: 'as' }];
    },
    spotlight() {
      typed = '';
      return [{ t: 'kp', k: 'space', m: ['cmd'] }];
    },
    missionControl() {
      typed = '';
      return [{ t: 'kp', k: 'up', m: ['ctrl'] }];
    },
  };
}
