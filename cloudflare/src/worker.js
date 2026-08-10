const FALLBACK_CONTENT_TYPES = {
  html: "text/html; charset=utf-8",
  js: "application/javascript; charset=utf-8",
  wasm: "application/wasm",
  pck: "application/octet-stream",
  json: "application/json; charset=utf-8",
  png: "image/png",
  svg: "image/svg+xml",
  ico: "image/x-icon",
  webmanifest: "application/manifest+json",
};

function normalizeKey(pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }

  let key = decoded.replace(/^\/+/, "");
  if (key === "" || key.endsWith("/")) {
    key += "index.html";
  }

  const segments = key.split("/");
  if (segments.some((segment) => segment === "..")) {
    return null;
  }

  return key;
}

function fallbackContentType(key) {
  const filename = key.split("/").pop() || "";
  const dot = filename.lastIndexOf(".");
  if (dot === -1) {
    return "application/octet-stream";
  }
  return FALLBACK_CONTENT_TYPES[filename.slice(dot + 1).toLowerCase()] || "application/octet-stream";
}

function responseHeaders(object, key) {
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  if (!headers.has("content-type")) {
    headers.set("content-type", fallbackContentType(key));
  }
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "public, max-age=0, must-revalidate");
  headers.set("x-content-type-options", "nosniff");
  return headers;
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const url = new URL(request.url);
    const key = normalizeKey(url.pathname);
    if (key === null) {
      return new Response("Bad Request", { status: 400 });
    }

    const object = request.method === "HEAD"
      ? await env.WEB_BUCKET.head(key)
      : await env.WEB_BUCKET.get(key);

    if (object === null) {
      return new Response("Not Found", { status: 404 });
    }

    const headers = responseHeaders(object, key);
    const ifNoneMatch = request.headers.get("if-none-match");
    if (ifNoneMatch && ifNoneMatch === object.httpEtag) {
      return new Response(null, { status: 304, headers });
    }

    return new Response(request.method === "HEAD" ? null : object.body, {
      status: 200,
      headers,
    });
  },
};
