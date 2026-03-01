# Local Model Experiments: MLX-LM vs Ollama vs Gemini

This document records experiments conducted on March 1, 2026 evaluating local AI models
for VoiceInk's transcription enhancement pipeline on an Apple Silicon Mac.

## Background

VoiceInk uses an AI enhancement step after speech-to-text transcription to clean up
grammar, correct vocabulary, remove filler words, and fix speech recognition errors.
Previously, this was done exclusively via cloud APIs (Gemini, OpenAI, etc). These
experiments evaluated whether local inference could replace or complement cloud APIs.

## Hardware

- Apple Silicon Mac (M-series)
- Sufficient unified memory for 7B 4-bit models (~4.5GB)

---

## Experiment 1: Ollama vs MLX-LM Speed

**Goal:** Compare local inference frameworks for basic text enhancement latency.

**Setup:**
- Ollama with Qwen3 4B model (llama.cpp/GGUF format)
- mlx-lm with Qwen2.5-3B-Instruct-4bit (Apple MLX/SafeTensors format)
- Same enhancement prompt and input text

**Results:**

| Framework | Model | Latency | Tokens/sec |
|-----------|-------|---------|------------|
| Ollama | Qwen3 4B | ~44 seconds | ~20-40 tok/s |
| mlx-lm | Qwen2.5-3B-Instruct-4bit | ~380ms | ~230 tok/s |

**Conclusion:** MLX-LM is 5-10x faster than Ollama on Apple Silicon due to native Metal
GPU acceleration. Ollama uses llama.cpp which doesn't optimize for the Apple Neural Engine
the way MLX does.

---

## Experiment 2: Model Size vs Quality (3B vs 7B vs Gemini)

**Goal:** Compare output quality across model sizes using 8 real VoiceInk transcriptions
pulled from the SwiftData database.

**Setup:**
- mlx-community/Qwen2.5-3B-Instruct-4bit (~1.8GB)
- mlx-community/Qwen2.5-7B-Instruct-4bit (~4.5GB)
- Gemini 2.5 Flash (cloud API)
- Same system prompt with custom vocabulary (29 terms)
- 8 historical transcriptions replayed through all 3 models

**Results:**

| Metric | Qwen 3B | Qwen 7B | Gemini 2.5 Flash |
|--------|---------|---------|------------------|
| Avg latency | 1.0-2.5s | 1.0-4.0s | 1.0-3.9s |
| Grammar cleanup | Acceptable | High | High |
| Vocabulary correction | Partial | Full (with context) | Full (with context) |
| Sentence reordering issues | Occasional | Rare | None |

