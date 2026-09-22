// Linkten ürün görseli kazıma (Open Graph) — saf yardımcılar.
//
// Bu dosya bilinçli olarak Deno'ya özgü API kullanmaz (DNS çözümleyici dışarıdan
// verilir); böylece birim testleri hızlı ve ağsız çalışır. Edge Function
// (fetch-og-image/index.ts) yalnızca kimlik/rol doğrulaması ve HTTP zarfından
// sorumludur.
//
// Güvenlik: bu kod kullanıcının verdiği URL'ye sunucudan istek atar (SSRF
// yüzeyi). Bu yüzden her istek — yönlendirmeler dahil — önce assertPublicUrl
// ile doğrulanır: yalnız http(s), 80/443 portu, kimlik bilgisi yok, iç ağ /
// loopback / link-local / metadata adresleri engelli.

export const MAX_HTML_BYTES = 1_000_000;
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // shop-images bucket sınırı
export const MIN_IMAGE_BYTES = 500; // izleme pikseli / boş yanıt eleği
export const MAX_REDIRECTS = 4;
export const FETCH_TIMEOUT_MS = 8_000;
export const MAX_IMAGE_CANDIDATES = 4;

export type ScrapeErrorCode =
  | "INVALID_URL"
  | "BLOCKED_URL"
  | "DNS_FAILED"
  | "FETCH_FAILED"
  | "TIMEOUT"
  | "TOO_MANY_REDIRECTS"
  | "NOT_HTML"
  | "NO_IMAGE"
  | "IMAGE_FAILED"
  | "IMAGE_TOO_LARGE"
  | "UNSUPPORTED_IMAGE";

/** İstemciye olduğu gibi gösterilebilen (Türkçe) beklenen hata. */
export class ScrapeError extends Error {
  constructor(public code: ScrapeErrorCode, message: string) {
    super(message);
    this.name = "ScrapeError";
  }
}

/** Ana makinenin tüm A/AAAA adreslerini döner; bulunamazsa boş dizi. */
export type DnsResolver = (hostname: string) => Promise<string[]>;

// ---------------------------------------------------------------------------
// IP / URL doğrulama (SSRF)
// ---------------------------------------------------------------------------

function parseIPv4(host: string): [number, number, number, number] | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return null;
  const parts = m.slice(1).map(Number);
  if (parts.some((p) => p > 255)) return null;
  return parts as [number, number, number, number];
}

function isBlockedIPv4([a, b, c]: number[]): boolean {
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a === 169 && b === 254) return true; // link-local + bulut metadata
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return true;
  if (a === 198 && (b === 18 || b === 19)) return true; // benchmark
  if (a === 198 && b === 51 && c === 100) return true; // TEST-NET-2
  if (a === 203 && b === 0 && c === 113) return true; // TEST-NET-3
  if (a >= 224) return true; // multicast + ayrılmış + broadcast
  return false;
}

/** "::ffff:1.2.3.4" gibi gömülü IPv4 biçimini de kapsayan 8x16-bit ayrıştırma. */
function parseIPv6(input: string): number[] | null {
  let host = input;
  const v4Tail = /(\d{1,3}(?:\.\d{1,3}){3})$/.exec(host);
  if (v4Tail) {
    const v4 = parseIPv4(v4Tail[1]);
    if (!v4) return null;
    host = host.slice(0, host.length - v4Tail[1].length) +
      ((v4[0] << 8) | v4[1]).toString(16) + ":" +
      ((v4[2] << 8) | v4[3]).toString(16);
  }
  const halves = host.split("::");
  if (halves.length > 2) return null;
  const toGroups = (s: string) => (s === "" ? [] : s.split(":"));
  const head = toGroups(halves[0]);
  const tail = halves.length === 2 ? toGroups(halves[1]) : [];
  const missing = 8 - head.length - tail.length;
  if (halves.length === 1 ? missing !== 0 : missing < 1) return null;
  const all = [...head, ...Array(halves.length === 2 ? missing : 0).fill("0"), ...tail];
  if (all.length !== 8) return null;
  const groups: number[] = [];
  for (const g of all) {
    if (!/^[0-9a-fA-F]{1,4}$/.test(g)) return null;
    groups.push(parseInt(g, 16));
  }
  return groups;
}

