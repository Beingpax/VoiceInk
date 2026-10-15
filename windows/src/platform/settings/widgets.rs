//! Typed wrappers around the standard Win32 controls, and the [`Builder`]
//! that lays them out in device-independent pixels.

use super::super::gdi;
use super::super::wide;
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::Graphics::Gdi::HFONT;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, GetWindowTextLengthW, GetWindowTextW, HMENU, IDYES, MB_ICONERROR, MB_ICONWARNING, MB_OK, MB_YESNO,
    MessageBoxW, SW_HIDE, SW_SHOW, SendMessageW, SetWindowTextW, ShowWindow, WINDOW_EX_STYLE, WINDOW_STYLE, WM_SETFONT,
    WS_CHILD, WS_EX_CLIENTEDGE, WS_TABSTOP, WS_VSCROLL,
};
use windows::core::{PCWSTR, w};

// Win32 control styles and messages (values from WinUser.h / CommCtrl.h).
const BS_DEFPUSHBUTTON: u32 = 0x1;
const BS_AUTOCHECKBOX: u32 = 0x3;
const BM_GETCHECK: u32 = 0xF0;
const BM_SETCHECK: u32 = 0xF1;
const CBS_DROPDOWN: u32 = 0x2;
const CBS_DROPDOWNLIST: u32 = 0x3;
const CB_ADDSTRING: u32 = 0x143;
const CB_GETCURSEL: u32 = 0x147;
const CB_RESETCONTENT: u32 = 0x14B;
const CB_SETCURSEL: u32 = 0x14E;
const CB_SETMINVISIBLE: u32 = 0x1701;
const LBS_NOTIFY: u32 = 0x1;
const LBS_NOINTEGRALHEIGHT: u32 = 0x100;
const LB_ADDSTRING: u32 = 0x180;
const LB_RESETCONTENT: u32 = 0x184;
const LB_SETCURSEL: u32 = 0x186;
const LB_GETCURSEL: u32 = 0x188;
const LB_SETITEMHEIGHT: u32 = 0x1A0;
const ES_MULTILINE: u32 = 0x4;
const ES_PASSWORD: u32 = 0x20;
const ES_AUTOVSCROLL: u32 = 0x40;
const ES_AUTOHSCROLL: u32 = 0x80;
const ES_WANTRETURN: u32 = 0x1000;
const ES_NUMBER: u32 = 0x2000;
const EM_SETCUEBANNER: u32 = 0x1501;

/// Notification codes (`HIWORD(wParam)` of `WM_COMMAND`).
pub const CBN_SELCHANGE: u32 = 1;
pub const LBN_SELCHANGE: u32 = 1;
pub const LBN_DBLCLK: u32 = 2;

// Layout (device-independent pixels).
pub const CLIENT_W: i32 = 880;
pub const CLIENT_H: i32 = 620;
pub const NAV_W: i32 = 180;
pub const LEFT: i32 = 212;
pub const CONTENT_W: i32 = CLIENT_W - LEFT - 24;
pub const LABEL_W: i32 = 190;
pub const FIELD_X: i32 = LEFT + LABEL_W;
pub const FIELD_W: i32 = CONTENT_W - LABEL_W;
pub const ROW: i32 = 34;
/// First row below the page title.
pub const TOP: i32 = 64;
/// Space between check boxes stacked under each other.
pub const CHECK_ROW: i32 = 28;
/// Offset of a hint line below its field.
pub const HINT_GAP: i32 = 26;
const COMBO_VISIBLE_ITEMS: usize = 14;
const NAV_ITEM_HEIGHT: i32 = 36;

fn send(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) -> isize {
    // SAFETY: standard control messages to a window we created; pointer
    // arguments (strings) are passed only where the message expects them and
    // outlive the synchronous call.
    unsafe { SendMessageW(hwnd, msg, Some(WPARAM(wparam)), Some(LPARAM(lparam))) }.0
}

fn window_text(hwnd: HWND) -> String {
    // SAFETY: the buffer is sized from GetWindowTextLengthW plus the terminator.
    unsafe {
        let len = usize::try_from(GetWindowTextLengthW(hwnd)).unwrap_or(0);
        let mut buf = vec![0u16; len + 1];
        let copied = usize::try_from(GetWindowTextW(hwnd, &mut buf)).unwrap_or(0);
        String::from_utf16_lossy(&buf[..copied])
    }
}

