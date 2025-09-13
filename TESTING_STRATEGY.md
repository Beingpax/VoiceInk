# Testing Strategy for VoiceInk on Windows

A robust testing strategy is essential for ensuring the quality, reliability, and maintainability of the VoiceInk application. This document outlines a multi-layered testing approach, including unit tests, integration tests, and manual UI testing.

## 1. Unit Testing

Unit tests are fast, isolated tests that verify the smallest individual components (units) of the application. They should form the foundation of the testing pyramid.

*   **Framework:** **xUnit** is recommended as a modern, flexible, and powerful testing framework for .NET.
*   **Mocking:** **Moq** is the recommended library for creating mock objects. Mocking is essential for isolating the unit under test from its dependencies (e.g., filesystem, network, or complex services).
*   **What to Test:**
    *   **Services:** All logic within services that does not directly depend on the UI or native handles. For example, a `DictionaryService` that manages word replacements.
    *   **ViewModels:** The logic within any ViewModels used in an MVVM architecture (e.g., data transformation, command logic).
    *   **Utility Classes:** Any helper or utility classes.

### Example Unit Test (Conceptual)

This example shows how you might test a hypothetical `DictionaryService`.

```csharp
// In a separate xUnit Test Project

using Xunit;
using Moq;

// Assume we have a service that replaces words
public class DictionaryService
{
    public virtual string ApplyReplacements(string inputText)
    {
        // In a real implementation, this would use a user-defined dictionary
        if (inputText.Contains("test input"))
        {
            return "test output";
        }
        return inputText;
    }
}

public class DictionaryServiceTests
{
    [Fact]
    public void ApplyReplacements_GivenMatchingText_ReturnsReplacedText()
    {
        // Arrange
        var service = new DictionaryService();
        var inputText = "This is a test input sentence.";
        var expectedText = "test output";

        // Act
        var result = service.ApplyReplacements(inputText);

        // Assert
        Assert.Equal(expectedText, result);
    }
}
```

## 2. Integration Testing

Integration tests verify that different components of the application work together correctly. They are slower than unit tests but provide more confidence in the system as a whole.

*   **What to Test:**
    *   **Transcription Pipeline:** The most critical integration test is the end-to-end flow of recording audio, processing it with `Whisper.net`, and receiving text.
    *   **Settings Persistence:** Tests that save settings, close the service, re-open it, and verify the settings were loaded correctly.
    *   **Database/File Interaction:** Any component that reads from or writes to the filesystem or a database.

### Example Integration Test Strategy

1.  Create a short, pre-recorded WAV file containing a known phrase (e.g., "Hello world").
2.  The test will read this audio file into a stream.
3.  It will initialize the *actual* `Whisper.net` processor with a small, fast model (like `ggml-tiny.en.bin`).
4.  It will process the audio stream.
5.  The test will assert that the transcribed text contains "Hello world".

## 3. Manual UI Testing

Manual testing is required to verify the user experience and visual aspects of the application that are difficult to automate.

### Manual Test Checklist (for current PoC + Hotkey feature)

| Test Case                               | Steps                                                                                                                                                             | Expected Result                                                                                               |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Basic Transcription**                 | 1. Launch app. <br> 2. Click "Record". <br> 3. Speak a phrase. <br> 4. Click "Stop & Transcribe".                                                                      | The spoken phrase appears in the text box.                                                                    |
| **Global Hotkey (App Focused)**         | 1. Launch app. <br> 2. Press `Ctrl+Shift+R`. <br> 3. Speak a phrase. <br> 4. Press `Ctrl+Shift+R` again.                                                               | The spoken phrase appears in the text box. The record/stop buttons update their state correctly.            |
| **Global Hotkey (App in Background)**   | 1. Launch app. <br> 2. Minimize the app window. <br> 3. Press `Ctrl+Shift+R`. <br> 4. Wait a few seconds. <br> 5. Press `Ctrl+Shift+R`. <br> 6. Restore the app window. | The app should have recorded and transcribed the audio captured while it was in the background.             |
| **UI State Management**                 | 1. Click "Record".                                                                                                                                                | "Record" button becomes disabled, "Stop & Transcribe" button becomes enabled. Progress bar is idle.         |
|                                         | 2. Click "Stop & Transcribe".                                                                                                                                     | "Stop" button becomes disabled. Progress bar becomes indeterminate. When done, "Record" button is enabled. |
| **Model Download**                      | 1. Delete the `ggml-base.en.bin` file from the build directory. <br> 2. Run the app and start a transcription.                                                      | The app should state that it is downloading the model before proceeding with the transcription.               |
