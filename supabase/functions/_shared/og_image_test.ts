// deno test _shared/og_image_test.ts
//
// `node:assert` hem Deno'da hem Node'da çalışır; testler ağa çıkmaz (sahte
// fetch + sahte DNS çözümleyici).

import assert from "node:assert/strict";
import {
  assertPublicUrl,
  extractPageMeta,
  isBlockedIp,
  MAX_IMAGE_BYTES,
  parseUserUrl,
  ScrapeError,
  scrapeProductImage,
  sniffImage,
} from "./og_image.ts";

const publicDns = () => Promise.resolve(["93.184.216.34"]);

async function codeOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
  } catch (e) {
    if (e instanceof ScrapeError) return e.code;
    throw e;
  }
  return "NO_ERROR";
}

function jpegBytes(size = 2000): Uint8Array {
  const b = new Uint8Array(size);
  b[0] = 0xff;
  b[1] = 0xd8;
  b[2] = 0xff;
  return b;
}

function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function imageResponse(bytes: Uint8Array, type = "image/jpeg"): Response {
  return new Response(bytes, { status: 200, headers: { "content-type": type } });
}

/** URL → Response eşlemeli sahte fetch; eşleşmeyen istek 404 döner. */
function fakeFetch(routes: Record<string, () => Response>): typeof fetch {
  return ((input: string | URL | Request) => {
    const key = String(input);
    const route = routes[key];
    return Promise.resolve(route ? route() : new Response("", { status: 404 }));
  }) as typeof fetch;
}

Deno.test("isBlockedIp: özel/iç IPv4 aralıkları engellenir, genel IP geçer", () => {
  for (
    const ip of [
      "127.0.0.1",
      "10.1.2.3",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.1.1",
      "169.254.169.254",
      "100.64.0.1",
      "0.0.0.0",
      "224.0.0.1",
      "255.255.255.255",
    ]
  ) assert.equal(isBlockedIp(ip), true, ip);
  for (const ip of ["8.8.8.8", "93.184.216.34", "172.32.0.1", "100.63.0.1"]) {
    assert.equal(isBlockedIp(ip), false, ip);
  }
});

Deno.test("isBlockedIp: IPv6 loopback, ULA, link-local ve gömülü IPv4 engellenir", () => {
  for (
    const ip of [
      "::1",
      "::",
      "fc00::1",
      "fd12:3456::1",
      "fe80::1",
      "ff02::1",
      "::ffff:127.0.0.1",
      "::ffff:7f00:1",
      "::ffff:a9fe:a9fe",
      "64:ff9b::7f00:1",
      "2002:7f00:1::1",
      "2001:0:4136:e378:8000:63bf:3fff:fdd2",
      "not-an-ip",
    ]
  ) assert.equal(isBlockedIp(ip), true, ip);
  for (const ip of ["2606:4700:4700::1111", "::ffff:8.8.8.8", "2a00:1450:4001::200e"]) {
    assert.equal(isBlockedIp(ip), false, ip);
  }
});

Deno.test("assertPublicUrl: yasak URL biçimleri reddedilir", async () => {
  const cases: [string, string][] = [
    ["http://localhost/", "BLOCKED_URL"],
    ["http://foo.localhost/", "BLOCKED_URL"],
    ["http://127.0.0.1/", "BLOCKED_URL"],
    ["http://2130706433/", "BLOCKED_URL"], // 127.0.0.1'in ondalık yazımı
    ["http://0x7f.1/", "BLOCKED_URL"],
    ["http://[::1]/", "BLOCKED_URL"],
    ["http://[::ffff:127.0.0.1]/", "BLOCKED_URL"],
    ["http://169.254.169.254/latest/meta-data", "BLOCKED_URL"],
    ["https://example.com:8080/", "BLOCKED_URL"],
    ["https://user:pass@example.com/", "BLOCKED_URL"],
    ["http://intranet/", "BLOCKED_URL"], // tek etiketli ad
    ["http://printer.local/", "BLOCKED_URL"],
    ["ftp://example.com/x", "INVALID_URL"],
  ];
  for (const [url, code] of cases) {
    assert.equal(await codeOf(assertPublicUrl(new URL(url), publicDns)), code, url);
  }
});

Deno.test("assertPublicUrl: DNS iç adrese çözülüyorsa (rebinding) reddedilir", async () => {
  const toPrivate = () => Promise.resolve(["93.184.216.34", "10.0.0.5"]);
  assert.equal(
    await codeOf(assertPublicUrl(new URL("https://evil.example.com/"), toPrivate)),
    "BLOCKED_URL",
  );
  assert.equal(
    await codeOf(
      assertPublicUrl(new URL("https://nx.example.com/"), () => Promise.resolve([])),
    ),
    "DNS_FAILED",
  );
  assert.equal(
    await codeOf(assertPublicUrl(new URL("https://example.com/"), publicDns)),
    "NO_ERROR",
  );
  assert.equal(
    await codeOf(assertPublicUrl(new URL("https://example.com:443/"), publicDns)),
    "NO_ERROR",
  );
});

