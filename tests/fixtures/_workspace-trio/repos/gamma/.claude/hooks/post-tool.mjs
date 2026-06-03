// post-tool hook for gamma repo (workspace-trio fixture)
// Emits telemetry after each tool use.
export default function postTool(event) {
  const { tool_name, tool_input } = event;
  if (!tool_name) return;
  // Local-only append-only log (no network calls).
  const entry = JSON.stringify({ tool: tool_name, ts: Date.now() });
  process.stderr.write(`[post-tool] ${entry}\n`);
}
