# Integrating whisper.cpp into a C# WPF Application on Windows

This document summarizes research on using `whisper.cpp` (a C++ implementation of OpenAI's Whisper model) within a C# WPF application environment on Windows.

## 1. Pre-built `whisper.cpp` DLLs for Windows

*   **Source:** Pre-compiled DLLs for `whisper.cpp` and its dependency `ggml` are not typically offered as direct release assets on the main `ggerganov/whisper.cpp` GitHub releases page.
*   **GitHub Actions Artifacts:** However, the project's Continuous Integration (CI) system (GitHub Actions) automatically builds these DLLs. These can be found as artifacts in successful CI run logs.
    *   **Example CI Run with Artifacts:** `https://github.com/ggml-org/whisper.cpp/actions/runs/15490317930` (link may become outdated as new runs occur; always check recent successful "CI" workflow runs on the Actions tab of the `ggerganov/whisper.cpp` repository).
    *   **Relevant DLLs (for x64):**
        *   `whisper_x64.dll` (the main library)
        *   `ggml_x64.dll` (core tensor library used by `whisper.cpp`)
        *   Potentially `ggml_base_x64.dll`, `ggml_cpu_x64.dll` depending on the exact build configuration and how ggml is linked. The CI run linked above produced these separately.
*   **Requirements/Dependencies:**
    *   Using these DLLs will require the **Visual C++ Redistributable** corresponding to the MSVC version used by the GitHub Actions runners that compiled them (usually a recent version like VS 2019 or 2022).
    *   CPU supporting AVX and AVX2 is often assumed for standard builds, though some builds might offer non-AVX variants.
*   **`whisper.h` Version:** The `whisper.h` header file version would correspond to the version in the `whisper.cpp` repository at the specific commit the CI run used to build the DLLs.

**Note:** Artifacts from GitHub Actions expire after a certain period (typically 90 days). For long-term use or specific versions, compiling from source or using a .NET wrapper library that manages these binaries is recommended.

## 2. Compiling `whisper.cpp` on Windows

If pre-built DLLs are not suitable (e.g., need a specific commit, different compile options, or artifacts are expired), `whisper.cpp` can be compiled on Windows:

*   **Method:** The primary method is using **CMake** with a C++ compiler like **MSVC** (Microsoft Visual C++, included with Visual Studio Community Edition).
*   **Basic Steps (MSVC):**
    1.  Clone the `whisper.cpp` repository: `git clone https://github.com/ggml-org/whisper.cpp.git`
    2.  Navigate to the directory: `cd whisper.cpp`
    3.  Create a build directory: `cmake -B build`
    4.  Build the project (Release configuration is recommended for performance): `cmake --build build --config Release`
*   **Building as a DLL:**
    *   The `whisper.cpp` `CMakeLists.txt` is configured to build `whisper` as a shared library (DLL on Windows) by default when appropriate options are set or not overridden.
    *   The CMake option `BUILD_SHARED_LIBS=ON` is standard for explicitly requesting shared libraries, e.g., `cmake -B build -DBUILD_SHARED_LIBS=ON`. However, the project's CMake file might handle this implicitly for the library target.
    *   The CI builds demonstrate that DLLs are produced, so the CMake setup supports this.
*   **Dependencies for Compilation:**
    *   CMake.
    *   Visual Studio with the "Desktop development with C++" workload installed.
*   **CMake Flags for Specific Features:**
    *   For GPU support (CUDA, OpenCL, etc.) or other specific backends (OpenBLAS, CoreML, OpenVINO), additional CMake flags are needed (e.g., `-DGGML_CUDA=ON`, `-DWHISPER_OPENVINO=ON`). These also require installing the respective SDKs/drivers. For a standard CPU-based DLL, these are typically off.

## 3. C# P/Invoke Examples for `whisper.cpp`

Directly using P/Invoke requires defining C# signatures for the C functions in `whisper.h`, and manually managing memory and data marshalling.

*   **Key Data Structures (from `whisper.h`):**
    *   `struct whisper_context_params`
    *   `struct whisper_full_params`
    *   Callbacks like `whisper_new_segment_callback`, `whisper_progress_callback`.
*   **Core Functions (from `whisper.h`):**
    *   `whisper_init_from_file_with_params()` / `whisper_init_from_buffer_with_params()`: To load a model.
    *   `whisper_full()` / `whisper_full_parallel()`: To run transcription on audio data.
    *   `whisper_full_n_segments()` / `whisper_full_n_segments_from_state()`: To get the number of transcribed segments.
    *   `whisper_full_get_segment_text()` / `whisper_full_get_segment_text_from_state()`: To get the text of a segment.
    *   `whisper_free()` / `whisper_free_state()`: To release resources.

**Recommendation:** Instead of writing P/Invoke code from scratch, using a well-maintained C# wrapper library is highly recommended.

## 4. Popular C# Bindings/Libraries for `whisper.cpp`

The official `whisper.cpp` README lists several .NET bindings. The most promising for general C# WPF applications is:

### [sandrohanea/Whisper.net](https://github.com/sandrohanea/whisper.net)

*   **Popularity:** Good (700+ stars, 100+ forks).
*   **Maintenance:** Actively maintained, with recent releases and CI. Uses `whisper.cpp` as a Git submodule, making it easy to track the underlying native code version.
*   **Ease of Use:**
    *   Provides NuGet packages for easy integration (`Whisper.net.AllRuntimes`, `Whisper.net`, `Whisper.net.Runtime`, etc.).
    *   Offers a high-level C# API that abstracts P/Invoke complexities.
    *   Includes examples for simple usage, NAudio integration, Blazor, and various hardware acceleration backends.
*   **Native DLL Handling:**
    *   The NuGet packages bundle the required native `whisper.dll` and `ggml.dll` (and variants for different hardware acceleration like CUDA, CoreML, OpenVINO, Vulkan).
    *   Supports Windows (x86, x64, ARM64), Linux, macOS, Android, iOS, and WebAssembly.
    *   Provides a `Whisper.net.Runtime.NoAvx` package for CPUs without AVX support.
*   **Dependencies:**
    *   For Windows: Microsoft Visual C++ Redistributable (VS 2019 or newer).
*   **P/Invoke Implementation:** Handles all P/Invoke calls internally. Users interact with a managed C# API.
*   **Key Features:**
    *   Model management (including downloading ggml models).
    *   Stream processing.
    *   Callback support for new segments and progress.
    *   Configuration of whisper parameters.

**Example Usage (`Whisper.net`):**
```csharp
// Ensure ggml model file (e.g., "ggml-base.bin") is available
using var whisperFactory = WhisperFactory.FromPath("ggml-base.bin");

using var processor = whisperFactory.CreateBuilder()
    .WithLanguage("auto") // Or specific language e.g., "en"
    .Build();

using var fileStream = File.OpenRead("path_to_your_audio.wav"); // Needs to be 16kHz mono WAV

await foreach (var segment in processor.ProcessAsync(fileStream))
{
    Console.WriteLine($"[{segment.Start}ms -> {segment.End}ms]: {segment.Text}");
}
```

### Other Bindings

*   **NickDarvey/whisper:** Also listed in `whisper.cpp` README. Less popular, primarily F#, and seems less actively maintained compared to `sandrohanea/Whisper.net`.

**Overall Recommendation for C# WPF:**
Using the **`sandrohanea/Whisper.net`** library is the most straightforward and robust approach. It simplifies development significantly by handling native binaries and providing a managed API. This avoids the need for manual DLL compilation and P/Invoke implementation.