function isBlockedIPv6(g: number[]): boolean {
  const embeddedV4 = (hi: number, lo: number) =>
    isBlockedIPv4([hi >> 8, hi & 255, lo >> 8, lo & 255]);
  const firstFiveZero = g.slice(0, 5).every((x) => x === 0);
  if (firstFiveZero && g[5] === 0 && g[6] === 0 && (g[7] === 0 || g[7] === 1)) {
    return true; // :: ve ::1
  }
  if (firstFiveZero && g[5] === 0xffff) return embeddedV4(g[6], g[7]); // v4-mapped
  if (firstFiveZero && g[5] === 0) return embeddedV4(g[6], g[7]); // v4-compatible
  // NAT64 (64:ff9b::/96): gömülü IPv4 hedefi belirler.
  if (g[0] === 0x64 && g[1] === 0xff9b && g.slice(2, 6).every((x) => x === 0)) {
    return embeddedV4(g[6], g[7]);
  }
  if ((g[0] & 0xfe00) === 0xfc00) return true; // fc00::/7 (ULA)
  if ((g[0] & 0xffc0) === 0xfe80) return true; // fe80::/10 (link-local)
  if ((g[0] & 0xffc0) === 0xfec0) return true; // fec0::/10 (site-local)
  if ((g[0] & 0xff00) === 0xff00) return true; // multicast
  if (g[0] === 0x2002) return embeddedV4(g[1], g[2]); // 6to4
  if (g[0] === 0x2001 && g[1] === 0) return true; // Teredo
  if (g[0] === 0x2001 && g[1] === 0x0db8) return true; // dokümantasyon
  return false;
}

/** Verilen adres (IPv4 ya da IPv6) iç/özel/ayrılmış aralıkta mı? Tanınmazsa true. */
export function isBlockedIp(address: string): boolean {
  const raw = address.trim().replace(/^\[|\]$/g, "").split("%")[0];
  const v4 = parseIPv4(raw);
  if (v4) return isBlockedIPv4(v4);
  if (raw.includes(":")) {
    const v6 = parseIPv6(raw);
    return v6 ? isBlockedIPv6(v6) : true;
  }
  return true; // ne v4 ne v6 → güvenme
}

const BLOCKED_HOST_SUFFIXES = [
  ".localhost",
  ".local",
  ".internal",
  ".localdomain",
  ".lan",
  ".home",
  ".corp",
  ".intranet",
];

/** URL'nin sunucudan istenmesi güvenli mi? Değilse ScrapeError fırlatır. */
export async function assertPublicUrl(
  url: URL,
  resolve: DnsResolver,
): Promise<void> {
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new ScrapeError("INVALID_URL", "Yalnızca http veya https bağlantısı girin");
  }
  if (url.username || url.password) {
    throw new ScrapeError("BLOCKED_URL", "Bu adrese erişilemez");
  }
  // URL.port varsayılan portta boş gelir; başka portlar iç ağ taraması için
  // kullanılabileceğinden reddedilir.
  if (url.port !== "" && url.port !== "80" && url.port !== "443") {
    throw new ScrapeError("BLOCKED_URL", "Bu adrese erişilemez");
  }

  // WHATWG URL ayrıştırıcısı 2130706433 / 0x7f.1 gibi biçimleri dotted-quad'a
  // normalleştirir; bu yüzden aşağıdaki literal kontrolü onları da yakalar.
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  const bare = host.replace(/^\[|\]$/g, "");
  if (parseIPv4(bare) || bare.includes(":")) {
    if (isBlockedIp(bare)) {
      throw new ScrapeError("BLOCKED_URL", "Bu adrese erişilemez");
    }
    return;
  }

  if (
    host === "localhost" ||
    !host.includes(".") ||
    BLOCKED_HOST_SUFFIXES.some((s) => host.endsWith(s))
  ) {
    throw new ScrapeError("BLOCKED_URL", "Bu adrese erişilemez");
  }

  const addresses = await resolve(host);
  if (addresses.length === 0) {
    throw new ScrapeError("DNS_FAILED", "Bu adres bulunamadı; bağlantıyı kontrol edin");
  }
  if (addresses.some(isBlockedIp)) {
    throw new ScrapeError("BLOCKED_URL", "Bu adrese erişilemez");
  }
}

