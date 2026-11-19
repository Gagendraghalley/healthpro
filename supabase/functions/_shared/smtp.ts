// Sends email over SMTP, without a library: TLS from the first byte (port
// 465), AUTH PLAIN, and a text + HTML message. Any SMTP provider works
// (Gmail with an app password, Brevo, Resend, Amazon SES...).
//
// Supabase's Edge Functions can't reach ports 25 or 587, so those become
// 465 (every provider above takes TLS there).
//
// Secrets: SMTP_HOST, SMTP_USER, SMTP_PASS; SMTP_PORT (465 by default);
// SMTP_FROM ('Health Pro <hello@example.bt>', or SMTP_USER as Health Pro).

export interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
}

export interface Email {
  to: string;
  subject: string;
  text: string;
  html: string;
}

/** What the server is reached through: a Deno.TlsConn, or a stand-in. */
export interface Conn {
  read(p: Uint8Array): Promise<number | null>;
  write(p: Uint8Array): Promise<number>;
  close(): void;
}

export type Connect = (host: string, port: number) => Promise<Conn>;

const tls: Connect = (hostname, port) => Deno.connectTls({ hostname, port });

export function smtpFromEnv(get: (key: string) => string | undefined = (k) => Deno.env.get(k)): SmtpConfig | null {
  const host = get('SMTP_HOST')?.trim();
  const user = get('SMTP_USER')?.trim();
  const pass = get('SMTP_PASS');
  if (!host || !user || !pass) return null;
  const asked = Number(get('SMTP_PORT') || 465);
  const port = !Number.isInteger(asked) || asked <= 0 || asked === 25 || asked === 587 ? 465 : asked;
  const from = get('SMTP_FROM')?.trim() || `Health Pro <${user}>`;
  return { host, port, user, pass, from };
}

/** 'a@b.bt' from 'Name <a@b.bt>' or 'a@b.bt'. */
export function addressOf(from: string): string {
  const m = from.match(/<([^<>]+)>/);
  return (m ? m[1] : from).trim();
}

