# Cloud Saves (Supabase)

## Overview

CloudSaveManager provides optional cloud save/load via Supabase REST API. Falls back to local save if unconfigured or offline.

## Setup

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Create the `saves` table:

```sql
CREATE TABLE saves (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  save_data JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE saves ENABLE ROW LEVEL SECURITY;

-- Policy: users can only access their own saves
CREATE POLICY "Users manage own saves" ON saves
  FOR ALL USING (auth.uid()::text = user_id);
```

3. Copy `.env.example` to `.env` and fill in your Supabase URL and anon key:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

## Authentication

Three methods available:
- `sign_in_anonymous()` — creates anonymous user (simplest)
- `sign_in_email(email, password)` — email/password login
- `sign_up_email(email, password)` — create new account

All auth responses trigger notifications via EventBus.

## API

| Method | Description |
|--------|-------------|
| `is_configured()` | Returns true if Supabase URL and key are set |
| `is_authenticated()` | Returns true if user is logged in |
| `sign_in_anonymous()` | Create/login anonymous user |
| `sign_in_email(email, password)` | Login with email |
| `sign_up_email(email, password)` | Register with email |
| `cloud_save(save_data)` | Upload save to Supabase |
| `cloud_load()` | Download latest save from Supabase |

## Data Flow

### Save
```
GameManager.save_game() -> local JSON
CloudSaveManager.cloud_save(data) -> POST to Supabase /rest/v1/saves
```

### Load
```
CloudSaveManager.cloud_load() -> GET from Supabase
-> Writes to local save path
-> GameManager reloads
```

## Notifications

All cloud operations post notifications:
- `NOTIF_CLOUD_CONNECTED` — auth success
- `NOTIF_CLOUD_SAVED` — upload success
- `NOTIF_CLOUD_LOADED` — download success
- `NOTIF_CLOUD_AUTH_FAILED` — auth error
- `NOTIF_CLOUD_LOAD_FAILED` — download error
- `NOTIF_CLOUD_NO_SAVE` — no save found
- `NOTIF_CLOUD_NOT_CONFIGURED` — missing config

## Key Files

- `scripts/services/CloudSaveManager.gd` — Supabase HTTP client
- `.env.example` — config template
- `.env` — actual config (git-ignored)
