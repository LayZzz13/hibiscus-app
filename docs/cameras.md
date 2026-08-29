# Hibiscus Camera Characters

This document defines the intended photographic identity and behavior of the ten built-in Hibiscus Camera characters.

These Camera characters are original photographic profiles inspired by broad imaging characteristics such as color-negative film, compact digital cameras, direct flash, instant photography, and monochrome photography. They are not intended to reproduce any specific commercial camera, film stock, sensor, or historical product exactly.

Camera and Grade serve different creative roles:

- **Camera** describes how the image feels captured.
- **Grade** describes how the resulting image is colored afterward.

The descriptions below are creative targets rather than fixed implementation constants. Individual tuning values may evolve, but each Camera should retain its intended photographic identity.

## General Design Principles

Every Camera character should first produce a technically usable and attractive photograph.

Differences should come from intentional combinations of:

- color response;
- tone response;
- highlight behavior;
- shadow behavior;
- contrast;
- sharpening and microcontrast;
- grain or texture;
- bloom or halation where appropriate;
- flash behavior;
- monochrome color response where applicable.

A Camera character should never rely primarily on:

- arbitrary underexposure;
- arbitrary overexposure;
- blur;
- excessive noise;
- haze;
- extreme global color casts.

Image degradation is not a substitute for character. Every Camera should remain sharp, usable, and visually intentional.

---

## ✨ Clear — Clean Modern

**Character:** Neutral · Natural · Modern

### Intent / overview

Clear is the neutral Hibiscus Camera. It produces a clean, natural image with restrained computational character while preserving modern image quality. Clear acts as the quality baseline for the other Camera characters.

### Color

- neutral overall balance;
- natural saturation;
- stable neutrals;
- pleasant, restrained skin response.

### Tone

- clean blacks;
- open midtones;
- gentle highlight rolloff;
- good usable dynamic range.

### Texture

- no obvious artificial grain;
- no deliberate halation;
- minimal bloom;
- restrained sharpening.

### Best suited for

- everyday photography;
- daylight;
- architecture;
- food;
- situations where minimal stylization is preferred.

---

## 🎞️ Negative — Color Negative

**Character:** Warm · Gentle · Photographic

### Intent / overview

Negative is inspired by the broad visual character of consumer color-negative photography, not by any specific film stock or film format.

### Color

- warm mids;
- subtly cooler or slightly green shadows;
- restrained greens;
- controlled reds;
- pleasant skin response.

### Tone

- softer highlight rolloff;
- gentler contrast than Clear;
- softer tonal transitions.

### Texture

- very fine grain;
- restrained bloom;
- subtle warm halation around strong highlights.

### Best suited for

- people;
- travel;
- everyday scenes;
- warm daylight;
- casual documentary photography.

---

## 💿 Digital — Early Digital / CCD

**Character:** Cool · Crisp · Direct

### Intent / overview

Digital is inspired by early compact digital and CCD-era photography. Its identity comes from direct color, firmer tone, and crisp rendering rather than artificial degradation.

### Color

- slightly cool or cyan overall balance;
- vivid blues;
- punchier reds;
- crisp, direct color response.

### Tone

- firmer highlights;
- slightly more limited dynamic-range feeling;
- stronger digital contrast.

### Texture

- crisp rendering;
- restrained sharpening;
- little or no visible artificial noise.

### Best suited for

- daylight snapshots;
- street scenes;
- architecture;
- scenes where a compact-digital character works well.

---

## ⚡️ Flash — Flash Compact

**Character:** Punchy · Direct · Energetic

### Intent / overview

Flash is built around direct-flash compact-camera energy. Its identity should come strongly from flash behavior when flash is used.

### Color

- warmer foreground subjects;
- cooler or slightly green ambient shadows;
- punchy color separation.

### Tone

- stronger contrast;
- deeper blacks;
- direct, energetic tonal response.

### Texture

