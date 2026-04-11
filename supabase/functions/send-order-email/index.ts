// Sipariş Bildirimi Edge Function
// Bu function yeni sipariş geldiğinde admin ve satıcıya e-posta gönderir.
// E-posta servisi olarak Resend kullanılmaktadır (ücretsiz 3000 email/ay)
// İki modda çalışır:
// 1. Trigger modu: pg_net trigger'ından gelen istekler (order_id, shop_id, total, order_number)
// 2. Direct modu: Dart tarafından gönderilen istekler (type, to, data)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface TriggerRequest {
  order_id: string;
  shop_id: string;
  total: number;
  order_number: string;
  customer_name?: string;
  delivery_address?: string;
}

interface DirectRequest {
  type: string;
  to: string;
  data: {
    orderId: string;
    orderNumber: string;
    shopName: string;
    customerName: string;
    deliveryAddress: string;
    totalAmount: string;
    orderItems: string[];
  };
}

// Resend API ile e-posta gönder
async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY environment variable is not set");
    return false;
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "CizreApp <noreply@cizreapp.com>",
        to: to,
        subject: subject,
        html: html,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error("Resend API error:", error);
      return false;
    }

    console.log(`✅ Email sent successfully to ${to}`);
    return true;
  } catch (error) {
    console.error("Email sending error:", error);
    return false;
  }
}