fn set_window_text(hwnd: HWND, text: &str) {
    // Edit controls want CRLF line breaks.
    let text = wide(&text.replace("\r\n", "\n").replace('\n', "\r\n"));
    // SAFETY: `text` is NUL-terminated and outlives the call.
    let _ = unsafe { SetWindowTextW(hwnd, PCWSTR(text.as_ptr())) };
}

pub fn set_visible(hwnd: HWND, visible: bool) {
    // SAFETY: ShowWindow accepts any window handle.
    let _ = unsafe { ShowWindow(hwnd, if visible { SW_SHOW } else { SW_HIDE }) };
}

fn index_of<T: PartialEq>(items: &[T], value: &T) -> usize {
    items.iter().position(|item| item == value).unwrap_or(0)
}

/// Static text.
#[derive(Debug, Clone, Copy, Default)]
pub struct Label(pub HWND);

impl Label {
    pub fn set(self, text: &str) {
        set_window_text(self.0, text);
    }
}

/// Single- or multi-line text field.
#[derive(Debug, Clone, Copy, Default)]
pub struct Edit(pub HWND);

impl Edit {
    /// The text with Windows line breaks normalized to `\n`.
    pub fn text(self) -> String {
        window_text(self.0).replace("\r\n", "\n")
    }

    pub fn trimmed(self) -> String {
        self.text().trim().to_string()
    }

    pub fn set(self, text: &str) {
        set_window_text(self.0, text);
    }

    /// Grey placeholder shown while the field is empty.
    pub fn set_cue(self, text: &str) {
        let text = wide(text);
        send(self.0, EM_SETCUEBANNER, 1, text.as_ptr() as isize);
    }

