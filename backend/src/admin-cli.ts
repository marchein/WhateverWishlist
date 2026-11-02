import { existsSync } from 'node:fs';
import { ZodError } from 'zod';
import { passwordFromPrompt, passwordFromStdin } from './admin-input.js';
import { listUsers, resetPassword } from './admin.js';
import { config } from './config.js';
import { openDatabase } from './db.js';

const HELP = `Wishlist administration (requires access to the API container and its database)

  node dist/admin-cli.js users
      List every user and their wishlists as JSON (no passwords, hashes or share tokens).

  node dist/admin-cli.js reset-password <email>
      Enter and confirm a new password at a hidden interactive prompt.

  node dist/admin-cli.js reset-password <email> --stdin
      Read one password line from stdin for automation.

Password resets sign the user out on every device. Public share links stay valid.
Passwords must be at least 8 characters and at most 72 UTF-8 bytes.
`;

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0 || (args.length === 1 && ['--help', '-h'].includes(args[0]))) {
    process.stdout.write(HELP);
    return;
  }
  const [command, email, option] = args;
  const usersCommand = command === 'users' && args.length === 1;
  const resetCommand = command === 'reset-password' && !!email &&
    (args.length === 2 || (args.length === 3 && option === '--stdin'));
  if (!usersCommand && !resetCommand) throw new Error(`Unknown command or arguments. Use --help for usage.`);
  if (!existsSync(config.databaseFile)) throw new Error('Database does not exist. Start the API first and check DATABASE_FILE.');
  const db = openDatabase(config.databaseFile);
  try {
    if (usersCommand) {
      process.stdout.write(`${JSON.stringify({ users: listUsers(db) }, null, 2)}\n`);
    } else {
      const password = option === '--stdin' ? await passwordFromStdin() : await passwordFromPrompt();
      const account = await resetPassword(db, email, password);
      process.stdout.write(`Password reset for ${account}. All login sessions revoked. Shared links unchanged.\n`);
    }
  } finally {
    db.close();
  }
}

try {
  await main();
} catch (error) {
  const message = error instanceof ZodError
    ? error.issues.map((issue) => issue.message).join('; ')
    : error instanceof Error ? error.message : 'Administration command failed';
  process.stderr.write(`Error: ${message}\n`);
  process.exitCode = 1;
}