**Key finding (Entry #382 - "chezmoi" test):**
All three models correctly transformed "chez moi as say che moi" into "chezmoi" when the
transcript contained contextual clues ("as in the application"). The vocabulary system
works when context is present.

**Conclusion:** 7B matches Gemini quality for most transcriptions. 3B is adequate for
simple cleanup but occasionally loses context or reorders sentences.

---

## Experiment 3: Phonetic Distance Without Hints

**Goal:** Test whether models can correct severe phonetic mismatches without explicit hints.

**Setup:**
- Test word: "chezmoi" (vocabulary entry)
- Parakeet transcribes it as: "shamua"
- No phonetic hints provided, just the vocabulary word

**Results:**

| Input | Qwen 3B | Qwen 7B | Gemini |
|-------|---------|---------|--------|
| "shamua" (no context) | Failed | Failed | Failed |
| "shamua" (with context: "as in the application") | Failed | Corrected | Corrected |
| "chessmoy" (closer phonetically) | Corrected | Corrected | Corrected |

**Conclusion:** When the phonetic distance is too large (shamua vs chezmoi), no model can
make the connection without either contextual clues or explicit phonetic hints.

---

## Experiment 4: Gemma 3 4B Evaluation

**Goal:** Test whether Google's Gemma 3 model family performs better than Qwen for this
specific task (ASR error correction).

**Setup:**
- mlx-community/gemma-3-4b-it-qat-4bit (QAT quantization, 659k downloads)
- Same prompt and test transcriptions as Experiment 2

**Results:**

| Correction | Qwen 7B | Gemma 3 4B | Gemini |
|-----------|---------|------------|--------|
| "clawed code" -> Claude Code | Partial (first only) | Failed | All corrected |
| "voicing the" -> VoiceInk | Failed | Failed | Corrected |
| General grammar cleanup | Good | Minimal | Good |
| Speed | 4.2s | 3.4s | 7.9s |

**Conclusion:** Gemma 3 4B performed worse than Qwen 7B for transcription enhancement.
It barely cleaned up the text, essentially passing it through with minor changes. Model
size matters more than model family for this task.

---

## Experiment 5: Phonetic Hints

**Goal:** Test whether adding explicit phonetic mistranscription mappings to vocabulary
entries improves correction accuracy.

**Format:** `VoiceInk (often heard as: voicing, voice ink, voice inc)`

**Setup:**
- Added phonetic hints to key vocabulary entries
- Tested with a natural sentence containing all target mistranscriptions:
  "I'm using voicing to dictate into clawed code right now. I need to update my shamua
  configuration and push the changes. The MLX elem model is working pretty well."

**Results (natural sentence with hints):**

| Correction | Qwen 7B (no hints) | Qwen 7B (with hints) | Gemini (with hints) |
|-----------|-------------------|---------------------|-------------------|
| voicing -> VoiceInk | Failed | **Corrected** | **Corrected** |
| clawed code -> Claude Code | **Corrected** | **Corrected** | **Corrected** |
| shamua -> chezmoi | Failed | Failed | **Corrected** |
| MLX elem -> MLXLM | **Corrected** | **Corrected** | **Corrected** |

**Conclusion:** Phonetic hints significantly improve Qwen 7B's correction accuracy. The
7B model went from 2/4 corrections to 3/4 with hints. Only the most extreme phonetic
mismatch (shamua -> chezmoi) still fails on the 7B model. Gemini handles all corrections
with hints.

---

## Experiment 6: Prompt Size Impact (Compact vs Full)

**Goal:** Test whether a shorter, vocabulary-focused prompt improves small model accuracy.

**Setup:**
- Original prompt: ~1,390 words (includes system instructions, clipboard context, window
  context, vocabulary, examples)
- Compact prompt: ~129 words (vocabulary-first, minimal rules)
- Same test sentence with phonetic hints

**Results:**

| Correction | Original prompt (1390w) | Compact prompt (129w) |
|-----------|------------------------|----------------------|
| voicing -> VoiceInk | **Corrected** | **Corrected** |
| clawed code -> Claude Code | **Corrected** | **Corrected** |
| shamua -> chezmoi | Failed | **Corrected** |
| MLX elem -> MLXLM | **Corrected** | **Corrected** |

**The compact prompt achieved 4/4 corrections vs 3/4 for the original prompt on Qwen 7B.**

**Prompt size breakdown (original):**

| Section | Words | Notes |
|---------|-------|-------|
| SYSTEM_INSTRUCTIONS | 630 | Rules, examples, formatting guidelines |
| CLIPBOARD_CONTEXT | ~2-600 | Varies (sometimes just a word, sometimes large) |
| CURRENT_WINDOW_CONTEXT | ~1,200 | Full terminal/app window dump |
| CUSTOM_VOCABULARY | varies | Vocabulary entries |

**Conclusion:** The 7B model's attention is diluted by the large prompt. The window context
(~1,200 words of terminal output) is the biggest contributor to noise. A focused, compact
prompt lets the model spend more capacity on vocabulary matching.

---

## Experiment 7: Context Awareness Toggle

**Goal:** Test real-world transcription quality with screen context disabled.

**Setup:**
- Context Awareness (screen capture) turned OFF in VoiceInk settings
- MLX-LM provider with Qwen 7B
- Natural dictation about development tools

**Raw transcript:** "I'm trying to talk about the voicing gap with you, Claude Code, to
see if these smaller models, Quinn, are better than using Gemini... Git Kraken, VS Code,
Visual Studio, JetBrains Writer"

**Results (same prompt, no phonetic hints yet):**

| Issue | Qwen 7B (no context) | Gemini (no context) |
|-------|---------------------|-------------------|
| voicing gap -> VoiceInk app | Failed | **VoiceInk** |
| Quinn -> Qwen | Failed | Removed |
| Git Kraken -> GitKraken | Kept as-is | **GitKraken** |
| JetBrains Writer -> Rider | Failed | **JetBrains Rider** |

**Conclusion:** Gemini's world knowledge allows it to infer corrections (JetBrains Writer
-> Rider) that no amount of vocabulary can teach a 7B model. However, turning off context
awareness reduced prompt size significantly and is recommended for local models.

---

## Summary of Recommendations

### For Local Models (MLX-LM with Qwen 7B)
1. **Use phonetic hints** on vocabulary entries for words that are commonly mistranscribed
2. **Turn off screen context** to reduce prompt noise (toggle in VoiceInk menu bar)
3. **Keep clipboard context** on (usually small, often helpful)
4. **Consider a compact prompt** optimized for smaller models (future feature)
5. **7B is the minimum** for acceptable quality; 3B loses too much context