// Sipariş bildirimi e-posta içeriği oluştur
function createOrderEmailHtml(
  recipientType: "admin" | "seller",
  orderNumber: string,
  shopName: string,
  total: string,
  customerName: string,
  deliveryAddress: string,
  orderItems: string[]
): string {
  const title = recipientType === "admin" 
    ? "🛒 Yeni Sipariş Alındı!" 
    : "🎉 Yeni Sipariş Geldi!";
  
  const subtitle = recipientType === "admin"
    ? `${shopName} dükkanına yeni bir sipariş geldi.`
    : "Mağazanıza yeni bir sipariş geldi!";

  const itemsHtml = orderItems.length > 0 
    ? orderItems.map(item => `<li style="padding: 5px 0;">${item}</li>`).join("")
    : "<li>Ürün detayları mevcut değil</li>";

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>${title}</title>
    </head>
    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
      <div style="background: linear-gradient(135deg, #D91A73 0%, #FF6B9D 100%); padding: 30px; border-radius: 10px 10px 0 0;">
        <h1 style="color: white; margin: 0; text-align: center;">${title}</h1>
        <p style="color: rgba(255,255,255,0.9); text-align: center; margin: 10px 0 0;">${subtitle}</p>
      </div>
      
      <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; border: 1px solid #eee; border-top: none;">
        <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
          <h2 style="color: #D91A73; margin-top: 0;">📦 Sipariş Detayları</h2>
          
          <table style="width: 100%; border-collapse: collapse;">
            <tr>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;"><strong>Sipariş No:</strong></td>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;">#${orderNumber}</td>
            </tr>
            <tr>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;"><strong>Dükkan:</strong></td>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;">${shopName}</td>
            </tr>
            <tr>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;"><strong>Müşteri:</strong></td>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;">${customerName}</td>
            </tr>
            <tr>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;"><strong>Teslimat Adresi:</strong></td>
              <td style="padding: 10px 0; border-bottom: 1px solid #eee;">${deliveryAddress}</td>
            </tr>
          </table>
        </div>

        <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
          <h3 style="color: #333; margin-top: 0;">🛍️ Ürünler</h3>
          <ul style="padding-left: 20px; margin: 0;">
            ${itemsHtml}
          </ul>
        </div>

        <div style="background: #D91A73; color: white; padding: 20px; border-radius: 8px; text-align: center;">
          <h2 style="margin: 0;">Toplam: ₺${total}</h2>
        </div>

        <p style="text-align: center; color: #666; margin-top: 20px; font-size: 14px;">
          Bu e-posta otomatik olarak gönderilmiştir.<br>
          Lütfen siparişi en kısa sürede hazırlayın.
        </p>
      </div>

      <div style="text-align: center; margin-top: 20px; color: #999; font-size: 12px;">
        © ${new Date().getFullYear()} CizreApp. Tüm hakları saklıdır.
      </div>
    </body>
    </html>
  `;
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();

    // Mod 2: Dart tarafından doğrudan çağrılan mod (type, to, data)
    if (body.type && body.to && body.data) {
      const directReq = body as DirectRequest;
      console.log(`📧 Direct mode - Processing ${directReq.type} email to ${directReq.to}`);
      
      const { orderId, orderNumber, shopName, customerName, deliveryAddress, totalAmount, orderItems } = directReq.data;
      
      const recipientType = directReq.type === 'new_order_admin' ? 'admin' : 'seller';
      
      const html = createOrderEmailHtml(
        recipientType,
        orderNumber || orderId || 'N/A',
        shopName || 'Mağaza',
        totalAmount || '0.00',
        customerName || 'Müşteri',
        deliveryAddress || 'Adres belirtilmemiş',
        orderItems || []
      );
      
      const subject = recipientType === 'admin' 
        ? `🛒 Yeni Sipariş: ${shopName} - #${orderNumber}`
        : `🎉 Yeni Sipariş: #${orderNumber}`;
      
      const success = await sendEmail(directReq.to, subject, html);
      
      return new Response(
        JSON.stringify({ 
          success, 
          message: success ? "Email sent successfully" : "Email sending failed",
          mode: "direct",
          type: directReq.type,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: success ? 200 : 500,
        }
      );
    }

    // Mod 1: Trigger modu (pg_net'ten gelen - order_id, shop_id, total, order_number)
    const { order_id, shop_id, total, order_number, customer_name, delivery_address, order_items: triggerItems } = body as TriggerRequest & { order_items?: any[] };
    
    console.log(`📧 Trigger mode - Processing order email for order: ${order_id}`);

    // Supabase client oluştur
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Dükkan bilgilerini al (sahip email'i dahil)
    const { data: shop, error: shopError } = await supabase
      .from("shops")
      .select(`
        id,
        name,
        owner_id,
        profiles!shops_owner_id_fkey(email, full_name)
      `)
      .eq("id", shop_id)
      .single();

    if (shopError) {
      console.error("Shop fetch error:", shopError);
      throw new Error(`Shop not found: ${shopError.message}`);
    }

    // Sipariş ürünlerini al - trigger'dan gelen varsa kullan, yoksa veritabanından çek
    let itemsList: string[] = [];
    
    if (triggerItems && Array.isArray(triggerItems) && triggerItems.length > 0) {
      // Trigger'dan gelen ürünleri kullan
      console.log(`📦 Using ${triggerItems.length} items from trigger`);
      itemsList = triggerItems.map((item: any) => {
        const name = item.product_name || 'Ürün';
        const qty = item.quantity || 1;
        const price = item.price || 0;
        return `${name} x${qty} - ₺${(price * qty).toFixed(2)}`;
      });
    } else {
      // Trigger'dan gelmediyse veritabanından çek
      console.log('📦 Fetching items from database');
      const { data: orderItems, error: itemsError } = await supabase
        .from("order_items")
        .select("product_name, quantity, price")
        .eq("order_id", order_id);

      if (itemsError) {
        console.error("Order items fetch error:", itemsError);
      }

      itemsList = orderItems?.map(item =>
        `${item.product_name} x${item.quantity} - ₺${(item.price * item.quantity).toFixed(2)}`
      ) || [];
    }

    // Admin e-postalarını al (role = 'admin' olanlar)
    const { data: admins, error: adminError } = await supabase
      .from("profiles")
      .select("email")
      .eq("role", "admin");

    if (adminError) {
      console.error("Admin fetch error:", adminError);
    }

    const shopName = shop?.name || "Bilinmeyen Dükkan";
    const sellerEmail = (shop?.profiles as any)?.email;
    const finalCustomerName = customer_name || "Müşteri";
    const finalAddress = delivery_address || "Adres belirtilmemiş";
    const totalStr = typeof total === 'number' ? total.toFixed(2) : String(total || '0.00');

    // Satıcıya e-posta gönder
    if (sellerEmail) {
      const sellerHtml = createOrderEmailHtml(
        "seller",
        order_number,
        shopName,
        totalStr,
        finalCustomerName,
        finalAddress,
        itemsList
      );
      await sendEmail(sellerEmail, `🎉 Yeni Sipariş: #${order_number}`, sellerHtml);
    } else {
      console.log("⚠️ Seller email not found");
    }

    // Admin'lere e-posta gönder
    if (admins && admins.length > 0) {
      for (const admin of admins) {
        if (admin.email) {
          const adminHtml = createOrderEmailHtml(
            "admin",
            order_number,
            shopName,
            totalStr,
            finalCustomerName,
            finalAddress,
            itemsList
          );
          await sendEmail(admin.email, `🛒 Yeni Sipariş: ${shopName} - #${order_number}`, adminHtml);
        }
      }
    } else {
      console.log("⚠️ No admin emails found");
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: "Order notification emails sent",
        mode: "trigger",
        seller_notified: !!sellerEmail,
        admins_notified: admins?.length || 0
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
