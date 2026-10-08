import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SENTINEL, createKeyboard, createModifiers, diff } from '../keyboard.js';

/** Feeds the keyboard a series of field contents (without the sentinel) and collects the commands. */
function typeInto(keyboard, ...values) {
  return values.flatMap((v) => keyboard.input(SENTINEL + v));
}

test('diff: plain typing only adds text', () => {
  assert.deepEqual(diff('hel', 'hello'), { bs: 0, s: 'lo' });
  assert.deepEqual(diff('', 'a'), { bs: 0, s: 'a' });
});

test('diff: deleting sends Backspaces', () => {
  assert.deepEqual(diff('hello', 'hel'), { bs: 2, s: '' });
});

test('diff: a corrected word is erased back to where it changed and retyped', () => {
  assert.deepEqual(diff('teh ', 'the '), { bs: 3, s: 'he ' });
  assert.deepEqual(diff('I lik', 'I like'), { bs: 0, s: 'e' });
});

test('diff: counts whole characters, as the Mac’s Backspace deletes them', () => {
  assert.deepEqual(diff('ok 👍🏽', 'ok '), { bs: 1, s: '' });
  assert.deepEqual(diff('e', 'é'), { bs: 1, s: 'é' }); // e + combining accent is one new character
  assert.deepEqual(diff('café', 'cafe'), { bs: 1, s: 'e' });
});

test('typing sends each change and keeps the field and strip in step', () => {
  const keyboard = createKeyboard();
  assert.deepEqual(typeInto(keyboard, 'h', 'hi'), [{ t: 'tx', bs: 0, s: 'h' }, { t: 'tx', bs: 0, s: 'i' }]);
  assert.equal(keyboard.typed, 'hi');
  assert.equal(keyboard.field, SENTINEL + 'hi');
  assert.deepEqual(typeInto(keyboard, 'h'), [{ t: 'tx', bs: 1, s: '' }]);
  assert.equal(keyboard.typed, 'h');
});

test('a paste or dictation revision goes out as one frame', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'wreck a nice');
  assert.deepEqual(typeInto(keyboard, 'recognize speech'), [{ t: 'tx', bs: 12, s: 'recognize speech' }]);
});

test('an unchanged field sends nothing', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'a');
  assert.deepEqual(typeInto(keyboard, 'a'), []);
});

test('Backspace on an empty field still reaches the Mac', () => {
  const keyboard = createKeyboard();
  assert.deepEqual(keyboard.input(''), [{ t: 'kp', k: 'del' }]);
  assert.equal(keyboard.field, SENTINEL);
  assert.deepEqual(keyboard.input(''), [{ t: 'kp', k: 'del' }]);
});

test('Return goes out as the Return key and starts the field over', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'hi');
  assert.deepEqual(typeInto(keyboard, 'hi\n'), [{ t: 'kp', k: 'return' }]);
  assert.equal(keyboard.typed, '');
  assert.deepEqual(typeInto(keyboard, 'x'), [{ t: 'tx', bs: 0, s: 'x' }]);
});

test('pasted lines are typed with Returns between them', () => {
  const keyboard = createKeyboard();
  assert.deepEqual(typeInto(keyboard, 'one\ntwo'), [
    { t: 'tx', bs: 0, s: 'one' },
    { t: 'kp', k: 'return' },
    { t: 'tx', bs: 0, s: 'two' },
  ]);
  assert.equal(keyboard.typed, 'two');
});

test('keys that move the Mac’s cursor start the field over; forward delete doesn’t', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'abc');
  assert.deepEqual(keyboard.key('fwddel'), [{ t: 'kp', k: 'fwddel' }]);
  assert.equal(keyboard.typed, 'abc');
  for (const k of ['left', 'tab', 'esc']) {
    typeInto(keyboard, 'abc');
    assert.deepEqual(keyboard.key(k), [{ t: 'kp', k }]);
    assert.equal(keyboard.typed, '');
  }
  // After the reset a corrected word can't erase text from before the cursor moved.
  assert.deepEqual(typeInto(keyboard, 'x'), [{ t: 'tx', bs: 0, s: 'x' }]);
});

