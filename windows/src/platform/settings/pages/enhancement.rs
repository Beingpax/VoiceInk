//! AI clean-up of transcripts: provider, model, prompt and context.

use super::super::widgets::{
    Builder, CBN_SELCHANGE, CHECK_ROW, CheckBox, ComboBox, Edit, FIELD_W, FIELD_X, Label, ROW, TOP, set_visible,
};
use super::{KeyChanges, KeyField, Page, PageContext, model_override, models_or_default};
use crate::config::{Config, EnhancementProvider};

const ID_PROVIDER: u16 = 1;
const ID_REMOVE_KEY: u16 = 2;
const TIMEOUT_RANGE_SECS: (u64, u64) = (5, 600);

pub struct Enhancement {
    enabled: CheckBox,
    provider: ComboBox,
    model: ComboBox,
    prompt: ComboBox,
    /// Prompt ids in the order of `prompt`'s rows.
    prompt_ids: Vec<String>,
    key: KeyField,
    endpoint_label: Label,
    endpoint: Edit,
    /// Endpoints of the self-hosted providers; the field shows the selected one.
    endpoints: Endpoints,
    window_context: CheckBox,
    clipboard_context: CheckBox,
    selection_context: CheckBox,
    skip_short: CheckBox,
    short_words: Edit,
    timeout: Edit,
}

#[derive(Default)]
struct Endpoints {
    ollama: String,
    custom: String,
    /// The provider whose endpoint the field currently shows.
    shown: Option<EnhancementProvider>,
}

impl Endpoints {
    fn slot(&mut self, provider: EnhancementProvider) -> Option<&mut String> {
        match provider {
            EnhancementProvider::Ollama => Some(&mut self.ollama),
            EnhancementProvider::Custom => Some(&mut self.custom),
            _ => None,
        }
    }
}

fn endpoint_caption(provider: EnhancementProvider) -> Option<&'static str> {
    match provider {
        EnhancementProvider::Ollama => Some("Ollama URL"),
        EnhancementProvider::Custom => Some("Chat endpoint"),
        _ => None,
    }
}

impl Enhancement {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let mut y = TOP;
        let enabled = b.option("Clean up transcripts with AI", y);
        y += ROW;
        b.row_label("Provider", y);
        let provider = b.combo(y, 280, false, ID_PROVIDER);
        y += ROW;
        b.row_label("Model", y);
        let model = b.combo(y, 280, true, 0);
        y += ROW;
        b.row_label("Prompt", y);
        let prompt = b.combo(y, 280, false, 0);
        y += ROW;
        b.row_label("API key", y);
        let key_edit = b.password(y, 230);
        b.button("Remove", FIELD_X + 238, y - 2, 80, ID_REMOVE_KEY);
        let key = KeyField { edit: key_edit, status: b.label("", FIELD_X + 328, y, FIELD_W - 328) };
        y += ROW;
        let endpoint_label = b.row_label("", y);
        let endpoint = b.edit(y, FIELD_W);
        y += ROW + 8;
        b.row_label("Context", y);
        let window_context = b.option("Active window title and app", y);
        y += CHECK_ROW;
        let clipboard_context = b.option("Clipboard text", y);
        y += CHECK_ROW;
        let selection_context = b.option("Selected text (copied when recording starts)", y);
        y += ROW + 4;
        let skip_short = b.check("Skip AI for short dictations of at most", FIELD_X, y, 290);
        let short_words = b.number_at(FIELD_X + 296, y, 50);
        b.label("words", FIELD_X + 352, y, 60);
        y += ROW;
        b.row_label("Timeout (seconds)", y);
        let timeout = b.number(y, 80);
        Self {
            enabled,
            provider,
            model,
            prompt,
            prompt_ids: Vec::new(),
            key,
            endpoint_label,
            endpoint,
            endpoints: Endpoints::default(),
            window_context,
            clipboard_context,
            selection_context,
            skip_short,
            short_words,
            timeout,
        }
    }

    fn selected_provider(&self) -> EnhancementProvider {
        self.provider.pick(&EnhancementProvider::ALL)
    }

    /// Keeps what the user typed into the endpoint field.
    fn remember_endpoint(&mut self) {
        let typed = self.endpoint.trimmed();
        if let Some(slot) = self.endpoints.shown.and_then(|provider| self.endpoints.slot(provider)) {
            *slot = typed;
        }
    }

    fn provider_changed(&mut self, model: Option<&str>, cx: &PageContext<'_>) {
        let provider = self.selected_provider();
        self.model.fill(models_or_default(provider.models(), provider.default_model()));
        self.model.set_text(model.unwrap_or(provider.default_model()));
        self.remember_endpoint();
        self.endpoints.shown = Some(provider);
        let value = self.endpoints.slot(provider).map(|s| s.clone()).unwrap_or_default();
        self.endpoint.set(&value);
        self.endpoint_label.set(endpoint_caption(provider).unwrap_or(""));
        self.show_endpoint();
        self.key.show(provider.credential_key(), cx);
    }

    /// Only Ollama and the custom provider need an endpoint.
    fn show_endpoint(&self) {
        set_visible(self.endpoint.0, endpoint_caption(self.selected_provider()).is_some());
    }

    fn show_prompts(&mut self, config: &Config, selected: &str) {
        self.prompt_ids = config.prompts.iter().map(|p| p.id.clone()).collect();
        self.prompt.fill(config.prompts.iter().map(|p| p.title.as_str()));
        self.prompt.select_value(&self.prompt_ids, &selected.to_string());
    }

    fn selected_prompt(&self) -> Option<&String> {
        self.prompt.selected().and_then(|row| self.prompt_ids.get(row))
    }
}

