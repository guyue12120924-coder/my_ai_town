const LARGE_WEB_ASSETS = new Map([
  ["/index.wasm", "application/wasm"],
  ["/index.pck", "application/octet-stream"],
]);

function assetRequest(request, pathname) {
  const url = new URL(request.url);
  url.pathname = pathname;
  url.search = "";
  return new Request(url.toString(), { method: "GET" });
}

async function loadChunkManifest(request, env, pathname) {
  const response = await env.ASSETS.fetch(assetRequest(request, `${pathname}.parts.json`));
  if (!response.ok) return null;

  let manifest;
  try {
    manifest = await response.json();
  } catch {
    return null;
  }

  if (!manifest || !Array.isArray(manifest.parts) || manifest.parts.length === 0) {
    return null;
  }

  return manifest;
}

function createChunkStream(request, env, parts) {
  let partIndex = 0;
  let reader = null;

  return new ReadableStream({
    async pull(controller) {
      try {
        while (true) {
          if (reader) {
            const { done, value } = await reader.read();
            if (!done) {
              controller.enqueue(value);
              return;
            }
            reader = null;
            continue;
          }

          if (partIndex >= parts.length) {
            controller.close();
            return;
          }

          const partName = String(parts[partIndex++] || "");
          if (!/^[A-Za-z0-9._-]+$/.test(partName)) {
            throw new Error(`Invalid web asset chunk name: ${partName}`);
          }

          const response = await env.ASSETS.fetch(assetRequest(request, `/${partName}`));
          if (!response.ok || !response.body) {
            throw new Error(`Missing web asset chunk: ${partName}`);
          }
          reader = response.body.getReader();
        }
      } catch (error) {
        controller.error(error);
      }
    },

    async cancel(reason) {
      if (reader) {
        await reader.cancel(reason).catch(() => {});
      }
    },
  });
}

function chunkedHeaders(manifest, contentType) {
  const headers = new Headers({
    "Content-Type": manifest.contentType || contentType,
    "Content-Encoding": manifest.contentEncoding || "gzip",
    "Cache-Control": "public, max-age=0, must-revalidate",
    "Vary": "Accept-Encoding",
    "X-Content-Type-Options": "nosniff",
    "X-AI-Town-Chunked-Asset": "1",
  });

  if (manifest.sha256) {
    headers.set("ETag", `\"sha256-${manifest.sha256}\"`);
  }
  if (Number.isFinite(Number(manifest.encodedSize)) && Number(manifest.encodedSize) > 0) {
    headers.set("Content-Length", String(manifest.encodedSize));
  }
  return headers;
}

async function serveLargeAsset(request, env, pathname, contentType) {
  const manifest = await loadChunkManifest(request, env, pathname);
  if (!manifest) {
    return new Response("Web build is not available yet.", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  const headers = chunkedHeaders(manifest, contentType);
  const etag = headers.get("ETag");
  if (etag && request.headers.get("If-None-Match") === etag) {
    return new Response(null, { status: 304, headers });
  }

  if (request.method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }

  // The chunk stream already contains a complete gzip-encoded representation.
  // Cloudflare defaults to encodeBody="automatic" and may compress a response
  // again when Content-Encoding is present. Mark the body as pre-encoded so the
  // browser receives exactly one gzip layer and transparently decodes it before
  // WebAssembly.instantiateStreaming() sees the bytes.
  return new Response(createChunkStream(request, env, manifest.parts), {
    status: 200,
    headers,
    encodeBody: "manual",
  });
}

export async function handleWebAsset(request, env) {
  if (!env.ASSETS) {
    return new Response("Web assets are not configured.", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD" },
    });
  }

  const pathname = new URL(request.url).pathname;
  const contentType = LARGE_WEB_ASSETS.get(pathname);
  if (contentType) {
    return serveLargeAsset(request, env, pathname, contentType);
  }

  return env.ASSETS.fetch(request);
}
