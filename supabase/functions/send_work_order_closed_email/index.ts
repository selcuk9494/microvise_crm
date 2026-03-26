type Payload = {
  to: string;
  customerName: string;
  workOrderTitle: string;
  signatureDataUrl: string;
};

declare const Deno: {
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
  env: { get: (key: string) => string | undefined };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(
        JSON.stringify({ error: "RESEND_API_KEY is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as Partial<Payload>;
    const to = body.to?.trim();
    if (!to) {
      return new Response(JSON.stringify({ error: "to is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const customerName = body.customerName ?? "";
    const workOrderTitle = body.workOrderTitle ?? "";
    const signatureDataUrl = body.signatureDataUrl ?? "";

    const html = `
      <div style="font-family: Inter, -apple-system, Segoe UI, Roboto, Arial, sans-serif; line-height:1.45; color:#0f172a;">
        <h2 style="margin:0 0 8px 0;">İş Emri Kapanış</h2>
        <p style="margin:0 0 12px 0; color:#475569;">
          Sayın ${escapeHtml(customerName)}, iş emriniz tamamlanmıştır.
        </p>
        <div style="padding:12px 14px; border:1px solid #e5e7eb; border-radius:12px; background:#f8fafc; margin:0 0 14px 0;">
          <div style="font-weight:600; margin:0 0 4px 0;">İş Emri</div>
          <div style="color:#334155;">${escapeHtml(workOrderTitle)}</div>
        </div>
        <div style="font-weight:600; margin:0 0 6px 0;">İmza</div>
        <div style="border:1px solid #e5e7eb; border-radius:12px; overflow:hidden; background:#fff; padding:10px;">
          <img alt="İmza" src="${signatureDataUrl}" style="max-width:100%; height:auto; display:block;" />
        </div>
        <p style="margin:14px 0 0 0; color:#64748b; font-size:12px;">
          Bu e-posta Microvise CRM üzerinden otomatik gönderilmiştir.
        </p>
      </div>
    `;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Microvise CRM <noreply@microvise.net>",
        to: [to],
        subject: "İş Emri Tamamlandı",
        html,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      return new Response(JSON.stringify({ error: data }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: true, data }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function escapeHtml(input: string): string {
  return input
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
