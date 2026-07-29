# Alan `n_parallel` fork findings

## Verdict

`n_parallel=1` is safe for Alan's single-request use and recovers the full
requested context. The Android emulator functional probes passed: the
2,365-token Gemma Full prompt completed at `contextSize=4096`, streaming,
cancellation, and three repeated cycles remained functional, and the warm
Full-generate MemProbe peak fell from 4,046.6 MB at 16384/4 to 3,320.2 MB at
4096/1 (726.4 MB lower, 18.0%). These are emulator PSS measurements despite
the app's legacy "RSS" label, and are not device gate evidence. Raw lines are
in `alan-n-parallel-emulator-evidence.txt`.

## Base and implementation

- Upstream base is exactly
  `3b1351a957920bf2a0df3709cce1e3a7195c479e`.
- Implementation commit is
  `35a9ab186a0e5f9c4a52fb0a299c7630c98d5f5e`.
- The exact implementation diff is
  `0001-Make-n_parallel-configurable-with-a-single-slot-default.patch`.
- `OpenAiRequest.nParallel` and low-level
  `FllamaInferenceRequest.nParallel` both default to 1.
- The Dart-to-FFI request struct now carries `n_parallel`; native
  `run_inference()` validates/falls back to the single-slot default and assigns
  it to `common_params`.
- `n_parallel` is now part of the cached `ServerResources` identity, so an
  idle cached model is rebuilt when the slot count changes.
- The web request path and web default were kept consistent at 1.
- No network call, dependency, permission, or network-shaped app path was
  added.

## Queue and lifetime review

No queue logic assumes four slots:

- Extra completion tasks are deferred when no slot is free and promoted when a
  slot releases (`server-queue.cpp:63-99`,
  `server-context.cpp:1091-1093`). With one slot, concurrent callers serialize.
- fllama cancellation bookkeeping is keyed by the Dart request ID in an
  `unordered_set`, independent of llama.cpp slot IDs
  (`fllama_inference_queue.cpp:221-234`). When a reader stops, its destructor
  posts a high-priority llama.cpp cancel task, including for deferred work
  (`server-queue.h:164-204`, `server-queue.cpp:430-445`).
- The 120-second idle timeout and 30-second cleanup cadence depend on
  `active_users` and `last_used`, not slot count
  (`fllama_inference_queue.cpp:9-10,261-289`). A deferred or active request
  holds an active-user reference, so the context cannot be evicted underneath
  it.
- Context destruction still terminates and joins the dedicated server loop
  (`fllama_inference_queue.cpp:15-19`).

## Remaining risks

1. **Changing load-time parameters while a model is busy still reuses the old
   context.** Existing behavior at `fllama_inference_queue.cpp:92-101` applies
   to `n_ctx`, GPU layers, draft parameters, and now `n_parallel`: the second
   request gets the busy context even when parameters differ. Alan is safe
   because it permits one request at a time and always uses 1. A general-purpose
   upstream-quality follow-up should wait, reject, or key contexts by the full
   load configuration instead of silently reusing mismatched parameters.
2. **The native struct change is an ABI break.** Dart bindings and the native
   library must be built from the same fork commit. Flutter native-assets does
   that in the verified APK; mixing an old binary with the new generated Dart
   struct is unsupported.
3. **Unload behavior is unchanged.** The model remains cached until the
   120–150-second idle-eviction window. This fork answers the slot/context/KV
   issue only.
4. **Memory evidence is emulator-only and warm-cache-sensitive.** The new
   coexistence run followed the acceptance Full run in the same process. The
   warm-to-warm comparison is the least misleading reading; physical-device G3
   remains pending.

## Acceptance results

- Full scenario at 4096/1: PASS, 300 streamed ticks, coherent output, no
  1024-token context error.
- Streaming: PASS via the 300 callback ticks recorded by `Bench`.
- Cancellation: PASS functionally; stream closed 11 ms after the cancel
  request on this emulator.
- Repeated cycles: PASS, three coherent outputs, final MemProbe value
  3,085.3 MB versus 3,077.5 MB before cycle 1.
- Warm Full-generate MemProbe comparison: 3,320.2 MB at 4096/1 versus
  4,046.6 MB at 16384/4.
- Fork tests: 3 passed; analysis: clean.
- Isolated Alan tests: 26 passed; APK build passed. Alan analysis retained its
  pre-existing `avoid_print` info and exited 1.

Every measured input to these findings appears verbatim in
`alan-n-parallel-emulator-evidence.txt`; percentages and deltas are direct
arithmetic from those raw values.