/** Kullanıcının yapıştırdığı metni URL'ye çevirir; şema yoksa https varsayar. */
export function parseUserUrl(raw: unknown): URL {
  if (typeof raw !== "string") {
    throw new ScrapeError("INVALID_URL", "Geçerli bir bağlantı girin");
  }
  let text = raw.trim();
  if (text.length === 0 || text.length > 2048 || /\s/.test(text)) {
    throw new ScrapeError("INVALID_URL", "Geçerli bir bağlantı girin");
  }
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) text = `https://${text}`;
  try {
    return new URL(text);
  } catch {
    throw new ScrapeError("INVALID_URL", "Geçerli bir bağlantı girin");
  }
}

// ---------------------------------------------------------------------------
// HTML meta ayrıştırma
// ---------------------------------------------------------------------------

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
};

export function decodeEntities(text: string): string {
  return text.replace(
    /&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|([a-zA-Z]{2,6}));/g,
    (whole, dec, hex, name) => {
      if (name) return NAMED_ENTITIES[name.toLowerCase()] ?? whole;
      const code = dec ? parseInt(dec, 10) : parseInt(hex, 16);
      if (!Number.isFinite(code) || code < 1 || code > 0x10ffff) return whole;
      try {
        return String.fromCodePoint(code);
      } catch {
        return whole;
      }
    },
  );
}

function parseAttributes(tag: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  // İlk token etiket adının kendisidir (<meta); atla.
  const body = tag.replace(/^<\s*[a-zA-Z0-9]+/, "");
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) {
    const name = m[1].toLowerCase();
    if (name in attrs) continue; // HTML'de ilk öznitelik geçerlidir
    attrs[name] = decodeEntities(m[2] ?? m[3] ?? m[4] ?? "");
  }
  return attrs;
}

// Düşük sayı = yüksek öncelik.
const META_PRIORITY: Record<string, number> = {
  "og:image:secure_url": 0,
  "og:image": 1,
  "og:image:url": 2,
  "twitter:image": 3,
  "twitter:image:src": 4,
  "image": 5, // itemprop="image"
};
const LINK_IMAGE_SRC_PRIORITY = 6;
const JSON_LD_PRIORITY = 7;

function collectJsonLdImages(node: unknown, out: string[], depth = 0): void {
  if (depth > 6 || node == null) return;
  if (Array.isArray(node)) {
    for (const item of node) collectJsonLdImages(item, out, depth + 1);
    return;
  }
  if (typeof node !== "object") return;
  const obj = node as Record<string, unknown>;
  const image = obj["image"];
  const pushImage = (v: unknown) => {
    if (typeof v === "string") out.push(v);
    else if (Array.isArray(v)) v.forEach(pushImage);
    else if (v && typeof v === "object") {
      const url = (v as Record<string, unknown>)["url"] ??
        (v as Record<string, unknown>)["contentUrl"];
      if (typeof url === "string") out.push(url);
    }
  };
  pushImage(image);
  const graph = obj["@graph"];
  if (graph) collectJsonLdImages(graph, out, depth + 1);
}

export interface PageMeta {
  /** Öncelik sırasına göre, tekilleştirilmiş, mutlak http(s) görsel URL'leri. */
  images: string[];
  title: string | null;
}

