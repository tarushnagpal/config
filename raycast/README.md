# Raycast script commands

## AI Usage (`ai-usage.py`)

Shows Claude and Codex plan limits (session + weekly, with reset times) and Respan spend for your own key (today + this month).

### Setup (macOS)

1. Raycast → Settings → Extensions → **+** → **Add Script Directory** → pick this `raycast/` folder.
2. Search "AI Usage" in Raycast, then set a hotkey on it (Settings → Extensions → AI Usage → Hotkey).
3. Store the Respan key in the keychain (prompts for the value, so it stays out of shell history):

   ```sh
   security add-generic-password -a "$USER" -s respan-api-key -w
   ```

   Alternatively, use `$RESPAN_API_KEY` or `~/.keys/respan_key.txt`.

On first run, macOS asks whether `security` may read the "Claude Code-credentials" keychain item. Choose **Always Allow**.

### Where the data comes from

| Source | How |
| --- | --- |
| Claude | `api.anthropic.com/api/oauth/usage` using Claude Code's OAuth token (read-only; the token is never refreshed here) |
| Codex | `codex app-server` → `account/rateLimits/read`, using Codex's own login |
| Respan | `api.respan.ai/api/request-logs/summary`, filtered to your key (logs are org-wide) |