- controlled medium texture;
- subtle bloom around strong lights;
- no excessive blur or noise.

### Best suited for

- nightlife;
- parties;
- indoor scenes;
- restaurants;
- direct-flash portraits;
- evening snapshots.

---

## 🖼️ Instant — Instant

**Character:** Creamy · Warm · Soft

### Intent / overview

Instant is inspired by soft instant-photo character while preserving useful clarity.

### Color

- creamy warm whites;
- slightly reduced saturation;
- pleasant peach and warm skin response;
- muted blues.

### Tone

- softer contrast;
- gentle black lift;
- smooth highlights.

### Texture

- very subtle texture;
- gentle softness without blur.

### Best suited for

- people;
- food;
- home;
- daylight;
- casual personal photography.

---

## 🎟️ Disposable — Disposable

**Character:** Casual · Imperfect · Daylight

### Intent / overview

Disposable is inspired by inexpensive daylight disposable cameras. It embraces controlled imperfection without sacrificing a usable photograph.

### Color

- slightly stronger yellow and green response;
- straightforward consumer-film color;
- imperfect but usable color separation.

### Tone

- simpler highlight response;
- moderate contrast;
- slightly imperfect corner response.

### Texture

- controlled coarse grain;
- mild vignette;
- clear central detail.

### Best suited for

- outdoor daylight;
- travel;
- beaches;
- casual snapshots;
- intentionally imperfect photography.

---

## 🌙 Night — Night Digital

**Character:** Cool · Luminous · Urban

### Intent / overview

Night is designed specifically for night and artificial-light scenes. It separates illuminated subjects from dark surroundings without globally lifting the image.

### Color

- cool blue and cyan ambient color;
- controlled magenta and cyan response;
- clear separation around artificial light sources.

### Tone

- deep blacks;
- bright subjects without globally lifting exposure;
- stronger night contrast.

### Texture

- restrained texture;
- clean enough to preserve detail.

### Best suited for

- city streets;
- neon;
- convenience stores;
- subway scenes;
- nightlife;
- low-light urban photography.

---

## 🌸 Portrait — Portrait

**Character:** Warm · Gentle · People-focused

### Intent / overview

Portrait is designed primarily around people. It favors pleasant skin response and gentle tonal transitions without becoming a beauty filter.

### Color

- pleasant skin response;
- warm mids;
- controlled reds and magentas;
- restrained greens.

### Tone

- softer highlight rolloff;
- slightly gentler contrast;
- lower microcontrast on skin.

### Texture

- little or no obvious grain;
- no artificial skin smoothing.

### Best suited for

- portraits;
- people;
- indoor social photography;
- daylight portraits.

---

## 🏙️ Street — Street

**Character:** Dense · Graphic · Structured

### Intent / overview

Street is designed for dense, graphic urban photography with strong structural separation and detailed shadows.

### Color

- restrained greens;
- warm neutrals and mids;
- subtly cooler shadows;
- controlled overall saturation.

### Tone

- deep but detailed blacks;
- stronger midtone contrast;
- crisp structural separation.

### Texture

- fine grain;
- strong but controlled microcontrast.

### Best suited for

- streets;
- buildings;
- shadows;
- signage;
- architecture;
- urban scenes.

---

## 🌓 Mono — Monochrome

**Character:** Tonal · Expressive · Monochrome

### Intent / overview

Mono is a dedicated monochrome Camera character. It should translate source color relationships into deliberate grayscale separation rather than merely removing saturation.

### Color response

- different source hues should map intentionally into grayscale;
- reds, yellows, greens, blues, and skin tones should retain useful tonal separation.

### Tone

- deep but detailed blacks;
- smooth highlights;
- medium-to-strong contrast;
- clear grayscale separation.

### Texture

- subtle monochrome grain;
- restrained bloom where useful.

### Best suited for

- portraits;
- architecture;
- street photography;
- high-contrast scenes;
- shape- and texture-focused photography.
