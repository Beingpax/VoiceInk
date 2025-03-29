import Foundation

@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = UserDefaults.standard.transcriptionPrompt {
        didSet {
            UserDefaults.standard.transcriptionPrompt = transcriptionPrompt
        }
    }
    
    private var dictionaryWords: [String] = []
    private let saveKey = UserDefaultsKeys.WhisperPrompts.savedPrompts
    
    // Language-specific base prompts
    private let languagePrompts: [String: String] = [
        // English
        "en": "Hello, how are you doing? Nice to meet you.",
        
        // Asian Languages
        "hi": "नमस्ते, कैसे हैं आप? आपसे मिलकर अच्छा लगा।",
        "bn": "নমস্কার, কেমন আছেন? আপনার সাথে দেখা হয়ে ভালো লাগলো।",
        "ja": "こんにちは、お元気ですか？お会いできて嬉しいです。",
        "ko": "안녕하세요, 잘 지내시나요? 만나서 반갑습니다.",
        "zh": "你好，最近好吗？见到你很高兴。",
        "th": "สวัสดีครับ/ค่ะ, สบายดีไหม? ยินดีที่ได้พบคุณ",
        "vi": "Xin chào, bạn khỏe không? Rất vui được gặp bạn.",
        "yue": "你好，最近點呀？見到你好開心。",
        
        // European Languages
        "es": "¡Hola, ¿cómo estás? Encantado de conocerte.",
        "fr": "Bonjour, comment allez-vous? Ravi de vous rencontrer.",
        "de": "Hallo, wie geht es dir? Schön dich kennenzulernen.",
        "it": "Ciao, come stai? Piacere di conoscerti.",
        "pt": "Olá, como você está? Prazer em conhecê-lo.",
        "ru": "Здравствуйте, как ваши дела? Приятно познакомиться.",
        "pl": "Cześć, jak się masz? Miło cię poznać.",
        "nl": "Hallo, hoe gaat het? Aangenaam kennis te maken.",
        "tr": "Merhaba, nasılsın? Tanıştığımıza memnun oldum.",
        
        // Middle Eastern Languages
        "ar": "مرحباً، كيف حالك؟ سعيد بلقائك.",
        "fa": "سلام، حال شما چطور است؟ از آشنایی با شما خوشوقتم.",
        "he": ",שלום, מה שלומך? נעים להכיר",
        
        // South Asian Languages
        "ta": "வணக்கம், எப்படி இருக்கிறீர்கள்? உங்களை சந்தித்ததில் மகிழ்ச்சி.",
        "te": "నమస్కారం, ఎలా ఉన్నారు? కలవడం చాలా సంతోషం.",
        "ml": "നമസ്കാരം, സുഖമാണോ? കണ്ടതിൽ സന്തോഷം.",
        "kn": "ನಮಸ್ಕಾರ, ಹೇಗಿದ್ದೀರಾ? ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿ ಸಂತೋಷವಾಗಿದೆ.",
        "ur": "السلام علیکم، کیسے ہیں آپ؟ آپ سے مل کر خوشی ہوئی۔",
        
        // Default prompt for unsupported languages
        "default": ""
    ]
    
    init() {
        loadDictionaryItems()
        updateTranscriptionPrompt()
        
        // Setup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleLanguageChange() {
        updateTranscriptionPrompt()
    }
    
    private func loadDictionaryItems() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        
        if let savedItems = try? JSONDecoder().decode([DictionaryItem].self, from: data) {
            let enabledWords = savedItems.filter { $0.isEnabled }.map { $0.word }
            dictionaryWords = enabledWords
            updateTranscriptionPrompt()
        }
    }
    
    func updateDictionaryWords(_ words: [String]) {
        dictionaryWords = words
        updateTranscriptionPrompt()
    }
    
    private func updateTranscriptionPrompt() {
        // Get the currently selected language from UserDefaults
        
        let transcriptionServiceType = UserDefaults.standard.transcriptionServiceType
        let selectedLanguage: String
        switch transcriptionServiceType {
        case .local:
            selectedLanguage = UserDefaults.standard.selectedLanguage ?? "en"
        case .cloud:
            selectedLanguage = UserDefaults.standard.cloudTranscriptionLanguage ?? "en"
        }
        
        // Get the appropriate base prompt for the selected language
        let basePrompt = languagePrompts[selectedLanguage] ?? languagePrompts["default"]!
        
        var prompt = basePrompt
        var allWords = ["VoiceInk"]
        allWords.append(contentsOf: dictionaryWords)
        
        if !allWords.isEmpty {
            prompt += "\nImportant words: " + allWords.joined(separator: ", ")
        }
        
        transcriptionPrompt = prompt
    }
    
    func saveDictionaryItems(_ items: [DictionaryItem]) async {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
            let enabledWords = items.filter { $0.isEnabled }.map { $0.word }
            dictionaryWords = enabledWords
            updateTranscriptionPrompt()
        }
    }
} 