function resolveHttpUrl(value: string, base: string): string | null {
  const v = value.trim();
  if (!v || v.startsWith("data:")) return null;
  try {
    const u = new URL(v, base);
    return u.protocol === "http:" || u.protocol === "https:" ? u.toString() : null;
  } catch {
    return null;
  }
}

export function extractPageMeta(html: string, pageUrl: string): PageMeta {
  const found: { priority: number; order: number; url: string }[] = [];
  let order = 0;
  const add = (priority: number, raw: string) => {
    const url = resolveHttpUrl(raw, pageUrl);
    if (url) found.push({ priority, order: order++, url });
  };

  // Yorum satırları içindeki sahte etiketleri yok say.
  const source = html.replace(/<!--[\s\S]*?-->/g, "");

  let ogTitle: string | null = null;
  let twitterTitle: string | null = null;

  for (const m of source.matchAll(/<meta\b[^>]*>/gi)) {
    const attrs = parseAttributes(m[0]);
    const key = (attrs["property"] ?? attrs["name"] ?? attrs["itemprop"] ?? "")
      .toLowerCase();
    const content = attrs["content"];
    if (!key || content == null) continue;
    if (key in META_PRIORITY) add(META_PRIORITY[key], content);
    else if (key === "og:title") ogTitle ??= content;
    else if (key === "twitter:title") twitterTitle ??= content;
  }

  for (const m of source.matchAll(/<link\b[^>]*>/gi)) {
    const attrs = parseAttributes(m[0]);
    const rel = (attrs["rel"] ?? "").toLowerCase().split(/\s+/);
    if (rel.includes("image_src") && attrs["href"]) {
      add(LINK_IMAGE_SRC_PRIORITY, attrs["href"]);
    }
  }

  for (
    const m of source.matchAll(
      /<script\b[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi,
    )
  ) {
    try {
      const images: string[] = [];
      collectJsonLdImages(JSON.parse(m[1].trim()), images);
      for (const img of images) add(JSON_LD_PRIORITY, img);
    } catch {
      // Bozuk JSON-LD yaygındır; diğer kaynaklara devam.
    }
  }

  found.sort((a, b) => a.priority - b.priority || a.order - b.order);
  const images: string[] = [];
  for (const f of found) if (!images.includes(f.url)) images.push(f.url);

  let title = ogTitle ?? twitterTitle;
  if (!title) {
    const t = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(source);
    title = t ? decodeEntities(t[1]) : null;
  }
  title = title?.replace(/\s+/g, " ").trim().slice(0, 200) || null;

  return { images, title };
}

// ---------------------------------------------------------------------------
// Görsel biçimi
// ---------------------------------------------------------------------------

export interface ImageKind {
  mime: "image/jpeg" | "image/png" | "image/webp";
  ext: "jpg" | "png" | "webp";
}

/** Content-Type başlığına değil baytlara bakar (HTML hata sayfası görsel sayılmasın). */
export function sniffImage(b: Uint8Array): ImageKind | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    return { mime: "image/jpeg", ext: "jpg" };
  }
  if (
    b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e &&
    b[3] === 0x47 && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a &&
    b[7] === 0x0a
  ) {
    return { mime: "image/png", ext: "png" };
  }
  if (
    b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 &&
    b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 &&
    b[11] === 0x50
  ) {
    return { mime: "image/webp", ext: "webp" };
  }
  return null;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

// ---------------------------------------------------------------------------
// Ağ
// ---------------------------------------------------------------------------

export interface ScrapeDeps {
  resolve: DnsResolver;
  fetchFn?: typeof fetch;
}

const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
// Bazı siteler tarayıcı UA'sını, bazıları ise kendini tanıtan botları
// engelliyor (ölçüm: Trendyol yalnız bunu, Hepsiburada yalnız tarayıcıyı
// kabul ediyor). Engel yanıtında ikinci kez bununla denenir. Başka bir
// şirketin tarayıcısı (Googlebot vb.) taklit EDİLMEZ.
const BOT_UA = "Mozilla/5.0 (compatible; CizreAppBot/1.0; +https://cizreapp.com)";
const BLOCKED_STATUSES = new Set([401, 403, 429, 503]);