    /// Parses the field as a whole number.
    ///
    /// # Errors
    /// Returns a user-facing message naming the field.
    pub fn number(self, field: &str) -> Result<u64, String> {
        self.trimmed().parse().map_err(|_| format!("{field} must be a number"))
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct CheckBox(pub HWND);

impl CheckBox {
    pub fn checked(self) -> bool {
        send(self.0, BM_GETCHECK, 0, 0) == 1
    }

    pub fn set(self, checked: bool) {
        send(self.0, BM_SETCHECK, usize::from(checked), 0);
    }
}

/// Drop-down list, optionally with an editable text field.
#[derive(Debug, Clone, Copy, Default)]
pub struct ComboBox(pub HWND);

impl ComboBox {
    pub fn fill<S: AsRef<str>>(self, items: impl IntoIterator<Item = S>) {
        send(self.0, CB_RESETCONTENT, 0, 0);
        for item in items {
            let item = wide(item.as_ref());
            send(self.0, CB_ADDSTRING, 0, item.as_ptr() as isize);
        }
    }

    pub fn selected(self) -> Option<usize> {
        usize::try_from(send(self.0, CB_GETCURSEL, 0, 0)).ok()
    }

    pub fn select(self, index: usize) {
        send(self.0, CB_SETCURSEL, index, 0);
    }

    /// The edit text of an editable combo box.
    pub fn text(self) -> String {
        window_text(self.0).trim().to_string()
    }

    pub fn set_text(self, text: &str) {
        set_window_text(self.0, text);
    }

    /// Fills the box from `(value, label)` pairs and selects `current`.
    pub fn show_choices<T: PartialEq + Copy>(self, choices: &[(T, &str)], current: T) {
        self.fill(choices.iter().map(|(_, label)| *label));
        let values: Vec<T> = choices.iter().map(|(value, _)| *value).collect();
        self.select(index_of(&values, &current));
    }

    /// The selected value of a box filled by [`Self::show_choices`].
    pub fn choice<T: Copy>(self, choices: &[(T, &str)]) -> T {
        self.pick(&choices.iter().map(|(value, _)| *value).collect::<Vec<_>>())
    }

    /// Selects `current` in a box whose rows correspond to `items`.
    pub fn select_value<T: PartialEq>(self, items: &[T], current: &T) {
        self.select(index_of(items, current));
    }

    /// The item for the selected row (the first one when nothing is selected).
    ///
    /// # Panics
    /// When `items` is empty.
    pub fn pick<T: Copy>(self, items: &[T]) -> T {
        items[self.selected().unwrap_or(0).min(items.len() - 1)]
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct ListBox(pub HWND);

impl ListBox {
    pub fn fill<S: AsRef<str>>(self, items: impl IntoIterator<Item = S>) {
        send(self.0, LB_RESETCONTENT, 0, 0);
        for item in items {
            let item = wide(item.as_ref());
            send(self.0, LB_ADDSTRING, 0, item.as_ptr() as isize);
        }
    }

    pub fn selected(self) -> Option<usize> {
        usize::try_from(send(self.0, LB_GETCURSEL, 0, 0)).ok()
    }

    pub fn select(self, index: usize) {
        send(self.0, LB_SETCURSEL, index, 0);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Warning,
    Error,
}

pub fn message_box(owner: HWND, text: &str, severity: Severity) {
    let text = wide(text);
    let icon = match severity {
        Severity::Warning => MB_ICONWARNING,
        Severity::Error => MB_ICONERROR,
    };
    // SAFETY: `text` is NUL-terminated and outlives the modal call.
    unsafe { MessageBoxW(Some(owner), PCWSTR(text.as_ptr()), w!("VoiceInk"), MB_OK | icon) };
}

/// Asks a yes/no question; true for "Yes".
pub fn confirm(owner: HWND, question: &str) -> bool {
    let question = wide(question);
    // SAFETY: `question` is NUL-terminated and outlives the modal call.
    unsafe { MessageBoxW(Some(owner), PCWSTR(question.as_ptr()), w!("VoiceInk"), MB_YESNO | MB_ICONWARNING) == IDYES }
}

/// Creates child controls on one page and remembers them so the window can
/// show or hide the page as a whole. Control ids are page-relative and
/// offset by `id_base`.
pub struct Builder<'a> {
    parent: HWND,
    scale: f32,
    font: &'a gdi::Owned,
    title_font: &'a gdi::Owned,
    id_base: u16,
    controls: Vec<HWND>,
}

impl<'a> Builder<'a> {
    pub fn new(parent: HWND, scale: f32, font: &'a gdi::Owned, title_font: &'a gdi::Owned) -> Self {
        Self { parent, scale, font, title_font, id_base: 0, controls: Vec::new() }
    }

    /// Starts the next page; its local ids are offset by `id_base`.
    pub fn begin_page(&mut self, id_base: u16) {
        self.id_base = id_base;
    }

    /// Controls created since the last call.
    pub fn take_controls(&mut self) -> Vec<HWND> {
        std::mem::take(&mut self.controls)
    }

    pub fn px(&self, value: i32) -> i32 {
        (value as f32 * self.scale).round() as i32
    }

    fn create(&mut self, class: PCWSTR, text: &str, style: u32, ex: u32, rect: (i32, i32, i32, i32), id: u16) -> HWND {
        let (x, y, width, height) = rect;
        let text = wide(text);
        let id = if id == 0 { 0 } else { usize::from(self.id_base + id) };
        // SAFETY: creates a child of our own window with a static class name;
        // the control id travels in the HMENU parameter as documented.
        let hwnd = unsafe {
            CreateWindowExW(
                WINDOW_EX_STYLE(ex),
                class,
                PCWSTR(text.as_ptr()),
                WS_CHILD | WINDOW_STYLE(style),
                self.px(x),
                self.px(y),
                self.px(width),
                self.px(height),
                Some(self.parent),
                Some(HMENU(id as *mut _)),
                GetModuleHandleW(None).ok().map(Into::into),
                None,
            )
        }
        .unwrap_or_default();
        send(hwnd, WM_SETFONT, HFONT::from(self.font).0 as usize, 1);
        self.controls.push(hwnd);
        hwnd
    }

    /// A custom window class (e.g. the stats panel).
    pub fn custom(&mut self, class: PCWSTR, rect: (i32, i32, i32, i32)) -> HWND {
        self.create(class, "", 0, 0, rect, 0)
    }

    pub fn title(&mut self, text: &str) {
        let hwnd = self.create(w!("STATIC"), text, 0, 0, (LEFT, 14, CONTENT_W, 32), 0);
        send(hwnd, WM_SETFONT, HFONT::from(self.title_font).0 as usize, 1);
    }

    /// Wrapped static text spanning `width` × `height`.
    pub fn text(&mut self, text: &str, rect: (i32, i32, i32, i32)) -> Label {
        Label(self.create(w!("STATIC"), text, 0, 0, rect, 0))
    }

    pub fn label(&mut self, text: &str, x: i32, y: i32, width: i32) -> Label {
        self.text(text, (x, y + 4, width, 20))
    }

    /// The caption left of a field row.
    pub fn row_label(&mut self, text: &str, y: i32) -> Label {
        self.label(text, LEFT, y, LABEL_W - 12)
    }

    /// Grey explanatory line under a field.
    pub fn hint(&mut self, text: &str, y: i32) -> Label {
        self.text(text, (FIELD_X, y, FIELD_W, 20))
    }

    fn edit_with(&mut self, rect: (i32, i32, i32, i32), style: u32) -> Edit {
        Edit(self.create(w!("EDIT"), "", WS_TABSTOP.0 | ES_AUTOHSCROLL | style, WS_EX_CLIENTEDGE.0, rect, 0))
    }

    pub fn edit(&mut self, y: i32, width: i32) -> Edit {
        self.edit_with((FIELD_X, y, width, 24), 0)
    }

    pub fn number_at(&mut self, x: i32, y: i32, width: i32) -> Edit {
        self.edit_with((x, y, width, 24), ES_NUMBER)
    }

    pub fn number(&mut self, y: i32, width: i32) -> Edit {
        self.number_at(FIELD_X, y, width)
    }

    pub fn password(&mut self, y: i32, width: i32) -> Edit {
        self.edit_with((FIELD_X, y, width, 24), ES_PASSWORD)
    }

    pub fn multiline(&mut self, rect: (i32, i32, i32, i32)) -> Edit {
        Edit(self.create(
            w!("EDIT"),
            "",
            WS_TABSTOP.0 | WS_VSCROLL.0 | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
            WS_EX_CLIENTEDGE.0,
            rect,
            0,
        ))
    }

    /// A drop-down; `editable` allows typing values that are not in the list.
    pub fn combo(&mut self, y: i32, width: i32, editable: bool, id: u16) -> ComboBox {
        let kind = if editable { CBS_DROPDOWN } else { CBS_DROPDOWNLIST };
        // The height includes the opened list.
        let hwnd = self.create(w!("COMBOBOX"), "", WS_TABSTOP.0 | WS_VSCROLL.0 | kind, 0, (FIELD_X, y, width, 300), id);
        send(hwnd, CB_SETMINVISIBLE, COMBO_VISIBLE_ITEMS, 0);
        ComboBox(hwnd)
    }

    pub fn check(&mut self, text: &str, x: i32, y: i32, width: i32) -> CheckBox {
        CheckBox(self.create(w!("BUTTON"), text, WS_TABSTOP.0 | BS_AUTOCHECKBOX, 0, (x, y, width, 24), 0))
    }

    /// A check box in the field column.
    pub fn option(&mut self, text: &str, y: i32) -> CheckBox {
        self.check(text, FIELD_X, y, FIELD_W)
    }

    pub fn button(&mut self, text: &str, x: i32, y: i32, width: i32, id: u16) -> HWND {
        self.create(w!("BUTTON"), text, WS_TABSTOP.0, 0, (x, y, width, 28), id)
    }

    pub fn default_button(&mut self, text: &str, rect: (i32, i32, i32, i32), id: u16) -> HWND {
        self.create(w!("BUTTON"), text, WS_TABSTOP.0 | BS_DEFPUSHBUTTON, 0, rect, id)
    }

    pub fn list(&mut self, rect: (i32, i32, i32, i32), id: u16, bordered: bool) -> ListBox {
        let ex = if bordered { WS_EX_CLIENTEDGE.0 } else { 0 };
        ListBox(self.create(
            w!("LISTBOX"),
            "",
            WS_TABSTOP.0 | WS_VSCROLL.0 | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT,
            ex,
            rect,
            id,
        ))
    }

    /// The navigation list with tall rows.
    pub fn navigation(&mut self, items: &[&str], id: u16) -> ListBox {
        let list = self.list((0, 0, NAV_W, CLIENT_H), id, false);
        send(list.0, LB_SETITEMHEIGHT, 0, self.px(NAV_ITEM_HEIGHT) as isize);
        list.fill(items.iter().map(|item| format!("   {item}")));
        list
    }
}
