// =====================================================
// AI CHAT PROXY - ÇOKLU SAĞLAYICI EDGE FUNCTION
// =====================================================
// Akıllı routing (göreve özel varsayılan sağlayıcı):
//   - text:    textProvider    -> pollinations -> gemini -> groq -> openrouter -> openai
//   - vision:  visionProvider  -> pollinations -> gemini -> openrouter -> openai
//   - image:   imageProvider   -> pollinations -> gemini (imagen) -> openrouter -> openai
//
// Pollinations.ai: ücretsiz, API anahtarı gerektirmez
// HuggingFace:    ücretsiz inference (anahtar opsiyonel)
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// API anahtarı getter'ları - veritabanı veya environment'dan okur
function getApiKeys() {
  return {
    gemini: (globalThis as any).geminiApiKey || Deno.env.get("GEMINI_API_KEY"),
    groq: (globalThis as any).groqApiKey || Deno.env.get("GROQ_API_KEY"),
    openrouter: (globalThis as any).openrouterApiKey || Deno.env.get("OPENROUTER_API_KEY"),
    openai: (globalThis as any).openaiApiKey || Deno.env.get("OPENAI_API_KEY"),
    huggingface: (globalThis as any).huggingfaceApiKey || Deno.env.get("HUGGINGFACE_API_KEY"),
  };
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface RequestBody {
  conversation_id?: string;
  message: string;
  attachments?: Array<{ storage_path: string; mime_type: string }>;
  action: "text" | "vision" | "image_generation";
  image_prompt?: string; // sadece image_generation için
}

// =====================================================
// SAĞLAYICI ROUTING
// =====================================================

interface ChatResponse {
  content: string;
  provider: string;
  model: string;
  tokens: number;
  generatedImages?: Array<{ storage_path: string; url: string }>;
}

interface ProviderSettings {
  systemPrompt: string;
  temperature: number;
  maxOutputTokens: number;
  // text sağlayıcı için varsayılan
  textProvider: string;
  visionProvider: string;
  imageProvider: string;
  // modeller
  gemini: { text: string; vision: string; image: string };
  groq: { text: string; vision: string };
  openrouter: { text: string; vision: string; image: string };
  openai: { text: string; vision: string; image: string };
  pollinations: { text: string; image: string };
  huggingface: { text: string };
  // API anahtarları
  geminiApiKey?: string;
  groqApiKey?: string;
  openrouterApiKey?: string;
  openaiApiKey?: string;
  huggingfaceApiKey?: string;
}

async function loadSettings(): Promise<ProviderSettings> {
  const { data, error } = await supabase
    .from("ai_settings")
    .select("*")
    .eq("id", 1)
    .single();

  if (error || !data) {
    throw new Error("AI ayarları yüklenemedi");
  }

  if (!data.enabled) {
    throw new Error("AI özelliği devre dışı");
  }

  // API anahtarlarını veritabanından veya environment'dan al
  const keys = getApiKeys();
  const geminiApiKey = data.gemini_api_key || keys.gemini;
  const groqApiKey = data.groq_api_key || keys.groq;
  const openrouterApiKey = data.openrouter_api_key || keys.openrouter;
  const openaiApiKey = data.openai_api_key || keys.openai;
  const huggingfaceApiKey = data.huggingface_api_key || keys.huggingface;

  // Global değişkenlere ata (sağlayıcı fonksiyonları için)
  (globalThis as any).geminiApiKey = geminiApiKey;
  (globalThis as any).groqApiKey = groqApiKey;
  (globalThis as any).openrouterApiKey = openrouterApiKey;
  (globalThis as any).openaiApiKey = openaiApiKey;
  (globalThis as any).huggingfaceApiKey = huggingfaceApiKey;

  // Göreve özel provider (geriye dönük: eski "provider" kolonuna fallback)
  const fallbackProvider = (data.provider as string) || "pollinations";

  return {
    systemPrompt:
      data.system_prompt ||
      "Sen CizreApp kullanıcılarına yardımcı olan bir Türkçe yapay zeka asistanısın.",
    temperature: parseFloat(data.temperature) || 0.7,
    maxOutputTokens: data.max_output_tokens || 2048,
    textProvider: (data.text_provider as string) || fallbackProvider,
    visionProvider: (data.vision_provider as string) || fallbackProvider,
    imageProvider: (data.image_provider as string) || fallbackProvider,
    gemini: {
      text: data.text_model,
      vision: data.vision_model,
      image: data.image_model,
    },
    groq: {
      text: data.groq_text_model || "llama-3.3-70b-versatile",
      vision: data.groq_vision_model || "llama-3.2-90b-vision-preview",
    },
    openrouter: {
      text: data.openrouter_text_model || "google/gemini-2.0-flash-exp:free",
      vision: data.openrouter_vision_model || "google/gemini-2.0-flash-exp:free",
      image: data.openrouter_image_model || "stable-diffusion-xl",
    },
    openai: {
      text: data.openai_text_model || "gpt-4o-mini",
      vision: data.openai_vision_model || "gpt-4o-mini",
      image: data.openai_image_model || "dall-e-3",
    },
    pollinations: {
      text: data.pollinations_text_model || "openai",
      image: data.pollinations_image_model || "flux",
    },
    huggingface: {
      text: data.huggingface_text_model || "meta-llama/Llama-3.2-3B-Instruct",
    },
    // API anahtarları
    geminiApiKey,
    groqApiKey,
    openrouterApiKey,
    openaiApiKey,
    huggingfaceApiKey,
  };
}

// =====================================================
// YARDIMCI: Hata sınıfı
// =====================================================

class ProviderError extends Error {
  constructor(public provider: string, message: string) {
    super(message);
    this.name = "ProviderError";
  }
}

// =====================================================
// POLLINATIONS (text + image - ücretsiz, anahtarsız)
// =====================================================
// Text:  POST https://text.pollinations.ai/openai  (OpenAI uyumlu)
// Image: GET  https://image.pollinations.ai/prompt/{prompt}  -> binary

async function callPollinationsText(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = []
): Promise<ChatResponse> {
  const isVision = attachments.length > 0;
  const model = settings.pollinations.text;
  // Pollinations: vision destekleyen modelleri öncelikli dene
  const url = "https://text.pollinations.ai/openai";

  const messages: any[] = [{ role: "system", content: settings.systemPrompt }];
  for (const msg of history) {
    messages.push({ role: msg.role, content: msg.content });
  }

  if (isVision) {
    const contentParts: any[] = [{ type: "text", text: message }];
    for (const att of attachments) {
      contentParts.push({
        type: "image_url",
        image_url: { url: `data:${att.mime_type};base64,${att.base64}` },
      });
    }
    messages.push({ role: "user", content: contentParts });
  } else {
    messages.push({ role: "user", content: message });
  }

  const body = {
    model,
    messages,
    temperature: settings.temperature,
    max_tokens: settings.maxOutputTokens,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("pollinations", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content || "";
  const tokens = data.usage?.total_tokens || 0;

  return { content: text, provider: "pollinations", model, tokens };
}

async function callPollinationsImage(
  settings: ProviderSettings,
  prompt: string
): Promise<ChatResponse> {
  const model = settings.pollinations.image || "flux";
  // image.pollinations.ai/{model}/{prompt} (yeni format) veya ?model= (eski)
  const safePrompt = encodeURIComponent(prompt);
  const url = `https://image.pollinations.ai/prompt/${safePrompt}?model=${model}&width=1024&height=1024&nologo=true&enhance=true`;

  const res = await fetch(url, { method: "GET" });

  if (!res.ok) {
    throw new ProviderError("pollinations", `Image HTTP ${res.status}`);
  }

  const arrayBuffer = await res.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  if (!bytes || bytes.length < 100) {
    throw new ProviderError("pollinations", "Image data boş/küçük");
  }

  const fileName = `${Date.now()}_gen.png`;
  const path = `anon/${fileName}`;

  const { error: uploadError } = await supabase.storage
    .from("ai-generated")
    .upload(path, bytes, { contentType: "image/png", upsert: false });

  if (uploadError) {
    throw new ProviderError("pollinations", "Storage yükleme hatası");
  }

  return {
    content: "İşte oluşturduğum görsel:",
    provider: "pollinations",
    model,
    tokens: 0,
    generatedImages: [{ storage_path: `ai-generated/${path}`, url: "" }],
  };
}

// =====================================================
// HUGGINGFACE INFERENCE API (ücretsiz text)
// =====================================================

async function callHuggingFaceText(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>
): Promise<ChatResponse> {
  const model = settings.huggingface.text;
  // HF router üzeriden OpenAI uyumlu chat completions (yeni)
  const url = "https://router.huggingface.co/v1/chat/completions";

  const messages: any[] = [{ role: "system", content: settings.systemPrompt }];
  for (const msg of history) {
    messages.push({ role: msg.role, content: msg.content });
  }
  messages.push({ role: "user", content: message });

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (settings.huggingfaceApiKey) {
    headers["Authorization"] = `Bearer ${settings.huggingfaceApiKey}`;
  }

  const body = {
    model,
    messages,
    temperature: settings.temperature,
    max_tokens: settings.maxOutputTokens,
    stream: false,
  };

  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("huggingface", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content || "";
  const tokens = data.usage?.total_tokens || 0;

  return { content: text, provider: "huggingface", model, tokens };
}

// =====================================================
// GEMINI (text + vision + image)
// =====================================================

async function callGemini(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = []
): Promise<ChatResponse> {
  const keys = getApiKeys();
  if (!keys.gemini) throw new ProviderError("gemini", "API key yok");

  const isVision = attachments.length > 0;
  const model = isVision ? settings.gemini.vision : settings.gemini.text;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${keys.gemini}`;

  // Mesaj geçmişini Gemini formatına dönüştür
  const contents: any[] = [];

  // System instruction
  const systemInstruction = {
    parts: [{ text: settings.systemPrompt }],
  };

  // Geçmiş mesajları ekle
  for (const msg of history) {
    contents.push({
      role: msg.role === "assistant" ? "model" : "user",
      parts: [{ text: msg.content }],
    });
  }

  // Mevcut mesaj
  const currentParts: any[] = [];
  if (isVision) {
    for (const att of attachments) {
      currentParts.push({
        inline_data: {
          mime_type: att.mime_type,
          data: att.base64,
        },
      });
    }
  }
  currentParts.push({ text: message });
  contents.push({ role: "user", parts: currentParts });

  const body = {
    system_instruction: systemInstruction,
    contents,
    generationConfig: {
      temperature: settings.temperature,
      maxOutputTokens: settings.maxOutputTokens,
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("gemini", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || "";
  const tokens = data.usageMetadata?.totalTokenCount || 0;

  return { content: text, provider: "gemini", model, tokens };
}

async function callGeminiImage(
  settings: ProviderSettings,
  prompt: string
): Promise<ChatResponse> {
  const keys = getApiKeys();
  if (!keys.gemini) throw new ProviderError("gemini", "API key yok");

  const model = settings.gemini.image;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:predict?key=${keys.gemini}`;

  const body = {
    instances: [{ prompt }],
    parameters: {
      sampleCount: 1,
      aspectRatio: "1:1",
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    throw new ProviderError("gemini", `Image HTTP ${res.status}`);
  }

  const data = await res.json();
  const b64 = data.predictions?.[0]?.bytesBase64Encoded;

  if (!b64) throw new ProviderError("gemini", "Image data yok");

  // Storage'a yükle
  const userId = "anon";
  const fileName = `${Date.now()}_gen.png`;
  const path = `${userId}/${fileName}`;

  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const { error: uploadError } = await supabase.storage
    .from("ai-generated")
    .upload(path, bytes, { contentType: "image/png", upsert: false });

  if (uploadError) throw new ProviderError("gemini", "Storage yükleme hatası");

  return {
    content: "İşte oluşturduğum görsel:",
    provider: "gemini",
    model,
    tokens: 0,
    generatedImages: [{ storage_path: `ai-generated/${path}`, url: "" }],
  };
}

// =====================================================
// GROQ (text + vision, hızlı fallback)
// =====================================================

async function callGroq(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = []
): Promise<ChatResponse> {
  const keys = getApiKeys();
  const groqApiKey = settings.groqApiKey || (globalThis as any).groqApiKey || keys.groq;
  if (!groqApiKey) throw new ProviderError("groq", "API key yok");

  const isVision = attachments.length > 0;
  const model = isVision ? settings.groq.vision : settings.groq.text;
  const url = "https://api.groq.com/openai/v1/chat/completions";

  const messages: any[] = [{ role: "system", content: settings.systemPrompt }];
  for (const msg of history) {
    messages.push({ role: msg.role, content: msg.content });
  }

  if (isVision) {
    const contentParts: any[] = [{ type: "text", text: message }];
    for (const att of attachments) {
      contentParts.push({
        type: "image_url",
        image_url: { url: `data:${att.mime_type};base64,${att.base64}` },
      });
    }
    messages.push({ role: "user", content: contentParts });
  } else {
    messages.push({ role: "user", content: message });
  }

  const body = {
    model,
    messages,
    temperature: settings.temperature,
    max_tokens: settings.maxOutputTokens,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${groqApiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("groq", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content || "";
  const tokens = data.usage?.total_tokens || 0;

  return { content: text, provider: "groq", model, tokens };
}

// =====================================================
// OPENROUTER (çok yönlü yedek)
// =====================================================

async function callOpenRouter(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = []
): Promise<ChatResponse> {
  const keys = getApiKeys();
  if (!keys.openrouter) throw new ProviderError("openrouter", "API key yok");

  const isVision = attachments.length > 0;
  const model = isVision ? settings.openrouter.vision : settings.openrouter.text;
  const url = "https://openrouter.ai/api/v1/chat/completions";

  const messages: any[] = [{ role: "system", content: settings.systemPrompt }];
  for (const msg of history) {
    messages.push({ role: msg.role, content: msg.content });
  }

  if (isVision) {
    const contentParts: any[] = [{ type: "text", text: message }];
    for (const att of attachments) {
      contentParts.push({
        type: "image_url",
        image_url: { url: `data:${att.mime_type};base64,${att.base64}` },
      });
    }
    messages.push({ role: "user", content: contentParts });
  } else {
    messages.push({ role: "user", content: message });
  }

  const body = {
    model,
    messages,
    temperature: settings.temperature,
    max_tokens: settings.maxOutputTokens,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${keys.openrouter}`,
      "HTTP-Referer": SUPABASE_URL,
      "X-Title": "CizreApp",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("openrouter", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content || "";
  const tokens = data.usage?.total_tokens || 0;

  return { content: text, provider: "openrouter", model, tokens };
}

async function callOpenRouterImage(
  settings: ProviderSettings,
  prompt: string
): Promise<ChatResponse> {
  const keys = getApiKeys();
  if (!keys.openrouter) throw new ProviderError("openrouter", "API key yok");

  const model = settings.openrouter.image;
  const url = "https://openrouter.ai/api/v1/images/generations";

  const body = { model, prompt, n: 1, size: "1024x1024" };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${keys.openrouter}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    throw new ProviderError("openrouter", `Image HTTP ${res.status}`);
  }

  const data = await res.json();
  const imageUrl = data.data?.[0]?.url;
  if (!imageUrl) throw new ProviderError("openrouter", "Image URL yok");

  const imgRes = await fetch(imageUrl);
  const bytes = new Uint8Array(await imgRes.arrayBuffer());
  const path = `anon/${Date.now()}_gen.png`;

  await supabase.storage
    .from("ai-generated")
    .upload(path, bytes, { contentType: "image/png", upsert: false });

  return {
    content: "İşte oluşturduğum görsel:",
    provider: "openrouter",
    model,
    tokens: 0,
    generatedImages: [{ storage_path: `ai-generated/${path}`, url: imageUrl }],
  };
}

// =====================================================
// OPENAI (son çare, ücretli)
// =====================================================

async function callOpenAI(
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = []
): Promise<ChatResponse> {
  const keys = getApiKeys();
  if (!keys.openai) throw new ProviderError("openai", "API key yok");

  const isVision = attachments.length > 0;
  const model = isVision ? settings.openai.vision : settings.openai.text;
  const url = "https://api.openai.com/v1/chat/completions";

  const messages: any[] = [{ role: "system", content: settings.systemPrompt }];
  for (const msg of history) {
    messages.push({ role: msg.role, content: msg.content });
  }

  if (isVision) {
    const contentParts: any[] = [{ type: "text", text: message }];
    for (const att of attachments) {
      contentParts.push({
        type: "image_url",
        image_url: { url: `data:${att.mime_type};base64,${att.base64}` },
      });
    }
    messages.push({ role: "user", content: contentParts });
  } else {
    messages.push({ role: "user", content: message });
  }

  const body = {
    model,
    messages,
    temperature: settings.temperature,
    max_tokens: settings.maxOutputTokens,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${keys.openai}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new ProviderError("openai", `HTTP ${res.status}: ${errText.substring(0, 200)}`);
  }

  const data = await res.json();
  const text = data.choices?.[0]?.message?.content || "";
  const tokens = data.usage?.total_tokens || 0;

  return { content: text, provider: "openai", model, tokens };
}

// =====================================================
// FALLBACK ROUTING (göreve özel varsayılan + zincir)
// =====================================================

// Görev türüne göre sıralı sağlayıcı listesi döndürür.
// İlk eleman admin'in varsayılanı, sonrakiler otomatik fallback.
function getProviderChain(task: "text" | "vision" | "image", settings: ProviderSettings): string[] {
  let primary = settings.textProvider;
  if (task === "vision") primary = settings.visionProvider;
  if (task === "image") primary = settings.imageProvider;

  primary = (primary || "pollinations").toLowerCase();

  if (task === "text") {
    const chain = [primary];
    if (!chain.includes("pollinations")) chain.push("pollinations");
    if (!chain.includes("huggingface")) chain.push("huggingface");
    if (!chain.includes("gemini")) chain.push("gemini");
    if (!chain.includes("groq")) chain.push("groq");
    if (!chain.includes("openrouter")) chain.push("openrouter");
    if (!chain.includes("openai")) chain.push("openai");
    return chain;
  }

  if (task === "vision") {
    // Vision için pollinations/groq/huggingface son sırada (sınırlı destek)
    const chain = [primary];
    if (!chain.includes("pollinations")) chain.push("pollinations");
    if (!chain.includes("gemini")) chain.push("gemini");
    if (!chain.includes("openrouter")) chain.push("openrouter");
    if (!chain.includes("openai")) chain.push("openai");
    return chain;
  }

  // image
  const chain = [primary];
  if (!chain.includes("pollinations")) chain.push("pollinations");
  if (!chain.includes("gemini")) chain.push("gemini");
  if (!chain.includes("openrouter")) chain.push("openrouter");
  if (!chain.includes("openai")) chain.push("openai");
  return chain;
}

async function callProvider(
  provider: string,
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = [],
  imagePrompt?: string
): Promise<ChatResponse> {
  switch (provider) {
    case "pollinations":
      if (imagePrompt) return callPollinationsImage(settings, imagePrompt);
      return callPollinationsText(settings, message, history, attachments);
    case "huggingface":
      return callHuggingFaceText(settings, message, history);
    case "gemini":
      if (imagePrompt) return callGeminiImage(settings, imagePrompt);
      return callGemini(settings, message, history, attachments);
    case "groq":
      return callGroq(settings, message, history, attachments);
    case "openrouter":
      if (imagePrompt) return callOpenRouterImage(settings, imagePrompt);
      return callOpenRouter(settings, message, history, attachments);
    case "openai":
      return callOpenAI(settings, message, history, attachments);
    default:
      throw new ProviderError(provider, "Bilinmeyen sağlayıcı");
  }
}

async function callWithChain(
  task: "text" | "vision" | "image",
  settings: ProviderSettings,
  message: string,
  history: Array<{ role: string; content: string }>,
  attachments: Array<{ storage_path: string; mime_type: string; base64: string }> = [],
  imagePrompt?: string
): Promise<ChatResponse> {
  const chain = getProviderChain(task, settings);
  const errors: string[] = [];

  for (const p of chain) {
    try {
      console.log(`[${task}] ${p} deneniyor...`);
      const result = await callProvider(p, settings, message, history, attachments, imagePrompt);
      return result;
    } catch (err: any) {
      const msg = err instanceof ProviderError ? err.message : String(err);
      console.warn(`[${task}] ${p} başarısız: ${msg.substring(0, 100)}`);
      errors.push(`${p}: ${msg.substring(0, 80)}`);
    }
  }

  throw new Error(
    `Tüm sağlayıcılar başarısız (${task}). Zincir: ${chain.join(" → ")}. Hatalar: ${errors.join(" | ")}`
  );
}

// =====================================================
// ATTACHMENT YÜKLEME
// =====================================================

async function loadAttachment(att: { storage_path: string; mime_type: string }) {
  const { data, error } = await supabase.storage
    .from("ai-uploads")
    .download(att.storage_path.replace(/^ai-uploads\//, ""));

  if (error || !data) throw new Error("Dosya yüklenemedi");

  const arrayBuffer = await data.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  const base64 = btoa(String.fromCharCode(...bytes));

  return { ...att, base64 };
}

// =====================================================
// CONVERSATION YÖNETİMİ
// =====================================================

async function getOrCreateConversation(
  userId: string,
  conversationId: string | null
): Promise<string> {
  if (conversationId) {
    return conversationId;
  }

  const { data, error } = await supabase
    .from("ai_conversations")
    .insert({
      user_id: userId,
      provider: "auto",
      title: "Yeni Sohbet"
    })
    .select("id")
    .single();

  if (error || !data) {
    console.error("INSERT hatası:", error);
    throw new Error("Konuşma oluşturulamadı: " + (error?.message || "Bilinmeyen hata"));
  }

  return data.id;
}

async function loadHistory(conversationId: string) {
  const { data, error } = await supabase
    .from("ai_messages")
    .select("role, content")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .limit(20);

  if (error) return [];
  return (data || []).filter((m: any) => m.role !== "system");
}

async function saveMessage(
  conversationId: string,
  userId: string,
  role: string,
  content: string,
  provider: string | null,
  model: string | null,
  tokens: number,
  attachments: any[] = [],
  generatedImages: any[] = [],
  errorMsg: string | null = null
) {
  console.log(`[saveMessage] Kaydediliyor: role=${role}, convId=${conversationId}, contentLength=${content.length}`);

  const { data, error: insertError } = await supabase.from("ai_messages").insert({
    conversation_id: conversationId,
    user_id: userId,
    role,
    content,
    provider,
    model,
    tokens_used: tokens,
    attachments,
    generated_images: generatedImages,
    error: errorMsg,
  });

  if (insertError) {
    console.error("[saveMessage] HATA:", insertError);
  } else {
    console.log("[saveMessage] Başarılı: messageId=", data?.id);
  }
}

async function incrementUsage(userId: string, tokens: number, isImageGen: boolean) {
  try {
    await supabase.rpc("ai_increment_usage", {
      p_user_id: userId,
      p_tokens: tokens,
      p_is_image_generation: isImageGen,
    });
  } catch (e) {
    console.warn("Usage increment başarısız:", e);
  }
}

// =====================================================
// MAIN HANDLER
// =====================================================

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Yetkilendirme gerekli" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(token);

    if (userError || !userData.user) {
      return new Response(
        JSON.stringify({ error: "Geçersiz token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = userData.user.id;
    const body: RequestBody = await req.json();

    // Ayarları yükle
    const settings = await loadSettings();

    // Konuşma ID
    const conversationId = await getOrCreateConversation(userId, body.conversation_id || null);

    // Geçmiş mesajları yükle
    const history = await loadHistory(conversationId);

    // Kullanıcı mesajını kaydet
    await saveMessage(
      conversationId,
      userId,
      "user",
      body.message,
      null,
      null,
      0,
      body.attachments || []
    );

    let response: ChatResponse;
    let errorMessage: string | null = null;

    try {
      if (body.action === "text") {
        response = await callWithChain("text", settings, body.message, history);
      } else if (body.action === "vision") {
        const attachments = await Promise.all(
          (body.attachments || []).map(loadAttachment)
        );
        response = await callWithChain("vision", settings, body.message, history, attachments);
      } else if (body.action === "image_generation") {
        const prompt = body.image_prompt || body.message;
        response = await callWithChain("image", settings, body.message, history, [], prompt);
      } else {
        throw new Error("Geçersiz action");
      }
    } catch (err: any) {
      errorMessage = err.message || "Bilinmeyen hata";
      response = {
        content: `Üzgünüm, şu anda AI servisine ulaşılamıyor. Lütfen daha sonra tekrar deneyin.`,
        provider: "none",
        model: "none",
        tokens: 0,
      };
    }

    await saveMessage(
      conversationId,
      userId,
      "assistant",
      response.content,
      response.provider,
      response.model,
      response.tokens,
      [],
      response.generatedImages || [],
      errorMessage
    );

    await incrementUsage(userId, response.tokens, body.action === "image_generation");

    let userMsgId = null;
    let assistantMsgId = null;

    try {
      const userMsgData = await supabase
        .from("ai_messages")
        .select("id")
        .eq("conversation_id", conversationId)
        .eq("role", "user")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      userMsgId = userMsgData?.id || null;
    } catch (e) {
      console.warn("User msg ID alma hatası:", e);
    }

    try {
      const asstMsgData = await supabase
        .from("ai_messages")
        .select("id")
        .eq("conversation_id", conversationId)
        .eq("role", "assistant")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      assistantMsgId = asstMsgData?.id || null;
    } catch (e) {
      console.warn("Assistant msg ID alma hatası:", e);
    }

    const responseJson = {
      conversation_id: conversationId,
      user_message_id: userMsgId,
      assistant_message_id: assistantMsgId,
      assistant_content: response.content,
      content: response.content,
      provider: response.provider,
      model: response.model,
      tokens_used: response.tokens,
      generated_images: response.generatedImages || [],
      error: errorMessage,
    };

    console.log("Edge Function başarılı yanıt:", {
      conversationId,
      contentLength: response.content.length,
      provider: response.provider,
      hasError: !!errorMessage
    });

    return new Response(
      JSON.stringify(responseJson),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: any) {
    console.error("Genel hata:", err);
    return new Response(
      JSON.stringify({ error: err.message || "Bilinmeyen hata" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});