Deno.test("parseUserUrl: şema yoksa https eklenir, boşluk/çöp reddedilir", () => {
  assert.equal(parseUserUrl("  example.com/urun  ").toString(), "https://example.com/urun");
  assert.equal(parseUserUrl("http://example.com/a").protocol, "http:");
  for (const bad of ["", "   ", "a b", 42, null, "http://", "x".repeat(3000)]) {
    assert.throws(() => parseUserUrl(bad), ScrapeError);
  }
});

Deno.test("extractPageMeta: og:image, entity çözme ve göreli URL", () => {
  const html = `<html><head>
    <title>Sayfa &amp; Başlık</title>
    <meta property="og:title" content="Kırmızı   Domates &#39;Özel&#39;">
    <meta content="/img/a.jpg?w=1&amp;h=2" property="og:image">
  </head></html>`;
  const meta = extractPageMeta(html, "https://shop.example.com/urun/1");
  assert.deepEqual(meta.images, ["https://shop.example.com/img/a.jpg?w=1&h=2"]);
  assert.equal(meta.title, "Kırmızı Domates 'Özel'");
});

Deno.test("extractPageMeta: öncelik sırası og > twitter > itemprop > link > JSON-LD", () => {
  const html = `
    <script type="application/ld+json">{"@type":"Product","image":["https://c.test/ld1.jpg","https://c.test/ld2.jpg"]}</script>
    <link rel="image_src" href="//c.test/link.jpg">
    <meta itemprop="image" content="https://c.test/item.jpg">
    <meta name="twitter:image" content="https://c.test/tw.jpg">
    <meta property='og:image' content='https://c.test/og.jpg'>
    <meta property="og:image:secure_url" content="https://c.test/og-secure.jpg">
    <meta property="og:image" content="https://c.test/og.jpg">`;
  assert.deepEqual(extractPageMeta(html, "https://c.test/p").images, [
    "https://c.test/og-secure.jpg",
    "https://c.test/og.jpg",
    "https://c.test/tw.jpg",
    "https://c.test/item.jpg",
    "https://c.test/link.jpg",
    "https://c.test/ld1.jpg",
    "https://c.test/ld2.jpg",
  ]);
});

Deno.test("extractPageMeta: JSON-LD @graph/nesne biçimleri, yorum ve data: URI yok sayılır", () => {
  const html = `
    <!-- <meta property="og:image" content="https://c.test/commented.jpg"> -->
    <meta property="og:image" content="data:image/png;base64,AAAA">
    <script type="application/ld+json">{"@graph":[{"@type":"Product","image":{"@type":"ImageObject","url":"https://c.test/graph.jpg"}}]}</script>
    <script type="application/ld+json">{bozuk json</script>`;
  const meta = extractPageMeta(html, "https://c.test/");
  assert.deepEqual(meta.images, ["https://c.test/graph.jpg"]);
  assert.equal(meta.title, null);
});

Deno.test("extractPageMeta: og:title yoksa <title> kullanılır, görsel yoksa boş dizi", () => {
  const meta = extractPageMeta("<title> Sadece Başlık </title>", "https://c.test/");
  assert.equal(meta.title, "Sadece Başlık");
  assert.deepEqual(meta.images, []);
});

Deno.test("sniffImage: baytlara bakar; HTML/GIF görsel sayılmaz", () => {
  assert.equal(sniffImage(jpegBytes())?.ext, "jpg");
  assert.equal(
    sniffImage(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]))?.mime,
    "image/png",
  );
  const webp = new Uint8Array(16);
  webp.set([0x52, 0x49, 0x46, 0x46], 0);
  webp.set([0x57, 0x45, 0x42, 0x50], 8);
  assert.equal(sniffImage(webp)?.ext, "webp");
  assert.equal(sniffImage(new TextEncoder().encode("<html>")), null);
  assert.equal(sniffImage(new TextEncoder().encode("GIF89a....")), null);
});

Deno.test("scrapeProductImage: sayfadan og:image bulup indirir", async () => {
  const fetchFn = fakeFetch({
    "https://shop.test/urun": () =>
      htmlResponse(
        `<meta property="og:title" content="Ürün"><meta property="og:image" content="/i/p.jpg">`,
      ),
    "https://shop.test/i/p.jpg": () => imageResponse(jpegBytes()),
  });
  const r = await scrapeProductImage("shop.test/urun", { resolve: publicDns, fetchFn });
  assert.equal(r.imageUrl, "https://shop.test/i/p.jpg");
  assert.equal(r.title, "Ürün");
  assert.equal(r.mime, "image/jpeg");
  assert.equal(r.bytes.length, 2000);
});

Deno.test("scrapeProductImage: ilk aday indirilemezse sıradakine geçer", async () => {
  const fetchFn = fakeFetch({
    "https://shop.test/u": () =>
      htmlResponse(
        `<meta property="og:image" content="https://cdn.test/dead.jpg"><meta name="twitter:image" content="https://cdn.test/ok.jpg">`,
      ),
    "https://cdn.test/ok.jpg": () => imageResponse(jpegBytes()),
  });
  const r = await scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn });
  assert.equal(r.imageUrl, "https://cdn.test/ok.jpg");
});