### For Cloud Models (Gemini)
1. **Keep all context enabled** -- Gemini benefits from the extra signal
2. **Phonetic hints still help** but are less critical due to Gemini's world knowledge
3. **Full prompt is fine** -- Gemini handles long prompts without attention dilution

### Speed vs Quality Tradeoff

| Provider | Avg Latency | Quality | Privacy | Cost |
|----------|-------------|---------|---------|------|
| MLX-LM Qwen 7B | 1-4s | Good (with hints) | Full | Free |
| MLX-LM Qwen 3B | 0.5-2.5s | Acceptable | Full | Free |
| Gemini 2.5 Flash | 1-8s | Excellent | None | API fees |
| Ollama Qwen3 4B | 20-44s | Good | Full | Free |

### Key Vocabulary Entries That Need Phonetic Hints

| Word | Common mistranscriptions |
|------|-------------------------|
| VoiceInk | voicing, voice ink, voice inc, voice link |
| chezmoi | shamua, shemwa, chessmoy, chez moi, chambois |
| MLXLM | MLX LM, MLX elem, mxlxm |
| claude.md | claud.md |
| Wispr Flow | whisperflow |
| Avalonia UI | avaloni |

**Note:** "Claude" and "Claude Code" intentionally have no phonetic hints. See Experiment 8
below for why hints like "claw, clawed, cloud" cause more harm than good.

---

## Experiment 8: Phonetic Hint Overcorrection

**Goal:** Test whether phonetic hints on common-sounding words cause false corrections.

**Background:** The auto-generated phonetic hints for "claude" included `sladcode, claw,
cloud, clawed`. These were discovered by mining transcription history for patterns where the
AI enhancement corrected raw text to "claude."

**Setup:**
- Test sentence (raw): "the dog clawed me and I looked that up in clawed code to see what
  it might be, and then I found out that that person was such a clod"
- Expected: "clawed me" preserved, "clawed code" -> "Claude Code", "clod" preserved
- Tested with Gemini 2.5 Flash using progressively fewer hints

**Results:**

| Hints on "claude" | "dog clawed me" | "clawed code" | "a real clod" |
|-------------------|-----------------|---------------|---------------|
| sladcode, claw, cloud, clawed | claude.md | claude code | claude |
| claw, clawed | the dog claude | claude code | clod |
| *(none)* | **clawed me** | **claude code** | **clod** |

**Analysis:** Even Gemini overcorrects real English words when they appear as phonetic hints.
The hints tell the model "when you see 'clawed', it probably means 'claude'" which overrides
contextual understanding. With no hints, "claude code" as a compound vocabulary entry is
sufficient -- the model uses context to distinguish "the dog clawed me" from "Claude Code."

**Conclusion:** Phonetic hints should only be added for words that are NOT common English
words. Hints like "voiceync" -> VoiceInk or "chambois" -> chezmoi are safe because they
aren't real words. Hints like "claw" or "cloud" are dangerous because they suppress
legitimate uses of those words.

---

## Experiment 9: Transcription Model Comparison (Parakeet V2 vs Large v3 Turbo)

**Goal:** Compare transcription models on the same vocabulary-heavy input.

**Setup:**
- Same test sentence spoken twice, once with each model
- AI enhancement by Qwen 7B via MLX-LM
- Vocabulary words in transcription prompt (bare words only, no hint annotations)

**Results (raw transcription):**

| Phrase | Parakeet V2 | Large v3 Turbo |
|--------|-------------|----------------|
| Claude Code | Claude Code | Cloud Code |
| claude.md | claude.md | Cloud.md |
| VoiceInk | Voice Inc | Voice Link |
| dog clawed me | dog clawed me | dog clawed me |
| a real clod | a real claude | a real clawed |
| blood clot | blood clot | blood clot |
| drain clogged | drain is clocked | drain got clogged |

**Results (after AI enhancement):**

Both models' output was corrected to the same quality by the Qwen 7B enhancement:
- "Cloud Code" / "Voice Link" -> Claude Code / VoiceInk (corrected by enhancement)
- "dog clawed me" preserved correctly by both pipelines
- "blood clot" preserved correctly by both pipelines
- "drain got clogged" recovered by v3 Turbo pipeline (Parakeet had "clocked")
- "clod" lost by both (transcription-level ambiguity, not recoverable)

**Conclusion:** Each transcription model has different strengths. Parakeet handles proper
nouns better (Claude, claude.md); v3 Turbo handles common words better (clogged). The AI
enhancement layer compensates for most transcription errors regardless of which model is
used. The only unrecoverable cases are where the transcription model produces a grammatically
valid alternative (clod -> claude/clawed).

---

