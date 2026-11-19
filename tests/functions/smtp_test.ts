// SMTP without a library (supabase/functions/_shared/smtp.ts), against a
// stand-in mail server: signing in, sending, a refused address, a server
// that can't be reached.
//
//   deno test tests/functions/
import {
  buildMessage,
  type Conn,
  deliver,
  encodeHeader,
  type SmtpConfig,
  SmtpError,
  smtpFromEnv,
  SmtpSession,
} from '../../supabase/functions/_shared/smtp.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

function ok(value: unknown, what: string) {
  if (!value) throw new Error(what);
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** A mail server that answers as Gmail's does, and keeps what it's sent. */
class FakeServer implements Conn {
  commands: string[] = [];
  messages: string[] = [];
  closed = false;
  #replies: string[] = ['220 smtp.test ESMTP ready\r\n'];
  #unread = '';
  #data: string | null = null;
  #wake: (() => void) | null = null;

  constructor(readonly login: string, readonly refuse: string[] = []) {}

  async read(p: Uint8Array): Promise<number | null> {
    while (!this.#replies.length) {
      if (this.closed) return null;
      await new Promise<void>((resolve) => (this.#wake = resolve));
    }
    const bytes = encoder.encode(this.#replies.shift()!);
    p.set(bytes);
    return bytes.length;
  }

  write(p: Uint8Array): Promise<number> {
    this.#unread += decoder.decode(p);
    let end: number;
    while ((end = this.#unread.indexOf('\r\n')) >= 0) {
      const line = this.#unread.slice(0, end);
      this.#unread = this.#unread.slice(end + 2);
      this.#line(line);
    }
    this.#wake?.();
    this.#wake = null;
    return Promise.resolve(p.length);
  }

  close(): void {
    this.closed = true;
    this.#wake?.();
  }

  #line(line: string) {
    if (this.#data != null) {
      if (line === '.') {
        this.messages.push(this.#data);
        this.#data = null;
        this.#replies.push('250 2.0.0 OK queued\r\n');
      } else {
        this.#data += `${line.startsWith('..') ? line.slice(1) : line}\r\n`;
      }
      return;
    }
    this.commands.push(line.startsWith('AUTH') ? 'AUTH' : line);
    const verb = line.split(' ')[0].toUpperCase();
    if (verb === 'EHLO') this.#replies.push('250-smtp.test at your service\r\n250-AUTH LOGIN PLAIN\r\n250 SMTPUTF8\r\n');
    else if (verb === 'AUTH') this.#replies.push(line === this.login ? '235 2.7.0 Accepted\r\n' : '535 5.7.8 Username and Password not accepted\r\n');
    else if (verb === 'RCPT') this.#replies.push(this.refuse.some((r) => line.includes(r)) ? '550 5.1.1 No such user\r\n' : '250 OK\r\n');
    else if (verb === 'DATA') {
      this.#data = '';
      this.#replies.push('354 Go ahead\r\n');
    } else if (verb === 'MAIL' || verb === 'RSET') this.#replies.push('250 OK\r\n');
    else if (verb === 'QUIT') this.#replies.push('221 Bye\r\n');
    else this.#replies.push('502 Not here\r\n');
  }
}

const config: SmtpConfig = { host: 'smtp.test', port: 465, user: 'healthpro@gmail.com', pass: 'app pass', from: 'Health Pro <healthpro@gmail.com>' };
const login = `AUTH PLAIN ${btoa('\0healthpro@gmail.com\0app pass')}`;
const mail = (to: string) => ({ to, subject: 'Booked: Spin on Sat 21 Nov', text: 'Hi Xo,\n\nSee you there.', html: '<p>Hi Xo,</p>' });

/** A part of [message], decoded. */
function part(message: string, type: string): string {
  const start = message.indexOf(`Content-Type: ${type}`);
  const body = message.slice(message.indexOf('\r\n\r\n', start) + 4).split('\r\n--')[0];
  const bytes = Uint8Array.from(atob(body.replace(/\r\n/g, '')), (c) => c.charCodeAt(0));
  return decoder.decode(bytes);
}

Deno.test('signs in, sends an email, and says goodbye', async () => {
  const server = new FakeServer(login);
  const session = await SmtpSession.open(config, () => Promise.resolve(server));
  await session.send(mail('xo@x.bt'));
  await session.quit();
  same(server.commands, ['EHLO gmail.com', 'AUTH', 'MAIL FROM:<healthpro@gmail.com>', 'RCPT TO:<xo@x.bt>', 'DATA', 'QUIT']);
  ok(server.closed, 'the connection is closed');
  const message = server.messages[0];
  ok(message.includes('From: "Health Pro" <healthpro@gmail.com>\r\n'), 'from Health Pro');
  ok(message.includes('To: <xo@x.bt>\r\nSubject: Booked: Spin on Sat 21 Nov\r\n'), 'to Xo, with the subject');
  same(part(message, 'text/plain'), 'Hi Xo,\n\nSee you there.');
  same(part(message, 'text/html'), '<p>Hi Xo,</p>');
});

Deno.test('a wrong password: an error that says so, and the connection closed', async () => {
  const server = new FakeServer('AUTH PLAIN other');
  let error: unknown;
  try {
    await SmtpSession.open(config, () => Promise.resolve(server));
  } catch (e) {
    error = e;
  }
  ok(error instanceof SmtpError && error.code === 535 && error.message.includes('not accepted'), `got ${error}`);
  ok(!String(error).includes('app pass'), 'never the password');
  ok(server.closed, 'closed');
});

Deno.test('one refused address doesn\'t stop the rest', async () => {
  const server = new FakeServer(login, ['nobody@x.bt']);
  const result = await deliver(
    [{ id: 'a', mail: mail('xo@x.bt') }, { id: 'b', mail: mail('nobody@x.bt') }, { id: 'c', mail: mail('mindu@x.bt') }],
    () => SmtpSession.open(config, () => Promise.resolve(server)),
  );
  same(result.sent, ['a', 'c']);
  same(result.failed.map((f) => f.id), ['b']);
  ok(result.failed[0].error.startsWith('550'), result.failed[0].error);
  same(server.messages.length, 2);
  ok(server.commands.includes('RSET'), 'ready again after the refusal');
});

Deno.test('a server that can\'t be reached: all wait for the next try', async () => {
  const result = await deliver([{ id: 'a', mail: mail('xo@x.bt') }, { id: 'b', mail: mail('mindu@x.bt') }],
    () => Promise.reject(new Error('Connection refused')));
  same(result, { sent: [], failed: [{ id: 'a', error: 'Connection refused' }, { id: 'b', error: 'Connection refused' }] });
});

Deno.test('an address that would break the message isn\'t sent', async () => {
  const server = new FakeServer(login);
  const result = await deliver([{ id: 'a', mail: mail('x@y.bt>\r\nBcc: z@w.bt') }],
    () => SmtpSession.open(config, () => Promise.resolve(server)));
  same(result.sent, []);
  same(server.messages.length, 0);
});

Deno.test('secrets: none means no email; 587 and 25 become 465; Health Pro sends by default', () => {
  same(smtpFromEnv(() => undefined), null);
  const env = (vars: Record<string, string>) => (k: string) => vars[k];
  same(smtpFromEnv(env({ SMTP_HOST: 'smtp.gmail.com', SMTP_USER: 'a@gmail.com', SMTP_PASS: 'p', SMTP_PORT: '587' })),
    { host: 'smtp.gmail.com', port: 465, user: 'a@gmail.com', pass: 'p', from: 'Health Pro <a@gmail.com>' });
  same(smtpFromEnv(env({ SMTP_HOST: 'h', SMTP_USER: 'u', SMTP_PASS: 'p', SMTP_PORT: '2465', SMTP_FROM: 'HP <hi@hp.bt>' }))?.port, 2465);
});

Deno.test('headers: plain as is, anything else encoded; no line breaks get in', () => {
  same(encodeHeader('Booked: Spin'), 'Booked: Spin');
  same(encodeHeader('Spin\r\nBcc: x@y.bt'), 'Spin Bcc: x@y.bt');
  const encoded = encodeHeader('Booked: འབྲུག Yoga at Druk Gym, Saturday morning');
  ok(encoded.split('\r\n ').every((w) => w.startsWith('=?UTF-8?B?') && w.length <= 75), encoded);
  const decoded = encoded.split('\r\n ').map((w) => w.slice(10, -2)).map((b) => Uint8Array.from(atob(b), (c) => c.charCodeAt(0)));
  same(decoded.map((b) => decoder.decode(b)).join(''), 'Booked: འབྲུག Yoga at Druk Gym, Saturday morning');
  const message = buildMessage({ ...mail('xo@x.bt'), text: 'x'.repeat(3000) }, config.from);
  ok(message.split('\r\n').every((line) => line.length <= 998), 'no line too long');
});