Deno.test("scrapeProductImage: tarayıcı UA'sı engellenirse kendini tanıtan UA ile yeniden dener", async () => {
  const seenUas: string[] = [];
  const fetchFn = ((input: string | URL | Request, init?: RequestInit) => {
    const ua = (init?.headers as Record<string, string>)["User-Agent"];
    if (String(input) === "https://shop.test/u") {
      seenUas.push(ua);
      return Promise.resolve(
        ua.includes("CizreAppBot")
          ? htmlResponse(`<meta property="og:image" content="https://cdn.test/a.jpg">`)
          : new Response("denied", { status: 403 }),
      );
    }
    return Promise.resolve(imageResponse(jpegBytes()));
  }) as typeof fetch;
  const r = await scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn });
  assert.equal(r.imageUrl, "https://cdn.test/a.jpg");
  assert.equal(seenUas.length, 2);

  // İkisi de engelliyorsa kullanıcıya galeriyi öneren mesaj döner.
  const blocked = (() => Promise.resolve(new Response("no", { status: 403 }))) as typeof fetch;
  await assert.rejects(
    scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn: blocked }),
    (e: ScrapeError) => e.code === "FETCH_FAILED" && e.message.includes("galeriden"),
  );
});

Deno.test("scrapeProductImage: doğrudan görsel linki olduğu gibi kabul edilir", async () => {
  const fetchFn = fakeFetch({
    "https://cdn.test/a.jpg": () => imageResponse(jpegBytes()),
  });
  const r = await scrapeProductImage("https://cdn.test/a.jpg", { resolve: publicDns, fetchFn });
  assert.equal(r.imageUrl, "https://cdn.test/a.jpg");
  assert.equal(r.title, null);
});

Deno.test("scrapeProductImage: yönlendirme iç adrese giderse engellenir", async () => {
  const fetchFn = fakeFetch({
    "https://shop.test/u": () =>
      new Response(null, {
        status: 302,
        headers: { location: "http://169.254.169.254/latest/meta-data" },
      }),
  });
  assert.equal(
    await codeOf(scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn })),
    "BLOCKED_URL",
  );
});

Deno.test("scrapeProductImage: görsel yönlendirmesi iç adrese giderse o aday atlanır", async () => {
  const fetchFn = fakeFetch({
    "https://shop.test/u": () =>
      htmlResponse(`<meta property="og:image" content="https://cdn.test/redir.jpg">`),
    "https://cdn.test/redir.jpg": () =>
      new Response(null, { status: 301, headers: { location: "http://127.0.0.1/x.jpg" } }),
  });
  assert.equal(
    await codeOf(scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn })),
    "BLOCKED_URL",
  );
});

Deno.test("scrapeProductImage: yönlendirme döngüsü sınırlanır", async () => {
  const fetchFn = fakeFetch({
    "https://shop.test/u": () =>
      new Response(null, { status: 302, headers: { location: "https://shop.test/u" } }),
  });
  assert.equal(
    await codeOf(scrapeProductImage("https://shop.test/u", { resolve: publicDns, fetchFn })),
    "TOO_MANY_REDIRECTS",
  );
});

Deno.test("scrapeProductImage: hata durumları anlamlı kod döner", async () => {
  const run = (routes: Record<string, () => Response>, url: string) =>
    codeOf(scrapeProductImage(url, { resolve: publicDns, fetchFn: fakeFetch(routes) }));

  assert.equal(await run({}, "https://shop.test/missing"), "FETCH_FAILED"); // 404
  assert.equal(
    await run(
      {
        "https://shop.test/api": () =>
          new Response("{}", { headers: { "content-type": "application/json" } }),
      },
      "https://shop.test/api",
    ),
    "NOT_HTML",
  );
  assert.equal(
    await run({ "https://shop.test/x": () => htmlResponse("<p>görsel yok</p>") }, "https://shop.test/x"),
    "NO_IMAGE",
  );
  assert.equal(
    await run(
      {
        "https://shop.test/x": () => htmlResponse(`<meta property="og:image" content="https://c.test/a.gif">`),
        "https://c.test/a.gif": () =>
          imageResponse(new TextEncoder().encode("GIF89a" + "x".repeat(800)), "image/gif"),
      },
      "https://shop.test/x",
    ),
    "UNSUPPORTED_IMAGE",
  );
  assert.equal(
    await run(
      {
        "https://shop.test/x": () => htmlResponse(`<meta property="og:image" content="https://c.test/big.jpg">`),
        "https://c.test/big.jpg": () =>
          new Response(jpegBytes(), {
            headers: { "content-type": "image/jpeg", "content-length": String(MAX_IMAGE_BYTES + 1) },
          }),
      },
      "https://shop.test/x",
    ),
    "IMAGE_TOO_LARGE",
  );
  assert.equal(await run({}, "javascript:alert(1)"), "INVALID_URL");
  assert.equal(await run({}, "http://127.0.0.1:8000/admin"), "BLOCKED_URL");
});