## Experiment 10: Separating Vocabulary for Transcription vs Enhancement

**Goal:** Optimize what vocabulary information reaches each stage of the pipeline.

**Background:** VoiceInk was passing the full vocabulary string including phonetic hint
annotations to both the transcription model and the AI enhancement model:
```
Important Vocabulary: claude (often heard as: claw, clawed), VoiceInk (often heard as: voiceync)...
```

The transcription model (Whisper/Parakeet) uses the prompt as conditioning text -- it biases
recognition toward words in the prompt but cannot interpret instructions like "often heard
as." The `(often heard as: ...)` annotations waste prompt tokens and add noise.

**Change:** Split vocabulary formatting into two methods:
- `getTranscriptionVocabulary()` -- bare word list for biasing speech recognition
- `getCustomVocabulary()` -- full annotations with phonetic hints for AI enhancement

**Transcription prompt (before):**
```
Hello, how are you doing? Important Vocabulary: claude (often heard as: claw, clawed),
VoiceInk (often heard as: voiceync, voicelink, voiceinc, voice inc), chezmoi (often
heard as: chambois)...
```

**Transcription prompt (after):**
```
Hello, how are you doing? claude, claude code, claude.md, VoiceInk, chezmoi...
```

**Conclusion:** The transcription model gets a cleaner, shorter conditioning prompt with
just the words it needs to bias recognition. The AI enhancement model continues to receive
the full phonetic hint annotations it can interpret and act on.

---

## Summary of Recommendations

### For Local Models (MLX-LM with Qwen 7B)
1. **Use phonetic hints** on vocabulary entries for words that are commonly mistranscribed
2. **Avoid hints that are real English words** -- they cause overcorrection (see Experiment 8)
3. **Turn off screen context** to reduce prompt noise (toggle in VoiceInk menu bar)
4. **Keep clipboard context** on (usually small, often helpful)
5. **Consider a compact prompt** optimized for smaller models (future feature)
6. **7B is the minimum** for acceptable quality; 3B loses too much context

### For Cloud Models (Gemini)
1. **Keep all context enabled** -- Gemini benefits from the extra signal
2. **Phonetic hints still help** but are less critical due to Gemini's world knowledge
3. **Full prompt is fine** -- Gemini handles long prompts without attention dilution
4. **Same overcorrection risk** -- even Gemini overcorrects with aggressive hints

### Speed vs Quality Tradeoff

| Provider | Avg Latency | Quality | Privacy | Cost |
|----------|-------------|---------|---------|------|
| MLX-LM Qwen 7B | 1-4s | Good (with hints) | Full | Free |
| MLX-LM Qwen 3B | 0.5-2.5s | Acceptable | Full | Free |
| Gemini 2.5 Flash | 1-8s | Excellent | None | API fees |
| Ollama Qwen3 4B | 20-44s | Good | Full | Free |

---

## Technical Details

### mlx-lm Server Setup
```bash
# Install
brew install mlx-lm

# Start server (requires HuggingFace auth for gated models)
KMP_DUPLICATE_LIB_OK=TRUE mlx_lm.server \
  --model mlx-community/Qwen2.5-7B-Instruct-4bit \
  --port 8090
```

### VoiceInk Integration
- Provider: `AIProvider.local` ("MLX-LM" in UI)
- Client: `LocalMLXClient.swift` (OpenAI-compatible, no API key)
- Service: `LocalMLXService.swift` (connection check, model discovery)
- Auto-start: VoiceInk launches mlx_lm.server automatically when MLX-LM is selected
- API: OpenAI-compatible at `http://localhost:8090/v1/chat/completions`

### Phonetic Hints Implementation
- Model: `VocabularyWord.phoneticHints` field (String)
- Prompt format: `VoiceInk (often heard as: voicing, voice ink, voice inc)`
- UI: Expandable chip in Dictionary view with text field for hints
- Auto-generation: `PhoneticHintMiningService` mines transcription history for patterns
- Plausibility filter: Rejects morphological variants, abbreviations, containment patterns,
  and pairs with low bigram similarity (threshold 0.30)
- Transcription prompt: Bare word list only (no hint annotations) to avoid wasting tokens

### Auto-Generate Phonetic Hints
- Toggle: Post Processing settings -> "Auto-generate Phonetic Hints"
- Manual: Dictionary view -> "Generate Hints" button scans full transcription history
- Service: `PhoneticHintMiningService` compares raw vs enhanced text using `VocabularyDiffEngine`
- Filter: `isPlausiblePhoneticHint()` applies morphological, abbreviation, containment,
  and bigram similarity checks to reject false patterns
- Review: Discovered hints are presented in a sheet for user approval before applying