async function guardedFetch(
  start: URL,
  headers: Record<string, string>,
  deps: ScrapeDeps,
): Promise<{ res: Response; finalUrl: URL }> {
  const fetchFn = deps.fetchFn ?? fetch;
  let current = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicUrl(current, deps.resolve);
    let res: Response;
    try {
      res = await fetchFn(current.toString(), {
        method: "GET",
        headers,
        redirect: "manual",
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
    } catch (e) {
      const name = (e as Error)?.name;
      if (name === "TimeoutError" || name === "AbortError") {
        throw new ScrapeError("TIMEOUT", "Site zamanında yanıt vermedi");
      }
      throw new ScrapeError("FETCH_FAILED", "Siteye bağlanılamadı");
    }
    const location = res.headers.get("location");
    if (res.status >= 300 && res.status < 400 && location) {
      await res.body?.cancel();
      try {
        current = new URL(location, current);
      } catch {
        throw new ScrapeError("FETCH_FAILED", "Sayfa geçersiz yönlendirme yaptı");
      }
      continue;
    }
    return { res, finalUrl: current };
  }
  throw new ScrapeError("TOO_MANY_REDIRECTS", "Sayfa çok fazla yönlendirme yapıyor");
}

/** Gövdeyi en fazla [maxBytes] kadar okur; aşarsa kesip `truncated` işaretler. */
async function readCapped(
  res: Response,
  maxBytes: number,
): Promise<{ bytes: Uint8Array; truncated: boolean }> {
  if (!res.body) return { bytes: new Uint8Array(0), truncated: false };
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let truncated = false;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (total + value.length > maxBytes) {
        chunks.push(value.subarray(0, maxBytes - total));
        total = maxBytes;
        truncated = true;
        break;
      }
      chunks.push(value);
      total += value.length;
    }
  } catch {
    // Akış yarıda koptuysa elde olanla devam (HTML'de <head> genelde yeter).
    truncated = true;
  } finally {
    await reader.cancel().catch(() => {});
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    bytes.set(c, offset);
    offset += c.length;
  }
  return { bytes, truncated };
}

