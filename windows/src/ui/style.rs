//! Theme and shared layout helpers, so pages look consistent.

// Colours are written as the usual six-digit hex codes.
#![allow(clippy::unreadable_literal)]

use iced::widget::{column, container, row, text};
use iced::{Border, Color, Element, Font, Length, Theme, color, font};
use std::sync::OnceLock;

/// The accent colour (also used by the stats chart).
pub const ACCENT: Color = color!(0x2563EB);
pub const MUTED: Color = color!(0x6B7280);
pub const TILE: Color = color!(0xF3F4F6);
pub const EMPTY_BAR: Color = color!(0xD1D5DB);

pub const PAGE_PADDING: u16 = 24;
pub const SECTION_SPACING: u32 = 14;
pub const LABEL_WIDTH: f32 = 190.0;
pub const FIELD_WIDTH: f32 = 300.0;
pub const NAV_WIDTH: f32 = 190.0;
pub const RADIUS: f32 = 10.0;
/// Multi-line editors live in a scrolling page, so they need a fixed height.
pub const EDITOR_HEIGHT: f32 = 320.0;

pub fn theme() -> Theme {
    Theme::custom(
        "VoiceInk",
        iced::theme::Palette {
            background: Color::WHITE,
            text: color!(0x111827),
            primary: ACCENT,
            success: color!(0x16A34A),
            warning: color!(0xD97706),
            danger: color!(0xDC2626),
        },
    )
}

static FONT: OnceLock<Font> = OnceLock::new();

/// Chooses the UI font family once, at startup (see `Desktop::font_family`).
pub fn set_font(font: Font) {
    let _ = FONT.set(font);
}

/// The UI font (the system default until [`set_font`] is called).
pub fn font() -> Font {
    FONT.get().copied().unwrap_or(Font::DEFAULT)
}

pub fn semibold() -> Font {
    Font { weight: font::Weight::Semibold, ..font() }
}

pub fn bold() -> Font {
    Font { weight: font::Weight::Bold, ..font() }
}

pub fn title<'a, M: 'a>(label: &'a str) -> Element<'a, M> {
    text(label).size(24).font(semibold()).into()
}

/// Grey explanatory text.
pub fn hint<'a, M: 'a>(label: impl text::IntoFragment<'a>) -> Element<'a, M> {
    text(label).size(13).color(MUTED).into()
}

/// A labelled field row: caption on the left, control on the right.
pub fn field<'a, M: 'a>(label: &'a str, control: impl Into<Element<'a, M>>) -> Element<'a, M> {
    row![text(label).width(Length::Fixed(LABEL_WIDTH)), control.into()].spacing(12).align_y(iced::Center).into()
}

/// A field row with a hint underneath the control.
pub fn field_with_hint<'a, M: 'a>(label: &'a str, control: impl Into<Element<'a, M>>, note: &'a str) -> Element<'a, M> {
    column![field(label, control), row![iced::widget::space().width(Length::Fixed(LABEL_WIDTH + 12.0)), hint(note)]]
        .spacing(4)
        .into()
}

/// A check box or button indented to the field column.
pub fn indented<'a, M: 'a>(control: impl Into<Element<'a, M>>) -> Element<'a, M> {
    row![iced::widget::space().width(Length::Fixed(LABEL_WIDTH + 12.0)), control.into()].into()
}

/// A light rounded panel (stat tiles, chart).
pub fn tile(theme: &Theme) -> container::Style {
    let _ = theme;
    container::Style {
        background: Some(TILE.into()),
        border: Border { radius: RADIUS.into(), ..Border::default() },
        ..container::Style::default()
    }
}

/// The navigation sidebar background.
pub fn sidebar(theme: &Theme) -> container::Style {
    container::Style { background: Some(theme.extended_palette().background.weak.color.into()), ..Default::default() }
}

/// Wraps a value with a display label for pick lists.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Labeled<T> {
    pub value: T,
    pub label: &'static str,
}

impl<T> Labeled<T> {
    pub const fn new(value: T, label: &'static str) -> Self {
        Self { value, label }
    }
}

impl<T> std::fmt::Display for Labeled<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.label)
    }
}

/// The entry of `choices` whose value is `current`.
pub fn selected<T: PartialEq + Copy>(choices: &[Labeled<T>], current: T) -> Option<Labeled<T>> {
    choices.iter().copied().find(|c| c.value == current)
}
