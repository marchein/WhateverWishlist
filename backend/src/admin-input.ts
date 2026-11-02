import { createInterface } from 'node:readline/promises';
import { Writable, type Readable } from 'node:stream';

type PasswordInput = Readable & { isTTY?: boolean };

export async function passwordFromStdin(input: PasswordInput = process.stdin): Promise<string> {
  if (input.isTTY) throw new Error('--stdin expects piped input; omit it for the hidden prompt');
  input.setEncoding('utf8');
  let password = '';
  for await (const chunk of input) {
    password += String(chunk);
    if (Buffer.byteLength(password) > 1024) throw new Error('Password input is too long');
  }
  password = password.replace(/\r?\n$/, '');
  if (/[\r\n]/.test(password)) throw new Error('Provide exactly one password line on stdin');
  return password;
}

export async function passwordFromPrompt(
  input: PasswordInput = process.stdin,
  output: Writable = process.stderr,
): Promise<string> {
  if (!input.isTTY) throw new Error('Interactive input requires a TTY. Use --stdin for piped input.');
  const muted = new Writable({ write(_chunk, _encoding, callback) { callback(); } });
  const reader = createInterface({ input, output: muted, terminal: true, historySize: 0 });
  const abort = new AbortController();
  reader.once('SIGINT', () => abort.abort());
  reader.once('close', () => abort.abort());
  try {
    output.write('New password (hidden): ');
    const password = await reader.question('', { signal: abort.signal });
    output.write('\nConfirm password (hidden): ');
    const confirmation = await reader.question('', { signal: abort.signal });
    output.write('\n');
    if (password !== confirmation) throw new Error('Passwords do not match');
    return password;
  } catch (error) {
    if (abort.signal.aborted) {
      output.write('\n');
      throw new Error('Password reset canceled');
    }
    throw error;
  } finally {
    reader.close();
    muted.end();
  }
}