function decodeHtml(bytes: Uint8Array, contentType: string): string {
  const fromHeader = /charset\s*=\s*["']?([\w-]+)/i.exec(contentType)?.[1];
  const head = new TextDecoder("utf-8").decode(bytes.subarray(0, 4096));
  const fromMeta = /<meta[^>]+charset\s*=\s*["']?([\w-]+)/i.exec(head)?.[1];
  const label = (fromHeader ?? fromMeta ?? "utf-8").toLowerCase();
  try {
    return new TextDecoder(label).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

async function readImageResponse(
  res: Response,
): Promise<{ bytes: Uint8Array; kind: ImageKind }> {
  if (!res.ok) {
    await res.body?.cancel();
    throw new ScrapeError("IMAGE_FAILED", `Görsel indirilemedi (${res.status})`);
  }
  const declared = Number(res.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_IMAGE_BYTES) {
    await res.body?.cancel();
    throw new ScrapeError("IMAGE_TOO_LARGE", "Görsel 5 MB'tan büyük");
  }
  const { bytes, truncated } = await readCapped(res, MAX_IMAGE_BYTES);
  if (truncated) throw new ScrapeError("IMAGE_TOO_LARGE", "Görsel 5 MB'tan büyük");
  if (bytes.length < MIN_IMAGE_BYTES) {
    throw new ScrapeError("IMAGE_FAILED", "Görsel indirilemedi");
  }
  const kind = sniffImage(bytes);
  if (!kind) {
    throw new ScrapeError(
      "UNSUPPORTED_IMAGE",
      "Görsel biçimi desteklenmiyor (JPG, PNG veya WebP olmalı)",
    );
  }
  return { bytes, kind };
}

export interface ScrapeResult {
  /** Kazınan sayfanın (yönlendirmeler sonrası) adresi. */
  pageUrl: string;
  /** Görselin özgün adresi. */
  imageUrl: string;
  title: string | null;
  mime: ImageKind["mime"];
  ext: ImageKind["ext"];
  bytes: Uint8Array;
}

function pageHeaders(userAgent: string): Record<string, string> {
  return {
    "User-Agent": userAgent,
    "Accept": "text/html,application/xhtml+xml,image/jpeg,image/png,image/webp;q=0.8,*/*;q=0.5",
    "Accept-Language": "tr-TR,tr;q=0.9,en;q=0.7",
  };
}

function httpStatusMessage(status: number): string {
  if (status === 401 || status === 403) {
    return `Site otomatik erişimi engelledi (${status}); görseli galeriden yükleyin`;
  }
  if (status === 404 || status === 410) return `Sayfa bulunamadı (${status})`;
  return `Sayfa açılamadı (${status})`;
}

/**
 * URL'deki sayfanın ana görselini (og:image ve benzerleri) bulup indirir.
 * URL doğrudan bir görsele işaret ediyorsa o görseli döner.
 */
export async function scrapeProductImage(
  rawUrl: unknown,
  deps: ScrapeDeps,
): Promise<ScrapeResult> {
  const start = parseUserUrl(rawUrl);

  let page = await guardedFetch(start, pageHeaders(BROWSER_UA), deps);
  if (BLOCKED_STATUSES.has(page.res.status)) {
    await page.res.body?.cancel();
    page = await guardedFetch(start, pageHeaders(BOT_UA), deps);
  }
  const { res, finalUrl } = page;

  const contentType = (res.headers.get("content-type") ?? "").toLowerCase();

  // Kullanıcı doğrudan görsel bağlantısı yapıştırdıysa aynen kullan.
  if (res.ok && contentType.startsWith("image/")) {
    const { bytes, kind } = await readImageResponse(res);
    return {
      pageUrl: finalUrl.toString(),
      imageUrl: finalUrl.toString(),
      title: null,
      mime: kind.mime,
      ext: kind.ext,
      bytes,
    };
  }

  if (!res.ok) {
    await res.body?.cancel();
    throw new ScrapeError("FETCH_FAILED", httpStatusMessage(res.status));
  }
  if (
    contentType !== "" && !contentType.includes("html") &&
    !contentType.includes("xml")
  ) {
    await res.body?.cancel();
    throw new ScrapeError("NOT_HTML", "Bağlantı bir web sayfası değil");
  }

  const { bytes: htmlBytes } = await readCapped(res, MAX_HTML_BYTES);
  const meta = extractPageMeta(
    decodeHtml(htmlBytes, contentType),
    finalUrl.toString(),
  );
  if (meta.images.length === 0) {
    throw new ScrapeError("NO_IMAGE", "Bu sayfada ürün görseli bulunamadı");
  }

  let lastError: ScrapeError | null = null;
  for (const candidate of meta.images.slice(0, MAX_IMAGE_CANDIDATES)) {
    try {
      const { res: imgRes } = await guardedFetch(new URL(candidate), {
        "User-Agent": BROWSER_UA,
        // AVIF/JXL istemiyoruz: görsel yalnız jpeg/png/webp kabul edilir ve
        // bazı CDN'ler Accept'e göre biçim seçer.
        "Accept": "image/jpeg,image/png,image/webp;q=0.9,*/*;q=0.5",
        "Referer": finalUrl.origin + "/",
      }, deps);
      const { bytes, kind } = await readImageResponse(imgRes);
      return {
        pageUrl: finalUrl.toString(),
        imageUrl: candidate,
        title: meta.title,
        mime: kind.mime,
        ext: kind.ext,
        bytes,
      };
    } catch (e) {
      if (e instanceof ScrapeError) lastError = e;
      else throw e;
    }
  }
  throw lastError ??
    new ScrapeError("IMAGE_FAILED", "Görsel indirilemedi");
}
