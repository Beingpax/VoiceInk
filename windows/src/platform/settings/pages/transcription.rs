//! Speech-to-text provider, model, language and output clean-up.

use super::super::widgets::{
    Builder, CBN_SELCHANGE, CHECK_ROW, CheckBox, ComboBox, Edit, FIELD_W, FIELD_X, HINT_GAP, ROW, TOP,
};
use super::{KeyChanges, KeyField, Page, PageContext, model_override, models_or_default};
use crate::config::{Config, LANGUAGES, TranscriptionProvider};

const ID_PROVIDER: u16 = 1;
const ID_REMOVE_KEY: u16 = 2;

pub struct Transcription {
    provider: ComboBox,
    model: ComboBox,
    language: ComboBox,
    key: KeyField,
    endpoint: Edit,
    filter: CheckBox,
    formatting: CheckBox,
    fillers: Edit,
}

impl Transcription {
    pub fn build(b: &mut Builder<'_>) -> Self {
        let mut y = TOP;
        b.row_label("Provider", y);
        let provider = b.combo(y, 280, false, ID_PROVIDER);
        y += ROW;
        b.row_label("Model", y);
        let model = b.combo(y, 280, true, 0);
        y += ROW;
        b.row_label("Language", y);
        let language = b.combo(y, 280, false, 0);
        y += ROW;
        b.row_label("API key", y);
        let key_edit = b.password(y, 230);
        b.button("Remove", FIELD_X + 238, y - 2, 80, ID_REMOVE_KEY);
        let key = KeyField { edit: key_edit, status: b.label("", FIELD_X + 328, y, FIELD_W - 328) };
        y += ROW;
        b.row_label("Custom endpoint", y);
        let endpoint = b.edit(y, FIELD_W);
        y += HINT_GAP;
        b.hint("Used by the Custom provider, e.g. a local whisper.cpp server", y);
        y += ROW + 4;
        let filter = b.option("Remove filler words and noise tags like [MUSIC]", y);
        y += CHECK_ROW;
        let formatting = b.option("Format long dictations into paragraphs", y);
        y += ROW;
        b.row_label("Filler words", y);
        let fillers = b.edit(y, FIELD_W);
        y += HINT_GAP;
        b.hint("Comma separated", y);
        Self { provider, model, language, key, endpoint, filter, formatting, fillers }
    }

    fn selected_provider(&self) -> TranscriptionProvider {
        self.provider.pick(&TranscriptionProvider::ALL)
    }

    /// Shows the models and key state for the selected provider.
    fn provider_changed(&self, model: Option<&str>, cx: &PageContext<'_>) {
        let provider = self.selected_provider();
        self.model.fill(models_or_default(provider.models(), provider.default_model()));
        self.model.set_text(model.unwrap_or(provider.default_model()));
        self.key.show(provider.credential_key(), cx);
    }
}

impl Page for Transcription {
    fn load(&mut self, config: &Config, cx: &PageContext<'_>) {
        let settings = &config.transcription;
        self.provider.fill(TranscriptionProvider::ALL.iter().map(|p| p.display_name()));
        self.provider.select_value(&TranscriptionProvider::ALL, &settings.provider);
        self.provider_changed(Some(&settings.model_name()), cx);
        self.language.fill(LANGUAGES.iter().map(|(_, name)| *name));
        let codes: Vec<String> = LANGUAGES.iter().map(|(code, _)| code.to_string()).collect();
        self.language.select_value(&codes, &settings.language.to_ascii_lowercase());
        self.endpoint.set(&settings.custom_endpoint);
        self.filter.set(settings.filter_output);
        self.formatting.set(settings.text_formatting);
        self.fillers.set(&config.filler_words.join(", "));
    }

    fn apply(&mut self, config: &mut Config, keys: &mut KeyChanges) -> Result<(), String> {
        let provider = self.selected_provider();
        let settings = &mut config.transcription;
        settings.set_provider(provider);
        settings.model = model_override(self.model.text(), provider.default_model());
        settings.language = self.language.pick(LANGUAGES).0.to_string();
        settings.custom_endpoint = self.endpoint.trimmed();
        settings.filter_output = self.filter.checked();
        settings.text_formatting = self.formatting.checked();
        config.filler_words =
            self.fillers.text().split(',').map(|w| w.trim().to_lowercase()).filter(|w| !w.is_empty()).collect();
        self.key.collect(provider.credential_key(), keys);
        Ok(())
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
