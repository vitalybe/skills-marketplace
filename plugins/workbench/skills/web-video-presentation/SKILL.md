---
name: web-video-presentation
description: Build a video-like, auto-playing single-file HTML presentation (scenes, camera moves, animated UI, scrubber) from a script, using a Sonnet builder and an Opus reviewer. Use when the user wants a product demo or explainer "video" that is really a web page, or says "make a video from this script".
---

# Web video presentation

A single HTML file that plays like a video: a script turned into scenes, with smooth camera moves, animated screens and a play/pause scrubber. It plays in the browser.

## 1. Ask first (one AskUserQuestion, max 4 questions)

- What the overview or home view shows (for example the groups on an org map), if the script has one.
- How it ends (final result card, roadmap card, or both).
- Voiceover: on-screen text only (default), browser speech, or audio later.
- Output: HTML only (default).

## 2. Roles

- **Sonnet builds.**
- **Opus reviews, read-only.** It screenshots many timestamps and reports defects; the builder makes the edits.
- Send review fixes back to the same builder with SendMessage so it keeps its context.
- Use Haiku for exploration.

## 3. How it works (give the builder this structure)

- **One file**, `index.html`, plain HTML/CSS/JS, target 3-5 minutes.
- **One master timeline.** A single `render(t)` function draws the whole frame from the time `t` alone, so play, pause, scrub and seek all show the right picture.
- **Scenes as data.** The script becomes a list of scenes (start time, end time, title, tag). Each scene lists its beats (what appears, moves or changes at which second).
- **A stage.** A 16:9 canvas scaled to fit the viewport, with every scene's content on layers inside it.
- **A camera.** One transform (scale and position) on the stage, animated with easing between keyframes. It zooms from the home view into a screen, punches in on a detail, and zooms back out.
- **Screens as panels.** Each screen is an HTML/CSS panel (recreated from the user's screenshots or the codebase's styles) that fades in over the previous one.
- **Controls.** Space (play/pause), arrows (seek 5 s, shift 30 s), scrubber with scene markers, `F` for fullscreen, `?t=SECONDS` to open at a time, autoplay on load with a Play button as fallback.

## 4. The experience

- Smooth: eased moves, 60 fps, cheap per-frame work.
- Readable: hold each screen 3-5 s before punching in, and give text enough time to read.
- Continuous: scenes flow into each other with overlapping fades and camera moves.
- Paced: something changes at least every 3 s, and beats have room to breathe.
- Consistent: the same names, numbers and labels in every scene.

## 5. Toolbox (use what the script needs)

Pick from these to show what the user wants to show. Each one is driven by `t` and anchored to real elements.

- **Overview map:** nodes and arrows, with glowing nodes and pulses travelling along arrows to show handoffs.
- **Zoom and punch-in:** camera keyframes on a screen or an element.
- **Typing and chat:** messages typed out, collapsed "N steps" rows, chat bubbles.
- **Cursor and clicks:** a cursor that moves to a button, hovers, presses and shows the confirmed state.
- **Rings:** a highlight ring on an element, measured from the element each frame.
- **Status tags and badges:** a tag per scene (for example TODAY or FUTURE) and a "coming next" badge where it applies.
- **Annotation cards:** when the user wants to display information at a moment in the video. A short bold title plus one line, placed next to the thing it explains, fading in and out (about 0.4 s), one or two at once, 3-6 s on screen. Keep all cards in one array (start, end, position, title, text, target). Key lines from the script appear verbatim and larger.

## 6. Content

Follow the user's script, scene by scene. When the user corrects what a scene should show, change it.

## 7. Review loop

1. Builder reports, with screenshots of about 30 timestamps.
2. Opus review (read-only), at 1920x1080 and 1280x720: clipping, overlap, text cut off at zoom edges, rings off target, empty frames and muddy crossfades at scene boundaries, pacing, story logic, number consistency, JS errors, real-time smoothness.
3. Send the prioritized list to the builder, then re-check only the changed timestamps.
4. Stop when Opus says clean or the remaining items are cosmetic. Say what was never viewed by eye.

## 8. Hand-back

Report the file path, total length, scene start times, how to run, and the known rough edges. Offer a final Opus pass.