impl Page for Enhancement {
    fn load(&mut self, config: &Config, cx: &PageContext<'_>) {
        let settings = &config.enhancement;
        self.enabled.set(settings.enabled);
        self.provider.fill(EnhancementProvider::ALL.iter().map(|p| p.display_name()));
        self.provider.select_value(&EnhancementProvider::ALL, &settings.provider);
        self.endpoints = Endpoints {
            ollama: settings.ollama_base_url.clone(),
            custom: settings.custom_endpoint.clone(),
            shown: None,
        };
        self.provider_changed(Some(&settings.model_name()), cx);
        self.show_prompts(config, &settings.prompt_id);
        self.window_context.set(settings.use_window_context);
        self.clipboard_context.set(settings.use_clipboard_context);
        self.selection_context.set(settings.use_selected_text_context);
        self.skip_short.set(settings.skip_short_transcripts);
        self.short_words.set(&settings.short_transcript_word_threshold.to_string());
        self.timeout.set(&settings.timeout_secs.to_string());
    }

    fn apply(&mut self, config: &mut Config, keys: &mut KeyChanges) -> Result<(), String> {
        let provider = self.selected_provider();
        self.remember_endpoint();
        let settings = &mut config.enhancement;
        settings.enabled = self.enabled.checked();
        settings.set_provider(provider);
        settings.model = model_override(self.model.text(), provider.default_model());
        if let Some(id) = self.selected_prompt() {
            settings.prompt_id.clone_from(id);
        }
        settings.ollama_base_url.clone_from(&self.endpoints.ollama);
        settings.custom_endpoint.clone_from(&self.endpoints.custom);
        settings.use_window_context = self.window_context.checked();
        settings.use_clipboard_context = self.clipboard_context.checked();
        settings.use_selected_text_context = self.selection_context.checked();
        settings.skip_short_transcripts = self.skip_short.checked();
        settings.short_transcript_word_threshold =
            usize::try_from(self.short_words.number("Short dictation words")?).unwrap_or(usize::MAX);
        settings.timeout_secs = self.timeout.number("Timeout")?.clamp(TIMEOUT_RANGE_SECS.0, TIMEOUT_RANGE_SECS.1);
        self.key.collect(provider.credential_key(), keys);
        Ok(())
    }

    /// Prompts may have been added or deleted on the Prompts page.
    fn enter(&mut self, config: &Config, _cx: &PageContext<'_>) {
        let selected = self.selected_prompt().cloned().unwrap_or_else(|| config.enhancement.prompt_id.clone());
        self.show_prompts(config, &selected);
        self.show_endpoint();
    }

    fn command(&mut self, id: u16, code: u32, _config: &mut Config, cx: &PageContext<'_>) {
        match (id, code) {
            (ID_PROVIDER, CBN_SELCHANGE) => self.provider_changed(None, cx),
            (ID_REMOVE_KEY, _) => self.key.remove(self.selected_provider().credential_key(), cx),
            _ => {}
        }
    }

    fn saved(&mut self, cx: &PageContext<'_>) {
        self.key.edit.set("");
        self.key.show(self.selected_provider().credential_key(), cx);
    }
}
