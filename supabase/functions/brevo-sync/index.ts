// Supabase Edge Function: sends new appointments and order requests to Brevo.
//
// Triggered by Database Webhooks on INSERT into public.appointments and
// public.order_requests. For each new row it:
//   1. adds or updates the customer as a Brevo contact (optionally in a list),
//   2. emails the customer a confirmation,
//   3. emails the shop owner a notification.
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   BREVO_API_KEY    Brevo API key (Brevo → SMTP & API → API keys). Never put it in the website.
//   WEBHOOK_SECRET   Any long random string. The webhook must send it in the x-webhook-secret header.
//   SENDER_EMAIL     A verified Brevo sender, e.g. hey@northstarai.online
//   SENDER_NAME      Name shown to customers, e.g. Trousseau Row
//   OWNER_EMAIL      Where new-booking and new-order alerts go
//   BREVO_LIST_ID    Optional. Numeric ID of the Brevo list to add customers to.

const BREVO = "https://api.brevo.com/v3";

type Row = Record<string, unknown>;
type Payload = { type: string; table: string; record: Row };

const env = (name: string, required = true) => {
  const v = Deno.env.get(name) ?? "";
  if (required && !v) throw new Error(`Missing secret ${name}`);
  return v;
};

const esc = (v: unknown) =>
  String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

const money = (n: unknown) => "$" + Number(n ?? 0).toLocaleString("en-US");

const fmtDate = (d: unknown) =>
  d ? new Date(`${d}T00:00:00Z`).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric", timeZone: "UTC" }) : "";

async function brevo(path: string, body: unknown) {
  const res = await fetch(`${BREVO}${path}`, {
    method: "POST",
    headers: { "api-key": env("BREVO_API_KEY"), "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Brevo ${path} failed (${res.status}): ${await res.text()}`);
}

function upsertContact(email: string, name: string) {
  const listId = Number(env("BREVO_LIST_ID", false));
  const [first, ...rest] = name.trim().split(/\s+/);
  return brevo("/contacts", {
    email,
    attributes: { FIRSTNAME: first ?? "", LASTNAME: rest.join(" ") },
    ...(listId ? { listIds: [listId] } : {}),
    updateEnabled: true,
  });
}

function sendEmail(to: string, toName: string, subject: string, html: string, replyTo?: string) {
  return brevo("/smtp/email", {
    sender: { email: env("SENDER_EMAIL"), name: env("SENDER_NAME", false) || "Trousseau Row" },
    to: [{ email: to, name: toName }],
    ...(replyTo ? { replyTo: { email: replyTo } } : {}),
    subject,
    htmlContent: `<div style="font-family:Georgia,serif;max-width:560px;margin:auto;color:#2A1B28;line-height:1.5">${html}</div>`,
  });
}

function detailsTable(rows: [string, string][]) {
  return `<table style="border-collapse:collapse;width:100%;font-family:Arial,sans-serif;font-size:14px">${rows
    .filter(([, v]) => v)
    .map(([k, v]) => `<tr><td style="padding:6px 12px 6px 0;color:#6C5D67;vertical-align:top">${esc(k)}</td><td style="padding:6px 0">${esc(v)}</td></tr>`)
    .join("")}</table>`;
}

async function handleAppointment(r: Row) {
  const name = String(r.name), email = String(r.email), first = name.split(" ")[0];
  const when = `${fmtDate(r.appointment_date)} at ${r.time_slot}`;
  const details = detailsTable([
    ["Appointment", String(r.meeting_type)],
    ["When", when],
    ["Venue", String(r.venue ?? "")],
    ["Budget", String(r.budget ?? "")],
    ["Silhouettes", (r.silhouettes as string[] | null)?.join(", ") ?? ""],
    ["Wedding date", fmtDate(r.wedding_date)],
    ["Saved pieces", (r.saved_pieces as string[] | null)?.join(", ") ?? ""],
  ]);

  await upsertContact(email, name);
  await sendEmail(email, name, "We've received your stylist appointment request",
    `<h1 style="font-weight:normal">Thank you, ${esc(first)}.</h1>
     <p>We've received your request for <b>${esc(r.meeting_type)}</b> on <b>${esc(when)}</b>.
     A stylist will email you to confirm the time.</p>${details}`);
  await sendEmail(env("OWNER_EMAIL"), "Trousseau Row", `New appointment request: ${name}, ${when}`,
    `<h2>New appointment request</h2><p>${esc(name)} &lt;${esc(email)}&gt;</p>${details}`, email);
}

async function handleOrder(r: Row) {
  const name = String(r.name), email = String(r.email), first = name.split(" ")[0];
  const items = (r.items as Row[] | null) ?? [];
  const lines = items.map((i) => i.type === "swatch"
    ? `<li>Swatch: ${esc(i.name)} (${esc(i.colour)})</li>`
    : `<li><b>${esc(i.name)}</b> by ${esc(i.designer)}, ${esc(i.colour)}, ${esc(i.size)}${i.rush ? ", rush" : ""}: ${money(i.total_usd)}</li>`).join("");
  const summary = `<ul style="font-family:Arial,sans-serif;font-size:14px">${lines}</ul>` + detailsTable([
    ["Pieces subtotal", money(r.subtotal_usd)],
    ["Due now", money(r.due_now_usd)],
    ["Wedding date", fmtDate(r.wedding_date)],
  ]);

  await upsertContact(email, name);
  await sendEmail(email, name, "We've received your order request",
    `<h1 style="font-weight:normal">Thank you, ${esc(first)}.</h1>
     <p>A stylist will check the details and send you an invoice for <b>${money(r.due_now_usd)}</b>.
     Nothing has been charged yet.</p>${summary}`);
  await sendEmail(env("OWNER_EMAIL"), "Trousseau Row", `New order request: ${name}, ${money(r.due_now_usd)} due`,
    `<h2>New order request</h2><p>${esc(name)} &lt;${esc(email)}&gt;</p>${summary}`, email);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  // Only the database webhook knows this secret, so nobody else can trigger emails.
  if (req.headers.get("x-webhook-secret") !== env("WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }
  if (payload.type !== "INSERT" || !payload.record) return new Response("Ignored", { status: 200 });

  try {
    if (payload.table === "appointments") await handleAppointment(payload.record);
    else if (payload.table === "order_requests") await handleOrder(payload.record);
    else return new Response("Ignored table", { status: 200 });
    return new Response("OK", { status: 200 });
  } catch (e) {
    console.error(e);
    return new Response(String((e as Error).message), { status: 500 });
  }
});
