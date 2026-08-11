const LARGE_WEB_ASSETS = new Map([
  ["/index.wasm", "application/wasm"],
  ["/index.pck", "application/octet-stream"],
]);

function assetRequest(request, pathname) {
  const url = new URL(request.url);
  url.pathname = pathname;
  url.search = "";
  return new Request(url.toString(), {
    method: "GET",
    headers: {
      "Accept-Encoding": "identity",
      "Cache-Control": "no-cache",
    },
  });
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

function decodedAssetStream(request, env, manifest) {
  const source = createChunkStream(request, env, manifest.parts);
  const encoding = String(manifest.contentEncoding || "identity").toLowerCase();

  if (encoding === "gzip") {
    return source.pipeThrough(new DecompressionStream("gzip"));
  }
  if (encoding === "identity" || encoding === "") {
    return source;
  }

  throw new Error(`Unsupported web asset encoding: ${encoding}`);
}

function decodedHeaders(manifest, contentType) {
  const headers = new Headers({
    "Content-Type": manifest.contentType || contentType,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-AI-Town-Chunked-Asset": "1",
    "X-AI-Town-Manifest-Version": String(manifest.version || 0),
    "X-AI-Town-Source-Encoding": String(manifest.contentEncoding || "identity"),
  });

  if (manifest.sha256) {
    headers.set("ETag", `\"sha256-${manifest.sha256}-decoded\"`);
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

  const headers = decodedHeaders(manifest, contentType);

  if (request.method === "HEAD") {
    if (Number.isFinite(Number(manifest.originalSize)) && Number(manifest.originalSize) > 0) {
      headers.set("Content-Length", String(manifest.originalSize));
    }
    return new Response(null, { status: 200, headers, encodeBody: "manual" });
  }

  try {
    return new Response(decodedAssetStream(request, env, manifest), {
      status: 200,
      headers,
      encodeBody: "manual",
    });
  } catch (error) {
    return new Response(`Failed to prepare web asset: ${error?.message || error}`, {
      status: 500,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }
}

export async function getWebAssetStatus(request, env) {
  const wasm = await loadChunkManifest(request, env, "/index.wasm");
  const pck = await loadChunkManifest(request, env, "/index.pck");
  return Response.json({
    ok: Boolean(wasm && pck),
    wasm: wasm ? {
      version: wasm.version || 0,
      encoding: wasm.contentEncoding || "identity",
      parts: wasm.parts.length,
      originalSize: wasm.originalSize || null,
    } : null,
    pck: pck ? {
      version: pck.version || 0,
      encoding: pck.contentEncoding || "identity",
      parts: pck.parts.length,
      originalSize: pck.originalSize || null,
    } : null,
  }, {
    headers: { "Cache-Control": "no-store" },
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
  if (pathname === "/web-health") {
    return getWebAssetStatus(request, env);
  }

  const contentType = LARGE_WEB_ASSETS.get(pathname);
  if (contentType) {
    return serveLargeAsset(request, env, pathname, contentType);
  }

  return env.ASSETS.fetch(request);
}