/** Safe as an envelope and To address: one address, nothing that breaks a line or a header. */
export function isSendableAddress(email: string): boolean {
  return /^[^\s@<>()",;:\\]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(email) && email.length <= 254;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64(text: string): string {
  const bytes = encoder.encode(text);
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

/** A header's words: plain ASCII as is, anything else as RFC 2047 words of at most 75 characters. */
export function encodeHeader(value: string): string {
  const flat = value.replace(/[\r\n\t]+/g, ' ').trim();
  if (/^[\x20-\x7e]*$/.test(flat)) return flat;
  const words: string[] = [];
  let chunk = '';
  for (const ch of flat) {
    if (encoder.encode(chunk + ch).length > 45) {
      words.push(chunk);
      chunk = '';
    }
    chunk += ch;
  }
  if (chunk) words.push(chunk);
  return words.map((w) => `=?UTF-8?B?${base64(w)}?=`).join('\r\n ');
}

function formatFrom(from: string): string {
  const address = addressOf(from);
  const name = from.includes('<') ? from.slice(0, from.indexOf('<')).trim().replace(/^"|"$/g, '') : '';
  if (!name) return `<${address}>`;
  const plain = /^[A-Za-z0-9 .'-]*$/.test(name);
  return `${plain ? `"${name}"` : encodeHeader(name)} <${address}>`;
}

/** The whole message, headers and both parts, lines ending CRLF. */
export function buildMessage(mail: Email, from: string, opts: { date?: Date; id?: string; boundary?: string } = {}): string {
  const boundary = opts.boundary ?? `hp-${crypto.randomUUID()}`;
  const domain = addressOf(from).split('@')[1] || 'health-pro';
  const date = (opts.date ?? new Date()).toUTCString().replace('GMT', '+0000');
  const part = (type: string, body: string) =>
    [
      `--${boundary}`,
      `Content-Type: ${type}; charset=UTF-8`,
      'Content-Transfer-Encoding: base64',
      '',
      ...(base64(body).match(/.{1,76}/g) ?? ['']),
    ].join('\r\n');
  return [
    `From: ${formatFrom(from)}`,
    `To: <${mail.to}>`,
    `Subject: ${encodeHeader(mail.subject)}`,
    `Date: ${date}`,
    `Message-ID: <${opts.id ?? crypto.randomUUID()}@${domain}>`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    '',
    part('text/plain', mail.text),
    part('text/html', mail.html),
    `--${boundary}--`,
    '',
  ].join('\r\n');
}

export class SmtpError extends Error {
  constructor(readonly code: number, reply: string) {
    super(reply.slice(0, 300));
  }
}

/** One SMTP session: open, send any number of emails, quit. */
export class SmtpSession {
  #conn: Conn;
  #buffer = '';
  #from: string;
  #timeoutMs: number;

  private constructor(conn: Conn, from: string, timeoutMs: number) {
    this.#conn = conn;
    this.#from = from;
    this.#timeoutMs = timeoutMs;
  }

  static async open(config: SmtpConfig, connect: Connect = tls, timeoutMs = 20_000): Promise<SmtpSession> {
    const session = new SmtpSession(await connect(config.host, config.port), config.from, timeoutMs);
    try {
      await session.#reply(220);
      await session.#command(`EHLO ${addressOf(config.from).split('@')[1] || 'health-pro'}`, 250);
      await session.#command(`AUTH PLAIN ${base64(`\0${config.user}\0${config.pass}`)}`, 235);
    } catch (e) {
      session.close();
      throw e;
    }
    return session;
  }

  async send(mail: Email): Promise<void> {
    if (!isSendableAddress(mail.to)) throw new SmtpError(0, `Not an address to send to: ${mail.to}`);
    await this.#command(`MAIL FROM:<${addressOf(this.#from)}>`, 250);
    await this.#command(`RCPT TO:<${mail.to}>`, 250, 251);
    await this.#command('DATA', 354);
    // A line starting with '.' gets another (RFC 5321 4.5.2); then '.' alone ends it.
    const message = buildMessage(mail, this.#from).replace(/\r\n\./g, '\r\n..');
    await this.#write(`${message}.\r\n`);
    await this.#reply(250);
  }

  /** After a send that failed, ready for the next. */
  async reset(): Promise<void> {
    await this.#command('RSET', 250);
  }

  async quit(): Promise<void> {
    try {
      await this.#command('QUIT', 221);
    } catch {
      // Sent already; nothing to lose.
    } finally {
      this.close();
    }
  }

  close(): void {
    try {
      this.#conn.close();
    } catch {
      // Closed already.
    }
  }

  async #command(line: string, ...ok: number[]): Promise<string> {
    await this.#write(`${line}\r\n`);
    return this.#reply(...ok);
  }

  /** A reply: 'NNN-...' lines, then 'NNN ...'. An error unless its code is one of [ok]. */
  async #reply(...ok: number[]): Promise<string> {
    const lines: string[] = [];
    while (true) {
      const line = await this.#line();
      lines.push(line);
      if (/^\d{3}(?: |$)/.test(line)) break;
    }
    const last = lines[lines.length - 1];
    const code = Number(last.slice(0, 3));
    if (!ok.includes(code)) throw new SmtpError(code, lines.join(' '));
    return lines.join('\n');
  }

  async #line(): Promise<string> {
    while (true) {
      const end = this.#buffer.indexOf('\r\n');
      if (end >= 0) {
        const line = this.#buffer.slice(0, end);
        this.#buffer = this.#buffer.slice(end + 2);
        return line;
      }
      const chunk = new Uint8Array(4096);
      const n = await this.#timed(this.#conn.read(chunk));
      if (n === null) throw new SmtpError(0, 'The mail server closed the connection');
      this.#buffer += decoder.decode(chunk.subarray(0, n), { stream: true });
    }
  }

  async #write(text: string): Promise<void> {
    const bytes = encoder.encode(text);
    let done = 0;
    while (done < bytes.length) done += await this.#timed(this.#conn.write(bytes.subarray(done)));
  }

  #timed<T>(work: Promise<T>): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const late = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new SmtpError(0, 'The mail server took too long to answer')), this.#timeoutMs);
    });
    return Promise.race([work, late]).finally(() => clearTimeout(timer));
  }
}

export interface Outgoing {
  id: string;
  mail: Email;
}

export interface Delivery {
  sent: string[];
  failed: { id: string; error: string }[];
}

/**
 * Sends [outgoing] over one session, opened when first needed. One that's
 * refused doesn't stop the rest; a connection that breaks is opened again,
 * once.
 */
export async function deliver(outgoing: Outgoing[], open: () => Promise<SmtpSession>): Promise<Delivery> {
  const result: Delivery = { sent: [], failed: [] };
  let session: SmtpSession | null = null;
  let reopened = false;
  for (const [i, { id, mail }] of outgoing.entries()) {
    try {
      session ??= await open();
    } catch (e) {
      // Can't reach or sign in to the server: the rest wait for the next try.
      const error = message(e);
      for (const rest of outgoing.slice(i)) result.failed.push({ id: rest.id, error });
      return result;
    }
    try {
      await session.send(mail);
      result.sent.push(id);
    } catch (e) {
      result.failed.push({ id, error: message(e) });
      try {
        await session.reset();
      } catch {
        session.close();
        session = null;
        if (reopened) {
          for (const rest of outgoing.slice(i + 1)) result.failed.push({ id: rest.id, error: 'The mail server stopped answering' });
          return result;
        }
        reopened = true;
      }
    }
  }
  await session?.quit();
  return result;
}

function message(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
