import assert from 'node:assert/strict';
import { PassThrough, Readable } from 'node:stream';
import { describe, it } from 'node:test';
import { passwordFromPrompt, passwordFromStdin } from './admin-input.js';

class TestTerminal extends PassThrough {
  readonly isTTY = true;
  isRaw = false;

  setRawMode(enabled: boolean): this {
    this.isRaw = enabled;
    return this;
  }
}

function promptWithInput(first: string, confirmation?: string, cancel = false) {
  const input = new TestTerminal();
  const output = new PassThrough();
  let displayed = '';
  output.on('data', (chunk: Buffer) => {
    const text = chunk.toString();
    displayed += text;
    if (text.includes('New password')) {
      queueMicrotask(() => cancel ? input.write('\u0003') : input.write(`${first}\r`));
    }
    if (text.includes('Confirm password')) {
      queueMicrotask(() => confirmation === undefined ? input.end() : input.write(`${confirmation}\r`));
    }
  });
  return { input, result: passwordFromPrompt(input, output), displayed: () => displayed };
}

describe('administration password input', () => {
  it('accepts a confirmed password without echoing either entry and restores terminal mode', async () => {
    const password = 'hidden-test-password';
    const prompt = promptWithInput(password, password);
    assert.equal(await prompt.result, password);
    assert.match(prompt.displayed(), /New password/);
    assert.match(prompt.displayed(), /Confirm password/);
    assert.ok(!prompt.displayed().includes(password));
    assert.equal(prompt.input.isRaw, false);
  });

  it('rejects mismatched confirmation without echoing either password', async () => {
    const prompt = promptWithInput('first-test-password', 'other-test-password');
    await assert.rejects(prompt.result, /Passwords do not match/);
    assert.doesNotMatch(prompt.displayed(), /first-test-password|other-test-password/);
    assert.equal(prompt.input.isRaw, false);
  });

  it('handles Ctrl+C without leaving the terminal in raw mode', async () => {
    const prompt = promptWithInput('', undefined, true);
    await assert.rejects(prompt.result, /Password reset canceled/);
    assert.equal(prompt.input.isRaw, false);
  });

  it('cancels if input closes during confirmation', async () => {
    const prompt = promptWithInput('test-password');
    await assert.rejects(prompt.result, /Password reset canceled/);
    assert.equal(prompt.input.isRaw, false);
  });

  it('requires a terminal for hidden interactive input', async () => {
    await assert.rejects(passwordFromPrompt(Readable.from([])), /requires a TTY/);
  });

  it('accepts one piped line and preserves intentional password whitespace', async () => {
    assert.equal(await passwordFromStdin(Readable.from(['  test-', 'password  \r\n'])), '  test-password  ');
    assert.equal(await passwordFromStdin(Readable.from(['without-newline'])), 'without-newline');
    const unicode = Buffer.from('test-\u00e4-password\n');
    assert.equal(await passwordFromStdin(Readable.from([unicode.subarray(0, 6), unicode.subarray(6)])), 'test-\u00e4-password');
  });

  it('rejects a terminal or unbounded/multiline input in stdin mode', async () => {
    await assert.rejects(passwordFromStdin(new TestTerminal()), /expects piped input/);
    await assert.rejects(passwordFromStdin(Readable.from(['a'.repeat(1025)])), /too long/);
    await assert.rejects(passwordFromStdin(Readable.from(['first\nsecond\n'])), /exactly one password line/);
  });
});
