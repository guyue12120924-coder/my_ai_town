import agentWorker from "./worker.js";
import { handleWebAsset } from "./web-assets.js";

function isAgentRoute(request) {
  const url = new URL(request.url);
  return request.method === "OPTIONS"
    || url.pathname === "/health"
    || url.pathname.startsWith("/api/");
}

export default {
  async fetch(request, env, ctx) {
    if (isAgentRoute(request)) {
      return agentWorker.fetch(request, env, ctx);
    }
    return handleWebAsset(request, env);
  },
};
