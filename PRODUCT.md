# Ultra Transcribe
<!-- impeccable:product-schema 1 -->

## Platform
Native macOS, Apple Silicon, macOS 15 or later. Menu-bar agent app.

## Stack
SwiftUI and AppKit (NSStatusItem, NSPopover, NSMenu), Core Audio process tap and AVFoundation recording, local MLX Qwen3-ASR in an isolated Python runtime, OpenRouter for on-demand analysis.

## Users
A team lead in surprise calls with colleagues who speak English and Saudi Arabic.

## Product Purpose
Start recording from the menu bar in one click, get an accurate transcript that shows who said what, and turn it into actionable meeting notes on demand.

## Capabilities and Constraints
Menu-bar first: left-click panel, right-click native menu, no Dock icon. Auto-named meetings, renamable. Separate You (microphone) and Colleagues (Mac audio) tracks. Local transcription only; no local language model. AI analysis only on explicit click, transcript text only, through the user's OpenRouter key and chosen model, with editable templates. Transcription happens after stopping, not live. No per-person diarization inside the Colleagues track.

## Brand Commitments
Warm paper surfaces, orange record controls, dot-matrix waveform, monospaced uppercase metadata, compact recorder. You is green, Colleagues is orange.

## Product Principles
Fast and stealthy. Omit what isn't needed. Audio never leaves the Mac. Errors keep recordings recoverable.