test('modifiers: a tap applies to the next key only', () => {
  const mods = createModifiers();
  mods.tap('cmd', 0);
  assert.equal(mods.state('cmd'), 'once');
  assert.deepEqual(mods.active, ['cmd']);
  mods.consume();
  assert.deepEqual(mods.active, []);
});

test('modifiers: a quick double tap locks, a third tap unlocks, a slow second tap cancels', () => {
  const mods = createModifiers();
  mods.tap('shift', 0);
  mods.tap('shift', 200);
  assert.equal(mods.state('shift'), 'locked');
  mods.consume();
  assert.equal(mods.state('shift'), 'locked');
  mods.tap('shift', 5000);
  assert.equal(mods.state('shift'), 'off');

  mods.tap('opt', 6000);
  mods.tap('opt', 7000);
  assert.equal(mods.state('opt'), 'off');
});

test('a character typed with a modifier is a shortcut, sent by character, and spends the modifier', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'draft');
  keyboard.mods.tap('cmd', 0);
  keyboard.mods.tap('shift', 10);
  assert.deepEqual(typeInto(keyboard, 'draftz'), [{ t: 'kp', c: 'z', m: ['cmd', 'shift'] }]);
  assert.deepEqual(keyboard.mods.active, []);
  assert.equal(keyboard.field, SENTINEL);
  assert.deepEqual(typeInto(keyboard, 'a'), [{ t: 'tx', bs: 0, s: 'a' }]);
});

test('a locked modifier applies to every key until unlocked', () => {
  const keyboard = createKeyboard();
  keyboard.mods.tap('cmd', 0);
  keyboard.mods.tap('cmd', 100);
  assert.deepEqual(keyboard.key('right'), [{ t: 'kp', k: 'right', m: ['cmd'] }]);
  assert.deepEqual(keyboard.key('left'), [{ t: 'kp', k: 'left', m: ['cmd'] }]);
});

test('with modifiers, Space, Return and Backspace go out as those keys', () => {
  const keyboard = createKeyboard();
  keyboard.mods.tap('cmd', 0);
  assert.deepEqual(typeInto(keyboard, ' '), [{ t: 'kp', k: 'space', m: ['cmd'] }]);
  keyboard.mods.tap('cmd', 1000);
  assert.deepEqual(typeInto(keyboard, '\n'), [{ t: 'kp', k: 'return', m: ['cmd'] }]);
  typeInto(keyboard, 'some words');
  keyboard.mods.tap('opt', 2000);
  assert.deepEqual(typeInto(keyboard, 'some word'), [{ t: 'kp', k: 'del', m: ['opt'] }]);
  assert.equal(keyboard.typed, '');
  keyboard.mods.tap('opt', 3000);
  assert.deepEqual(keyboard.input(''), [{ t: 'kp', k: 'del', m: ['opt'] }]);
});

test('a swipe-typed word after a modifier: the first letter is the shortcut, the rest is typed', () => {
  const keyboard = createKeyboard();
  keyboard.mods.tap('ctrl', 0);
  assert.deepEqual(typeInto(keyboard, 'abc'), [{ t: 'kp', c: 'a', m: ['ctrl'] }, { t: 'tx', bs: 0, s: 'bc' }]);
  assert.equal(keyboard.typed, 'bc');
});

test('the palette ignores the sticky modifiers and starts the field over', () => {
  const keyboard = createKeyboard();
  typeInto(keyboard, 'abc');
  keyboard.mods.tap('opt', 0);
  assert.deepEqual(keyboard.appSwitcher(), [{ t: 'as' }]);
  assert.deepEqual(keyboard.spotlight(), [{ t: 'kp', k: 'space', m: ['cmd'] }]);
  assert.deepEqual(keyboard.missionControl(), [{ t: 'kp', k: 'up', m: ['ctrl'] }]);
  assert.equal(keyboard.typed, '');
  assert.deepEqual(keyboard.mods.active, ['opt']);
});
