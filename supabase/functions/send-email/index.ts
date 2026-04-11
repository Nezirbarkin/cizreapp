// Email Gönderme Edge Function
// Bu dosyayı Supabase Dashboard -> Edge Functions'da deploy edin

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { Resend } from "npm:resend@2.0.0";

const resend = new Resend(Deno.env.get("RESEND_API_KEY"));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface EmailRequest {
  type: "order_delivered" | "order_confirmed";
  to: string;
  data: {
    customerName: string;
    orderNumber: string;
    shopName: string;
    totalAmount: string;
    deliveredAt?: string;
    deliveryAddress?: string;
  };
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const body: EmailRequest = await req.json();
    const { type, to, data } = body;

    let subject: string;
    let html: string;

    if (type === "order_delivered") {
      subject = `Siparişiniz Teslim Edildi - #${data.orderNumber}`;
      html = `
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px; }
            .container { background: white; max-width: 600px; margin: 0 auto; padding: 30px; border-radius: 10px; }
            .header { text-align: center; padding-bottom: 20px; border-bottom: 2px solid #4CAF50; }
            .header h1 { color: #4CAF50; margin: 0; }
            .content { padding: 20px 0; }
            .order-box { background: #f9f9f9; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .footer { text-align: center; color: #888; font-size: 12px; margin-top: 20px; }
            .emoji { font-size: 48px; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <div class="emoji">🎉</div>
              <h1>Siparişiniz Teslim Edildi!</h1>
            </div>
            <div class="content">
              <p>Merhaba <strong>${data.customerName}</strong>,</p>
              <p>Siparişiniz başarıyla teslim edildi. Afiyet olsun!</p>
              
              <div class="order-box">
                <p><strong>Sipariş No:</strong> #${data.orderNumber}</p>
                <p><strong>Dükkan:</strong> ${data.shopName}</p>
                <p><strong>Toplam:</strong> ₺${data.totalAmount}</p>
                <p><strong>Teslim Tarihi:</strong> ${new Date(data.deliveredAt || "").toLocaleString("tr-TR")}</p>
              </div>
              
              <p>Bizi tercih ettiğiniz için teşekkür ederiz! 🙏</p>
              <p>Tekrar görüşmek üzere,<br><strong>Cizre App Ekibi</strong></p>
            </div>
            <div class="footer">
              <p>Bu email otomatik olarak gönderilmiştir. Lütfen yanıtlamayınız.</p>
            </div>
          </div>
        </body>
        </html>
      `;
    } else if (type === "order_confirmed") {
      subject = `Siparişiniz Alındı - #${data.orderNumber}`;
      html = `
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px; }
            .container { background: white; max-width: 600px; margin: 0 auto; padding: 30px; border-radius: 10px; }
            .header { text-align: center; padding-bottom: 20px; border-bottom: 2px solid #FF9800; }
            .header h1 { color: #FF9800; margin: 0; }
            .content { padding: 20px 0; }
            .order-box { background: #f9f9f9; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .footer { text-align: center; color: #888; font-size: 12px; margin-top: 20px; }
            .emoji { font-size: 48px; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <div class="emoji">📦</div>
              <h1>Siparişiniz Alındı!</h1>
            </div>
            <div class="content">
              <p>Merhaba <strong>${data.customerName}</strong>,</p>
              <p>Siparişiniz başarıyla alındı ve hazırlanmaya başlandı.</p>
              
              <div class="order-box">
                <p><strong>Sipariş No:</strong> #${data.orderNumber}</p>
                <p><strong>Dükkan:</strong> ${data.shopName}</p>
                <p><strong>Toplam:</strong> ₺${data.totalAmount}</p>
                <p><strong>Teslimat Adresi:</strong> ${data.deliveryAddress || "-"}</p>
              </div>
              
              <p>Siparişinizi uygulama üzerinden takip edebilirsiniz.</p>
              <p>Teşekkürler,<br><strong>Cizre App Ekibi</strong></p>
            </div>
            <div class="footer">
              <p>Bu email otomatik olarak gönderilmiştir. Lütfen yanıtlamayınız.</p>
            </div>
          </div>
        </body>
        </html>
      `;
    } else {
      throw new Error("Geçersiz email tipi");
    }

    const result = await resend.emails.send({
      from: "CizreApp <noreply@cizreapp.com>",
      to: [to],
      subject: subject,
      html: html,
    });

    console.log("Email gönderildi:", result);

    return new Response(JSON.stringify({ success: true, id: result.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("Email gönderme hatası:", error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
