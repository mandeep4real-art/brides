// Supabase Edge Function: receives the website's marketing lead form and
// creates a record in the Airtable "bridal info" base. The Make.com scenario
// "Integration Airtable" watches that table and runs on each new record.
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   AIRTABLE_TOKEN     Airtable personal access token with data.records:write on the base.
//                      Never put it in the website.
//   AIRTABLE_BASE_ID   Optional. Defaults to the base in the Make blueprint.
//   AIRTABLE_TABLE_ID  Optional. Defaults to the table in the Make blueprint.

const BASE_ID = Deno.env.get("AIRTABLE_BASE_ID") || "appfNxodjelb3C9ku";
const TABLE_ID = Deno.env.get("AIRTABLE_TABLE_ID") || "tbln3B7vu8ZrZmSky";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

// Best-effort protection against repeat submissions, per function instance.
const recent = new Map<string, number>();
const REPEAT_WINDOW_MS = 10 * 60 * 1000;

const clean = (v: unknown, max: number) => String(v ?? "").trim().slice(0, max);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid request." });
  }

  // Honeypot: real visitors never see or fill the "company" field.
  if (clean(body.company, 200)) return json(200, { ok: true });

  const name = clean(body.name, 120);
  const phone = clean(body.phone, 20).replace(/[\s()-]/g, "");
  const email = clean(body.email, 254);
  const weddingDate = clean(body.weddingDate, 10);
  const interest = clean(body.interest, 60);
  const message = clean(body.message, 1000);

  if (!name) return json(400, { error: "Add your name." });
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    return json(400, { error: "Add your mobile number with the country code, for example +91 98765 43210." });
  }
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(400, { error: "Check your email address." });
  if (weddingDate && !/^\d{4}-\d{2}-\d{2}$/.test(weddingDate)) return json(400, { error: "Check your wedding date." });
  if (body.consent !== true) return json(400, { error: "Tick the box to agree to a call and emails." });

  const now = Date.now();
  for (const [k, t] of recent) if (now - t > REPEAT_WINDOW_MS) recent.delete(k);
  if (recent.has(phone)) return json(200, { ok: true });
  recent.set(phone, now);

  const token = Deno.env.get("AIRTABLE_TOKEN");
  if (!token) {
    console.error("Missing secret AIRTABLE_TOKEN");
    return json(500, { error: "We couldn't save your details. Please try again later." });
  }

  const notes = [
    email && `Email: ${email}`,
    weddingDate && `Wedding date: ${weddingDate}`,
    interest && `Looking for: ${interest}`,
    message && `Message: ${message}`,
    `Consent to calls and emails: yes (${new Date(now).toISOString()})`,
    "Source: website lead form",
  ].filter(Boolean).join("\n");

  const res = await fetch(`https://api.airtable.com/v0/${BASE_ID}/${TABLE_ID}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ records: [{ fields: { Name: name, "mobile number": phone, Notes: notes } }], typecast: true }),
  });

  if (!res.ok) {
    recent.delete(phone);
    console.error(`Airtable error ${res.status}: ${await res.text()}`);
    return json(502, { error: "We couldn't save your details. Please try again in a moment." });
  }
  return json(200, { ok: true });
});
