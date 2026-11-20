---
name: image-gen
description: Generate images from a text prompt (optionally with reference images) via OpenRouter's openai/gpt-image-2, using a bundled script that logs cost and enforces a daily spend cap. Use whenever the user asks to generate, create, make or draw an image, picture, illustration, icon, sprite sheet, background or concept art with AI, or to restyle or extend an existing image using references - even if they don't name a model or tool.
---

# image-gen

One script, no dependencies beyond Python 3: `scripts/generate.py` (path relative to this skill's folder).

```bash
python3 <skill-dir>/scripts/generate.py --prompt "..." --out out.png [--ref a.png --ref b.webp] \
  [--size 1536x1024 | --aspect-ratio 3:2] [--quality low|medium|high|auto] [--n N] [--dry-run]
```

(`--prompt-file FILE` instead of `--prompt` for long prompts.)

## Workflow

1. Write the prompt. Say what is in the image, the style, the framing, and what must be absent. Put long prompts in a file.
2. Run with `--dry-run` first when the call is expensive (large `--size`, `--n` > 1, many refs).
3. Generate, then **look at the output** (Read the PNG) before reporting. Iterate on the prompt, not on luck.
4. Report the output path and the cost the script prints.

## Practical notes

- **References** (`--ref`, repeatable, any format) steer identity and style: pass an approved earlier result to keep a character or look consistent. Name each reference's role in the prompt ("the first image is the character, keep her identical").
- **Cost** scales with pixels: about $0.17 at 1536x1024 high, $0.26 at 2304x1536 high, low quality about 0.15x. Use `--quality low` for drafts.
- **Size** is `WxH` in multiples of 16.
- **Transparent assets:** the model has no alpha output. Ask for a flat pure `#00FF00` background with no gradient or shadow and key it out afterwards.
- **Sheets:** several poses or parts in one image cost one call; ask for a fixed grid with clear margins and an empty cell if the count does not fill it.
- The model re-renders the whole image on every call, so "change only X" edits drift elsewhere.

## Key, log, cap

- Key: `$OPENROUTER_API_KEY`, else the 1Password reference in `$IMAGE_GEN_KEY_REF` (default `op://Private/OpenRouter - API keys/music-video-images - key`), read through `~/hq/bin/keychain-secret` then `op read`. If it fails, ask the user to unlock 1Password.
- Log: every call is appended to `$IMAGE_GEN_LOG` (default `~/.cache/image-gen/gen-log.jsonl`).
- Cap: refuses to run once today's logged spend reaches `$IMAGE_GEN_DAILY_CAP` (default 5.00 USD). Do not raise it without asking the user.
- Use only the images endpoint (the script does); the chat endpoint failed for the gpt-5 image models on this account.
